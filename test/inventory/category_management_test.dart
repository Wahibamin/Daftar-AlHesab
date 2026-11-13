import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/inventory/models/item_model.dart';
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

  group('Category Management - SQLite Direct Relational Tests', () {
    late Database db;
    late SqliteInventoryRepository repo;
    late int testUnitId;

    setUp(() async {
      AppDatabase.instance.configureForTesting(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      db = await AppDatabase.instance.database;
      repo = SqliteInventoryRepository();

      // Setup a valid unit
      testUnitId = await db.insert(AppTables.units, {
        'name': 'قطعة',
        'symbol': 'حبة',
        'conversion_factor_int': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await AppDatabase.instance.close();
    });

    test('1. Insert and retrieve category in SQLite', () async {
      final id = await repo.insertCategory(
        CategoryModel(
          name: 'ألبان وأجبان',
          description: 'منتجات الحليب الطازجة والمبسترة',
          createdAt: DateTime.now(),
        ),
      );

      expect(id, greaterThan(0));

      final categories = await repo.getCategories();
      expect(
        categories.any((c) => c.id == id && c.name == 'ألبان وأجبان'),
        isTrue,
      );
    });

    test('2. Edit category name and description in SQLite', () async {
      final id = await repo.insertCategory(
        CategoryModel(
          name: 'مخبوزات قديم',
          description: 'وصف قديم',
          createdAt: DateTime.now(),
        ),
      );

      final created = (await repo.getCategories()).firstWhere(
        (c) => c.id == id,
      );
      final updatedCat = created.copyWith(
        name: 'مخبوزات طازجة وحلويات',
        description: 'كافة أنواع المخبوزات والحلويات الشرقية',
      );

      final rowsAffected = await repo.updateCategory(updatedCat);
      expect(rowsAffected, equals(1));

      final reloaded = (await repo.getCategories()).firstWhere(
        (c) => c.id == id,
      );
      expect(reloaded.name, equals('مخبوزات طازجة وحلويات'));
      expect(
        reloaded.description,
        equals('كافة أنواع المخبوزات والحلويات الشرقية'),
      );
    });

    test('3. Delete category when NO items are linked', () async {
      final id = await repo.insertCategory(
        CategoryModel(
          name: 'تصنيف فارغ قابل للحذف',
          description: 'بدون أصناف',
          createdAt: DateTime.now(),
        ),
      );

      final itemCount = await repo.getCategoryItemCount(id);
      expect(itemCount, equals(0));

      final deleted = await repo.deleteCategory(id);
      expect(deleted, equals(1));

      final categories = await repo.getCategories();
      expect(categories.any((c) => c.id == id), isFalse);
    });

    test('4. Block deletion when items ARE linked to category', () async {
      final catId = await repo.insertCategory(
        CategoryModel(
          name: 'مشروبات غازية',
          description: 'مشروبات متنوعة',
          createdAt: DateTime.now(),
        ),
      );

      // Link an item to this category
      await repo.insertItem(
        ItemModel(
          code: 'BEV-001',
          name: 'عصير برتقال طبيعي',
          unitId: testUnitId,
          categoryId: catId,
          costPrice: const Money(200),
          sellingPrice: const Money(350),
          stockQuantity: 20,
          minAlertLimit: 5,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final itemCount = await repo.getCategoryItemCount(catId);
      expect(itemCount, equals(1));

      // Attempting to delete MUST throw StateError to protect SQLite integrity
      expect(() => repo.deleteCategory(catId), throwsA(isA<StateError>()));

      // Verify category still exists in SQLite
      final categories = await repo.getCategories();
      expect(categories.any((c) => c.id == catId), isTrue);
    });

    test(
      '5. Archive and Unarchive category preserving linked items and historical data',
      () async {
        final catId = await repo.insertCategory(
          CategoryModel(
            name: 'شيبس وتسالي',
            description: 'وجبات خفيفة',
            createdAt: DateTime.now(),
          ),
        );

        final itemId = await repo.insertItem(
          ItemModel(
            code: 'SNACK-001',
            name: 'بطاطس مقرمشة',
            unitId: testUnitId,
            categoryId: catId,
            costPrice: const Money(150),
            sellingPrice: const Money(250),
            stockQuantity: 15,
            minAlertLimit: 3,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        // Archive category
        await repo.archiveCategory(catId);

        var reloaded = (await repo.getCategories()).firstWhere(
          (c) => c.id == catId,
        );
        expect(reloaded.isArchived, isTrue);
        expect(reloaded.cleanDescription, equals('وجبات خفيفة'));

        // Verify item still links to this category
        var item = await repo.getItemById(itemId);
        expect(item?.categoryId, equals(catId));

        // Unarchive category
        await repo.archiveCategory(catId, unarchive: true);

        reloaded = (await repo.getCategories()).firstWhere(
          (c) => c.id == catId,
        );
        expect(reloaded.isArchived, isFalse);
        expect(reloaded.description, equals('وجبات خفيفة'));
      },
    );
  });

  group('Category Management - ItemsPage UI Widget Tests', () {
    late FakeInventoryRepository fakeRepo;

    setUp(() async {
      fakeRepo = FakeInventoryRepository();
      await fakeRepo.seedDefaultDataIfEmpty();
    });

    testWidgets(
      'More menu contains Category Management options and opens dialog',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithRtlApp(ItemsPage(repository: fakeRepo)),
        );
        await tester.pumpAndSettle();

        // Find more menu button
        final moreMenu = find.byKey(const Key('items_page_more_menu'));
        expect(moreMenu, findsOneWidget);

        await tester.tap(moreMenu);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('menu_add_category')), findsOneWidget);
        expect(find.byKey(const Key('menu_manage_categories')), findsOneWidget);

        // Tap Add Category menu item
        await tester.tap(find.byKey(const Key('menu_add_category')));
        await tester.pumpAndSettle();

        // Verify Add Category Dialog opened
        expect(find.text('إضافة تصنيف جديد'), findsOneWidget);
        expect(
          find.byKey(const Key('add_category_name_field')),
          findsOneWidget,
        );

        // Enter category name and save
        await tester.enterText(
          find.byKey(const Key('add_category_name_field')),
          'عناية شخصية',
        );
        await tester.enterText(
          find.byKey(const Key('add_category_desc_field')),
          'شامبو وصابون',
        );
        await tester.tap(find.byKey(const Key('save_category_button')));
        await tester.pumpAndSettle();

        // Verify category exists in repo and UI chip
        final cats = await fakeRepo.getCategories();
        expect(cats.any((c) => c.name == 'عناية شخصية'), isTrue);
        expect(find.text('عناية شخصية'), findsWidgets);
      },
    );

    testWidgets('Manage Categories modal displays categories and item count', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapWithRtlApp(ItemsPage(repository: fakeRepo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('items_page_more_menu')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('menu_manage_categories')));
      await tester.pumpAndSettle();

      // Verify bottom sheet title and add button
      expect(find.text('إدارة وتعديل التصنيفات'), findsOneWidget);
      expect(
        find.byKey(const Key('modal_add_category_button')),
        findsOneWidget,
      );

      // Categories from seed are shown
      expect(find.text('عام'), findsWidgets);
    });
  });
}
