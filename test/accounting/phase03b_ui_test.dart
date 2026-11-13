import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/accounting/pages/expenses_page.dart';
import 'package:m3/features/accounting/pages/voucher_editor_page.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/accounting/widgets/treasury_accounts_card.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/pages/invoice_editor_page.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';

Widget wrap(Widget page, {double scale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Directionality(textDirection: TextDirection.rtl, child: page),
  ),
);

void main() {
  testWidgets(
    'Phase03B expense entry bank selection and cancellation affect the same single voucher',
    (tester) async {
      final repo = FakeVouchersRepository();
      await tester.pumpWidget(wrap(ExpensesPage(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مصروف جديد'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<int?>), findsNothing);
      await tester.enterText(
        find.byKey(const Key('voucher_amount')),
        '١٬٢٥٠٫٥٠',
      );
      await tester.enterText(
        find.byKey(const Key('expense_category')),
        'خدمات',
      );
      final statement = find.byKey(const Key('voucher_statement'));
      await tester.ensureVisible(statement);
      await tester.enterText(statement, 'صيانة المكتب');
      final bank = find.text(PaymentMethod.bank.arabicLabel);
      await tester.ensureVisible(bank);
      await tester.tap(bank);
      final save = find.text('حفظ وترحيل السند');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final saved = (await repo.getVouchers()).single;
      expect(saved.purpose, VoucherPurpose.expense);
      expect(saved.partyId, isNull);
      expect(saved.expenseCategory, 'خدمات');
      expect(saved.amount, const Money(125050));
      expect(saved.paymentMethod, PaymentMethod.bank);
      expect((await repo.getTreasuryBalances()).cash.balance, Money.zero);
      expect(
        (await repo.getTreasuryBalances()).bank.balance,
        const Money(-125050),
      );
      expect(await repo.getExpenseTotal(), const Money(125050));
      expect(find.text('صيانة المكتب'), findsOneWidget);
      await tester.tap(find.byTooltip('إلغاء المصروف'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'إلغاء المصروف'));
      await tester.pumpAndSettle();
      expect(await repo.getExpenseTotal(), Money.zero);
      expect((await repo.getTreasuryBalances()).bank.balance, Money.zero);
      expect(find.text('ملغى'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Phase03B expense requires statement and never displays false success',
    (tester) async {
      final repo = FakeVouchersRepository();
      await tester.pumpWidget(
        wrap(
          VoucherEditorPage(
            vouchersRepo: repo,
            initialPurpose: VoucherPurpose.expense,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('voucher_amount')), '50');
      final save = find.text('حفظ وترحيل السند');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('يرجى إدخال بيان المصروف'), findsOneWidget);
      expect(await repo.getVouchers(), isEmpty);
      expect(find.textContaining('بنجاح'), findsNothing);
    },
  );

  for (final method in [PaymentMethod.bank, PaymentMethod.cheque]) {
    testWidgets(
      'Phase03B invoice saves full settlement independently of $method',
      (tester) async {
        final repo = FakeInvoicesRepository();
        final now = DateTime.now();
        final draft = InvoiceModel.buildWithItems(
          invoiceNumber: 'UI-METHOD',
          invoiceType: InvoiceType.sale,
          paymentType: PaymentType.cash,
          paidAmount: const Money(1000),
          items: [
            InvoiceItemModel.create(
              itemId: 1,
              quantity: 1,
              unitPrice: const Money(1000),
            ),
          ],
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
        );
        final id = await repo.createInvoice(draft);
        await tester.pumpWidget(
          wrap(
            InvoiceEditorPage(
              invoicesRepo: repo,
              inventoryRepo: FakeInventoryRepository(),
              partiesRepo: FakePartiesRepository(),
              existingInvoice: await repo.getInvoiceById(id),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('invoice_payment_method')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(method.arabicLabel).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('اعتماد وترحيل'));
        await tester.pumpAndSettle();
        final saved = (await repo.getInvoiceById(id))!;
        expect(saved.isApproved, isTrue);
        expect(saved.paymentMethod, method);
        expect(saved.paymentType, PaymentType.cash);
        expect(saved.remainingAmount, Money.zero);
      },
    );
  }

  testWidgets(
    'Phase03B insufficient stock shows Arabic error and retains draft without success',
    (tester) async {
      final repo = FakeInvoicesRepository();
      final now = DateTime.now();
      repo.inMemoryItems[1] = ItemModel(
        id: 1,
        code: 'STOCK',
        name: 'صنف محدود',
        unitId: 1,
        costPrice: const Money(500),
        sellingPrice: const Money(1000),
        stockQuantity: 3,
        createdAt: now,
        updatedAt: now,
      );
      final id = await repo.createInvoice(
        InvoiceModel.buildWithItems(
          invoiceNumber: 'UI-STOCK',
          invoiceType: InvoiceType.sale,
          paymentType: PaymentType.cash,
          paidAmount: const Money(4000),
          items: [
            InvoiceItemModel.create(
              itemId: 1,
              quantity: 4,
              unitPrice: const Money(1000),
            ),
          ],
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await tester.pumpWidget(
        wrap(
          InvoiceEditorPage(
            invoicesRepo: repo,
            inventoryRepo: FakeInventoryRepository(),
            partiesRepo: FakePartiesRepository(),
            existingInvoice: await repo.getInvoiceById(id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('اعتماد وترحيل'));
      await tester.pumpAndSettle();
      expect(find.textContaining('المخزون غير كاف'), findsOneWidget);
      expect(find.textContaining('بنجاح'), findsNothing);
      expect((await repo.getInvoiceById(id))!.isDraft, isTrue);
      expect(repo.inMemoryItems[1]!.stockQuantity, 3);
    },
  );

  for (final width in [320.0, 600.0]) {
    testWidgets(
      'Phase03B expense ledger and entry fit width $width with large text',
      (tester) async {
        tester.view.physicalSize = Size(width, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          wrap(ExpensesPage(repository: FakeVouchersRepository()), scale: 1.6),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('مصروف جديد'));
        await tester.pumpAndSettle();
        final save = find.text('حفظ وترحيل السند');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        expect(save.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'Phase03B account balances remain separate at width $width and large text',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          wrap(
            const Scaffold(
              body: SingleChildScrollView(
                child: TreasuryAccountsCard(
                  snapshot: TreasurySnapshot(
                    cash: AccountCashFlow(balance: Money(123456)),
                    bank: AccountCashFlow(balance: Money(234567)),
                    transfers: AccountCashFlow(balance: Money(345678)),
                  ),
                  showFlows: true,
                ),
              ),
            ),
            scale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('balance_cash')), findsOneWidget);
        expect(find.byKey(const Key('balance_bank')), findsOneWidget);
        expect(find.byKey(const Key('balance_transfers')), findsOneWidget);
        expect(find.textContaining('1,234.56'), findsOneWidget);
        expect(find.textContaining('2,345.67'), findsOneWidget);
        expect(find.textContaining('3,456.78'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
