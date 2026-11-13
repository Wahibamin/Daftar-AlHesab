import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/pages/item_editor_page.dart';
import 'package:m3/features/inventory/pages/items_page.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/inventory/widgets/item_card.dart';
import 'package:m3/features/inventory/widgets/stock_adjustment_dialog.dart';
import 'package:m3/features/inventory/widgets/stock_badge.dart';

Widget _wrapWithRtlApp(Widget child) {
  return MaterialApp(
    theme: RafTheme.lightTheme,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

void main() {
  late FakeInventoryRepository repo;

  setUp(() async {
    repo = FakeInventoryRepository();
    await repo.seedDefaultDataIfEmpty();
  });

  group('Inventory Widgets - Visual Tests & Overflow Verification', () {
    testWidgets('StockBadge renders all stock statuses without error', (
      tester,
    ) async {
      final now = DateTime.now();

      // Normal stock item
      final normalItem = ItemModel(
        code: 'A1',
        name: 'Item 1',
        unitId: 1,
        costPrice: const Money(1000),
        sellingPrice: const Money(1500),
        stockQuantity: 50,
        minAlertLimit: 10,
        createdAt: now,
        updatedAt: now,
      );

      // Low stock item
      final lowStockItem = normalItem.copyWith(stockQuantity: 5);

      // Out of stock item
      final outOfStockItem = normalItem.copyWith(stockQuantity: 0);

      // Expired item
      final expiredItem = normalItem.copyWith(
        expiryDate: now.subtract(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        _wrapWithRtlApp(
          Scaffold(
            body: Column(
              children: [
                StockBadge(item: normalItem, unitSymbol: 'حبة'),
                StockBadge(item: lowStockItem, unitSymbol: 'حبة'),
                StockBadge(item: outOfStockItem, unitSymbol: 'حبة'),
                StockBadge(item: expiredItem, unitSymbol: 'حبة'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('50 حبة'), findsOneWidget);
      expect(find.text('منخفض (5 حبة)'), findsOneWidget);
      expect(find.text('نفد المخزون'), findsOneWidget);
      expect(find.text('منتهي الصلاحية'), findsOneWidget);
    });

    testWidgets(
      'ItemCard renders item details cleanly without overflow on narrow width',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final item = ItemModel(
          code: '6281001234567',
          name: 'أرز بسمتي هندي ممتاز طويل الحبة 10 كجم',
          unitId: 1,
          costPrice: const Money(5500), // 55.00 SAR
          sellingPrice: const Money(7500), // 75.00 SAR
          stockQuantity: 28,
          minAlertLimit: 5,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          _wrapWithRtlApp(
            Scaffold(
              body: ItemCard(
                item: item,
                unitName: 'كيس',
                categoryName: 'أغذية ومعلبات',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('أرز بسمتي هندي ممتاز طويل الحبة 10 كجم'),
          findsOneWidget,
        );
        expect(find.text('6281001234567'), findsOneWidget);
        expect(find.text('75.00'), findsOneWidget);
        expect(find.text('التكلفة: 55.00'), findsOneWidget);
        expect(find.text('28 كيس'), findsOneWidget);
      },
    );

    testWidgets('StockAdjustmentDialog updates variance in real-time', (
      tester,
    ) async {
      final item = ItemModel(
        id: 1,
        code: 'ADJ_01',
        name: 'شاي أحمر فاخر',
        unitId: 1,
        costPrice: const Money(1200), // 12.00 SAR
        sellingPrice: const Money(1800),
        stockQuantity: 50,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        _wrapWithRtlApp(
          Scaffold(
            body: StockAdjustmentDialog(item: item, repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially variance is 0
      expect(find.text('متطابق (0)'), findsOneWidget);

      // Enter physical count 45 (shortage of 5)
      final field = find.byType(TextField).first;
      await tester.enterText(field, '45');
      await tester.pumpAndSettle();

      expect(find.text('عجز (-5)'), findsOneWidget);
      // Financial impact: 5 * 12.00 = 60.00
      expect(find.text('60.00'), findsOneWidget);

      // Enter physical count 60 (surplus of 10)
      await tester.enterText(field, '60');
      await tester.pumpAndSettle();

      expect(find.text('فائض (+10)'), findsOneWidget);
      // Financial impact: 10 * 12.00 = 120.00
      expect(find.text('120.00'), findsOneWidget);
    });

    testWidgets('ItemEditorPage generates barcode and calculates margin live', (
      tester,
    ) async {
      final cats = await repo.getCategories();
      final units = await repo.getUnits();

      await tester.pumpWidget(
        _wrapWithRtlApp(
          ItemEditorPage(
            repository: repo,
            initialCategories: cats,
            initialUnits: units,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('إضافة صنف جديد'), findsOneWidget);

      // Tap generate barcode
      final generateBtn = find.text('توليد كود');
      expect(generateBtn, findsOneWidget);
      await tester.tap(generateBtn);
      await tester.pumpAndSettle();

      // Enter Cost price 50.00 and Selling price 75.00
      final costField = find.byKey(const Key('item_cost_field'));
      await tester.enterText(costField, '50.00');
      await tester.pumpAndSettle();

      final sellingField = find.byKey(const Key('item_selling_field'));
      await tester.enterText(sellingField, '75.00');
      await tester.pumpAndSettle();

      // Live margin calculation: 75.00 - 50.00 = 25.00
      expect(find.text('25.00'), findsOneWidget);
    });

    testWidgets(
      'ItemsPage lists items, searches, and filters without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844); // iPhone 14/15 size
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final item1 = ItemModel(
          code: '1001',
          name: 'زيت دوار الشمس 1.5 لتر',
          unitId: 1,
          categoryId: 3,
          costPrice: const Money(1500),
          sellingPrice: const Money(2000),
          stockQuantity: 30,
          minAlertLimit: 10,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final item2 = ItemModel(
          code: '1002',
          name: 'شامبو أطفال 400 مل',
          unitId: 1,
          categoryId: 4,
          costPrice: const Money(2200),
          sellingPrice: const Money(3200),
          stockQuantity: 4, // Low stock (< 5)
          minAlertLimit: 5,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await repo.insertItem(item1);
        await repo.insertItem(item2);
        final cats = await repo.getCategories();
        final units = await repo.getUnits();
        final items = await repo.getItems();

        await tester.pumpWidget(
          _wrapWithRtlApp(
            ItemsPage(
              repository: repo,
              initialItems: items,
              initialCategories: cats,
              initialUnits: units,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify both items rendered
        expect(find.text('زيت دوار الشمس 1.5 لتر'), findsOneWidget);
        expect(find.text('شامبو أطفال 400 مل'), findsOneWidget);

        // Search for 'زيت'
        final searchField = find.byType(TextField).first;
        await tester.enterText(searchField, 'زيت');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('زيت دوار الشمس 1.5 لتر'), findsOneWidget);
        expect(find.text('شامبو أطفال 400 مل'), findsNothing);

        // Clear search
        await tester.enterText(searchField, '');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Tap 'نواقص' filter chip
        final lowStockChip = find.text('نواقص (1)');
        expect(lowStockChip, findsOneWidget);
        await tester.tap(lowStockChip);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('شامبو أطفال 400 مل'), findsOneWidget);
        expect(find.text('زيت دوار الشمس 1.5 لتر'), findsNothing);
      },
    );

    testWidgets('ItemEditorPage can add new unit inline', (tester) async {
      final testRepo = FakeInventoryRepository();
      await testRepo.seedDefaultDataIfEmpty();

      await tester.pumpWidget(
        _wrapWithRtlApp(ItemEditorPage(repository: testRepo)),
      );
      await tester.pumpAndSettle();

      // Tap 'وحدة جديدة'
      final addUnitBtn = find.text('وحدة جديدة');
      expect(addUnitBtn, findsOneWidget);
      await tester.tap(addUnitBtn);
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('إضافة وحدة قياس جديدة'), findsOneWidget);
      final unitNameField = find.widgetWithText(TextFormField, 'اسم الوحدة *');
      final unitSymbolField = find.widgetWithText(
        TextFormField,
        'رمز / اختصار الوحدة *',
      );

      await tester.enterText(unitNameField, 'متر مكعب');
      await tester.enterText(unitSymbolField, 'م3');
      await tester.tap(find.text('إضافة'));
      await tester.pumpAndSettle();

      // Unit should now be present in repository
      final units = await testRepo.getUnits();
      expect(units.any((u) => u.name == 'متر مكعب'), isTrue);
    });

    test(
      'safeSeedMasterData adds standard units and categories safely and idempotently',
      () async {
        final testRepo = FakeInventoryRepository();
        final added = await testRepo.safeSeedMasterData();
        expect(added, greaterThan(0));

        final units = await testRepo.getUnits();
        expect(units.any((u) => u.name == 'قطعة'), isTrue);
        expect(units.any((u) => u.name == 'متر'), isTrue);
        expect(units.any((u) => u.name == 'باكت'), isTrue);

        final cats = await testRepo.getCategories();
        expect(cats.any((c) => c.name == 'عام'), isTrue);
        expect(cats.any((c) => c.name == 'خضروات وفواكه'), isTrue);

        // Running safeSeedMasterData again is idempotent (adds 0)
        final secondRun = await testRepo.safeSeedMasterData();
        expect(secondRun, equals(0));
      },
    );
  });
}
