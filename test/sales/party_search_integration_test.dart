import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/pages/invoice_editor_page.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: RafTheme.lightTheme,
    locale: const Locale('ar'),
    home: child,
  );
}

void main() {
  group('Phase 2 UI: Party Search & Selection Widget Tests', () {
    late FakeInvoicesRepository fakeInvoices;
    late FakeInventoryRepository fakeInventory;
    late FakePartiesRepository fakeParties;

    setUp(() async {
      fakeInvoices = FakeInvoicesRepository();
      fakeInventory = FakeInventoryRepository();
      fakeParties = FakePartiesRepository();

      await fakeInventory.seedDefaultDataIfEmpty();
      final units = await fakeInventory.getUnits();

      await fakeInventory.insertItem(
        ItemModel(
          code: 'PROD1',
          name: 'منتج تجريبي 1',
          unitId: units.first.id!,
          costPrice: const Money(1000),
          sellingPrice: const Money(1500),
          stockQuantity: 50,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await fakeParties.insertParty(
        PartyModel(
          name: 'مؤسسة الرياض التجارية',
          phone: '0501112233',
          type: PartyType.customer,
          currentBalance: Money.zero,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await fakeParties.insertParty(
        PartyModel(
          name: 'سوبرماركت النور والبركة',
          phone: '0554445566',
          type: PartyType.customer,
          currentBalance: Money.zero,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await fakeParties.insertParty(
        PartyModel(
          name: 'شركة الألبان الوطنية',
          phone: '0567778899',
          type: PartyType.supplier,
          currentBalance: Money.zero,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    });

    testWidgets('1. Search for existing customer by name in sales invoice', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          InvoiceEditorPage(
            invoicesRepo: fakeInvoices,
            inventoryRepo: fakeInventory,
            partiesRepo: fakeParties,
            initialType: InvoiceType.sale,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check default cash customer tile
      expect(find.text('عميل نقدي عام (افتراضي)'), findsOneWidget);

      // Open party modal
      await tester.tap(find.byKey(const Key('invoice_party_selector')));
      await tester.pumpAndSettle();

      expect(find.text('اختيار العميل'), findsOneWidget);
      expect(find.byKey(const Key('party_search_field')), findsOneWidget);

      // Search matching customer
      await tester.enterText(
        find.byKey(const Key('party_search_field')),
        'الرياض',
      );
      await tester.pumpAndSettle();

      expect(find.text('مؤسسة الرياض التجارية'), findsOneWidget);
      expect(find.text('سوبرماركت النور والبركة'), findsNothing);

      // Select customer
      await tester.tap(find.text('مؤسسة الرياض التجارية'));
      await tester.pumpAndSettle();

      // Check header updated
      expect(find.text('مؤسسة الرياض التجارية'), findsOneWidget);
    });

    testWidgets('2. Search for existing supplier by name in purchase invoice', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          InvoiceEditorPage(
            invoicesRepo: fakeInvoices,
            inventoryRepo: fakeInventory,
            partiesRepo: fakeParties,
            initialType: InvoiceType.purchase,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('مورد عام (نقدي)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('invoice_party_selector')));
      await tester.pumpAndSettle();

      expect(find.text('اختيار المورد'), findsOneWidget);

      // Supplier exists, customers do not show
      expect(find.text('شركة الألبان الوطنية'), findsOneWidget);
      expect(find.text('مؤسسة الرياض التجارية'), findsNothing);
      expect(find.text('سوبرماركت النور والبركة'), findsNothing);

      // Select supplier
      await tester.tap(find.text('شركة الألبان الوطنية'));
      await tester.pumpAndSettle();

      expect(find.text('شركة الألبان الوطنية'), findsOneWidget);
    });

    testWidgets(
      '3. Filter parties strictly by invoice type (Customer vs Supplier)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            InvoiceEditorPage(
              invoicesRepo: fakeInvoices,
              inventoryRepo: fakeInventory,
              partiesRepo: fakeParties,
              initialType: InvoiceType.sale,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('invoice_party_selector')));
        await tester.pumpAndSettle();

        // In sales invoice, customers must be visible, suppliers must NOT be visible
        expect(find.text('مؤسسة الرياض التجارية'), findsOneWidget);
        expect(find.text('سوبرماركت النور والبركة'), findsOneWidget);
        expect(find.text('شركة الألبان الوطنية'), findsNothing);
      },
    );

    testWidgets('4. Search for non-existent party shows clean empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          InvoiceEditorPage(
            invoicesRepo: fakeInvoices,
            inventoryRepo: fakeInventory,
            partiesRepo: fakeParties,
            initialType: InvoiceType.sale,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('invoice_party_selector')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('party_search_field')),
        'اسم غير موجود إطلاقاً',
      );
      await tester.pumpAndSettle();

      expect(find.text('لا توجد نتائج مطابقة للبحث'), findsOneWidget);
    });

    testWidgets(
      '5. Selecting default cash party returns to general cash customer',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            InvoiceEditorPage(
              invoicesRepo: fakeInvoices,
              inventoryRepo: fakeInventory,
              partiesRepo: fakeParties,
              initialType: InvoiceType.sale,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Select customer first
        await tester.tap(find.byKey(const Key('invoice_party_selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('مؤسسة الرياض التجارية'));
        await tester.pumpAndSettle();
        expect(find.text('مؤسسة الرياض التجارية'), findsOneWidget);

        // Reopen and select general cash
        await tester.tap(find.byKey(const Key('invoice_party_selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('party_default_tile')));
        await tester.pumpAndSettle();

        expect(find.text('عميل نقدي عام (افتراضي)'), findsOneWidget);
      },
    );
  });

  group('Phase 2 SQLite: Live SQLite Party Search & Integrity Tests', () {
    sqfliteFfiInit();

    late Database db;
    late String tempDbPath;
    late SqliteInvoicesRepository invoicesRepo;
    late SqlitePartiesRepository partiesRepo;
    late int customerId1;
    late int supplierId1;

    setUp(() async {
      final tempDir = await Directory.systemTemp.createTemp(
        'raf_party_sqlite_',
      );
      tempDbPath = '${tempDir.path}${Platform.pathSeparator}test.db';

      AppDatabase.instance.configureForTesting(
        factory: databaseFactoryFfi,
        path: tempDbPath,
      );
      db = await AppDatabase.instance.database;

      invoicesRepo = SqliteInvoicesRepository(AppDatabase.instance);
      partiesRepo = SqlitePartiesRepository(AppDatabase.instance);

      customerId1 = await partiesRepo.insertParty(
        PartyModel(
          name: 'مؤسسة الرياض التجارية',
          phone: '0501112233',
          type: PartyType.customer,
          currentBalance: Money.zero,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await partiesRepo.insertParty(
        PartyModel(
          name: 'سوبرماركت النور والبركة',
          phone: '0554445566',
          type: PartyType.customer,
          currentBalance: Money.zero,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      supplierId1 = await partiesRepo.insertParty(
        PartyModel(
          name: 'شركة الألبان الوطنية',
          phone: '0567778899',
          type: PartyType.supplier,
          currentBalance: Money.zero,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    });

    tearDown(() async {
      await AppDatabase.instance.close();
      try {
        final f = File(tempDbPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    });

    test(
      '1. Live SQLite query filters by type and partial search query',
      () async {
        // Query customers with partial name
        final customerResults = await partiesRepo.getParties(
          type: PartyType.customer,
          searchQuery: 'الرياض',
        );
        expect(customerResults.length, equals(1));
        expect(customerResults.first.name, equals('مؤسسة الرياض التجارية'));

        // Query suppliers with partial name
        final supplierResults = await partiesRepo.getParties(
          type: PartyType.supplier,
          searchQuery: 'الألبان',
        );
        expect(supplierResults.length, equals(1));
        expect(supplierResults.first.id, equals(supplierId1));
        expect(supplierResults.first.name, equals('شركة الألبان الوطنية'));

        // In supplier query, customer must not appear even if matching query
        final noCrossResults = await partiesRepo.getParties(
          type: PartyType.supplier,
          searchQuery: 'الرياض',
        );
        expect(noCrossResults, isEmpty);
      },
    );

    test(
      '2. Party search query does NOT mutate balance or insert records into SQLite',
      () async {
        final beforeCustomer = await partiesRepo.getPartyById(customerId1);
        final beforeCount =
            (await db.rawQuery(
                  'SELECT COUNT(*) as cnt FROM ${AppTables.parties}',
                )).first['cnt']
                as int;

        // Execute several search queries
        await partiesRepo.getParties(
          type: PartyType.customer,
          searchQuery: 'مؤسسة',
        );
        await partiesRepo.getParties(
          type: PartyType.customer,
          searchQuery: 'غير موجود',
        );
        await partiesRepo.getParties(
          type: PartyType.supplier,
          searchQuery: 'الألبان',
        );

        final afterCustomer = await partiesRepo.getPartyById(customerId1);
        final afterCount =
            (await db.rawQuery(
                  'SELECT COUNT(*) as cnt FROM ${AppTables.parties}',
                )).first['cnt']
                as int;

        expect(
          afterCount,
          equals(beforeCount),
          reason: 'Search must never insert records',
        );
        expect(
          afterCustomer!.currentBalance,
          equals(beforeCustomer!.currentBalance),
          reason: 'Search must never change balance',
        );
      },
    );

    test(
      '3. Select party, save invoice to SQLite, and verify party_id persistence',
      () async {
        final inventory = SqliteInventoryRepository();
        final now = DateTime.now();
        final unitId = await inventory.insertUnit(
          UnitModel(name: 'قطعة', symbol: 'حبة', createdAt: now),
        );
        final itemId = await inventory.insertItem(
          ItemModel(
            code: 'PARTY-PERSISTENCE',
            name: 'صنف اختبار ربط الطرف',
            unitId: unitId,
            costPrice: const Money(5000),
            sellingPrice: const Money(10000),
            createdAt: now,
            updatedAt: now,
          ),
        );
        final invoice = InvoiceModel(
          invoiceNumber: 'INV-2026-TEST',
          invoiceType: InvoiceType.sale,
          partyId: customerId1,
          invoiceDate: DateTime.now(),
          status: InvoiceStatus.draft,
          paymentType: PaymentType.cash,
          subtotal: const Money(10000),
          discount: Money.zero,
          tax: Money.zero,
          total: const Money(10000),
          paidAmount: const Money(10000),
          remainingAmount: Money.zero,
          // A 100 SAR header must have corresponding lines.
          items: [
            InvoiceItemModel.create(
              itemId: itemId,
              quantity: 1,
              unitPrice: const Money(10000),
            ),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final invId = await invoicesRepo.createInvoice(invoice);
        final retrieved = await invoicesRepo.getInvoiceById(invId);

        expect(retrieved, isNotNull);
        expect(retrieved!.partyId, equals(customerId1));
        expect(retrieved.invoiceNumber, equals('INV-2026-TEST'));
      },
    );

    test(
      '4. High volume party search query scalability test (200 records in SQLite)',
      () async {
        await db.transaction((txn) async {
          final now = DateTime.now().millisecondsSinceEpoch;
          for (int i = 0; i < 200; i++) {
            await txn.insert(AppTables.parties, {
              'name': 'عميل اختباري رقم $i',
              'phone': '050${i.toString().padLeft(7, '0')}',
              'type': PartyType.customer.dbValue,
              'current_balance_int': 0,
              'credit_limit_int': 100000,
              'is_active': 1,
              'created_at': now,
              'updated_at': now,
            });
          }
        });

        final results = await partiesRepo.getParties(
          type: PartyType.customer,
          searchQuery: 'رقم 15',
          limit: 20,
        );

        expect(results, isNotEmpty);
        expect(results.every((p) => p.name.contains('رقم 15')), isTrue);
      },
    );
  });
}
