import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/pages/item_editor_page.dart';
import 'package:m3/features/inventory/pages/items_page.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  sqfliteFfiInit();

  group('Unit and Category Management - Isolated SQLite Relational Tests', () {
    late Database db;
    late SqliteInventoryRepository repo;

    setUp(() async {
      AppDatabase.instance.configureForTesting(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      db = await AppDatabase.instance.database;
      repo = SqliteInventoryRepository();
    });

    tearDown(() async {
      await AppDatabase.instance.close();
    });

    test(
      '1. Add, edit, and persist unit across database close and reopen',
      () async {
        // Use temp file path for testing close & reopen persistence
        final tempDir = await Directory.systemTemp.createTemp('unit_test_');
        final dbPath = '${tempDir.path}/reopen_test.db';

        try {
          AppDatabase.instance.configureForTesting(
            factory: databaseFactoryFfi,
            path: dbPath,
          );
          var directRepo = SqliteInventoryRepository();

          // 1. Add unit
          final unitId = await directRepo.insertUnit(
            UnitModel(
              name: 'كرتون 24 حبة',
              symbol: 'ctn24',
              conversionFactor: 24,
              createdAt: DateTime.now(),
            ),
          );
          expect(unitId, greaterThan(0));

          // 2. Edit unit
          final addedUnit = (await directRepo.getUnits()).firstWhere(
            (u) => u.id == unitId,
          );
          final rowsUpdated = await directRepo.updateUnit(
            addedUnit.copyWith(
              name: 'كرتون ممتاز 24 حبة',
              symbol: 'ctn-sup-24',
              conversionFactor: 24,
            ),
          );
          expect(rowsUpdated, equals(1));

          // 3. Close database connection
          await AppDatabase.instance.close();

          // 4. Reopen database connection
          AppDatabase.instance.configureForTesting(
            factory: databaseFactoryFfi,
            path: dbPath,
          );
          directRepo = SqliteInventoryRepository();

          // 5. Verify data persisted completely
          final reloadedUnits = await directRepo.getUnits();
          final unitAfterReopen = reloadedUnits.firstWhere(
            (u) => u.id == unitId,
          );
          expect(unitAfterReopen.name, equals('كرتون ممتاز 24 حبة'));
          expect(unitAfterReopen.symbol, equals('ctn-sup-24'));
          expect(unitAfterReopen.conversionFactor, equals(24));
        } finally {
          await AppDatabase.instance.close();
          if (await File(dbPath).exists()) {
            await File(dbPath).delete();
          }
          await tempDir.delete(recursive: true);
        }
      },
    );

    test('2. Add and edit category in isolated SQLite', () async {
      // 1. Add category
      final catId = await repo.insertCategory(
        CategoryModel(
          name: 'مشروبات غازية منعشة',
          description: 'مشروبات بنكهات متعددة',
          createdAt: DateTime.now(),
        ),
      );
      expect(catId, greaterThan(0));

      // 2. Edit category
      final cat = (await repo.getCategories()).firstWhere((c) => c.id == catId);
      final rowsUpdated = await repo.updateCategory(
        cat.copyWith(
          name: 'عصائر ومشروبات طبيعية',
          description: 'عصائر طازجة ومعلبة',
        ),
      );
      expect(rowsUpdated, equals(1));

      final updated = (await repo.getCategories()).firstWhere(
        (c) => c.id == catId,
      );
      expect(updated.name, equals('عصائر ومشروبات طبيعية'));
      expect(updated.description, equals('عصائر طازجة ومعلبة'));
    });

    test('3. Prevent duplicate units and duplicate categories', () async {
      await repo.insertUnit(
        UnitModel(
          name: 'كيلوجرام دقيق',
          symbol: 'كجم-د',
          conversionFactor: 1,
          createdAt: DateTime.now(),
        ),
      );

      // Attempt inserting unit with same name
      expect(
        () => repo.insertUnit(
          UnitModel(
            name: 'كيلوجرام دقيق',
            symbol: 'كجم-مختلف',
            conversionFactor: 1,
            createdAt: DateTime.now(),
          ),
        ),
        throwsA(isA<StateError>()),
      );

      // Attempt inserting unit with same symbol
      expect(
        () => repo.insertUnit(
          UnitModel(
            name: 'اسم مختلف تماما',
            symbol: 'كجم-د',
            conversionFactor: 1,
            createdAt: DateTime.now(),
          ),
        ),
        throwsA(isA<StateError>()),
      );

      // Categories duplicate prevention
      await repo.insertCategory(
        CategoryModel(name: 'أجبان وألبان طازجة', createdAt: DateTime.now()),
      );

      expect(
        () => repo.insertCategory(
          CategoryModel(name: 'أجبان وألبان طازجة', createdAt: DateTime.now()),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('4. Delete unlinked unit or category succeeds', () async {
      final unitId = await repo.insertUnit(
        UnitModel(
          name: 'وحدة تجريبية فارغة',
          symbol: 'تجربة',
          conversionFactor: 1,
          createdAt: DateTime.now(),
        ),
      );

      final catId = await repo.insertCategory(
        CategoryModel(name: 'تصنيف تجريبي فارغ', createdAt: DateTime.now()),
      );

      expect(await repo.getUnitItemCount(unitId), equals(0));
      expect(await repo.getCategoryItemCount(catId), equals(0));

      final deletedUnit = await repo.deleteUnit(unitId);
      expect(deletedUnit, equals(1));

      final deletedCat = await repo.deleteCategory(catId);
      expect(deletedCat, equals(1));

      final units = await repo.getUnits();
      final cats = await repo.getCategories();
      expect(units.any((u) => u.id == unitId), isFalse);
      expect(cats.any((c) => c.id == catId), isFalse);
    });

    test(
      '5. Prevent deleting linked unit or category, and transition to archiving',
      () async {
        final unitId = await repo.insertUnit(
          UnitModel(
            name: 'حبة مرتبطة',
            symbol: 'ح-م',
            conversionFactor: 1,
            createdAt: DateTime.now(),
          ),
        );

        final catId = await repo.insertCategory(
          CategoryModel(name: 'تصنيف مرتبط', createdAt: DateTime.now()),
        );

        // Link an item to this unit and category
        final itemId = await repo.insertItem(
          ItemModel(
            code: 'LNK-001',
            name: 'صنف للاختبار المرتبط',
            unitId: unitId,
            categoryId: catId,
            costPrice: const Money(100),
            sellingPrice: const Money(150),
            stockQuantity: 10,
            minAlertLimit: 2,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        // 1. Deleting unit MUST be blocked and throw StateError
        expect(() => repo.deleteUnit(unitId), throwsA(isA<StateError>()));

        // 2. Deleting category MUST be blocked and throw StateError
        expect(() => repo.deleteCategory(catId), throwsA(isA<StateError>()));

        // 3. Transition to archiving unit
        final unitArchived = await repo.archiveUnit(unitId);
        expect(unitArchived, equals(1));

        // 4. Transition to archiving category
        final catArchived = await repo.archiveCategory(catId);
        expect(catArchived, equals(1));

        // 5. Verify both records are archived
        final reloadedUnit = (await repo.getUnits()).firstWhere(
          (u) => u.id == unitId,
        );
        expect(reloadedUnit.isArchived, isTrue);
        expect(reloadedUnit.cleanName, equals('حبة مرتبطة'));
        expect(reloadedUnit.cleanSymbol, equals('ح-م'));

        final reloadedCat = (await repo.getCategories()).firstWhere(
          (c) => c.id == catId,
        );
        expect(reloadedCat.isArchived, isTrue);
        expect(reloadedCat.cleanName, equals('تصنيف مرتبط'));

        // 6. Item retains relational link and displays cleanly
        final item = await repo.getItemById(itemId);
        expect(item?.unitId, equals(unitId));
        expect(item?.categoryId, equals(catId));
      },
    );

    test(
      '6. Safe master data seeding is idempotent and preserves existing records',
      () async {
        // 1. First seeding run
        final firstSeed = await repo.safeSeedMasterData();
        expect(firstSeed, greaterThanOrEqualTo(14)); // 8 units + 6 categories

        final unitsFirst = await repo.getUnits();
        final catsFirst = await repo.getCategories();
        expect(unitsFirst.length, greaterThanOrEqualTo(8));
        expect(catsFirst.length, greaterThanOrEqualTo(6));

        // 2. Second seeding run (idempotent, no duplicates)
        final secondSeed = await repo.safeSeedMasterData();
        expect(secondSeed, equals(0));

        final unitsSecond = await repo.getUnits();
        final catsSecond = await repo.getCategories();
        expect(unitsSecond.length, equals(unitsFirst.length));
        expect(catsSecond.length, equals(catsFirst.length));
      },
    );

    test(
      '7. Invoices, stock, and store settings are NOT affected by unit/category operations',
      () async {
        final now = DateTime.now();
        // Seed master data
        await repo.safeSeedMasterData();
        final units = await repo.getUnits();
        final categories = await repo.getCategories();

        // Create an item with initial stock
        final itemId = await repo.insertItem(
          ItemModel(
            code: 'STOCK-PROD',
            name: 'منتج مخزني أساسي',
            unitId: units.first.id!,
            categoryId: categories.first.id,
            costPrice: const Money(500),
            sellingPrice: const Money(800),
            stockQuantity: 50,
            minAlertLimit: 10,
            createdAt: now,
            updatedAt: now,
          ),
          initialStock: 50,
        );

        // Save store settings directly in app_settings table
        await db.insert(AppTables.appSettings, {
          'key': 'store_name',
          'value': 'متجر الوفاء للتجارة',
        });
        await db.insert(AppTables.appSettings, {
          'key': 'tax_number',
          'value': '300123456700003',
        });

        // Post a sales invoice directly
        final invoiceId = await db.insert(AppTables.invoices, {
          'invoice_number': 'INV-TEST-001',
          'party_id': null,
          'invoice_type': 'sale',
          'status': 'finalized',
          'payment_type': 'cash',
          'subtotal_int': 800,
          'discount_int': 0,
          'tax_int': 120,
          'total_int': 920,
          'paid_amount_int': 920,
          'remaining_amount_int': 0,
          'invoice_date': now.millisecondsSinceEpoch,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        });
        expect(invoiceId, greaterThan(0));

        await db.insert(AppTables.invoiceItems, {
          'invoice_id': invoiceId,
          'item_id': itemId,
          'quantity_int': 1,
          'unit_price_int': 800,
          'unit_cost_int': 500,
          'discount_int': 0,
          'tax_rate_percent': 15,
          'tax_amount_int': 120,
          'total_price_int': 920,
        });

        // Perform unit and category additions, edits, and archiving
        final newUnitId = await repo.insertUnit(
          UnitModel(
            name: 'دستة',
            symbol: 'دستة',
            conversionFactor: 12,
            createdAt: DateTime.now(),
          ),
        );
        await repo.archiveUnit(newUnitId);

        final newCatId = await repo.insertCategory(
          CategoryModel(name: 'تصنيف مؤقت', createdAt: DateTime.now()),
        );
        await repo.archiveCategory(newCatId);

        // Verify invoice is completely intact
        final invRows = await db.query(
          AppTables.invoices,
          where: 'id = ?',
          whereArgs: [invoiceId],
        );
        expect(invRows.length, equals(1));
        expect(invRows.first['total_int'], equals(920));
        expect(invRows.first['paid_amount_int'], equals(920));

        // Verify item stock is completely intact
        final item = await repo.getItemById(itemId);
        expect(item!.stockQuantity, equals(50));

        // Verify settings are completely intact
        final settingRows = await db.query(
          AppTables.appSettings,
          where: 'key = ?',
          whereArgs: ['store_name'],
        );
        expect(settingRows.first['value'], equals('متجر الوفاء للتجارة'));
      },
    );
  });

  group('Unit Management - UI and Dropdown Integration Tests', () {
    late FakeInventoryRepository fakeRepo;

    setUp(() async {
      fakeRepo = FakeInventoryRepository();
      await fakeRepo.safeSeedMasterData();
    });

    testWidgets(
      'ItemsPage more menu displays 5 distinct options without master data seeding option',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithRtlApp(ItemsPage(repository: fakeRepo)),
        );
        await tester.pumpAndSettle();

        // Tap more menu
        final moreMenu = find.byKey(const Key('items_page_more_menu'));
        expect(moreMenu, findsOneWidget);
        await tester.tap(moreMenu);
        await tester.pumpAndSettle();

        // Verify seeding option is removed
        expect(find.byKey(const Key('menu_safe_seed')), findsNothing);
        expect(find.text('تهيئة الوحدات والأصناف'), findsNothing);

        // Verify all 5 remaining distinct options exist
        expect(find.byKey(const Key('menu_add_category')), findsOneWidget);
        expect(find.byKey(const Key('menu_add_unit')), findsOneWidget);
        expect(find.byKey(const Key('menu_manage_categories')), findsOneWidget);
        expect(find.byKey(const Key('menu_manage_units')), findsOneWidget);
        expect(find.byKey(const Key('menu_refresh')), findsOneWidget);

        expect(find.text('إضافة تصنيف'), findsOneWidget);
        expect(find.text('إضافة وحدة قياس'), findsOneWidget);
        expect(find.text('تعديل تصنيف'), findsOneWidget);
        expect(find.text('تعديل وحدة قياس'), findsOneWidget);
        expect(find.text('تحديث القائمة'), findsOneWidget);
      },
    );

    testWidgets('Tapping Refresh menu item refreshes inventory list', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapWithRtlApp(ItemsPage(repository: fakeRepo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('items_page_more_menu')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('menu_refresh')));
      await tester.pumpAndSettle();

      expect(find.text('تم تحديث قائمة الأصناف بنجاح'), findsOneWidget);
    });

    testWidgets('Tapping Add Unit menu item opens dialog and saves new unit', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapWithRtlApp(ItemsPage(repository: fakeRepo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('items_page_more_menu')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('menu_add_unit')));
      await tester.pumpAndSettle();

      expect(find.text('إضافة وحدة قياس جديدة'), findsOneWidget);
      expect(find.byKey(const Key('add_unit_name_field')), findsOneWidget);
      expect(find.byKey(const Key('add_unit_symbol_field')), findsOneWidget);
      expect(find.byKey(const Key('add_unit_factor_field')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('add_unit_name_field')),
        'جالون سوبر',
      );
      await tester.enterText(
        find.byKey(const Key('add_unit_symbol_field')),
        'جالون',
      );
      await tester.enterText(
        find.byKey(const Key('add_unit_factor_field')),
        '4',
      );
      await tester.tap(find.byKey(const Key('save_unit_button')));
      await tester.pumpAndSettle();

      final units = await fakeRepo.getUnits();
      expect(
        units.any(
          (u) =>
              u.name == 'جالون سوبر' &&
              u.symbol == 'جالون' &&
              u.conversionFactor == 4,
        ),
        isTrue,
      );
    });

    testWidgets(
      'Tapping Manage Units opens modal bottom sheet with units and actions',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithRtlApp(ItemsPage(repository: fakeRepo)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('items_page_more_menu')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('menu_manage_units')));
        await tester.pumpAndSettle();

        expect(find.text('إدارة وحدات القياس'), findsOneWidget);
        expect(find.byKey(const Key('modal_add_unit_button')), findsOneWidget);
        expect(find.text('قطعة (حبة)'), findsWidgets);
      },
    );

    testWidgets(
      'ItemEditorPage excludes archived units from selection for new items',
      (tester) async {
        // Archive one unit
        final allUnits = await fakeRepo.getUnits();
        final ctnUnit = allUnits.firstWhere((u) => u.symbol == 'ctn');
        await fakeRepo.archiveUnit(ctnUnit.id!);

        final updatedUnits = await fakeRepo.getUnits();
        final cats = await fakeRepo.getCategories();

        // Launch ItemEditorPage for a NEW item
        await tester.pumpWidget(
          _wrapWithRtlApp(
            ItemEditorPage(
              repository: fakeRepo,
              initialCategories: cats,
              initialUnits: updatedUnits,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The archived unit should NOT be present in dropdown options
        expect(find.textContaining('[مؤرشف]'), findsNothing);
      },
    );
  });
}
