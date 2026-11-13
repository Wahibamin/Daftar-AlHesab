import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/accounting/pages/voucher_editor_page.dart';
import 'package:m3/features/accounting/pages/vouchers_list_page.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/pages/invoice_editor_page.dart';
import 'package:m3/features/sales/pages/invoices_list_page.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:m3/features/sales/widgets/invoice_item_tile.dart';
import 'package:m3/features/sales/widgets/invoice_summary_bottom_bar.dart';

Widget _wrap(Widget child, {Size size = const Size(800, 1000)}) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: RafColors.primary,
        surface: RafColors.surface,
      ),
      scaffoldBackgroundColor: RafColors.surfaceSecondary,
      fontFamily: 'Roboto',
    ),
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(textDirection: TextDirection.rtl, child: child),
    ),
  );
}

void main() {
  group('InvoiceItemTile Widget Tests', () {
    testWidgets(
      'Renders item details and fires increment, decrement and remove callbacks',
      (tester) async {
        bool incremented = false;
        bool decremented = false;
        bool removed = false;

        final item = InvoiceItemModel.create(
          itemId: 1,
          quantity: 3,
          unitPrice: const Money(1500), // 15.00 SAR
        );

        await tester.pumpWidget(
          _wrap(
            InvoiceItemTile(
              item: item,
              itemName: 'أرز بسمتي الشعلان 5 كجم',
              onIncrement: () => incremented = true,
              onDecrement: () => decremented = true,
              onRemove: () => removed = true,
            ),
          ),
        );

        // Verify item name rendered
        expect(find.text('أرز بسمتي الشعلان 5 كجم'), findsOneWidget);
        // Verify quantity rendered
        expect(find.text('3'), findsOneWidget);
        // Verify line total rendered (3 * 15 = 45.00 SAR)
        expect(find.textContaining('45.00'), findsOneWidget);

        // Tap increment
        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
        expect(incremented, isTrue);

        // Tap decrement
        await tester.tap(find.byIcon(Icons.remove));
        await tester.pump();
        expect(decremented, isTrue);

        // Tap remove
        await tester.tap(find.byIcon(Icons.delete_outline_rounded));
        await tester.pump();
        expect(removed, isTrue);
      },
    );

    testWidgets('Does not overflow on narrow mobile screen (360px width)', (
      tester,
    ) async {
      final item = InvoiceItemModel.create(
        itemId: 1,
        quantity: 12,
        unitPrice: const Money(125000), // 1,250.00 SAR
        discount: const Money(5000),
      );

      await tester.pumpWidget(
        _wrap(
          InvoiceItemTile(
            item: item,
            itemName: 'شاشة تلفزيون سامسونج ذكية فائقة الوضوح 65 بوصة 4K',
            onIncrement: () {},
            onDecrement: () {},
            onRemove: () {},
          ),
          size: const Size(360, 640),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(InvoiceItemTile), findsOneWidget);
    });
  });

  group('InvoiceSummaryBottomBar Widget Tests', () {
    testWidgets('Renders subtotal, discount, net total and fires actions', (
      tester,
    ) async {
      bool finalized = false;
      bool savedDraft = false;

      await tester.pumpWidget(
        _wrap(
          InvoiceSummaryBottomBar(
            subtotal: const Money(10000), // 100.00 SAR
            discount: const Money(1000), // 10.00 SAR
            netTotal: const Money(9000), // 90.00 SAR
            itemCount: 2,
            onFinalize: () => finalized = true,
            onSaveDraft: () => savedDraft = true,
          ),
        ),
      );

      expect(find.textContaining('100.00'), findsOneWidget);
      expect(find.textContaining('10.00'), findsOneWidget);
      expect(find.textContaining('90.00'), findsOneWidget);
      expect(find.text('2 بنود'), findsOneWidget);

      await tester.tap(find.text('مسودة'));
      await tester.pump();
      expect(savedDraft, isTrue);

      await tester.tap(find.text('اعتماد وترحيل'));
      await tester.pump();
      expect(finalized, isTrue);
    });
  });

  group('InvoiceEditorPage & InvoicesListPage Integration UI Tests', () {
    late FakeInvoicesRepository fakeInvoices;
    late FakeInventoryRepository fakeInventory;
    late FakePartiesRepository fakeParties;

    setUp(() async {
      fakeInvoices = FakeInvoicesRepository();
      fakeInventory = FakeInventoryRepository();
      fakeParties = FakePartiesRepository();

      await fakeInventory.seedDefaultDataIfEmpty();
      await fakeParties.seedDefaultDataIfEmpty();
      await fakeInventory.insertItem(
        ItemModel(
          code: 'MILK01',
          name: 'حليب المراعي 1 لتر',
          unitId: 1,
          costPrice: const Money(400),
          sellingPrice: const Money(600),
          stockQuantity: 50,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    });

    testWidgets('InvoiceEditorPage loads, allows adding item and saves draft', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          InvoiceEditorPage(
            invoicesRepo: fakeInvoices,
            inventoryRepo: fakeInventory,
            partiesRepo: fakeParties,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify initial state
      expect(find.text('نقطة البيع والفوترة'), findsOneWidget);
      expect(find.text('الفاتورة فارغة'), findsOneWidget);

      // Search for item by name in search bar
      await tester.enterText(find.byType(TextField).first, 'حليب');
      await tester.pumpAndSettle();

      // Find an item from search results and tap it
      final firstItemFinder = find.byType(ListTile).first;
      expect(firstItemFinder, findsOneWidget);
      await tester.tap(firstItemFinder);
      await tester.pumpAndSettle();

      // Item should now be present in the invoice list
      expect(find.byType(InvoiceItemTile), findsOneWidget);

      // Tap "مسودة" to save as draft
      await tester.tap(find.text('مسودة'));
      await tester.pumpAndSettle();

      // Verify draft invoice was created in fake repository
      final invoices = await fakeInvoices.getInvoices();
      expect(invoices.isNotEmpty, isTrue);
      expect(invoices.first.status, InvoiceStatus.draft);
    });

    testWidgets('InvoicesListPage renders tabs and displays seeded invoices', (
      tester,
    ) async {
      await fakeInvoices.seedDefaultInvoicesIfEmpty();

      await tester.pumpWidget(
        _wrap(
          InvoicesListPage(
            invoicesRepo: fakeInvoices,
            inventoryRepo: fakeInventory,
            partiesRepo: fakeParties,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header and tabs
      expect(find.text('سجل الفواتير والمبيعات'), findsOneWidget);
      expect(find.text('المبيعات'), findsOneWidget);
      expect(find.text('المشتريات'), findsOneWidget);
      expect(find.text('المرتجعات'), findsOneWidget);

      // Verify seeded invoice card
      expect(find.textContaining('INV-'), findsOneWidget);
      expect(find.text('معتمدة'), findsOneWidget);
    });
  });

  group('VoucherEditorPage & VouchersListPage Integration UI Tests', () {
    late FakeVouchersRepository fakeVouchers;
    late FakePartiesRepository fakeParties;

    setUp(() async {
      fakeVouchers = FakeVouchersRepository();
      fakeParties = FakePartiesRepository();
      await fakeParties.seedDefaultDataIfEmpty();
    });

    testWidgets(
      'VoucherEditorPage allows typing amount with thousands formatting and saves',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            VoucherEditorPage(
              vouchersRepo: fakeVouchers,
              partiesRepo: fakeParties,
              initialType: VoucherType.receipt,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('سند قبض مالي'), findsOneWidget);

        // Enter amount "1500" into amount text field
        final amountField = find.byType(TextField).first;
        await tester.enterText(amountField, '1500');
        await tester.pumpAndSettle();

        // Thousands separator formatter formats it to "1,500"
        expect(find.text('1,500'), findsOneWidget);

        // Scroll to save button and tap
        final saveBtnFinder = find.text('حفظ وترحيل السند');
        await tester.ensureVisible(saveBtnFinder);
        await tester.tap(saveBtnFinder);
        await tester.pumpAndSettle();

        // Verify voucher created in repository
        final vouchers = await fakeVouchers.getVouchers();
        expect(vouchers.isNotEmpty, isTrue);
        expect(vouchers.first.amount, const Money(150000)); // 1,500.00 SAR
        expect(vouchers.first.isReceipt, isTrue);
      },
    );

    testWidgets('VouchersListPage displays treasury balance and vouchers', (
      tester,
    ) async {
      await fakeVouchers.seedDefaultVouchersIfEmpty();

      await tester.pumpWidget(
        _wrap(
          VouchersListPage(
            vouchersRepo: fakeVouchers,
            partiesRepo: fakeParties,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('سجل السندات المالية والخزينة'), findsOneWidget);
      expect(find.text('الأرصدة المتاحة حسب الحساب'), findsOneWidget);
      expect(find.textContaining('1,000.00'), findsWidgets);
    });
  });
}
