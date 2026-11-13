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
  late int partyId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daftar_phase02_');
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
        code: 'PHASE02',
        name: 'صنف اختبار',
        unitId: unit,
        costPrice: const Money(6000),
        sellingPrice: const Money(10000),
        stockQuantity: 20,
        createdAt: date,
        updatedAt: date,
      ),
    );
    partyId = await parties.insertParty(
      PartyModel(
        name: 'طرف اختباري',
        phone: '0500000000',
        type: PartyType.both,
        createdAt: date,
        updatedAt: date,
      ),
    );
  });
  tearDown(() async {
    await manager.close();
    await directory.delete(recursive: true);
  });

  InvoiceModel invoice({
    String number = 'INV-001',
    int? party = -1,
    InvoiceType type = InvoiceType.sale,
    int paid = 0,
    int price = 10000,
    PaymentType? payment,
    InvoiceStatus status = InvoiceStatus.draft,
  }) => InvoiceModel.buildWithItems(
    invoiceNumber: number,
    partyId: party == -1 ? partyId : party,
    invoiceType: type,
    status: status,
    paymentType:
        payment ??
        (paid == 0
            ? PaymentType.credit
            : paid == price
            ? PaymentType.cash
            : PaymentType.partial),
    items: [
      InvoiceItemModel.create(
        itemId: itemId,
        quantity: 1,
        unitPrice: Money(price),
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

  group('DH-NEW-01', () {
    for (final originalStatus in [
      InvoiceStatus.draft,
      InvoiceStatus.approved,
      InvoiceStatus.cancelled,
    ]) {
      test(
        'new request cannot reuse number of $originalStatus invoice',
        () async {
          final id = await invoices.createInvoice(invoice());
          if (originalStatus == InvoiceStatus.approved) {
            await invoices.finalizeInvoice(id);
          }
          if (originalStatus == InvoiceStatus.cancelled) {
            await invoices.cancelInvoice(id);
          }
          final before = await snapshot();
          await expectLater(
            invoices.saveAndFinalizeInvoice(invoice(price: 20000)),
            throwsA(
              predicate((error) => error.toString().contains('رقم الفاتورة')),
            ),
          );
          expect(await snapshot(), before);
        },
      );
    }
    test(
      'same number and identical content without ID are still a new conflicting request',
      () async {
        await invoices.saveAndFinalizeInvoice(invoice());
        final before = await snapshot();
        await expectLater(
          invoices.saveAndFinalizeInvoice(invoice()),
          throwsA(anything),
        );
        expect(await snapshot(), before);
      },
    );
    test(
      'same ID with identical content retries safely across restart and changed catalog cost',
      () async {
        final original = invoice();
        final id = await invoices.saveAndFinalizeInvoice(original);
        final item = (await inventory.getItemById(itemId))!;
        await inventory.updateItem(item.copyWith(costPrice: const Money(9999)));
        await manager.close();
        db = await manager.database;
        final before = await snapshot();
        expect(
          await invoices.saveAndFinalizeInvoice(original.copyWith(id: id)),
          id,
        );
        expect(
          await invoices.saveAndFinalizeInvoice(
            (await invoices.getInvoiceById(id))!,
          ),
          id,
        );
        expect(await snapshot(), before);
      },
    );
    for (final field in [
      'financial',
      'number',
      'party',
      'date',
      'notes',
      'cost',
      'line discount',
      'payment type',
      'quantity',
      'tax',
    ]) {
      test(
        'same ID with changed $field is rejected without ledger changes',
        () async {
          final id = await invoices.saveAndFinalizeInvoice(invoice());
          final saved = (await invoices.getInvoiceById(id))!;
          final line = saved.items!.single;
          final changed = switch (field) {
            'financial' => invoice(price: 20000).copyWith(id: id),
            'number' => saved.copyWith(invoiceNumber: 'INV-OTHER'),
            'party' => saved.copyWith(partyId: partyId + 100),
            'date' => saved.copyWith(
              invoiceDate: date.add(const Duration(days: 1)),
            ),
            'notes' => saved.copyWith(notes: 'طلب مختلف'),
            'cost' => saved.copyWith(
              items: [line.copyWith(unitCost: const Money(1))],
            ),
            'payment type' => saved.copyWith(paymentType: PaymentType.transfer),
            'quantity' => saved.copyWith(
              subtotal: const Money(20000),
              total: const Money(20000),
              remainingAmount: const Money(20000),
              items: [
                line.copyWith(quantity: 2, totalPrice: const Money(20000)),
              ],
            ),
            'tax' => saved.copyWith(
              tax: const Money(1500),
              total: const Money(11500),
              remainingAmount: const Money(11500),
              items: [
                line.copyWith(
                  taxAmount: const Money(1500),
                  totalPrice: const Money(11500),
                ),
              ],
            ),
            _ => saved.copyWith(
              discount: const Money(100),
              total: const Money(9900),
              remainingAmount: const Money(9900),
              items: [
                line.copyWith(
                  discount: const Money(100),
                  totalPrice: const Money(9900),
                ),
              ],
            ),
          };
          final before = await snapshot();
          await expectLater(
            invoices.saveAndFinalizeInvoice(changed),
            throwsA(anything),
          );
          expect(await snapshot(), before);
        },
      );
    }
    test(
      'new draft duplicate is rejected and correct draft ID can be approved',
      () async {
        final id = await invoices.createInvoice(invoice());
        final before = await snapshot();
        await expectLater(
          invoices.createInvoice(invoice(price: 20000)),
          throwsA(
            predicate((error) => error.toString().contains('رقم الفاتورة')),
          ),
        );
        expect(await snapshot(), before);
        expect(
          await invoices.saveAndFinalizeInvoice(invoice().copyWith(id: id)),
          id,
        );
        expect((await inventory.getItemById(itemId))!.stockQuantity, 19);
      },
    );
    test(
      'renaming a draft to another number is rejected before any replacement',
      () async {
        await invoices.createInvoice(invoice());
        final second = await invoices.createInvoice(invoice(number: 'INV-002'));
        final before = await snapshot();
        await expectLater(
          invoices.updateInvoice(invoice().copyWith(id: second)),
          throwsA(
            predicate((error) => error.toString().contains('رقم الفاتورة')),
          ),
        );
        expect(await snapshot(), before);
      },
    );
    test(
      'SQLite UNIQUE constraint still protects invoice_number directly',
      () async {
        await invoices.createInvoice(invoice());
        await expectLater(
          db.insert(AppTables.invoices, invoice().toMap()),
          throwsA(
            isA<DatabaseException>().having(
              (error) => error.isUniqueConstraintError(),
              'unique constraint',
              isTrue,
            ),
          ),
        );
      },
    );
    test(
      'fake repository uses the same explicit identity and content retry rules',
      () async {
        final fake = FakeInvoicesRepository();
        final original = invoice();
        final id = await fake.saveAndFinalizeInvoice(original);
        expect(
          await fake.saveAndFinalizeInvoice(original.copyWith(id: id)),
          id,
        );
        await expectLater(
          fake.saveAndFinalizeInvoice(original),
          throwsA(isA<InvoiceConflictException>()),
        );
        await expectLater(
          fake.createInvoice(original),
          throwsA(isA<InvoiceConflictException>()),
        );
        await expectLater(
          fake.saveAndFinalizeInvoice(invoice(price: 20000).copyWith(id: id)),
          throwsA(isA<InvoiceConflictException>()),
        );
        expect((await fake.getInvoices()).single.totalInt, 10000);
      },
    );
    test(
      'failure during line insertion rolls back new header and every ledger',
      () async {
        await db.execute(
          "CREATE TRIGGER fail_phase02_line BEFORE INSERT ON invoice_items "
          "BEGIN SELECT RAISE(ABORT, 'injected line failure'); END",
        );
        final before = await snapshot();
        await expectLater(
          invoices.saveAndFinalizeInvoice(invoice()),
          throwsA(anything),
        );
        expect(await snapshot(), before);
      },
    );
    test(
      'concurrent different invoices with one number produce one success and one refusal',
      () async {
        final results = await Future.wait(
          [invoice(), invoice(price: 20000)].map((value) async {
            try {
              return await invoices.saveAndFinalizeInvoice(value);
            } catch (error) {
              return error;
            }
          }),
        );
        expect(results.whereType<int>().length, 1);
        expect((await invoices.getInvoices()).length, 1);
        expect((await inventory.getItemById(itemId))!.stockQuantity, 19);
        expect((await inventory.getItemMovements(itemId)).length, 2);
      },
    );
  });

  group('DH-NEW-02', () {
    for (final type in InvoiceType.values) {
      for (final payment in PaymentType.values) {
        final paid = switch (payment) {
          PaymentType.cash => 10000,
          PaymentType.credit => 0,
          _ => 3000,
        };
        test(
          '$type $payment anonymous posting follows actual remaining debt',
          () async {
            final request = invoice(
              type: type,
              payment: payment,
              paid: paid,
              party: null,
            );
            final before = await snapshot();
            if (paid == 10000) {
              await invoices.saveAndFinalizeInvoice(request);
              expect(
                (await invoices.getInvoices()).single.remainingAmountInt,
                0,
              );
            } else {
              await expectLater(
                invoices.saveAndFinalizeInvoice(request),
                throwsA(anything),
              );
              expect(await snapshot(), before);
            }
          },
        );
        test(
          '$type $payment valid party receives correct debt direction',
          () async {
            if (payment == PaymentType.transfer &&
                (type == InvoiceType.purchase ||
                    type == InvoiceType.saleReturn)) {
              await fundTreasury(
                db,
                amount: paid,
                method: 'transfer',
                number: 'TEST-FUNDING-TRANSFER',
              );
            }
            await invoices.saveAndFinalizeInvoice(
              invoice(type: type, payment: payment, paid: paid),
            );
            final positive =
                type == InvoiceType.purchase || type == InvoiceType.saleReturn;
            final expected = (10000 - paid) * (positive ? 1 : -1);
            expect(
              (await parties.getPartyById(partyId))!.currentBalanceInt,
              expected,
            );
            expect(
              (await parties.getAccountStatement(
                partyId,
              )).currentBalance.rawUnits,
              expected,
            );
          },
        );
      }
    }
    for (final path in ['saveAndFinalize', 'finalize', 'create approved']) {
      test(
        '$path refuses unassigned debt atomically while allowing incomplete draft',
        () async {
          final request = invoice(party: null);
          final id = path == 'finalize'
              ? await invoices.createInvoice(request)
              : null;
          final before = await snapshot();
          await expectLater(switch (path) {
            'finalize' => invoices.finalizeInvoice(id!),
            'create approved' => invoices.createInvoice(
              request.copyWith(status: InvoiceStatus.approved),
            ),
            _ => invoices.saveAndFinalizeInvoice(request),
          }, throwsA(anything));
          expect(await snapshot(), before);
        },
      );
    }
    for (final path in ['saveAndFinalize', 'finalize', 'create approved']) {
      test(
        '$path nonexistent party is rejected with no partial effects',
        () async {
          int? id;
          if (path == 'finalize') {
            id = await invoices.createInvoice(invoice());
            // Simulate a legacy orphan on an isolated test database only.
            await db.execute('PRAGMA foreign_keys = OFF');
            await db.update(
              AppTables.invoices,
              {'party_id': 999999},
              where: 'id = ?',
              whereArgs: [id],
            );
            await db.execute('PRAGMA foreign_keys = ON');
          }
          final before = await snapshot();
          await expectLater(switch (path) {
            'finalize' => invoices.finalizeInvoice(id!),
            'create approved' => invoices.createInvoice(
              invoice(party: 999999, status: InvoiceStatus.approved),
            ),
            _ => invoices.saveAndFinalizeInvoice(invoice(party: 999999)),
          }, throwsA(anything));
          expect(await snapshot(), before);
        },
      );
    }
    test(
      'incomplete draft can be completed with a party and then approved once',
      () async {
        final id = await invoices.createInvoice(invoice(party: null));
        await expectLater(invoices.finalizeInvoice(id), throwsArgumentError);
        await invoices.updateInvoice(invoice().copyWith(id: id));
        await invoices.finalizeInvoice(id);
        expect((await inventory.getItemById(itemId))!.stockQuantity, 19);
        expect(
          (await parties.getPartyById(partyId))!.currentBalanceInt,
          -10000,
        );
      },
    );
    test(
      'party posting failure rolls back invoice, lines, stock, movements and treasury',
      () async {
        await db.execute(
          "CREATE TRIGGER fail_phase02_party BEFORE UPDATE OF current_balance_int ON parties "
          "BEGIN SELECT RAISE(ABORT, 'injected party posting failure'); END",
        );
        final before = await snapshot();
        await expectLater(
          invoices.saveAndFinalizeInvoice(invoice(paid: 3000)),
          throwsA(anything),
        );
        expect(await snapshot(), before);
      },
    );
    for (final payment in [
      PaymentType.cash,
      PaymentType.credit,
      PaymentType.partial,
    ]) {
      test(
        'inconsistent $payment amounts cannot be posted but can be drafted',
        () async {
          final paid = payment == PaymentType.credit
              ? 3000
              : payment == PaymentType.partial
              ? 10000
              : 0;
          final id = await invoices.createInvoice(
            invoice(payment: payment, paid: paid),
          );
          final before = await snapshot();
          await expectLater(invoices.finalizeInvoice(id), throwsA(anything));
          expect(await snapshot(), before);
        },
      );
    }
    test('fully settled bank transfer without party remains allowed', () async {
      await invoices.saveAndFinalizeInvoice(
        invoice(payment: PaymentType.transfer, paid: 10000, party: null),
      );
      expect(await treasury.getTreasuryBalance(), const Money(110000));
    });
  });
}
