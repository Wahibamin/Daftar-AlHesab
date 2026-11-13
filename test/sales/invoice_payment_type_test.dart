import 'dart:io';
import '../../test_support/funded_treasury.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/pages/invoice_editor_page.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget _wrap(Widget child, {Size size = const Size(393, 873)}) {
  return MaterialApp(
    theme: RafTheme.lightTheme,
    locale: const Locale('ar'),
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

void main() {
  group('Phase 4 UI: Payment Switcher & Validation Tests', () {
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
          code: 'P01',
          name: 'منتج تجريبي نقدي وآجل',
          unitId: units.first.id!,
          costPrice: const Money(5000), // 50.00 SAR
          sellingPrice: const Money(10000), // 100.00 SAR
          stockQuantity: 100,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await fakeParties.insertParty(
        PartyModel(
          name: 'عميل تجريبي للدفع',
          phone: '0512345678',
          type: PartyType.customer,
          currentBalance: Money.zero,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    });

    testWidgets(
      '1. Switch between Cash, Credit, and Partial updates UI controls immediately',
      (tester) async {
        tester.view.physicalSize = const Size(393 * 2.0, 873 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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

        // By default, cash is selected and partial input is hidden
        expect(find.byKey(const Key('partial_paid_input')), findsNothing);

        // Tap 'آجل'
        await tester.tap(find.text('آجل'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('partial_paid_input')), findsNothing);

        // Tap 'جزئي'
        await tester.tap(find.text('جزئي'));
        await tester.pumpAndSettle();

        // Partial input field appears
        expect(find.byKey(const Key('partial_paid_input')), findsOneWidget);
        expect(find.text('المتبقي الآجل'), findsOneWidget);
      },
    );

    testWidgets('2. Partial payment dynamically calculates remaining debt', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393 * 2.0, 873 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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

      // Add item: 100.00 SAR
      await tester.enterText(find.byType(TextField).first, 'منتج تجريبي');
      await tester.pumpAndSettle();
      await tester.tap(find.text('منتج تجريبي نقدي وآجل'));
      await tester.pumpAndSettle();

      // Switch to partial
      await tester.tap(find.text('جزئي'));
      await tester.pumpAndSettle();

      // Enter 40.00 SAR paid
      await tester.enterText(
        find.byKey(const Key('partial_paid_input')),
        '40.00',
      );
      await tester.pumpAndSettle();

      // Remaining should be 100.00 - 40.00 = 60.00 SAR
      expect(find.textContaining('60.00'), findsWidgets);
    });

    testWidgets(
      '3. Blocks finalizing partial invoice without party or with invalid amount',
      (tester) async {
        tester.view.physicalSize = const Size(393 * 2.0, 873 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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

        // Add item
        await tester.enterText(find.byType(TextField).first, 'منتج');
        await tester.pumpAndSettle();
        await tester.tap(find.text('منتج تجريبي نقدي وآجل'));
        await tester.pumpAndSettle();

        // Select Partial without party
        await tester.tap(find.text('جزئي'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('اعتماد وترحيل'));
        await tester.pumpAndSettle();

        // Warning snackbar appears
        expect(
          find.text('يجب تحديد العميل أو المورد للفواتير ذات السداد الجزئي'),
          findsOneWidget,
        );
      },
    );
  });

  group('Phase 4 SQLite: Accounting & Treasury Integration Tests', () {
    sqfliteFfiInit();

    late Database db;
    late String tempDbPath;
    late SqliteInvoicesRepository invoicesRepo;
    late SqliteInventoryRepository inventoryRepo;
    late SqlitePartiesRepository partiesRepo;
    late SqliteVouchersRepository vouchersRepo;
    late int testCustomerId;
    late int testSupplierId;
    late int testItemId;

    setUp(() async {
      final tempDir = await Directory.systemTemp.createTemp(
        'raf_payment_sqlite_',
      );
      tempDbPath = '${tempDir.path}${Platform.pathSeparator}test.db';

      AppDatabase.instance.configureForTesting(
        factory: databaseFactoryFfi,
        path: tempDbPath,
      );
      db = await AppDatabase.instance.database;

      invoicesRepo = SqliteInvoicesRepository(AppDatabase.instance);
      inventoryRepo = SqliteInventoryRepository(AppDatabase.instance);
      partiesRepo = SqlitePartiesRepository(AppDatabase.instance);
      vouchersRepo = SqliteVouchersRepository(AppDatabase.instance);

      await inventoryRepo.safeSeedMasterData();
      final units = await inventoryRepo.getUnits();

      testItemId = await inventoryRepo.insertItem(
        ItemModel(
          code: 'PAY001',
          name: 'صنف اختبار السداد',
          unitId: units.first.id!,
          costPrice: const Money(5000), // 50.00 SAR
          sellingPrice: const Money(10000), // 100.00 SAR
          stockQuantity: 100,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        initialStock: 100,
      );

      testCustomerId = await partiesRepo.insertParty(
        PartyModel(
          name: 'عميل السداد المحاسبي',
          phone: '0509990001',
          type: PartyType.customer,
          currentBalance: Money.zero,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      testSupplierId = await partiesRepo.insertParty(
        PartyModel(
          name: 'مورد السداد المحاسبي',
          phone: '0509990002',
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
      '1. Cash Sales Invoice: full paid amount in treasury, remaining is 0, party balance unaffected',
      () async {
        final initialTreasury = await vouchersRepo.getTreasuryBalance();

        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-CASH-001',
          partyId: testCustomerId,
          invoiceType: InvoiceType.sale,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.cash,
          items: [
            InvoiceItemModel.create(
              itemId: testItemId,
              quantity: 2,
              unitPrice: const Money(10000), // 100.00 * 2 = 200.00 SAR
            ),
          ],
          paidAmount: const Money(20000), // Full 200.00 SAR
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await invoicesRepo.saveAndFinalizeInvoice(invoice);

        final customer = await partiesRepo.getPartyById(testCustomerId);
        final finalTreasury = await vouchersRepo.getTreasuryBalance();

        // Customer balance remains 0 (Cash transaction)
        expect(customer!.currentBalance, equals(Money.zero));

        // Treasury received full 200.00 SAR
        expect(finalTreasury, equals(initialTreasury + const Money(20000)));

        // Foreign key check
        expect(await db.rawQuery('PRAGMA foreign_key_check;'), isEmpty);
      },
    );

    test(
      '2. Credit Sales Invoice: paid is 0, customer owes full remaining debt, treasury unaffected',
      () async {
        final initialTreasury = await vouchersRepo.getTreasuryBalance();

        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-CREDIT-001',
          partyId: testCustomerId,
          invoiceType: InvoiceType.sale,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.credit,
          items: [
            InvoiceItemModel.create(
              itemId: testItemId,
              quantity: 2,
              unitPrice: const Money(10000), // 200.00 SAR
            ),
          ],
          paidAmount: Money.zero,
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await invoicesRepo.saveAndFinalizeInvoice(invoice);

        final customer = await partiesRepo.getPartyById(testCustomerId);
        final finalTreasury = await vouchersRepo.getTreasuryBalance();

        // Customer balance decreased by 200.00 SAR (Debtor owes us)
        expect(customer!.currentBalance, equals(const Money(-20000)));

        // Treasury is untouched
        expect(finalTreasury, equals(initialTreasury));
      },
    );

    test(
      '3. Partial Sales Invoice: paid amount enters treasury, remaining debt assigned to customer',
      () async {
        final initialTreasury = await vouchersRepo.getTreasuryBalance();

        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-PARTIAL-001',
          partyId: testCustomerId,
          invoiceType: InvoiceType.sale,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.partial,
          items: [
            InvoiceItemModel.create(
              itemId: testItemId,
              quantity: 2,
              unitPrice: const Money(10000), // 200.00 SAR
            ),
          ],
          paidAmount: const Money(
            10000,
          ), // Paid 100.00 SAR, remaining 100.00 SAR
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await invoicesRepo.saveAndFinalizeInvoice(invoice);

        final customer = await partiesRepo.getPartyById(testCustomerId);
        final finalTreasury = await vouchersRepo.getTreasuryBalance();

        // Customer owes exactly the remaining 100.00 SAR
        expect(customer!.currentBalance, equals(const Money(-10000)));

        // Treasury received exactly the paid 100.00 SAR
        expect(finalTreasury, equals(initialTreasury + const Money(10000)));
      },
    );

    test(
      '4. Partial Purchase Invoice: paid amount leaves treasury, remaining debt owed to supplier',
      () async {
        await fundTreasury(await AppDatabase.instance.database);
        final initialTreasury = await vouchersRepo.getTreasuryBalance();

        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'PUR-PARTIAL-001',
          partyId: testSupplierId,
          invoiceType: InvoiceType.purchase,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.partial,
          items: [
            InvoiceItemModel.create(
              itemId: testItemId,
              quantity: 1,
              unitPrice: const Money(5000), // 50.00 SAR
            ),
          ],
          paidAmount: const Money(2000), // Paid 20.00 SAR, remaining 30.00 SAR
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await invoicesRepo.saveAndFinalizeInvoice(invoice);

        final supplier = await partiesRepo.getPartyById(testSupplierId);
        final finalTreasury = await vouchersRepo.getTreasuryBalance();

        // We owe supplier the remaining 30.00 SAR (+3000 creditor)
        expect(supplier!.currentBalance, equals(const Money(3000)));

        // Treasury decreased by exactly the 20.00 SAR cash paid
        expect(finalTreasury, equals(initialTreasury - const Money(2000)));
      },
    );
  });
}
