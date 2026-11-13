import 'dart:io';
import '../../test_support/funded_treasury.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/reports/repositories/reports_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final manager = AppDatabase.instance;
  final invoices = SqliteInvoicesRepository(manager);
  final inventory = SqliteInventoryRepository(manager);
  final parties = SqlitePartiesRepository(manager);
  final vouchers = SqliteVouchersRepository(manager);
  final reports = SqliteReportsRepository(manager);
  final date = DateTime(2026, 11, 5, 12);
  late Directory directory;
  late Database db;
  late int itemId;
  late int partyId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daftar_regression_');
    manager.configureForTesting(
      factory: databaseFactoryFfi,
      path: '${directory.path}/isolated.db',
    );
    db = await manager.database;
    final unitId = await inventory.insertUnit(
      UnitModel(name: 'قطعة', symbol: 'حبة', createdAt: date),
    );
    itemId = await inventory.insertItem(
      ItemModel(
        code: 'TEST',
        name: 'منتج',
        unitId: unitId,
        costPrice: const Money(6000),
        sellingPrice: const Money(10000),
        stockQuantity: 20,
        createdAt: date,
        updatedAt: date,
      ),
    );
    partyId = await parties.insertParty(
      PartyModel(
        name: 'طرف',
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
    String number = 'INV-TEST',
    InvoiceType type = InvoiceType.sale,
    InvoiceStatus status = InvoiceStatus.draft,
    int paid = 0,
    int discount = 0,
  }) => InvoiceModel.buildWithItems(
    invoiceNumber: number,
    partyId: partyId,
    invoiceType: type,
    status: status,
    paymentType: paid == 0
        ? PaymentType.credit
        : paid == 10000 - discount
        ? PaymentType.cash
        : PaymentType.partial,
    items: [
      InvoiceItemModel.create(
        itemId: itemId,
        quantity: 1,
        unitPrice: const Money(10000),
      ),
    ],
    additionalDiscount: Money(discount),
    paidAmount: Money(paid),
    invoiceDate: date,
    createdAt: date,
    updatedAt: date,
  );

  VoucherModel voucher({
    String number = 'REC-TEST',
    int amount = 2500,
    VoucherType type = VoucherType.receipt,
    VoucherStatus status = VoucherStatus.approved,
    String? reference,
  }) => VoucherModel(
    voucherNumber: number,
    voucherType: type,
    status: status,
    partyId: partyId,
    amount: Money(amount),
    paymentMethod: PaymentMethod.cash,
    referenceNumber: reference,
    voucherDate: date,
    createdAt: date,
  );

  Future<void> reconcile() async {
    final party = (await parties.getPartyById(partyId))!;
    final statement = await parties.getAccountStatement(partyId);
    expect(statement.currentBalance, party.currentBalance);
  }

  group('FIN-01', () {
    test('cancelled payload cannot be created or approved', () async {
      final cancelled = invoice(status: InvoiceStatus.cancelled);
      await expectLater(invoices.createInvoice(cancelled), throwsStateError);
      await expectLater(
        invoices.saveAndFinalizeInvoice(cancelled),
        throwsStateError,
      );
      expect(await invoices.getInvoices(), isEmpty);
    });
    test('missing explicit ID cannot post or alter stock', () async {
      await expectLater(
        invoices.saveAndFinalizeInvoice(invoice().copyWith(id: 999999)),
        throwsStateError,
      );
      expect((await inventory.getItemById(itemId))!.stockQuantity, 20);
    });
    for (final original in InvoiceStatus.values) {
      for (final requested in InvoiceStatus.values) {
        test('draft update $original -> $requested', () async {
          final id = await invoices.createInvoice(invoice());
          if (original == InvoiceStatus.approved) {
            await invoices.finalizeInvoice(id);
          }
          if (original == InvoiceStatus.cancelled) {
            await invoices.cancelInvoice(id);
          }
          final saved = (await invoices.getInvoiceById(id))!;
          final attempt = saved.copyWith(status: requested, notes: 'تغيير');
          if (original == InvoiceStatus.draft &&
              requested == InvoiceStatus.draft) {
            await invoices.updateInvoice(attempt);
            expect((await invoices.getInvoiceById(id))!.notes, 'تغيير');
          } else {
            await expectLater(
              invoices.updateInvoice(attempt),
              throwsStateError,
            );
            expect((await invoices.getInvoiceById(id))!.status, original);
          }
          await reconcile();
        });
      }
    }
    for (final type in InvoiceType.values) {
      test('$type posting and cancellation affect ledger once', () async {
        if (type == InvoiceType.purchase || type == InvoiceType.saleReturn) {
          await fundTreasury(db);
        }
        final draft = invoice(type: type, paid: 2500);
        final id = await invoices.createInvoice(draft);
        await invoices.updateInvoice(
          draft.copyWith(id: id, notes: 'مسودة قديمة'),
        );
        await Future.wait([
          invoices.finalizeInvoice(id),
          invoices.finalizeInvoice(id),
        ]);
        // Retry the actual persisted content, including the edited draft note.
        await invoices.saveAndFinalizeInvoice(
          (await invoices.getInvoiceById(id))!,
        );
        final incoming =
            type == InvoiceType.purchase || type == InvoiceType.saleReturn;
        expect(
          (await inventory.getItemById(itemId))!.stockQuantity,
          incoming ? 21 : 19,
        );
        expect(
          (await parties.getPartyById(partyId))!.currentBalanceInt,
          incoming ? 7500 : -7500,
        );
        await reconcile();
        await Future.wait([
          invoices.cancelInvoice(id),
          invoices.cancelInvoice(id),
        ]);
        expect((await inventory.getItemById(itemId))!.stockQuantity, 20);
        expect((await parties.getPartyById(partyId))!.currentBalanceInt, 0);
        expect((await inventory.getItemMovements(itemId)).length, 3);
        await expectLater(invoices.finalizeInvoice(id), throwsStateError);
        await expectLater(
          invoices.saveAndFinalizeInvoice(draft.copyWith(id: id)),
          throwsStateError,
        );
        await reconcile();
      });
    }
    test('cancel draft has no stock or balance reversal', () async {
      final id = await invoices.createInvoice(invoice());
      await invoices.cancelInvoice(id);
      await invoices.cancelInvoice(id);
      expect((await inventory.getItemById(itemId))!.stockQuantity, 20);
      expect((await inventory.getItemMovements(itemId)).length, 1);
      await reconcile();
    });
  });

  group('FIN-02', () {
    for (final type in InvoiceType.values) {
      for (final paid in [0, 2500, 10000]) {
        test(
          '$type paid=$paid plus independent matching-reference voucher',
          () async {
            final incoming =
                type == InvoiceType.sale || type == InvoiceType.purchaseReturn;
            final funding = incoming ? 0 : 100000;
            if (!incoming) await fundTreasury(db, amount: funding);
            final id = await invoices.saveAndFinalizeInvoice(
              invoice(type: type, paid: paid),
            );
            final vId = await vouchers.createVoucher(
              voucher(
                type: incoming ? VoucherType.receipt : VoucherType.payment,
                reference: 'INV-TEST',
              ),
            );
            final expected = Money((paid + 2500) * (incoming ? 1 : -1));
            expect(
              await vouchers.getTreasuryBalance(),
              Money(funding) + expected,
            );
            final report = await reports.getTreasuryCashFlowReport(
              startDate: DateTime(2026, 11, 5),
              endDate: DateTime(2026, 11, 6),
            );
            expect(report.netCashFlow, expected);
            expect(report.currentTreasuryBalance, Money(funding) + expected);
            await reconcile();
            await vouchers.deleteVoucher(vId);
            expect(
              await vouchers.getTreasuryBalance(),
              Money(funding + paid * (incoming ? 1 : -1)),
            );
            await invoices.cancelInvoice(id);
            expect(await vouchers.getTreasuryBalance(), Money(funding));
          },
        );
      }
    }
    test(
      'invoice-only payment counted once; voucher outside period remains cumulative',
      () async {
        await invoices.saveAndFinalizeInvoice(invoice(paid: 10000));
        expect((await vouchers.getVouchers()), isEmpty);
        expect(await vouchers.getTreasuryBalance(), const Money(10000));
        await vouchers.createVoucher(
          voucher().copyWith(voucherDate: date.add(const Duration(days: 2))),
        );
        final report = await reports.getTreasuryCashFlowReport(
          startDate: DateTime(2026, 11, 5),
          endDate: DateTime(2026, 11, 6),
        );
        expect(report.netCashFlow, const Money(10000));
        expect(report.currentTreasuryBalance, const Money(12500));
      },
    );
  });

  test(
    'FIN-03 stale metadata save preserves financial balances and statement',
    () async {
      final stale = (await parties.getPartyById(partyId))!;
      await invoices.saveAndFinalizeInvoice(invoice());
      await parties.updateParty(
        stale.copyWith(
          name: 'اسم جديد',
          phone: '0555555555',
          currentBalance: const Money(99999),
          openingBalance: const Money(99999),
        ),
      );
      final party = (await parties.getPartyById(partyId))!;
      expect(party.name, 'اسم جديد');
      expect(party.currentBalanceInt, -10000);
      expect(party.openingBalanceInt, 0);
      await reconcile();
    },
  );

  test(
    'FIN-04 stale item metadata save preserves sold quantity and movement history',
    () async {
      final stale = (await inventory.getItemById(itemId))!;
      await invoices.saveAndFinalizeInvoice(invoice());
      await inventory.updateItem(
        stale.copyWith(name: 'اسم صنف جديد', sellingPrice: const Money(11000)),
      );
      expect((await inventory.getItemById(itemId))!.stockQuantity, 19);
      expect((await inventory.getItemMovements(itemId)).length, 2);
      await inventory.recordStockAdjustment(itemId: itemId, actualStock: 17);
      await inventory.updateItem(stale);
      expect((await inventory.getItemById(itemId))!.stockQuantity, 17);
      expect((await inventory.getItemMovements(itemId)).length, 3);
    },
  );

  group('FIN-05', () {
    test(
      'explicit existing tax amounts survive validation and SQLite round trip',
      () async {
        final base = invoice();
        final taxed = base.copyWith(
          tax: const Money(1500),
          total: const Money(11500),
          remainingAmount: const Money(11500),
          items: [
            base.items!.single.copyWith(
              taxRatePercent: 15,
              taxAmount: const Money(1500),
              totalPrice: const Money(11500),
            ),
          ],
        );
        final id = await invoices.saveAndFinalizeInvoice(taxed);
        final saved = (await invoices.getInvoiceById(id))!;
        expect(saved.taxInt, 1500);
        expect(saved.items!.single.taxAmountInt, 1500);
        expect(saved.items!.single.taxRatePercent, 15);
        expect(saved.totalInt, 11500);
        await reconcile();
      },
    );
    for (final discount in [0, 5000, 10000, 15000, -1]) {
      test(
        '100 invoice discount=$discount validated on every save path',
        () async {
          // copyWith deliberately bypasses builders to exercise repository validation.
          final malformed = invoice().copyWith(
            discount: Money(discount),
            total: Money(10000 - discount),
            remainingAmount: Money(10000 - discount),
          );
          if (discount >= 0 && discount <= 10000) {
            final id = await invoices.createInvoice(malformed);
            await invoices.finalizeInvoice(id);
            expect(
              (await invoices.getInvoiceById(id))!.totalInt,
              10000 - discount,
            );
          } else {
            await expectLater(
              invoices.createInvoice(malformed),
              throwsArgumentError,
            );
            await expectLater(
              invoices.saveAndFinalizeInvoice(malformed),
              throwsArgumentError,
            );
            final id = await invoices.createInvoice(invoice());
            await expectLater(
              invoices.updateInvoice(malformed.copyWith(id: id)),
              throwsArgumentError,
            );
            await db.update(
              AppTables.invoices,
              {
                'discount_int': discount,
                'total_int': 10000 - discount,
                'remaining_amount_int': 10000 - discount,
              },
              where: 'id = ?',
              whereArgs: [id],
            );
            await expectLater(
              invoices.finalizeInvoice(id),
              throwsArgumentError,
            );
            expect((await inventory.getItemById(itemId))!.stockQuantity, 20);
          }
        },
      );
    }
    for (final field in [
      'quantity',
      'price',
      'discount',
      'line total',
      'header total',
    ]) {
      test('reject inconsistent $field', () async {
        final valid = invoice();
        var line = valid.items!.single;
        line = switch (field) {
          'quantity' => line.copyWith(quantity: -1),
          'price' => line.copyWith(unitPrice: const Money(-1)),
          'discount' => line.copyWith(discount: const Money(10001)),
          'line total' => line.copyWith(totalPrice: const Money(1)),
          _ => line,
        };
        final bad = valid.copyWith(
          items: [line],
          total: field == 'header total' ? const Money(1) : valid.total,
        );
        await expectLater(
          invoices.saveAndFinalizeInvoice(bad),
          throwsArgumentError,
        );
        expect((await inventory.getItemById(itemId))!.stockQuantity, 20);
      });
    }
  });

  test(
    'FIN-06 archived debtor and creditor remain in metrics and statements',
    () async {
      await invoices.saveAndFinalizeInvoice(invoice());
      await parties.deleteParty(partyId);
      final creditor = await parties.insertParty(
        PartyModel(
          name: 'مورد مؤرشف',
          phone: '0511111111',
          type: PartyType.supplier,
          currentBalance: const Money(5000),
          openingBalance: const Money(5000),
          createdAt: date,
          updatedAt: date,
        ),
      );
      await parties.deleteParty(creditor);
      expect(await parties.getParties(), isEmpty);
      expect((await parties.getParties(includeArchived: true)).length, 2);
      final metrics = await reports.getDashboardMetrics();
      expect(metrics.totalReceivables, const Money(10000));
      expect(metrics.totalPayables, const Money(5000));
      await reconcile();
      expect(
        (await parties.getAccountStatement(creditor)).currentBalance,
        const Money(5000),
      );
    },
  );

  group('FIN-07', () {
    test(
      'voucher cancellation failure rolls back both state and party reversal',
      () async {
        final id = await vouchers.createVoucher(voucher());
        await db.execute(
          "CREATE TRIGGER reject_voucher_cancel BEFORE UPDATE OF status ON vouchers "
          "BEGIN SELECT RAISE(ABORT, 'injected cancellation failure'); END",
        );
        await expectLater(vouchers.deleteVoucher(id), throwsA(anything));
        expect((await vouchers.getVoucherById(id))!.isApproved, isTrue);
        expect((await parties.getPartyById(partyId))!.currentBalanceInt, 2500);
        expect(await vouchers.getTreasuryBalance(), const Money(2500));
        await reconcile();
      },
    );
    for (final amount in [0, -1]) {
      test('invalid voucher amount=$amount has no effect', () async {
        await expectLater(
          vouchers.createVoucher(voucher(amount: amount)),
          throwsArgumentError,
        );
        expect(await vouchers.getVouchers(), isEmpty);
        await reconcile();
      });
    }
    test('cancelled voucher cannot be posted', () async {
      await expectLater(
        vouchers.createVoucher(voucher(status: VoucherStatus.cancelled)),
        throwsStateError,
      );
      expect(await vouchers.getVouchers(), isEmpty);
      await reconcile();
    });
    for (final type in VoucherType.values) {
      test(
        '$type duplicate posting and repeated cancellation are safe',
        () async {
          if (type == VoucherType.payment) await fundTreasury(db);
          final v = voucher(type: type);
          final id = await vouchers.createVoucher(v);
          await expectLater(vouchers.createVoucher(v), throwsA(anything));
          final expected = type == VoucherType.receipt ? 2500 : -2500;
          expect(
            (await parties.getPartyById(partyId))!.currentBalanceInt,
            expected,
          );
          await reconcile();
          await Future.wait([
            vouchers.deleteVoucher(id),
            vouchers.deleteVoucher(id),
          ]);
          expect((await parties.getPartyById(partyId))!.currentBalanceInt, 0);
          expect(
            await vouchers.getTreasuryBalance(),
            type == VoucherType.payment ? const Money(100000) : Money.zero,
          );
          await expectLater(
            vouchers.createVoucher(v.copyWith(id: id)),
            throwsA(anything),
          );
          await reconcile();
        },
      );
    }
    test('missing party rolls back voucher insert', () async {
      await expectLater(
        vouchers.createVoucher(voucher().copyWith(partyId: 999999)),
        throwsA(anything),
      );
      expect(await vouchers.getVouchers(), isEmpty);
    });
  });

  group('FIN-08', () {
    test('builder preserves overpayment evidence instead of clamping it', () {
      expect(invoice(paid: 10001).remainingAmountInt, -1);
      expect(invoice(paid: 10001).isFullyPaid, isFalse);
    });
    for (final paid in [-1, 10001]) {
      test(
        'invalid payment=$paid rejected even with clamped remaining',
        () async {
          final bad = invoice().copyWith(
            paidAmount: Money(paid),
            remainingAmount: Money.zero,
          );
          await expectLater(invoices.createInvoice(bad), throwsArgumentError);
          await expectLater(
            invoices.saveAndFinalizeInvoice(bad),
            throwsArgumentError,
          );
          expect((await inventory.getItemById(itemId))!.stockQuantity, 20);
        },
      );
    }
    test('inconsistent remaining rejected', () async {
      await expectLater(
        invoices.saveAndFinalizeInvoice(
          invoice().copyWith(remainingAmount: Money.zero),
        ),
        throwsArgumentError,
      );
    });
  });

  test(
    'FIN-01 cancellation failure rolls back stock, party, movement and state',
    () async {
      final id = await invoices.saveAndFinalizeInvoice(invoice());
      await db.execute(
        "CREATE TRIGGER reject_invoice_cancel BEFORE UPDATE OF status ON invoices "
        "BEGIN SELECT RAISE(ABORT, 'injected cancellation failure'); END",
      );
      await expectLater(invoices.cancelInvoice(id), throwsA(anything));
      expect((await invoices.getInvoiceById(id))!.isApproved, isTrue);
      expect((await inventory.getItemById(itemId))!.stockQuantity, 19);
      expect((await inventory.getItemMovements(itemId)).length, 2);
      expect((await parties.getPartyById(partyId))!.currentBalanceInt, -10000);
      await reconcile();
    },
  );

  test(
    'SQLite persistence after reopen preserves ledgers, cash, and cancellations',
    () async {
      final id = await invoices.saveAndFinalizeInvoice(invoice(paid: 2500));
      await vouchers.createVoucher(voucher(reference: 'INV-TEST'));
      await manager.close();
      db = await manager.database;
      expect((await inventory.getItemById(itemId))!.stockQuantity, 19);
      expect(await vouchers.getTreasuryBalance(), const Money(5000));
      await reconcile();
      await invoices.cancelInvoice(id);
      await manager.close();
      db = await manager.database;
      await invoices.cancelInvoice(id);
      expect((await inventory.getItemById(itemId))!.stockQuantity, 20);
      expect((await inventory.getItemMovements(itemId)).length, 3);
      expect(await vouchers.getTreasuryBalance(), const Money(2500));
      await reconcile();
    },
  );
}
