// QA-only entrypoint. Production Release always builds lib/main.dart.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/database/business_data_wiper.dart';
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
import 'package:sqflite/sqflite.dart';
import 'license_android_test.dart' as license;
import 'phase04_device_test.dart' as screens;

void main() {
  license.main();
  screens.main();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Final native SQLite arithmetic, policies, rollback and volume',
    (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final manager = AppDatabase.instance;
      final db = await manager.database;
      expect(db.path.contains('/com.example.m3.licenseqa/'), true);
      final evidence = <Map<String, Object?>>[];
      void record(String id, Map<String, Object?> data) {
        evidence.add({'check': id, ...data});
        debugPrint('FINAL_QA_RESULT ${jsonEncode(evidence.last)}');
        binding.reportData = {
          ...?binding.reportData,
          'native_accounting': evidence,
        };
      }

      await BusinessDataWiper().clearAllBusinessData();
      final inv = SqliteInventoryRepository();
      final parties = SqlitePartiesRepository();
      final invoices = SqliteInvoicesRepository();
      final vouchers = SqliteVouchersRepository();
      final reports = SqliteReportsRepository();
      final now = DateTime.now();
      final unit = await inv.insertUnit(
        UnitModel(name: 'Final QA', symbol: 'FQ', createdAt: now),
      );
      Future<int> item(String code, int stock, int cost, int price) =>
          inv.insertItem(
            ItemModel(
              code: code,
              name: 'سلعة اختبار $code',
              unitId: unit,
              stockQuantity: stock,
              costPrice: Money(cost),
              sellingPrice: Money(price),
              createdAt: now,
              updatedAt: now,
            ),
            initialStock: stock,
          );
      final a = await item('QA-A', 10, 600, 1000);
      final b = await item('QA-B', 5, 2000, 3000);
      final customer = await parties.insertParty(
        PartyModel(
          name: 'QA Customer',
          phone: '',
          type: PartyType.customer,
          currentBalance: const Money(-1000),
          openingBalance: const Money(-1000),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final supplier = await parties.insertParty(
        PartyModel(
          name: 'QA Supplier',
          phone: '',
          type: PartyType.supplier,
          createdAt: now,
          updatedAt: now,
        ),
      );
      InvoiceModel request(
        String number,
        InvoiceType type,
        List<InvoiceItemModel> lines, {
        int? party,
        PaymentType payment = PaymentType.credit,
        int paid = 0,
        int discount = 0,
      }) => InvoiceModel.buildWithItems(
        invoiceNumber: number,
        invoiceType: type,
        partyId: party,
        paymentType: payment,
        paymentMethod: PaymentMethod.bank,
        paidAmount: Money(paid),
        additionalDiscount: Money(discount),
        items: lines,
        invoiceDate: now,
        createdAt: now,
        updatedAt: now,
      );
      Future<int> voucher(
        String number,
        int amount,
        PaymentMethod method, {
        int? party,
        VoucherType type = VoucherType.receipt,
        VoucherPurpose purpose = VoucherPurpose.general,
      }) => vouchers.createVoucher(
        VoucherModel(
          voucherNumber: number,
          amount: Money(amount),
          paymentMethod: method,
          partyId: party,
          voucherType: type,
          purpose: purpose,
          statement: 'Final acceptance $number',
          voucherDate: now,
          createdAt: now,
        ),
      );
      Future<ProfitLossReportModel> pnl() => reports.getProfitLossReport(
        startDate: DateTime(2000),
        endDate: DateTime(2100),
      );
      final saleRequest = request(
        'QA-MULTI',
        InvoiceType.sale,
        [
          InvoiceItemModel.create(
            itemId: a,
            quantity: 3,
            unitPrice: const Money(1000),
          ),
          InvoiceItemModel.create(
            itemId: b,
            quantity: 2,
            unitPrice: const Money(3000),
          ),
        ],
        party: customer,
        payment: PaymentType.partial,
        paid: 3000,
        discount: 1000,
      );
      final sale = await invoices.saveAndFinalizeInvoice(saleRequest);
      expect((await inv.getItemById(a))!.stockQuantity, 7);
      expect((await inv.getItemById(b))!.stockQuantity, 3);
      expect(
        (await parties.getPartyById(customer))!.currentBalance,
        const Money(-6000),
      );
      final receipt = await voucher(
        'QA-RECEIPT',
        2000,
        PaymentMethod.cash,
        party: customer,
      );
      await voucher(
        'QA-EXPENSE',
        500,
        PaymentMethod.cash,
        type: VoucherType.payment,
        purpose: VoucherPurpose.expense,
      );
      var profit = await pnl();
      expect(profit.totalRevenues, const Money(8000));
      expect(profit.costOfGoodsSold, const Money(5800));
      expect(profit.grossProfit, const Money(2200));
      expect(profit.operatingExpenses, const Money(500));
      expect(profit.netProfit, const Money(1700));
      var balances = await vouchers.getTreasuryBalances();
      expect(balances.cash.balance, const Money(1500));
      expect(balances.bank.balance, const Money(3000));
      final valuation = await reports.getInventoryValuationReport();
      expect(valuation.totalCostValuation, const Money(10200));
      expect(valuation.totalRetailValuation, const Money(16000));
      record('multi_item_discount_profit_inventory', {
        'gross': 90,
        'discount': 10,
        'sales': 80,
        'cogs': 58,
        'gross_profit': 22,
        'expense': 5,
        'net_profit': 17,
        'stock_a': 7,
        'stock_b': 3,
        'stock_cost': 102,
        'cash': 15,
        'bank': 30,
      });
      final statement = await parties.getAccountStatement(customer);
      expect(statement.currentBalance, const Money(-4000));
      expect(statement.entries.last.runningBalance, const Money(-4000));
      expect(
        (await invoices.getInvoiceById(sale))!.remainingAmount,
        const Money(5000),
      );
      record('independent_receipt_allocation_policy', {
        'opening_debt': 10,
        'invoice_remaining': 50,
        'independent_receipt': 20,
        'customer_debt': 40,
        'invoice_header_still': 50,
        'explicit_allocation_supported': false,
      });
      final cheque = await voucher('QA-UNCLEARED', 2500, PaymentMethod.cheque);
      expect(
        (await vouchers.getTreasuryBalances()).transfers.balance,
        const Money(2500),
      );
      record('uncleared_cheque_policy', {
        'transfers_increased': 25,
        'clearance_state_supported': false,
      });
      await vouchers.deleteVoucher(cheque);
      final overdraft = await voucher(
        'QA-OVERDRAFT',
        2000,
        PaymentMethod.cash,
        type: VoucherType.payment,
        purpose: VoucherPurpose.expense,
      );
      expect(
        (await vouchers.getTreasuryBalances()).cash.balance,
        const Money(-500),
      );
      expect((await pnl()).netProfit, const Money(-300));
      record('negative_cash_policy', {
        'cash': -5,
        'expenses': 25,
        'net_profit': -3,
        'negative_balance_allowed': true,
      });
      await vouchers.deleteVoucher(overdraft);
      final purchase = await invoices.saveAndFinalizeInvoice(
        request('QA-PURCHASE', InvoiceType.purchase, [
          InvoiceItemModel.create(
            itemId: a,
            quantity: 2,
            unitPrice: const Money(800),
          ),
        ], party: supplier),
      );
      expect((await inv.getItemById(a))!.stockQuantity, 9);
      expect(
        (await parties.getPartyById(supplier))!.currentBalance,
        const Money(1600),
      );
      final saleReturn = await invoices.saveAndFinalizeInvoice(
        request('QA-SALE-RETURN', InvoiceType.saleReturn, [
          InvoiceItemModel.create(
            itemId: a,
            quantity: 1,
            unitPrice: const Money(1000),
          ),
        ], party: customer),
      );
      final purchaseReturn = await invoices.saveAndFinalizeInvoice(
        request('QA-PURCHASE-RETURN', InvoiceType.purchaseReturn, [
          InvoiceItemModel.create(
            itemId: a,
            quantity: 1,
            unitPrice: const Money(800),
          ),
        ], party: supplier),
      );
      expect((await inv.getItemById(a))!.stockQuantity, 9);
      expect(
        (await parties.getPartyById(supplier))!.currentBalance,
        const Money(800),
      );
      expect((await pnl()).netProfit, const Money(1300));
      record('purchase_returns_and_profit', {
        'supplier_owed': 8,
        'stock_a': 9,
        'net_profit': 13,
      });
      await invoices.cancelInvoice(purchaseReturn);
      await invoices.cancelInvoice(saleReturn);
      await invoices.cancelInvoice(purchase);
      expect((await inv.getItemById(a))!.stockQuantity, 7);
      expect((await pnl()).netProfit, const Money(1700));
      final beforeRetry = await db.query(AppTables.inventoryMovements);
      await Future.wait([
        invoices.saveAndFinalizeInvoice(saleRequest.copyWith(id: sale)),
        invoices.saveAndFinalizeInvoice(saleRequest.copyWith(id: sale)),
      ]);
      expect(await db.query(AppTables.inventoryMovements), beforeRetry);
      record('concurrent_approved_retries', {'duplicate_movements': 0});
      await db.execute(
        "CREATE TRIGGER qa_abort BEFORE INSERT ON inventory_movements WHEN NEW.reference_type = 'invoice' BEGIN SELECT RAISE(ABORT, 'QA injected ledger failure'); END",
      );
      try {
        await expectLater(
          invoices.saveAndFinalizeInvoice(
            request(
              'QA-ABORT',
              InvoiceType.sale,
              [
                InvoiceItemModel.create(
                  itemId: a,
                  quantity: 1,
                  unitPrice: const Money(1000),
                ),
              ],
              payment: PaymentType.cash,
              paid: 1000,
            ),
          ),
          throwsA(isA<DatabaseException>()),
        );
      } finally {
        await db.execute('DROP TRIGGER qa_abort');
      }
      expect(await invoices.getInvoiceByNumber('QA-ABORT'), isNull);
      expect((await inv.getItemById(a))!.stockQuantity, 7);
      expect(await db.query(AppTables.inventoryMovements), beforeRetry);
      record('native_mid_transaction_abort_rolls_back', {
        'invoice_absent': true,
        'stock_unchanged': true,
        'ledger_unchanged': true,
      });
      final zero = await item('QA-ZERO', 5, 0, 1000);
      await invoices.saveAndFinalizeInvoice(
        request(
          'QA-ZERO-SALE',
          InvoiceType.sale,
          [
            InvoiceItemModel.create(
              itemId: zero,
              quantity: 1,
              unitPrice: const Money(1000),
            ),
          ],
          payment: PaymentType.cash,
          paid: 1000,
        ),
      );
      final historical = await pnl();
      await inv.updateItem(
        (await inv.getItemById(zero))!.copyWith(costPrice: const Money(500)),
      );
      expect((await pnl()).costOfGoodsSold, historical.costOfGoodsSold);
      record('zero_cost_history_regression', {
        'historical_cogs_unchanged': true,
      });
      final watch = Stopwatch()..start();
      final bulkIds = <int>[];
      for (var i = 0; i < 500; i++) {
        bulkIds.add(
          await item(
            'QA-BULK-${i.toString().padLeft(4, '0')}',
            i == 0 ? 500 : 10,
            500,
            1000,
          ),
        );
      }
      final insertMs = watch.elapsedMilliseconds;
      watch.reset();
      for (var i = 0; i < 120; i++) {
        await invoices.saveAndFinalizeInvoice(
          request(
            'QA-BULK-INV-$i',
            InvoiceType.sale,
            [
              InvoiceItemModel.create(
                itemId: bulkIds.first,
                quantity: 1,
                unitPrice: const Money(1000),
              ),
            ],
            payment: PaymentType.cash,
            paid: 1000,
          ),
        );
      }
      final invoiceMs = watch.elapsedMilliseconds;
      watch.reset();
      expect(
        (await inv.getItems(searchQuery: 'QA-BULK-0499', limit: 30)).length,
        1,
      );
      final searchMs = watch.elapsedMilliseconds;
      watch.stop();
      expect((await inv.getItemById(bulkIds.first))!.stockQuantity, 380);
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      final duplicates = await db.rawQuery(
        "SELECT reference_id,item_id,movement_type,COUNT(*) n FROM inventory_movements WHERE reference_type='invoice' GROUP BY reference_id,item_id,movement_type HAVING COUNT(*)>1",
      );
      expect(duplicates, isEmpty);
      record('native_volume_integrity', {
        'inserted_items': 500,
        'inserted_invoices': 120,
        'item_insert_ms': insertMs,
        'invoice_insert_ms': invoiceMs,
        'search_ms': searchMs,
        'bulk_item_stock': 380,
        'integrity': 'ok',
        'foreign_key_violations': 0,
        'duplicate_invoice_movements': 0,
      });
      record('native_final_snapshot', {
        'items': (await db.rawQuery(
          'SELECT COUNT(*) n FROM items',
        )).single['n'],
        'invoices': (await db.rawQuery(
          'SELECT COUNT(*) n FROM invoices',
        )).single['n'],
        'receipt_id': receipt,
        'cash_raw':
            (await vouchers.getTreasuryBalances()).cash.balance.rawUnits,
        'bank_raw':
            (await vouchers.getTreasuryBalances()).bank.balance.rawUnits,
      });
      await manager.close();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Text('Final QA complete; synthetic data retained'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
