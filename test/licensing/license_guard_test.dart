import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/licensing/license_service.dart';
import 'package:m3/core/licensing/license_state.dart';
import 'package:m3/core/licensing/licensed_database.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'fakes.dart';

void main() {
  sqfliteFfiInit();
  late Database raw;
  late LicensedDatabase db;
  late FakeLicenseService service;
  setUp(() async {
    raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await raw.execute('CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)');
    service = FakeLicenseService();
    db = LicensedDatabase(raw, LicenseGuard(service));
  });
  tearDown(() async {
    await raw.close();
  });
  test('Held connection cannot read or mutate after license loss', () async {
    await db.insert('test', {'value': 'preserved'});
    service.set(const LicenseState(LicenseStatus.expired));
    for (final operation in <Future<void> Function()>[
      () async {
        await db.insert('test', {'value': 'blocked'});
      },
      () async {
        await db.rawUpdate("UPDATE test SET value='blocked'");
      },
      () async {
        await db.rawDelete('DELETE FROM test');
      },
      () async {
        await db.execute('DELETE FROM test');
      },
      () async {
        await db.rawQuery('DELETE FROM test RETURNING *');
      },
      () async {
        await db.query('test');
      },
    ]) {
      await expectLater(operation(), throwsA(isA<LicenseRequiredException>()));
    }
    expect((await raw.query('test')).single['value'], 'preserved');
  });
  for (final offset in [
    const Duration(days: -1),
    const Duration(minutes: -1),
    Duration.zero,
    const Duration(minutes: 1),
    const Duration(days: 1),
  ]) {
    test('FakeClock SQLite boundary $offset preserves existing data', () async {
      final storage = MemoryLicenseStorage();
      final clock = FakeLicenseClock(DateTime.utc(2026, 1, 31, 12));
      final licenses = TemporaryTrialLicenseService(
        storage: storage,
        clock: clock,
        verifier: FakeCodeVerifier(),
      );
      final initial = await licenses.activate(testOnlyCode);
      final guarded = LicensedDatabase(raw, LicenseGuard(licenses));
      await guarded.insert('test', {'value': 'preserved'});
      clock.advance(initial.expiresAt!.difference(clock.utc) + offset);
      if (offset.isNegative) {
        await guarded.insert('test', {'value': 'allowed'});
        expect((await raw.query('test')).length, 2);
      } else {
        await expectLater(
          guarded.insert('test', {'value': 'blocked'}),
          throwsA(isA<LicenseRequiredException>()),
        );
        expect((await raw.query('test')).length, 1);
      }
      expect(
        (await raw.query(
          'test',
          where: 'value = ?',
          whereArgs: ['preserved'],
        )).length,
        1,
      );
      licenses.dispose();
    });
  }
  test(
    'Accepted transaction completes atomically across expiry; next starts blocked',
    () async {
      await db.transaction((txn) async {
        await txn.insert('test', {'value': 'first'});
        service.set(const LicenseState(LicenseStatus.expired));
        await txn.insert('test', {'value': 'second'});
      });
      expect((await raw.query('test')).length, 2);
      await expectLater(
        db.transaction((txn) => txn.delete('test')),
        throwsA(isA<LicenseRequiredException>()),
      );
    },
  );
  test(
    'Queued transaction checks validity when it acquires SQLite, not before',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final first = db.transaction((txn) async {
        entered.complete();
        await release.future;
        await txn.insert('test', {'value': 'first'});
      });
      await entered.future;
      final queued = db.transaction(
        (txn) => txn.insert('test', {'value': 'must-not-run'}),
      );
      final rejection = expectLater(
        queued,
        throwsA(isA<LicenseRequiredException>()),
      );
      service.set(const LicenseState(LicenseStatus.expired));
      release.complete();
      await first;
      await rejection;
      expect((await raw.query('test')).length, 1);
    },
  );
  test('Batch created while valid cannot commit after expiry', () async {
    final b = db.batch();
    b.insert('test', {'value': 'blocked'});
    service.set(const LicenseState(LicenseStatus.expired));
    await expectLater(b.commit(), throwsA(isA<LicenseRequiredException>()));
    expect(await raw.query('test'), isEmpty);
  });
  test(
    'Transaction batch finishes on its original permit without checking midway',
    () async {
      await db.transaction((txn) async {
        final b = txn.batch();
        b.insert('test', {'value': 'one'});
        service.set(const LicenseState(LicenseStatus.expired));
        b.insert('test', {'value': 'two'});
        await b.commit();
      });
      expect((await raw.query('test')).length, 2);
    },
  );
  test(
    'Escaped transaction handles and unsupported dev APIs fail closed',
    () async {
      late Transaction escaped;
      await db.transaction((txn) async {
        escaped = txn;
      });
      expect(
        () => escaped.insert('test', {'value': 'escaped'}),
        throwsStateError,
      );
      expect(() => db.batch().apply(), throwsUnsupportedError);
      // ignore: deprecated_member_use
      expect(() => db.devInvokeMethod('execute'), throwsUnsupportedError);
    },
  );
  test('Active SQL failure still rolls the entire transaction back', () async {
    await expectLater(
      db.transaction((txn) async {
        await txn.insert('test', {'value': 'partial'});
        await txn.execute('not valid SQL');
      }),
      throwsA(isA<DatabaseException>()),
    );
    expect(await raw.query('test'), isEmpty);
  });
  group('Accounting repository boundaries', () {
    late Directory directory;
    late Database accounting;
    late FakeLicenseService licenses;
    late int item;
    final manager = AppDatabase.instance;
    final inventory = SqliteInventoryRepository();
    final invoices = SqliteInvoicesRepository();
    final vouchers = SqliteVouchersRepository();
    final date = DateTime.utc(2026, 1, 1);
    InvoiceModel request() => InvoiceModel.buildWithItems(
      invoiceNumber: 'LICENSE-INV',
      invoiceType: InvoiceType.sale,
      paymentMethod: PaymentMethod.bank,
      paidAmount: const Money(1000),
      items: [
        InvoiceItemModel.create(
          itemId: item,
          quantity: 1,
          unitPrice: const Money(1000),
        ),
      ],
      invoiceDate: date,
      createdAt: date,
      updatedAt: date,
    );
    Future<Map<String, Object?>> snapshot() async => {
      for (final table in [
        AppTables.items,
        AppTables.parties,
        AppTables.invoices,
        AppTables.invoiceItems,
        AppTables.inventoryMovements,
        AppTables.vouchers,
      ])
        table: await accounting.query(table, orderBy: 'id'),
    };
    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'daftar_license_accounting_',
      );
      manager.configureForTesting(
        factory: databaseFactoryFfi,
        path: '${directory.path}/isolated.db',
      );
      accounting = await manager.database;
      final unit = await inventory.insertUnit(
        UnitModel(name: 'License test unit', symbol: 'u', createdAt: date),
      );
      item = await inventory.insertItem(
        ItemModel(
          code: 'LICENSE-ITEM',
          name: 'Isolated item',
          unitId: unit,
          stockQuantity: 20,
          costPrice: const Money(600),
          sellingPrice: const Money(1000),
          createdAt: date,
          updatedAt: date,
        ),
      );
      licenses = FakeLicenseService();
      manager.configureForTesting(
        factory: databaseFactoryFfi,
        path: '${directory.path}/isolated.db',
        licenseGuard: LicenseGuard(licenses),
      );
    });
    tearDown(() async {
      await manager.close();
      await directory.delete(recursive: true);
    });
    for (final status in [
      LicenseStatus.activationRequired,
      LicenseStatus.expired,
      LicenseStatus.clockChanged,
      LicenseStatus.unavailable,
    ]) {
      test(
        'Direct financial repository calls with $status cannot post or delete data',
        () async {
          final held = await manager.database;
          final before = await snapshot();
          licenses.set(LicenseState(status));
          await expectLater(
            invoices.saveAndFinalizeInvoice(request()),
            throwsA(isA<LicenseRequiredException>()),
          );
          await expectLater(
            vouchers.createVoucher(
              VoucherModel(
                voucherNumber: 'LICENSE-V',
                voucherType: VoucherType.receipt,
                amount: const Money(100),
                paymentMethod: PaymentMethod.cash,
                voucherDate: date,
                createdAt: date,
              ),
            ),
            throwsA(isA<LicenseRequiredException>()),
          );
          await expectLater(
            held.delete(AppTables.items),
            throwsA(isA<LicenseRequiredException>()),
          );
          expect(await snapshot(), before);
          expect(await accounting.getVersion(), 6);
        },
      );
    }
    test(
      'Valid trial preserves invoice, stock and bank posting across reopen',
      () async {
        await invoices.saveAndFinalizeInvoice(request());
        expect((await inventory.getItemById(item))!.stockQuantity, 19);
        expect(
          (await vouchers.getTreasuryBalances()).bank.balance,
          const Money(1000),
        );
        final before = await snapshot();
        await manager.close();
        manager.configureForTesting(
          factory: databaseFactoryFfi,
          path: '${directory.path}/isolated.db',
          licenseGuard: LicenseGuard(licenses),
        );
        expect((await inventory.getItemById(item))!.stockQuantity, 19);
        expect((await invoices.getInvoices()).length, 1);
        licenses.set(const LicenseState(LicenseStatus.expired));
        // Independently reopen the isolated file, proving expiry never deletes it.
        final inspection = await databaseFactoryFfi.openDatabase(
          '${directory.path}/isolated.db',
        );
        expect(
          await inspection.query(AppTables.invoices),
          before[AppTables.invoices],
        );
        expect(
          await inspection.query(AppTables.items),
          before[AppTables.items],
        );
      },
    );
    test(
      'Party-type transaction validation still rejects an incompatible supplier',
      () async {
        final party = await SqlitePartiesRepository().insertParty(
          PartyModel(
            name: 'supplier',
            phone: '',
            type: PartyType.supplier,
            createdAt: date,
            updatedAt: date,
          ),
        );
        final before = await snapshot();
        await expectLater(
          invoices.saveAndFinalizeInvoice(request().copyWith(partyId: party)),
          throwsA(anything),
        );
        expect(await snapshot(), before);
      },
    );
  });
}
