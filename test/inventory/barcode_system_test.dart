import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/services/barcode_generator_service.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/core/widgets/barcode_scanner_dialog.dart';
import 'package:m3/features/inventory/data/inventory_repository.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/pages/item_editor_page.dart';
import 'package:m3/features/inventory/pages/items_page.dart';
import 'package:m3/features/inventory/services/barcode_label_service.dart';
import 'package:m3/features/inventory/widgets/barcode_label_dialog.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/pages/invoice_editor_page.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('1. Barcode Generation & SQLite DB Uniqueness Tests', () {
    late String dbPath;
    late Directory tempDir;
    late SqliteInventoryRepository repo;
    late int defaultUnitId;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('raf_barcode_db_test_');
      dbPath = p.join(tempDir.path, 'barcode_test.db');
      AppDatabase.instance.configureForTesting(
        factory: databaseFactoryFfi,
        path: dbPath,
      );
      repo = SqliteInventoryRepository(AppDatabase.instance);

      defaultUnitId = await repo.insertUnit(
        UnitModel(
          name: 'قطعة',
          symbol: 'قطعة',
          conversionFactor: 1,
          createdAt: DateTime.now(),
        ),
      );
    });

    tearDown(() async {
      await AppDatabase.instance.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'BarcodeGeneratorService generates non-empty, unique 12-digit internal barcode',
      () async {
        final code1 =
            await BarcodeGeneratorService.generateUniqueInternalBarcode(repo);
        final code2 =
            await BarcodeGeneratorService.generateUniqueInternalBarcode(repo);

        expect(code1, isNotEmpty);
        expect(code2, isNotEmpty);
        expect(code1.startsWith('200'), isTrue);
        expect(code2.startsWith('200'), isTrue);
        expect(code1, isNot(equals(code2)));
      },
    );

    test('Database enforces UNIQUE constraint on items.code', () async {
      final now = DateTime.now();
      final item1 = ItemModel(
        code: 'BARCODE_UNIQUE_123',
        name: 'منتج أ الأصلي',
        unitId: defaultUnitId,
        costPrice: const Money(1000),
        sellingPrice: const Money(1500),
        stockQuantity: 10,
        createdAt: now,
        updatedAt: now,
      );
      await repo.insertItem(item1);

      // Attempting to insert second item with identical code must throw DatabaseException
      final duplicateItem = ItemModel(
        code: 'BARCODE_UNIQUE_123',
        name: 'منتج ب المكرر',
        unitId: defaultUnitId,
        costPrice: const Money(2000),
        sellingPrice: const Money(2500),
        stockQuantity: 5,
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () async => await repo.insertItem(duplicateItem),
        throwsA(isA<DatabaseException>()),
      );
    });

    test(
      'Lookup by exact barcode returns item, and non-existent barcode returns null',
      () async {
        final now = DateTime.now();
        await repo.insertItem(
          ItemModel(
            code: '628100123456',
            name: 'شاي أخضر طبيعي',
            unitId: defaultUnitId,
            costPrice: const Money(500),
            sellingPrice: const Money(800),
            stockQuantity: 20,
            createdAt: now,
            updatedAt: now,
          ),
        );

        final found = await repo.getItemByCode('628100123456');
        expect(found, isNotNull);
        expect(found!.name, 'شاي أخضر طبيعي');

        final notFound = await repo.getItemByCode('NON_EXISTENT_999');
        expect(notFound, isNull);
      },
    );
  });

  group('2. Barcode Label PDF Generation Tests', () {
    test(
      'BarcodeLabelService generates scannable PDF without tax and matches requested copy count',
      () async {
        final now = DateTime.now();
        final item = ItemModel(
          id: 1,
          code: '200987654321',
          name: 'أرز بسمتي فاخر 5 كجم',
          unitId: 1,
          costPrice: const Money(3000),
          sellingPrice: const Money(4500),
          stockQuantity: 15,
          createdAt: now,
          updatedAt: now,
        );

        // Test standard size
        final pdfBytesSingle = await BarcodeLabelService.generateLabelsPdf(
          item: item,
          unitSymbol: 'كجم',
          size: BarcodeLabelSize.standard50x30,
          copies: 1,
          showPrice: true,
          showUnit: true,
        );
        expect(pdfBytesSingle, isNotEmpty);
        expect(pdfBytesSingle.length, greaterThan(100));

        // Test multi-copies
        final pdfBytesMultiple = await BarcodeLabelService.generateLabelsPdf(
          item: item,
          unitSymbol: 'كجم',
          size: BarcodeLabelSize.compact40x25,
          copies: 3,
          showPrice: false,
          showUnit: false,
        );
        expect(pdfBytesMultiple, isNotEmpty);
        expect(pdfBytesMultiple.length, greaterThan(100));
      },
    );
  });

  group('3. Barcode Scanning in UI Screens Tests', () {
    late FakeInventoryRepository fakeRepo;
    late FakeInvoicesRepository fakeInvoices;
    late FakePartiesRepository fakeParties;
    late UnitModel defaultUnit;

    setUp(() async {
      fakeRepo = FakeInventoryRepository();
      fakeInvoices = FakeInvoicesRepository();
      fakeParties = FakePartiesRepository();

      await fakeRepo.seedDefaultDataIfEmpty();
      final units = await fakeRepo.getUnits();
      defaultUnit = units.first;
    });

    tearDown(() {
      BarcodeScannerDialog.mockBarcodeResult = null;
    });

    Widget wrap(Widget child) {
      return MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      );
    }

    testWidgets(
      'ItemEditorPage fills barcode from scanner and generates unique code',
      (tester) async {
        tester.view.physicalSize = const Size(600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final cats = await fakeRepo.getCategories();
        final units = await fakeRepo.getUnits();

        await tester.pumpWidget(
          wrap(
            ItemEditorPage(
              repository: fakeRepo,
              initialCategories: cats,
              initialUnits: units,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify barcode field exists
        final codeField = find.byKey(const Key('item_code_field'));
        expect(codeField, findsOneWidget);

        // Tap generate barcode button
        final generateBtn = find.byKey(const Key('generate_code_button'));
        expect(generateBtn, findsOneWidget);
        await tester.tap(generateBtn);
        await tester.pumpAndSettle();

        // Simulate camera scan
        BarcodeScannerDialog.mockBarcodeResult = 'EAN13_998877665544';
        final scanBtn = find.byKey(const Key('scan_barcode_button'));
        expect(scanBtn, findsOneWidget);
        await tester.tap(scanBtn);
        await tester.pumpAndSettle();

        expect(find.text('EAN13_998877665544'), findsOneWidget);
      },
    );

    testWidgets(
      'ItemEditorPage prompts when scanned barcode belongs to existing item',
      (tester) async {
        tester.view.physicalSize = const Size(600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final now = DateTime.now();
        await fakeRepo.insertItem(
          ItemModel(
            code: 'EXISTING_BARCODE_777',
            name: 'منتج مسجل مسبقاً',
            unitId: defaultUnit.id!,
            costPrice: const Money(1000),
            sellingPrice: const Money(1200),
            stockQuantity: 8,
            createdAt: now,
            updatedAt: now,
          ),
        );

        final cats = await fakeRepo.getCategories();
        final units = await fakeRepo.getUnits();

        await tester.pumpWidget(
          wrap(
            ItemEditorPage(
              repository: fakeRepo,
              initialCategories: cats,
              initialUnits: units,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Simulate scanning existing barcode
        BarcodeScannerDialog.mockBarcodeResult = 'EXISTING_BARCODE_777';
        final scanBtn = find.byKey(const Key('scan_barcode_button'));
        await tester.tap(scanBtn);
        await tester.pumpAndSettle();

        // Dialog appears alerting about existing item
        expect(find.text('الباركود مستخدم مسبقاً'), findsOneWidget);
        expect(find.text('فتح الصنف الموجود'), findsOneWidget);

        // Dismiss dialog
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
        expect(find.text('الباركود مستخدم مسبقاً'), findsNothing);
      },
    );

    testWidgets('ItemsPage barcode search filters matching item', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      await fakeRepo.insertItem(
        ItemModel(
          code: 'SEARCH_CODE_111',
          name: 'قهوة عربية مختصة',
          unitId: defaultUnit.id!,
          costPrice: const Money(2000),
          sellingPrice: const Money(3000),
          stockQuantity: 10,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await fakeRepo.insertItem(
        ItemModel(
          code: 'SEARCH_CODE_222',
          name: 'هيل أمريكي درجة أولى',
          unitId: defaultUnit.id!,
          costPrice: const Money(1500),
          sellingPrice: const Money(2500),
          stockQuantity: 12,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final cats = await fakeRepo.getCategories();
      final units = await fakeRepo.getUnits();
      final items = await fakeRepo.getItems();

      await tester.pumpWidget(
        wrap(
          ItemsPage(
            repository: fakeRepo,
            initialItems: items,
            initialCategories: cats,
            initialUnits: units,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('قهوة عربية مختصة'), findsOneWidget);
      expect(find.text('هيل أمريكي درجة أولى'), findsOneWidget);

      // Simulate camera scan search
      BarcodeScannerDialog.mockBarcodeResult = 'SEARCH_CODE_111';
      final cameraBtn = find.byKey(const Key('items_search_camera_button'));
      expect(cameraBtn, findsOneWidget);
      await tester.tap(cameraBtn);
      await tester.pumpAndSettle();

      // List now only shows the scanned coffee item
      expect(find.text('قهوة عربية مختصة'), findsOneWidget);
      expect(find.text('هيل أمريكي درجة أولى'), findsNothing);
    });

    testWidgets(
      'InvoiceEditorPage adds item directly when scanned and handles non-existent gracefully',
      (tester) async {
        tester.view.physicalSize = const Size(600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final now = DateTime.now();
        await fakeRepo.insertItem(
          ItemModel(
            code: 'INVOICE_ITEM_CODE_555',
            name: 'سكر أبيض ناعم 10 كجم',
            unitId: defaultUnit.id!,
            costPrice: const Money(1200),
            sellingPrice: const Money(1800),
            stockQuantity: 50,
            createdAt: now,
            updatedAt: now,
          ),
        );

        await fakeParties.insertParty(
          PartyModel(
            name: 'عميل نقدي تجريبي',
            phone: '0501112233',
            type: PartyType.customer,
            currentBalance: Money.zero,
            openingBalance: Money.zero,
            creditLimit: Money.zero,
            createdAt: now,
            updatedAt: now,
          ),
        );

        await tester.pumpWidget(
          wrap(
            InvoiceEditorPage(
              invoicesRepo: fakeInvoices,
              inventoryRepo: fakeRepo,
              partiesRepo: fakeParties,
              initialType: InvoiceType.sale,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Scan barcode of sugar item
        BarcodeScannerDialog.mockBarcodeResult = 'INVOICE_ITEM_CODE_555';
        final invoiceScanBtn = find.byKey(
          const Key('invoice_scan_barcode_button'),
        );
        expect(invoiceScanBtn, findsOneWidget);
        await tester.tap(invoiceScanBtn);
        await tester.pumpAndSettle();

        // Item is now added to invoice items list
        expect(find.text('سكر أبيض ناعم 10 كجم'), findsOneWidget);

        // Scan non-existent barcode
        BarcodeScannerDialog.mockBarcodeResult = 'UNKNOWN_BARCODE_000';
        await tester.tap(invoiceScanBtn);
        await tester.pumpAndSettle();

        // Shows warning message without crashing
        expect(
          find.textContaining('لم يتم العثور على منتج بهذا الباركود'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'ItemEditorPage permits keeping existing barcode on edit, but blocks collision with another item',
      (tester) async {
        tester.view.physicalSize = const Size(600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final now = DateTime.now();
        final itemA = ItemModel(
          id: 1,
          code: 'ITEM_CODE_AAA',
          name: 'منتج أ',
          unitId: defaultUnit.id!,
          costPrice: const Money(1000),
          sellingPrice: const Money(1500),
          stockQuantity: 10,
          createdAt: now,
          updatedAt: now,
        );
        final itemB = ItemModel(
          id: 2,
          code: 'ITEM_CODE_BBB',
          name: 'منتج ب',
          unitId: defaultUnit.id!,
          costPrice: const Money(2000),
          sellingPrice: const Money(2500),
          stockQuantity: 5,
          createdAt: now,
          updatedAt: now,
        );

        await fakeRepo.insertItem(itemA);
        await fakeRepo.insertItem(itemB);

        final cats = await fakeRepo.getCategories();
        final units = await fakeRepo.getUnits();

        // Open item A in edit mode
        await tester.pumpWidget(
          wrap(
            ItemEditorPage(
              itemToEdit: itemA,
              repository: fakeRepo,
              initialCategories: cats,
              initialUnits: units,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Try saving with item B's barcode (collision)
        final codeField = find.byKey(const Key('item_code_field'));
        await tester.enterText(codeField, 'ITEM_CODE_BBB');
        await tester.pumpAndSettle();

        final saveBtn = find.byKey(const Key('appbar_save_item_button'));
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Blocked with error snackbar
        expect(
          find.textContaining('الباركود مستخدم بالفعل لصنف آخر'),
          findsOneWidget,
        );

        // Revert to item A's original barcode and save
        await tester.enterText(codeField, 'ITEM_CODE_AAA');
        await tester.pumpAndSettle();
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Success, no collision error
        expect(
          find.textContaining('الباركود مستخدم بالفعل لصنف آخر'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'BarcodeLabelDialog renders preview, toggles price and unit, and increments copies',
      (tester) async {
        tester.view.physicalSize = const Size(600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final item = ItemModel(
          id: 1,
          code: '200112233445',
          name: 'شوكولاتة بالحليب',
          unitId: defaultUnit.id!,
          costPrice: const Money(500),
          sellingPrice: const Money(750),
          stockQuantity: 100,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          wrap(
            Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => BarcodeLabelDialog.show(
                    ctx,
                    item: item,
                    unitSymbol: 'قطعة',
                    storeName: 'تموينات الوفاء',
                  ),
                  child: const Text('فتح ملصق الباركود'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('فتح ملصق الباركود'));
        await tester.pumpAndSettle();

        expect(find.text('طباعة ملصق الباركود'), findsOneWidget);
        expect(find.text('شوكولاتة بالحليب'), findsOneWidget);
        expect(find.text('200112233445'), findsOneWidget);
        expect(
          find.text('تموينات الوفاء'),
          findsNothing,
        ); // Store name hidden by default

        // Increment copies
        expect(find.text('1'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.add_circle_outline));
        await tester.pumpAndSettle();
        expect(find.text('2'), findsOneWidget);

        // Toggle store name
        await tester.tap(find.text('عرض اسم المتجر'));
        await tester.pumpAndSettle();
        expect(find.text('تموينات الوفاء'), findsOneWidget);

        // Dismiss dialog
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
        expect(find.text('طباعة ملصق الباركود'), findsNothing);
      },
    );
  });
}
