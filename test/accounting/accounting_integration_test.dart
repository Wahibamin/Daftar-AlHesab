import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/reports/repositories/reports_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late SqlitePartiesRepository partiesRepo;
  late SqliteInvoicesRepository invoicesRepo;
  late SqliteVouchersRepository vouchersRepo;
  late SqliteReportsRepository reportsRepo;

  setUp(() async {
    AppDatabase.instance.configureForTesting(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    db = await AppDatabase.instance.database;
    partiesRepo = SqlitePartiesRepository();
    invoicesRepo = SqliteInvoicesRepository();
    vouchersRepo = SqliteVouchersRepository();
    reportsRepo = SqliteReportsRepository();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Future<int> createTestUnitAndItem({
    required String code,
    required String name,
    required int costPriceInt,
    required int sellingPriceInt,
    required int stockQty,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final unitId = await db.insert(AppTables.units, {
      'name': 'حبة',
      'symbol': 'حبة',
      'conversion_factor_int': 1,
      'created_at': now,
    });

    final itemId = await db.insert(AppTables.items, {
      'code': code,
      'name': name,
      'unit_id': unitId,
      'cost_price_int': costPriceInt,
      'selling_price_int': sellingPriceInt,
      'stock_quantity_int': stockQty,
      'min_alert_limit_int': 5,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    return itemId;
  }

  group('Scenario 1: Account Statement & Exact Running Balance Reconciliation', () {
    test(
      'Account statement reconciles opening balance, sale, partial payment, return, and voucher',
      () async {
        final now = DateTime.now();

        // 1. Create party with Opening Balance = -500.00 SAR (debtor 500.00 SAR)
        final partyId = await partiesRepo.insertParty(
          PartyModel(
            name: 'مؤسسة التقنية العالمية',
            phone: '0501112233',
            type: PartyType.customer,
            currentBalance: const Money(-50000), // -500.00 SAR
            openingBalance: const Money(-50000),
            createdAt: now.subtract(const Duration(days: 5)),
            updatedAt: now.subtract(const Duration(days: 5)),
          ),
        );

        final itemId = await createTestUnitAndItem(
          code: 'ITEM-01',
          name: 'طابعة باركود',
          costPriceInt: 2000, // 20.00 SAR
          sellingPriceInt: 3000, // 30.00 SAR
          stockQty: 50,
        );

        // 2. Create and finalize Sale Invoice:
        // 10 items @ 30.00 = 300.00 SAR.
        // Paid at counter = 100.00 SAR. Remaining = 200.00 SAR.
        final invNum = await invoicesRepo.generateNextInvoiceNumber(
          InvoiceType.sale,
        );
        final itemLine = InvoiceItemModel.create(
          itemId: itemId,
          quantity: 10,
          unitPrice: const Money(3000),
        );

        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: invNum,
          partyId: partyId,
          invoiceType: InvoiceType.sale,
          paymentType: PaymentType.partial,
          items: [itemLine],
          paidAmount: const Money(10000),
          invoiceDate: now.subtract(const Duration(days: 3)),
          createdAt: now.subtract(const Duration(days: 3)),
          updatedAt: now.subtract(const Duration(days: 3)),
        );
        await invoicesRepo.saveAndFinalizeInvoice(invoice);

        // Verify balance after invoice: -500 - 200 = -700.00 SAR
        var party = await partiesRepo.getPartyById(partyId);
        expect(party!.currentBalance, const Money(-70000));

        // 3. Create and finalize Sale Return:
        // 2 items @ 30.00 = 60.00 SAR.
        // Paid refund = 0 SAR (credited to customer account). Remaining = 60.00 SAR.
        final returnNum = await invoicesRepo.generateNextInvoiceNumber(
          InvoiceType.saleReturn,
        );
        final returnLine = InvoiceItemModel.create(
          itemId: itemId,
          quantity: 2,
          unitPrice: const Money(3000),
        );

        final returnInvoice = InvoiceModel.buildWithItems(
          invoiceNumber: returnNum,
          partyId: partyId,
          invoiceType: InvoiceType.saleReturn,
          paymentType: PaymentType.credit,
          items: [returnLine],
          paidAmount: Money.zero,
          invoiceDate: now.subtract(const Duration(days: 2)),
          createdAt: now.subtract(const Duration(days: 2)),
          updatedAt: now.subtract(const Duration(days: 2)),
        );
        await invoicesRepo.saveAndFinalizeInvoice(returnInvoice);

        // Verify balance after return: -700 + 60 = -640.00 SAR
        party = await partiesRepo.getPartyById(partyId);
        expect(party!.currentBalance, const Money(-64000));

        // 4. Create Receipt Voucher for 240.00 SAR
        final voucherNum = await vouchersRepo.generateNextVoucherNumber(
          VoucherType.receipt,
        );
        final voucher = VoucherModel(
          voucherNumber: voucherNum,
          voucherType: VoucherType.receipt,
          partyId: partyId,
          amount: const Money(24000), // 240.00 SAR
          paymentMethod: PaymentMethod.cash,
          statement: 'سداد دفعة من الحساب',
          voucherDate: now.subtract(const Duration(days: 1)),
          createdAt: now.subtract(const Duration(days: 1)),
        );
        await vouchersRepo.createVoucher(voucher);

        // Verify balance after voucher: -640 + 240 = -400.00 SAR
        party = await partiesRepo.getPartyById(partyId);
        expect(party!.currentBalance, const Money(-40000));

        // 5. Fetch Account Statement
        final statement = await partiesRepo.getAccountStatement(partyId);

        // Verify statement summary metadata
        expect(statement.openingBalance, const Money(-50000));
        expect(statement.currentBalance, const Money(-40000));
        expect(statement.currentBalance, party.currentBalance);

        // Verify entries breakdown:
        // Entry 0: Opening Balance (-500.00)
        // Entry 1: Sale invoice total (debit 300.00)
        // Entry 2: Sale cash payment (credit 100.00)
        // Entry 3: Sale return total (credit 60.00)
        // Entry 4: Receipt voucher (credit 240.00)
        expect(statement.entries.length, 5);

        expect(statement.entries[0].transactionType, 'رصيد افتتاحي');
        expect(statement.entries[0].debit, const Money(50000));
        expect(statement.entries[0].credit, Money.zero);
        expect(statement.entries[0].runningBalance, const Money(-50000));

        expect(statement.entries[1].transactionType, 'فاتورة مبيعات');
        expect(statement.entries[1].debit, const Money(30000));
        expect(statement.entries[1].credit, Money.zero);
        expect(statement.entries[1].runningBalance, const Money(-80000));

        expect(statement.entries[2].transactionType, 'سداد نقدي');
        expect(statement.entries[2].debit, Money.zero);
        expect(statement.entries[2].credit, const Money(10000));
        expect(statement.entries[2].runningBalance, const Money(-70000));

        expect(statement.entries[3].transactionType, 'مرتجع مبيعات');
        expect(statement.entries[3].debit, Money.zero);
        expect(statement.entries[3].credit, const Money(6000));
        expect(statement.entries[3].runningBalance, const Money(-64000));

        expect(statement.entries[4].transactionType, 'سند قبض');
        expect(statement.entries[4].debit, Money.zero);
        expect(statement.entries[4].credit, const Money(24000));
        expect(statement.entries[4].runningBalance, const Money(-40000));

        // Invariant: totalCredit - totalDebit == currentBalance
        expect(
          statement.totalCredit - statement.totalDebit,
          statement.currentBalance,
        );
      },
    );
  });

  group(
    'Scenario 2: Drafts and Cancelled Records Do Not Affect Approved Balance',
    () {
      test(
        'Drafts and cancelled invoices and vouchers are excluded from account statement and balance',
        () async {
          final now = DateTime.now();

          final partyId = await partiesRepo.insertParty(
            PartyModel(
              name: 'شركة النور',
              phone: '0554443322',
              type: PartyType.customer,
              createdAt: now,
              updatedAt: now,
            ),
          );

          final itemId = await createTestUnitAndItem(
            code: 'ITEM-02',
            name: 'شاشة نقطة بيع',
            costPriceInt: 5000,
            sellingPriceInt: 8000,
            stockQty: 20,
          );

          // 1. Create a draft invoice
          final draftNum = await invoicesRepo.generateNextInvoiceNumber(
            InvoiceType.sale,
          );
          final draftInvoice = InvoiceModel.buildWithItems(
            invoiceNumber: draftNum,
            partyId: partyId,
            invoiceType: InvoiceType.sale,
            status: InvoiceStatus.draft,
            paymentType: PaymentType.credit,
            items: [
              InvoiceItemModel.create(
                itemId: itemId,
                quantity: 2,
                unitPrice: const Money(8000),
              ),
            ],
            invoiceDate: now,
            createdAt: now,
            updatedAt: now,
          );
          await invoicesRepo.createInvoice(draftInvoice);

          // Balance should still be zero
          var party = await partiesRepo.getPartyById(partyId);
          expect(party!.currentBalance, Money.zero);

          // Statement should have zero entries
          var statement = await partiesRepo.getAccountStatement(partyId);
          expect(statement.entries, isEmpty);

          // 2. Create and finalize an approved invoice for 1000 SAR (no tax for simplicity)
          final invNum = await invoicesRepo.generateNextInvoiceNumber(
            InvoiceType.sale,
          );
          final approvedInvoice = InvoiceModel(
            invoiceNumber: invNum,
            partyId: partyId,
            invoiceType: InvoiceType.sale,
            status: InvoiceStatus.approved,
            paymentType: PaymentType.credit,
            subtotal: const Money(100000),
            discount: Money.zero,
            tax: Money.zero,
            total: const Money(100000),
            paidAmount: Money.zero,
            remainingAmount: const Money(100000),
            invoiceDate: now,
            createdAt: now,
            updatedAt: now,
            items: [
              InvoiceItemModel(
                itemId: itemId,
                quantity: 1,
                unitPrice: const Money(100000),
                taxRatePercent: 0,
                taxAmount: Money.zero,
                totalPrice: const Money(100000),
              ),
            ],
          );
          final invId = await invoicesRepo.saveAndFinalizeInvoice(
            approvedInvoice,
          );

          party = await partiesRepo.getPartyById(partyId);
          expect(party!.currentBalance, const Money(-100000));

          // 3. Cancel the approved invoice
          await invoicesRepo.cancelInvoice(invId);

          party = await partiesRepo.getPartyById(partyId);
          expect(party!.currentBalance, Money.zero); // Reverted to zero!

          // Statement should have zero active entries
          statement = await partiesRepo.getAccountStatement(partyId);
          expect(statement.entries, isEmpty);

          // 4. Create and cancel a voucher
          final vNum = await vouchersRepo.generateNextVoucherNumber(
            VoucherType.receipt,
          );
          final vId = await vouchersRepo.createVoucher(
            VoucherModel(
              voucherNumber: vNum,
              voucherType: VoucherType.receipt,
              partyId: partyId,
              amount: const Money(50000),
              paymentMethod: PaymentMethod.cash,
              voucherDate: now,
              createdAt: now,
            ),
          );

          party = await partiesRepo.getPartyById(partyId);
          expect(party!.currentBalance, const Money(50000));

          await vouchersRepo.deleteVoucher(vId);

          party = await partiesRepo.getPartyById(partyId);
          expect(party!.currentBalance, Money.zero); // Reverted to zero!

          final voucherInDb = await vouchersRepo.getVoucherById(vId);
          expect(voucherInDb!.isCancelled, isTrue); // Preserved in audit trail!

          statement = await partiesRepo.getAccountStatement(partyId);
          expect(statement.entries, isEmpty);
        },
      );
    },
  );

  group('Scenario 3: Treasury Cash Flow Integrity Without Duplication', () {
    test(
      'Cash and credit invoices and vouchers report into treasury cash flow without double counting',
      () async {
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month, 28, 23, 59, 59);

        final itemId = await createTestUnitAndItem(
          code: 'ITEM-03',
          name: 'طابعة فواتير',
          costPriceInt: 1000,
          sellingPriceInt: 2000,
          stockQty: 50,
        );

        // 1. Direct counter cash sale: total 300, paid 300
        final inv1Num = await invoicesRepo.generateNextInvoiceNumber(
          InvoiceType.sale,
        );
        await invoicesRepo.saveAndFinalizeInvoice(
          InvoiceModel(
            invoiceNumber: inv1Num,
            invoiceType: InvoiceType.sale,
            status: InvoiceStatus.approved,
            paymentType: PaymentType.cash,
            subtotal: const Money(30000),
            discount: Money.zero,
            tax: Money.zero,
            total: const Money(30000),
            paidAmount: const Money(30000), // 300 cash collected
            remainingAmount: Money.zero,
            invoiceDate: now,
            createdAt: now,
            updatedAt: now,
            items: [
              InvoiceItemModel(
                itemId: itemId,
                quantity: 1,
                unitPrice: const Money(30000),
                taxRatePercent: 0,
                taxAmount: Money.zero,
                totalPrice: const Money(30000),
              ),
            ],
          ),
        );

        // 2. Pure credit sale: total 500, paid 0 (MUST NOT enter treasury)
        final debtorId = await partiesRepo.insertParty(
          PartyModel(
            name: 'طرف اختبار الخزينة',
            phone: '0500000000',
            type: PartyType.customer,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final inv2Num = await invoicesRepo.generateNextInvoiceNumber(
          InvoiceType.sale,
        );
        await invoicesRepo.saveAndFinalizeInvoice(
          InvoiceModel(
            invoiceNumber: inv2Num,
            partyId: debtorId,
            invoiceType: InvoiceType.sale,
            status: InvoiceStatus.approved,
            paymentType: PaymentType.credit,
            subtotal: const Money(50000),
            discount: Money.zero,
            tax: Money.zero,
            total: const Money(50000),
            paidAmount: Money.zero, // 0 cash
            remainingAmount: const Money(50000),
            invoiceDate: now,
            createdAt: now,
            updatedAt: now,
            items: [
              InvoiceItemModel(
                itemId: itemId,
                quantity: 1,
                unitPrice: const Money(50000),
                taxRatePercent: 0,
                taxAmount: Money.zero,
                totalPrice: const Money(50000),
              ),
            ],
          ),
        );

        // 3. Partial sale: total 400, paid 100 at counter
        final inv3Num = await invoicesRepo.generateNextInvoiceNumber(
          InvoiceType.sale,
        );
        await invoicesRepo.saveAndFinalizeInvoice(
          InvoiceModel(
            invoiceNumber: inv3Num,
            partyId: debtorId,
            invoiceType: InvoiceType.sale,
            status: InvoiceStatus.approved,
            paymentType: PaymentType.partial,
            subtotal: const Money(40000),
            discount: Money.zero,
            tax: Money.zero,
            total: const Money(40000),
            paidAmount: const Money(10000), // 100 cash collected
            remainingAmount: const Money(30000),
            invoiceDate: now,
            createdAt: now,
            updatedAt: now,
            items: [
              InvoiceItemModel(
                itemId: itemId,
                quantity: 1,
                unitPrice: const Money(40000),
                taxRatePercent: 0,
                taxAmount: Money.zero,
                totalPrice: const Money(40000),
              ),
            ],
          ),
        );

        // 4. A later independent receipt may reference invoice 3. The reference
        // is free text: it does not identify the down payment as the same event.
        // Invoice posting itself generates no voucher (covered by regression).
        final subsequentVoucherNum = await vouchersRepo
            .generateNextVoucherNumber(VoucherType.receipt);
        await vouchersRepo.createVoucher(
          VoucherModel(
            voucherNumber: subsequentVoucherNum,
            voucherType: VoucherType.receipt,
            amount: const Money(10000),
            paymentMethod: PaymentMethod.cash,
            referenceNumber: inv3Num, // References invoice 3!
            voucherDate: now,
            createdAt: now,
          ),
        );

        // 5. Independent cash receipt voucher (250 SAR)
        final independentVoucherNum = await vouchersRepo
            .generateNextVoucherNumber(VoucherType.receipt);
        await vouchersRepo.createVoucher(
          VoucherModel(
            voucherNumber: independentVoucherNum,
            voucherType: VoucherType.receipt,
            amount: const Money(25000),
            paymentMethod: PaymentMethod.cash,
            voucherDate: now,
            createdAt: now,
          ),
        );

        // 6. Payment voucher for expenses (150 SAR)
        final expenseVoucherNum = await vouchersRepo.generateNextVoucherNumber(
          VoucherType.payment,
        );
        await vouchersRepo.createVoucher(
          VoucherModel(
            voucherNumber: expenseVoucherNum,
            voucherType: VoucherType.payment,
            purpose: VoucherPurpose.expense,
            statement: 'مصروف تشغيل اختباري',
            amount: const Money(15000),
            paymentMethod: PaymentMethod.cash,
            voucherDate: now,
            createdAt: now,
          ),
        );

        // Verify Treasury Report:
        // Cash Inflows = Invoice 1 (300) + Invoice 3 (100) + Later Receipt (100) + Independent Voucher (250) = 750.00 SAR
        // Cash Outflows = Expense Voucher (150) = 150.00 SAR
        // Net Cash Flow = 750 - 150 = 600.00 SAR
        final report = await reportsRepo.getTreasuryCashFlowReport(
          startDate: start,
          endDate: end,
        );

        expect(report.totalReceipts, const Money(75000));
        expect(report.totalPayments, const Money(15000));
        expect(report.netCashFlow, const Money(60000));
        expect(report.currentTreasuryBalance, const Money(60000));

        // Vouchers repository getTreasuryBalance() matches exactly
        final treasuryBal = await vouchersRepo.getTreasuryBalance();
        expect(treasuryBal, const Money(60000));
      },
    );
  });

  group('Scenario 4: Changing Item Cost Does Not Alter Historical Invoice COGS', () {
    test(
      'Historical COGS and P&L remain immutable when item cost price is updated',
      () async {
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month, 28, 23, 59, 59);

        // 1. Create item with cost = 10.00 SAR (1000 units), price = 25.00 SAR (2500 units)
        final itemId = await createTestUnitAndItem(
          code: 'ITEM-04',
          name: 'قارئ باركود لاسلكي',
          costPriceInt: 1000,
          sellingPriceInt: 2500,
          stockQty: 50,
        );

        // 2. Finalize Sale Invoice: 5 units @ 25.00 SAR = 125.00 SAR (no tax)
        final invNum = await invoicesRepo.generateNextInvoiceNumber(
          InvoiceType.sale,
        );
        await invoicesRepo.saveAndFinalizeInvoice(
          InvoiceModel(
            invoiceNumber: invNum,
            invoiceType: InvoiceType.sale,
            status: InvoiceStatus.approved,
            paymentType: PaymentType.cash,
            subtotal: const Money(12500),
            discount: Money.zero,
            tax: Money.zero,
            total: const Money(12500),
            paidAmount: const Money(12500),
            remainingAmount: Money.zero,
            invoiceDate: now,
            createdAt: now,
            updatedAt: now,
            items: [
              InvoiceItemModel(
                itemId: itemId,
                quantity: 5,
                unitPrice: const Money(2500),
                taxRatePercent: 0,
                taxAmount: Money.zero,
                totalPrice: const Money(12500),
              ),
            ],
          ),
        );

        // Initial P&L:
        // Revenue = 125.00 SAR
        // COGS = 5 * 10.00 = 50.00 SAR
        // Gross Profit = 75.00 SAR
        var pnl = await reportsRepo.getProfitLossReport(
          startDate: start,
          endDate: end,
        );
        expect(pnl.totalRevenues, const Money(12500));
        expect(pnl.costOfGoodsSold, const Money(5000));
        expect(pnl.grossProfit, const Money(7500));

        // 3. Update Item cost price in items table to 40.00 SAR (4000 units)
        await db.update(
          AppTables.items,
          {'cost_price_int': 4000},
          where: 'id = ?',
          whereArgs: [itemId],
        );

        // 4. Re-query P&L Report:
        // COGS MUST STILL BE 50.00 SAR! It must NOT become 5 * 40 = 200.00 SAR!
        pnl = await reportsRepo.getProfitLossReport(
          startDate: start,
          endDate: end,
        );
        expect(pnl.costOfGoodsSold, const Money(5000));
        expect(pnl.grossProfit, const Money(7500));
      },
    );
  });

  group('Scenario 5: Preventing Number Collisions on Deletion and Retries', () {
    test(
      'Generating next invoice/voucher number after cancellation does not duplicate numbers',
      () async {
        final now = DateTime.now();
        final year = now.year;

        final itemId = await createTestUnitAndItem(
          code: 'ITEM-NUM',
          name: 'صنف ترقيم',
          costPriceInt: 500,
          sellingPriceInt: 1000,
          stockQty: 50,
        );

        final num1 = await invoicesRepo.generateNextInvoiceNumber(
          InvoiceType.sale,
        );
        expect(num1, 'INV-$year-0001');

        final inv1 = InvoiceModel(
          invoiceNumber: num1,
          invoiceType: InvoiceType.sale,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.cash,
          subtotal: const Money(1000),
          discount: Money.zero,
          tax: Money.zero,
          total: const Money(1000),
          paidAmount: const Money(1000),
          remainingAmount: Money.zero,
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
          items: [
            InvoiceItemModel(
              itemId: itemId,
              quantity: 1,
              unitPrice: const Money(1000),
              taxRatePercent: 0,
              taxAmount: Money.zero,
              totalPrice: const Money(1000),
            ),
          ],
        );
        final inv1Id = await invoicesRepo.createInvoice(inv1);

        final num2 = await invoicesRepo.generateNextInvoiceNumber(
          InvoiceType.sale,
        );
        expect(num2, 'INV-$year-0002');

        final inv2 = InvoiceModel(
          invoiceNumber: num2,
          invoiceType: InvoiceType.sale,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.cash,
          subtotal: const Money(1000),
          discount: Money.zero,
          tax: Money.zero,
          total: const Money(1000),
          paidAmount: const Money(1000),
          remainingAmount: Money.zero,
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
          items: [
            InvoiceItemModel(
              itemId: itemId,
              quantity: 1,
              unitPrice: const Money(1000),
              taxRatePercent: 0,
              taxAmount: Money.zero,
              totalPrice: const Money(1000),
            ),
          ],
        );
        await invoicesRepo.createInvoice(inv2);

        // Cancel invoice 1
        await invoicesRepo.cancelInvoice(inv1Id);

        // Next generated number MUST be INV-yyyy-0003, not colliding with 0001 or 0002!
        final num3 = await invoicesRepo.generateNextInvoiceNumber(
          InvoiceType.sale,
        );
        expect(num3, 'INV-$year-0003');

        // 2. Vouchers Numbering Test
        final vNum1 = await vouchersRepo.generateNextVoucherNumber(
          VoucherType.receipt,
        );
        expect(vNum1, 'REC-$year-0001');

        final v1Id = await vouchersRepo.createVoucher(
          VoucherModel(
            voucherNumber: vNum1,
            voucherType: VoucherType.receipt,
            amount: const Money(1000),
            paymentMethod: PaymentMethod.cash,
            voucherDate: now,
            createdAt: now,
          ),
        );

        final vNum2 = await vouchersRepo.generateNextVoucherNumber(
          VoucherType.receipt,
        );
        expect(vNum2, 'REC-$year-0002');

        await vouchersRepo.createVoucher(
          VoucherModel(
            voucherNumber: vNum2,
            voucherType: VoucherType.receipt,
            amount: const Money(1000),
            paymentMethod: PaymentMethod.cash,
            voucherDate: now,
            createdAt: now,
          ),
        );

        // Soft-cancel voucher 2
        await vouchersRepo.deleteVoucher(v1Id);

        // Next voucher number MUST be REC-yyyy-0003!
        final vNum3 = await vouchersRepo.generateNextVoucherNumber(
          VoucherType.receipt,
        );
        expect(vNum3, 'REC-$year-0003');
      },
    );
  });
}
