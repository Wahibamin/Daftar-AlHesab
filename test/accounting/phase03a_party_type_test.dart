import 'dart:io';
import '../../test_support/funded_treasury.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final manager = AppDatabase.instance;
  final invoices = SqliteInvoicesRepository(manager);
  final inventory = SqliteInventoryRepository(manager);
  final parties = SqlitePartiesRepository(manager);
  final treasury = SqliteVouchersRepository(manager);
  final date = DateTime(2026, 11, 5, 12);
  late Directory directory;
  late Database db;
  late int itemId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daftar_phase03a_');
    manager.configureForTesting(
      factory: databaseFactoryFfi,
      path: '${directory.path}/isolated.db',
    );
    db = await manager.database;
    await fundTreasury(db);
    final unit = await inventory.insertUnit(
      UnitModel(name: 'قطعة', symbol: 'حبة', createdAt: date),
    );
    itemId = await inventory.insertItem(
      ItemModel(
        code: 'PHASE03A',
        name: 'صنف اختبار',
        unitId: unit,
        costPrice: const Money(6000),
        sellingPrice: const Money(10000),
        stockQuantity: 20,
        createdAt: date,
        updatedAt: date,
      ),
    );
  });
  tearDown(() async {
    await manager.close();
    await directory.delete(recursive: true);
  });

  bool isSale(InvoiceType type) =>
      type == InvoiceType.sale || type == InvoiceType.saleReturn;
  PartyType expectedParty(InvoiceType type) =>
      isSale(type) ? PartyType.customer : PartyType.supplier;
  PartyType wrongParty(InvoiceType type) =>
      isSale(type) ? PartyType.supplier : PartyType.customer;
  Future<int> createParty(PartyType type) => parties.insertParty(
    PartyModel(
      name: 'طرف اختبار',
      phone: '0500000000',
      type: type,
      createdAt: date,
      updatedAt: date,
    ),
  );
  InvoiceModel invoice(
    InvoiceType type,
    int? party, {
    int paid = 0,
    String number = 'PHASE03A-001',
  }) => InvoiceModel.buildWithItems(
    invoiceNumber: number,
    partyId: party,
    invoiceType: type,
    paymentType: paid == 10000
        ? PaymentType.cash
        : paid == 0
        ? PaymentType.credit
        : PaymentType.partial,
    items: [
      InvoiceItemModel.create(
        itemId: itemId,
        quantity: 1,
        unitPrice: const Money(10000),
      ),
    ],
    paidAmount: Money(paid),
    invoiceDate: date,
    createdAt: date,
    updatedAt: date,
  );

  Future<Map<String, Object?>> snapshot() async => {
    for (final table in [
      AppTables.invoices,
      AppTables.invoiceItems,
      AppTables.items,
      AppTables.inventoryMovements,
      AppTables.parties,
      AppTables.vouchers,
    ])
      table: await db.query(table, orderBy: 'id'),
    'treasury': (await treasury.getTreasuryBalance()).rawUnits,
  };
  final arabicMismatch = throwsA(
    predicate(
      (error) =>
          error is ArgumentError &&
          error.toString().contains('نوع الطرف غير متوافق'),
    ),
  );

  Future<int?> prepare(
    InvoiceModel request,
    String path, {
    bool orphan = false,
  }) async {
    if (path != 'finalize') return null;
    if (!orphan) return invoices.createInvoice(request);
    final valid = await createParty(expectedParty(request.invoiceType));
    final id = await invoices.createInvoice(request.copyWith(partyId: valid));
    // A legacy orphan is simulated only in the isolated test database.
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.update(
      AppTables.invoices,
      {'party_id': request.partyId},
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.execute('PRAGMA foreign_keys = ON');
    return id;
  }

  Future<void> post(InvoiceModel request, String path, int? id) async {
    switch (path) {
      case 'finalize':
        await invoices.finalizeInvoice(id!);
      case 'create approved':
        await invoices.createInvoice(
          request.copyWith(status: InvoiceStatus.approved),
        );
      default:
        await invoices.saveAndFinalizeInvoice(request);
    }
  }

  Future<void> verifyPosted(InvoiceType type, int? party, int remaining) async {
    final stockIn =
        type == InvoiceType.purchase || type == InvoiceType.saleReturn;
    expect(
      (await inventory.getItemById(itemId))!.stockQuantity,
      stockIn ? 21 : 19,
    );
    expect((await inventory.getItemMovements(itemId)).length, 2);
    if (party != null) {
      final balance = (stockIn ? 1 : -1) * remaining;
      expect((await parties.getPartyById(party))!.currentBalanceInt, balance);
      expect(
        (await parties.getAccountStatement(party)).currentBalance.rawUnits,
        balance,
      );
    }
    final cashIn =
        type == InvoiceType.sale || type == InvoiceType.purchaseReturn;
    expect(
      (await treasury.getTreasuryBalance()).rawUnits,
      100000 + (10000 - remaining) * (cashIn ? 1 : -1),
    );
    expect(
      (await invoices.getInvoices()).single.status,
      InvoiceStatus.approved,
    );
  }

  group('Phase03A party compatibility', () {
    for (final type in InvoiceType.values) {
      for (final partyType in <PartyType?>[...PartyType.values, null]) {
        for (final path in ['saveAndFinalize', 'finalize', 'create approved']) {
          test(
            '$type $partyType via $path validates debt party before posting',
            () async {
              final party = partyType == null
                  ? 999999
                  : await createParty(partyType);
              final request = invoice(type, party);
              final id = await prepare(
                request,
                path,
                orphan: partyType == null,
              );
              final before = await snapshot();
              final compatible =
                  partyType == PartyType.both ||
                  partyType == expectedParty(type);
              if (compatible) {
                await post(request, path, id);
                await verifyPosted(type, party, 10000);
              } else {
                await expectLater(
                  post(request, path, id),
                  partyType == null ? throwsArgumentError : arabicMismatch,
                );
                expect(await snapshot(), before);
              }
            },
          );
        }
      }
      for (final path in ['saveAndFinalize', 'finalize', 'create approved']) {
        test(
          '$type full cash without party remains allowed via $path',
          () async {
            final request = invoice(type, null, paid: 10000);
            final id = await prepare(request, path);
            await post(request, path, id);
            await verifyPosted(type, null, 0);
          },
        );
        test(
          '$type full cash with wrong party is still rejected via $path',
          () async {
            final party = await createParty(wrongParty(type));
            final request = invoice(type, party, paid: 10000);
            final id = await prepare(request, path);
            final before = await snapshot();
            await expectLater(post(request, path, id), arabicMismatch);
            expect(await snapshot(), before);
          },
        );
      }
      test(
        '$type partial payment with both posts the correct 70 debt',
        () async {
          final party = await createParty(PartyType.both);
          await invoices.saveAndFinalizeInvoice(
            invoice(type, party, paid: 3000),
          );
          await verifyPosted(type, party, 7000);
        },
      );
      test('$type partial without party remains rejected atomically', () async {
        final before = await snapshot();
        await expectLater(
          invoices.saveAndFinalizeInvoice(invoice(type, null, paid: 3000)),
          throwsArgumentError,
        );
        expect(await snapshot(), before);
      });
      test(
        '$type incomplete and incompatible drafts can be saved and corrected',
        () async {
          final id = await invoices.createInvoice(invoice(type, null));
          final wrong = await createParty(wrongParty(type));
          await invoices.updateInvoice(invoice(type, wrong).copyWith(id: id));
          final before = await snapshot();
          await expectLater(invoices.finalizeInvoice(id), arabicMismatch);
          expect(await snapshot(), before);
          final correct = await createParty(expectedParty(type));
          await invoices.updateInvoice(invoice(type, correct).copyWith(id: id));
          await invoices.finalizeInvoice(id);
          await verifyPosted(type, correct, 10000);
        },
      );
      for (final path in ['saveAndFinalize', 'finalize']) {
        test(
          '$type rereads changed SQLite party type for an existing draft via $path',
          () async {
            final party = await createParty(expectedParty(type));
            final request = invoice(type, party);
            final id = await invoices.createInvoice(request);
            final savedParty = (await parties.getPartyById(party))!;
            await parties.updateParty(
              savedParty.copyWith(type: wrongParty(type)),
            );
            final before = await snapshot();
            await expectLater(
              post(request.copyWith(id: id), path, id),
              arabicMismatch,
            );
            expect(await snapshot(), before);
          },
        );
      }
      for (final compatible in [true, false]) {
        test(
          '$type archived party retains archive policy but must be compatible=$compatible',
          () async {
            final party = await createParty(
              compatible ? expectedParty(type) : wrongParty(type),
            );
            await parties.deleteParty(party);
            final request = invoice(type, party);
            final id = await invoices.createInvoice(request);
            final before = await snapshot();
            if (compatible) {
              await invoices.finalizeInvoice(id);
              expect((await parties.getPartyById(party))!.isActive, isFalse);
              await verifyPosted(type, party, 10000);
            } else {
              await expectLater(invoices.finalizeInvoice(id), arabicMismatch);
              expect(await snapshot(), before);
            }
          },
        );
      }
      test(
        '$type approved identical retries stay no-op after party type/archive changes',
        () async {
          final party = await createParty(expectedParty(type));
          final request = invoice(type, party);
          final id = await invoices.saveAndFinalizeInvoice(request);
          await parties.updateParty(
            (await parties.getPartyById(
              party,
            ))!.copyWith(type: wrongParty(type)),
          );
          await parties.deleteParty(party);
          final before = await snapshot();
          expect(
            await invoices.saveAndFinalizeInvoice(request.copyWith(id: id)),
            id,
          );
          await invoices.finalizeInvoice(id);
          expect(await snapshot(), before);
          await expectLater(
            invoices.saveAndFinalizeInvoice(
              request.copyWith(id: id, notes: 'طلب مختلف'),
            ),
            throwsA(isA<InvoiceConflictException>()),
          );
          expect(await snapshot(), before);
        },
      );
    }
    test(
      'unrecognized stored party type is not silently treated as customer',
      () async {
        final party = await createParty(PartyType.customer);
        await db.update(
          AppTables.parties,
          {'type': 'unrecognized'},
          where: 'id = ?',
          whereArgs: [party],
        );
        final before = await snapshot();
        await expectLater(
          invoices.saveAndFinalizeInvoice(invoice(InvoiceType.sale, party)),
          arabicMismatch,
        );
        expect(await snapshot(), before);
      },
    );
  });
}
