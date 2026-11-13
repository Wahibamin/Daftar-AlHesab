// Explicit physical-device QA: uses the real app database and resets its
// experimental business data after identity/signature checks outside this test.
// Run only with --dart-define=DAFTAR_DEVICE_QA=true on the approved handset.
import 'dart:convert';
import '../test/licensing/fakes.dart';
import 'dart:io';
import 'support/phase04_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:m3/main.dart' as app;
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/database/business_data_wiper.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/accounting/pages/voucher_editor_page.dart';
import 'package:m3/features/accounting/pages/vouchers_list_page.dart';
import 'package:m3/features/accounting/pages/expenses_page.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/pages/item_editor_page.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/pages/party_editor_page.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/reports/repositories/reports_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/pages/invoice_editor_page.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:m3/features/settings/pages/store_settings_page.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('DAFTAR_DEVICE_QA');
  testWidgets(
    'Phase04 real Android UI and accounting validation',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      final manager = AppDatabase.instance;
      // Explicit Debug-only business QA injection; never a distribution bypass.
      manager.configureForTesting();
      var db = await manager.database;
      const qaPackage = String.fromEnvironment(
        'DAFTAR_QA_PACKAGE',
        defaultValue: 'com.example.m3',
      );
      expect([
        'com.example.m3',
        'com.example.m3.licenseqa',
      ], contains(qaPackage));
      expect(db.path.contains('/$qaPackage/'), isTrue);
      expect(db.path.endsWith('/databases/raf_erp.db'), isTrue);
      final results = <Map<String, Object?>>[];
      void record(String name, Map<String, Object?> data) {
        final result = <String, Object?>{'check': name, ...data};
        results.add(result);
        debugPrint('PHASE04_RESULT ${jsonEncode(result)}');
      }

      final initial = <String, Object?>{
        'version': await db.getVersion(),
        for (final table in ['items', 'parties', 'invoices', 'vouchers'])
          table: (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM $table',
          )).single['n'],
      };
      expect(initial['version'], 5);
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      record('initial_database_metadata_only', initial);

      // Explicitly authorized experimental app data only. No other package or DB.
      await BusinessDataWiper().clearAllBusinessData();
      record('experimental_business_data_reset', {
        'package': 'com.example.m3',
        'version': await db.getVersion(),
      });
      final inventory = SqliteInventoryRepository();
      await inventory.insertUnit(
        UnitModel(name: 'PH04 Unit', symbol: 'QA', createdAt: DateTime.now()),
      );
      final parties = SqlitePartiesRepository();
      final invoices = SqliteInvoicesRepository();
      final vouchers = SqliteVouchersRepository();
      final reports = SqliteReportsRepository();
      await StoreSettingsManager.instance.loadSettings();

      Future<void> settle() async {
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 30),
        );
        expect(tester.takeException(), isNull);
      }

      Future<void> showPage(Widget page) async {
        await tester.pumpWidget(
          app.RafApp(
            licenseService: FakeLicenseService(),
            key: UniqueKey(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  key: const Key('qa_open'),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => page)),
                  child: const Text('Open QA page'),
                ),
              ),
            ),
          ),
        );
        await settle();
        await tester.tap(find.byKey(const Key('qa_open')));
        await settle();
      }

      Future<void> enter(Finder field, String text) async {
        await tester.ensureVisible(field);
        await tester.enterText(field, text);
        FocusManager.instance.primaryFocus?.unfocus();
        await settle();
      }

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await settle();
      }

      Future<Map<String, Object?>> snapshot() => phase04Snapshot(manager);
      Future<ProfitLossReportModel> profit() => reports.getProfitLossReport(
        startDate: DateTime(2000),
        endDate: DateTime(2100),
      );
      Future<VoucherModel> voucherUi(
        String statement,
        String amount,
        PaymentMethod method, {
        VoucherPurpose purpose = VoucherPurpose.general,
        VoucherType type = VoucherType.receipt,
        int? party,
      }) async {
        await showPage(
          VoucherEditorPage(
            initialPurpose: purpose,
            initialType: type,
            initialPartyId: party,
          ),
        );
        await enter(find.byKey(const Key('voucher_amount')), amount);
        await enter(find.byKey(const Key('voucher_statement')), statement);
        await tap(find.text(method.arabicLabel));
        await tap(find.text('حفظ وترحيل السند'));
        final rows = await vouchers.getVouchers(searchQuery: statement);
        expect(rows.length, 1);
        return rows.single;
      }

      await tester.pumpWidget(
        app.RafApp(key: UniqueKey(), licenseService: FakeLicenseService()),
      );
      await settle();
      expect(find.text('دفتر الحساب لإدارة المبيعات والمخزون'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('الرئيسية'))),
        TextDirection.rtl,
      );
      for (final label in [
        'الفواتير',
        'المخزون',
        'الأطراف',
        'التقارير',
        'الرئيسية',
      ]) {
        await tap(find.text(label));
      }
      record('root_navigation_empty_screens_rtl', {'tabs': 5, 'exceptions': 0});

      final cash = await voucherUi('PH04 Cash 100', '100', PaymentMethod.cash);
      final bank = await voucherUi('PH04 Bank 200', '200', PaymentMethod.bank);
      final transfer = await voucherUi(
        'PH04 Transfer 300',
        '300',
        PaymentMethod.transfer,
      );
      var balances = await vouchers.getTreasuryBalances();
      expect(balances.cash.balance, const Money(10000));
      expect(balances.bank.balance, const Money(20000));
      expect(balances.transfers.balance, const Money(30000));
      expect(balances.total.balance, const Money(60000));
      await showPage(VouchersListPage());
      for (final account in ['cash', 'bank', 'transfers']) {
        expect(find.byKey(Key('balance_$account')), findsOneWidget);
      }
      record('cash_bank_transfer_separate', {
        'cash': 100,
        'bank': 200,
        'transfers': 300,
        'total': 600,
        'voucher_ids': [cash.id, bank.id, transfer.id],
      });
      await vouchers.deleteVoucher(bank.id!);
      await vouchers.deleteVoucher(bank.id!);
      expect((await vouchers.getTreasuryBalances()).bank.balance, Money.zero);
      record('bank_voucher_cancel_twice', {'bank': 0, 'total': 400});

      final expense = await voucherUi(
        'PH04 Electricity',
        '50',
        PaymentMethod.cash,
        purpose: VoucherPurpose.expense,
        type: VoucherType.payment,
      );
      expect(
        (await vouchers.getTreasuryBalances()).cash.balance,
        const Money(5000),
      );
      expect((await profit()).operatingExpenses, const Money(5000));
      expect(await vouchers.getExpenseTotal(), const Money(5000));
      await showPage(ExpensesPage());
      expect(
        find.descendant(
          of: find.byType(Card),
          matching: find.text('PH04 Electricity'),
        ),
        findsOneWidget,
      );
      await enter(find.byKey(const Key('expense_search')), 'PH04 Electricity');
      expect(
        find.descendant(
          of: find.byType(Card),
          matching: find.text('PH04 Electricity'),
        ),
        findsOneWidget,
      );
      await tap(find.byTooltip('إلغاء المصروف'));
      await tap(find.widgetWithText(FilledButton, 'إلغاء المصروف'));
      await vouchers.deleteVoucher(expense.id!);
      expect(
        (await vouchers.getTreasuryBalances()).cash.balance,
        const Money(10000),
      );
      expect((await profit()).operatingExpenses, Money.zero);
      record('expense_single_post_search_and_cancel', {
        'cash_after_expense': 50,
        'expense_in_profit': 50,
        'cash_after_cancel': 100,
        'expense_after_cancel': 0,
      });

      await showPage(VoucherEditorPage(initialPurpose: VoucherPurpose.expense));
      await enter(find.byKey(const Key('voucher_amount')), '50');
      final invalidBefore = await snapshot();
      await tap(find.text('حفظ وترحيل السند'));
      expect(find.text('يرجى إدخال بيان المصروف'), findsOneWidget);
      expect(await snapshot(), invalidBefore);
      record('empty_expense_statement_rejected', {
        'unchanged': true,
        'false_success': false,
      });

      await showPage(ItemEditorPage());
      await tap(find.byKey(const Key('appbar_save_item_button')));
      expect(await inventory.getItems(), isEmpty);
      await enter(find.byKey(const Key('item_name_field')), 'PH04 Stock Item');
      await enter(find.byKey(const Key('item_code_field')), 'PH04-STOCK');
      await enter(find.byKey(const Key('item_cost_field')), '6');
      await enter(find.byKey(const Key('item_selling_field')), '10');
      final openingStock = find.byKey(const Key('item_initial_stock_field'));
      await tester.scrollUntilVisible(
        openingStock,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await enter(openingStock, '10');
      await tap(find.byKey(const Key('appbar_save_item_button')));
      final item = (await inventory.getItems(searchQuery: 'PH04-STOCK')).single;
      expect(item.stockQuantity, 10);
      record('item_ui_create_and_empty_validation', {
        'stock': 10,
        'cost': 6,
        'price': 10,
      });

      Future<int> partyUi(String name, PartyType type, String phone) async {
        await showPage(PartyEditorPage(initialType: type));
        await enter(find.byType(TextFormField).at(0), name);
        await enter(find.byType(TextFormField).at(1), phone);
        await tap(find.text('حفظ'));
        return (await parties.getParties(searchQuery: name)).single.id!;
      }

      final customer = await partyUi(
        'PH04 Customer',
        PartyType.customer,
        '0500000001',
      );
      final supplier = await partyUi(
        'PH04 Supplier',
        PartyType.supplier,
        '0500000002',
      );
      record('customer_supplier_ui_creation', {
        'customer_id': customer,
        'supplier_id': supplier,
      });

      InvoiceModel invoice(
        String number,
        InvoiceType type,
        int quantity, {
        int? party,
        PaymentType payment = PaymentType.cash,
        int? paid,
      }) {
        final now = DateTime.now();
        return InvoiceModel.buildWithItems(
          invoiceNumber: number,
          invoiceType: type,
          partyId: party,
          paymentType: payment,
          items: [
            InvoiceItemModel.create(
              itemId: item.id!,
              quantity: quantity,
              unitPrice: const Money(1000),
            ),
          ],
          paidAmount: Money(
            paid ?? (payment == PaymentType.credit ? 0 : quantity * 1000),
          ),
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
        );
      }

      Future<int> approveUi(
        InvoiceModel request, {
        bool reject = false,
        String? message,
      }) async {
        final id = await invoices.createInvoice(request);
        await showPage(
          InvoiceEditorPage(existingInvoice: await invoices.getInvoiceById(id)),
        );
        final before = await snapshot();
        await tap(find.text('اعتماد وترحيل'));
        final saved = (await invoices.getInvoiceById(id))!;
        if (reject) {
          expect(saved.isDraft, isTrue);
          expect(find.textContaining(message!), findsOneWidget);
          expect(find.textContaining('بنجاح'), findsNothing);
          expect(await snapshot(), before);
        } else {
          expect(saved.isApproved, isTrue);
        }
        return id;
      }

      final sale = await approveUi(invoice('PH04-SALE4', InvoiceType.sale, 4));
      expect((await inventory.getItemById(item.id!))!.stockQuantity, 6);
      await approveUi(
        invoice('PH04-REJECT7', InvoiceType.sale, 7),
        reject: true,
        message: 'المخزون غير كاف',
      );
      expect((await inventory.getItemById(item.id!))!.stockQuantity, 6);
      final savedSale = (await invoices.getInvoiceById(sale))!;
      final beforeRetry = await snapshot();
      await invoices.saveAndFinalizeInvoice(savedSale);
      expect(await snapshot(), beforeRetry);
      record('stock_10_sell4_reject7_retry', {
        'initial': 10,
        'after_sale': 6,
        'after_reject': 6,
        'partial_ledger': false,
        'duplicate_retry': false,
      });
      await invoices.cancelInvoice(sale);
      await invoices.cancelInvoice(sale);
      expect((await inventory.getItemById(item.id!))!.stockQuantity, 10);
      expect(
        (await vouchers.getTreasuryBalances()).cash.balance,
        const Money(10000),
      );
      record('sale_cancel_reverses_once', {'stock': 10, 'cash': 100});

      final credit = await approveUi(
        invoice(
          'PH04-CREDIT',
          InvoiceType.sale,
          3,
          party: customer,
          payment: PaymentType.credit,
        ),
      );
      expect(
        (await parties.getPartyById(customer))!.currentBalance,
        const Money(-3000),
      );
      final repayment = await voucherUi(
        'PH04 Customer repayment',
        '10',
        PaymentMethod.cash,
        party: customer,
      );
      expect(
        (await parties.getPartyById(customer))!.currentBalance,
        const Money(-2000),
      );
      final creditAfter = (await invoices.getInvoiceById(credit))!;
      record('credit_and_independent_partial_receipt', {
        'invoice_total': 30,
        'customer_debt': 20,
        'invoice_header_remaining': creditAfter.remainingAmount.rawUnits / 100,
        'allocation_note':
            'Independent receipt settles party balance, not an allocated invoice payment.',
      });
      await vouchers.deleteVoucher(repayment.id!);
      await invoices.cancelInvoice(credit);

      final partial = await approveUi(
        invoice(
          'PH04-PARTIAL',
          InvoiceType.sale,
          3,
          party: customer,
          payment: PaymentType.partial,
          paid: 1000,
        ),
      );
      expect(
        (await invoices.getInvoiceById(partial))!.remainingAmount,
        const Money(2000),
      );
      expect(
        (await parties.getPartyById(customer))!.currentBalance,
        const Money(-2000),
      );
      await invoices.cancelInvoice(partial);
      await approveUi(
        invoice(
          'PH04-WRONG-PARTY',
          InvoiceType.sale,
          1,
          party: supplier,
          payment: PaymentType.credit,
        ),
        reject: true,
        message: 'نوع الطرف غير متوافق',
      );
      record('partial_invoice_and_supplier_type_refusal', {
        'paid': 10,
        'remaining': 20,
        'incompatible_party_rejected': true,
      });

      final purchase = await approveUi(
        invoice(
          'PH04-PURCHASE',
          InvoiceType.purchase,
          2,
          party: supplier,
          payment: PaymentType.credit,
        ),
      );
      expect((await inventory.getItemById(item.id!))!.stockQuantity, 12);
      final supplierPayment = await voucherUi(
        'PH04 Supplier settlement',
        '10',
        PaymentMethod.cash,
        type: VoucherType.payment,
        party: supplier,
      );
      expect(
        (await parties.getPartyById(supplier))!.currentBalance,
        const Money(1000),
      );
      expect((await profit()).operatingExpenses, Money.zero);
      await vouchers.deleteVoucher(supplierPayment.id!);
      await invoices.cancelInvoice(purchase);
      record('purchase_supplier_payment_is_not_expense', {
        'stock_after_purchase': 12,
        'supplier_remaining': 10,
        'operating_expenses': 0,
      });

      for (final type in [InvoiceType.saleReturn, InvoiceType.purchaseReturn]) {
        final id = await approveUi(invoice('PH04-${type.name}', type, 1));
        expect(
          (await inventory.getItemById(item.id!))!.stockQuantity,
          type == InvoiceType.saleReturn ? 11 : 9,
        );
        await invoices.cancelInvoice(id);
        expect((await inventory.getItemById(item.id!))!.stockQuantity, 10);
        record('return_${type.name}_and_cancel', {
          'stock_during': type == InvoiceType.saleReturn ? 11 : 9,
          'stock_after_cancel': 10,
        });
      }

      final cheque = await voucherUi(
        'PH04 Uncleared cheque',
        '25',
        PaymentMethod.cheque,
      );
      balances = await vouchers.getTreasuryBalances();
      expect(balances.transfers.balance, const Money(32500));
      expect(balances.cash.balance, const Money(10000));
      record('cheque_policy_observed_risk', {
        'transfers_includes_uncleared_cheque': true,
        'cash_unchanged': true,
        'collection_status_represented': false,
        'available_funds_risk': true,
      });
      await vouchers.deleteVoucher(cheque.id!);
      final large = await voucherUi(
        'PH04 Large decimal',
        '١٢٣٤٥٦٧٨٫٩٠',
        PaymentMethod.bank,
      );
      expect(large.amount, const Money(1234567890));
      await vouchers.deleteVoucher(large.id!);
      await showPage(VoucherEditorPage());
      await enter(find.byKey(const Key('voucher_amount')), '0');
      final invalidAmountBefore = await snapshot();
      await tap(find.text('حفظ وترحيل السند'));
      expect(find.text('يرجى إدخال مبلغ صحيح أكبر من الصفر'), findsOneWidget);
      expect(await snapshot(), invalidAmountBefore);
      record('large_arabic_decimal_and_zero_rejection', {
        'exact_raw_units': 1234567890,
        'zero_rejected': true,
      });

      await tester.pumpWidget(
        app.RafApp(key: UniqueKey(), licenseService: FakeLicenseService()),
      );
      await settle();
      for (var round = 0; round < 2; round++) {
        for (final label in [
          'الفواتير',
          'المخزون',
          'الأطراف',
          'التقارير',
          'الرئيسية',
        ]) {
          await tester.tap(find.text(label));
          await tester.pump(const Duration(milliseconds: 30));
        }
      }
      await settle();
      await tap(find.text('التقارير'));
      await tap(find.text('حركة الخزينة'));
      expect(find.byKey(const Key('balance_cash')), findsOneWidget);
      final beforeClose = await snapshot();
      await tester.pumpWidget(const SizedBox.shrink());
      await settle();
      await manager.close();
      final reopened = await manager.database;
      db = reopened;
      expect(await reopened.getVersion(), 5);
      expect(await snapshot(), beforeClose);
      expect(
        (await reopened.rawQuery(
          'PRAGMA integrity_check',
        )).single.values.single,
        'ok',
      );
      expect(await reopened.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      record('rapid_navigation_reports_reopen_integrity', {
        'switches': 10,
        'schema': 5,
        'integrity': 'ok',
        'foreign_key_violations': 0,
        'persisted': true,
      });
      record('final_test_state', {
        'stock': (await inventory.getItemById(item.id!))!.stockQuantity,
        'cash':
            (await vouchers.getTreasuryBalances()).cash.balance.rawUnits / 100,
        'bank':
            (await vouchers.getTreasuryBalances()).bank.balance.rawUnits / 100,
        'transfers':
            (await vouchers.getTreasuryBalances()).transfers.balance.rawUnits /
            100,
        'expenses': (await vouchers.getExpenseTotal()).rawUnits / 100,
      });
      binding.reportData = {...?binding.reportData, 'phase04_checks': results};
      await tester.pumpWidget(
        app.RafApp(key: UniqueKey(), licenseService: FakeLicenseService()),
      );
      await settle();
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
