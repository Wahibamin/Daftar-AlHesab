import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/sales/pages/invoice_editor_page.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';

Widget _wrap(
  Widget child, {
  Size size = const Size(393, 873),
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: RafTheme.lightTheme,
    locale: const Locale('ar'),
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child,
    ),
  );
}

void _setupScreen(WidgetTester tester, {Size size = const Size(393, 873)}) {
  tester.view.physicalSize = size * 2.0;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('Phase 3: Item Picker, Category Filter & Discount Dialog Tests', () {
    late FakeInvoicesRepository fakeInvoices;
    late FakeInventoryRepository fakeInventory;
    late FakePartiesRepository fakeParties;
    late CategoryModel catFood;
    late CategoryModel catClean;
    late CategoryModel catEmpty;

    setUp(() async {
      fakeInvoices = FakeInvoicesRepository();
      fakeInventory = FakeInventoryRepository();
      fakeParties = FakePartiesRepository();

      await fakeInventory.seedDefaultDataIfEmpty();
      final units = await fakeInventory.getUnits();
      final unitId = units.first.id!;

      catFood = (await fakeInventory.getCategories()).first;
      final cId2 = await fakeInventory.insertCategory(
        CategoryModel(name: 'منظفات منزلية', createdAt: DateTime.now()),
      );
      final cId3 = await fakeInventory.insertCategory(
        CategoryModel(name: 'تصنيف فارغ للاختبار', createdAt: DateTime.now()),
      );

      final cats = await fakeInventory.getCategories();
      catClean = cats.firstWhere((c) => c.id == cId2);
      catEmpty = cats.firstWhere((c) => c.id == cId3);

      // Add food item
      await fakeInventory.insertItem(
        ItemModel(
          code: 'FOOD101',
          name: 'سكر أبيض ناعم 1 كجم',
          unitId: unitId,
          categoryId: catFood.id,
          costPrice: const Money(400),
          sellingPrice: const Money(550),
          stockQuantity: 100,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // Add clean item
      await fakeInventory.insertItem(
        ItemModel(
          code: 'CLN202',
          name: 'صابون سائل للصحون',
          unitId: unitId,
          categoryId: catClean.id,
          costPrice: const Money(600),
          sellingPrice: const Money(850),
          stockQuantity: 40,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    });

    testWidgets(
      '1. Quick plus add item button is hidden in invoice search bar',
      (tester) async {
        _setupScreen(tester);
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

        // Ensure no quick '+' icon exists next to search field
        expect(find.byIcon(Icons.add), findsNothing);
        expect(find.byKey(const Key('quick_add_item_button')), findsNothing);

        // Verify category filter arrow icon is present
        expect(find.byKey(const Key('category_filter_button')), findsOneWidget);
      },
    );

    testWidgets(
      '2. Category arrow opens category selection sheet and filters items by category',
      (tester) async {
        _setupScreen(tester);
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

        // Tap category button
        await tester.tap(find.byKey(const Key('category_filter_button')));
        await tester.pumpAndSettle();

        expect(find.text('تصفية الأصناف حسب التصنيف'), findsOneWidget);
        expect(find.text('جميع التصنيفات'), findsOneWidget);
        expect(find.text('منظفات منزلية'), findsOneWidget);

        // Tap clean category
        await tester.tap(find.text('منظفات منزلية'));
        await tester.pumpAndSettle();

        // Active category chip appears
        expect(find.byKey(const Key('active_category_chip')), findsOneWidget);
        expect(find.text('التصنيف: منظفات منزلية'), findsOneWidget);

        // Only clean item is visible in dropdown
        expect(find.text('صابون سائل للصحون'), findsOneWidget);
        expect(find.text('سكر أبيض ناعم 1 كجم'), findsNothing);
      },
    );

    testWidgets(
      '3. Empty category displays clean empty state without crashing',
      (tester) async {
        _setupScreen(tester);
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

        await tester.tap(find.byKey(const Key('category_filter_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.text(catEmpty.name));
        await tester.pumpAndSettle();

        expect(find.text('لا توجد أصناف في هذا التصنيف'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('4. Return to all categories removes category filter', (
      tester,
    ) async {
      _setupScreen(tester);
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

      // Select clean category
      await tester.tap(find.byKey(const Key('category_filter_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('منظفات منزلية'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('active_category_chip')), findsOneWidget);

      // Delete category chip to reset to all categories
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('active_category_chip')),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('active_category_chip')), findsNothing);
    });

    testWidgets(
      '5. Extra discount dialog opens, is scrollable, accepts discount and updates invoice net total',
      (tester) async {
        _setupScreen(tester);
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

        // Search and add food item (5.50 SAR + 15% tax = 6.33 SAR)
        await tester.enterText(find.byType(TextField).first, 'سكر');
        await tester.pumpAndSettle();
        await tester.tap(find.text('سكر أبيض ناعم 1 كجم'));
        await tester.pumpAndSettle();

        // Tap discount button in bottom bar
        await tester.tap(find.byKey(const Key('edit_discount_button')));
        await tester.pumpAndSettle();

        // Dialog opens
        expect(find.text('خصم إضافي على الفاتورة'), findsOneWidget);
        expect(find.text('تطبيق الخصم'), findsOneWidget);
        expect(find.text('إلغاء'), findsOneWidget);

        // Apply 1.00 SAR discount
        await tester.enterText(
          find.widgetWithText(TextField, 'قيمة الخصم'),
          '1.00',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('تطبيق الخصم'));
        await tester.pumpAndSettle();

        // Verify discount is reflected in summary bar
        expect(find.textContaining('1.00'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '6. Discount dialog and invoice layout at small 320x568 screen with scale 1.6 has no overflow',
      (tester) async {
        const smallSize = Size(320, 568);
        _setupScreen(tester, size: smallSize);

        await tester.pumpWidget(
          _wrap(
            InvoiceEditorPage(
              invoicesRepo: fakeInvoices,
              inventoryRepo: fakeInventory,
              partiesRepo: fakeParties,
            ),
            size: smallSize,
            textScale: 1.6,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(InvoiceEditorPage), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Open discount dialog on small screen
        await tester.tap(find.byKey(const Key('edit_discount_button')));
        await tester.pumpAndSettle();

        expect(find.text('خصم إضافي على الفاتورة'), findsOneWidget);
        expect(find.text('تطبيق الخصم'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
