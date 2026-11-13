import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

// Observes completion only: validation and posting use the real SQLite method.
class ObservedSqliteInvoicesRepository extends SqliteInvoicesRepository {
  final finished = Completer<void>();
  @override
  Future<int> saveAndFinalizeInvoice(InvoiceModel invoice) async {
    try {
      return await super.saveAndFinalizeInvoice(invoice);
    } finally {
      if (!finished.isCompleted) finished.complete();
    }
  }
}

void main() {
  sqfliteFfiInit();
  for (final type in [InvoiceType.sale, InvoiceType.purchase]) {
    testWidgets(
      'Phase03A $type incompatible party shows Arabic refusal without success',
      (tester) async {
        tester.view.physicalSize = const Size(432, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final manager = AppDatabase.instance;
        final observer = ObservedSqliteInvoicesRepository();
        final inventory = FakeInventoryRepository();
        final parties = FakePartiesRepository();
        late Directory directory;
        late InvoiceModel draft;
        late Database db;
        final date = DateTime(2026, 11, 5, 12);
        Future<T?> real<T>(Future<T> Function() body) =>
            tester.runAsync(() async {
              final result = await body().timeout(const Duration(seconds: 15));
              return result;
            });

        Future<Map<String, Object?>> snapshot() async => {
          for (final table in [
            AppTables.invoices,
            AppTables.invoiceItems,
            AppTables.items,
            AppTables.inventoryMovements,
            AppTables.parties,
            AppTables.vouchers,
          ])
            table: await db.query(table, orderBy: 'id'),
          'treasury':
              (await SqliteVouchersRepository().getTreasuryBalance()).rawUnits,
        };
        await real(() async {
          directory = await Directory.systemTemp.createTemp(
            'daftar_phase03a_ui_',
          );
          manager.configureForTesting(
            factory: databaseFactoryFfi,
            path: '${directory.path}/isolated.db',
          );
          db = await manager.database;
          final realInventory = SqliteInventoryRepository();
          final realParties = SqlitePartiesRepository();
          final unit = UnitModel(name: 'قطعة', symbol: 'حبة', createdAt: date);
          final unitId = await realInventory.insertUnit(unit);
          final item = ItemModel(
            code: 'TYPE-UI',
            name: 'صنف اختبار الطرف',
            unitId: unitId,
            costPrice: const Money(6000),
            sellingPrice: const Money(10000),
            stockQuantity: 20,
            createdAt: date,
            updatedAt: date,
          );
          final itemId = await realInventory.insertItem(item);
          await inventory.insertUnit(unit.copyWith(id: unitId));
          await inventory.insertItem(item.copyWith(id: itemId));
          final wrong = PartyModel(
            name: 'طرف غير متوافق للاختبار',
            phone: '0500000000',
            type: type == InvoiceType.sale
                ? PartyType.supplier
                : PartyType.customer,
            createdAt: date,
            updatedAt: date,
          );
          final partyId = await realParties.insertParty(wrong);
          await parties.insertParty(wrong.copyWith(id: partyId));
          final request = InvoiceModel.buildWithItems(
            invoiceNumber: 'TYPE-UI-001',
            partyId: partyId,
            invoiceType: type,
            paymentType: PaymentType.credit,
            items: [
              InvoiceItemModel.create(
                itemId: itemId,
                quantity: 1,
                unitPrice: const Money(10000),
              ),
            ],
            invoiceDate: date,
            createdAt: date,
            updatedAt: date,
          );
          final id = await SqliteInvoicesRepository().createInvoice(request);
          draft = (await SqliteInvoicesRepository().getInvoiceById(id))!;
        });
        addTearDown(() async {
          await manager.close();
          await directory.delete(recursive: true);
        });
        final before = await real(snapshot);
        await tester.pumpWidget(
          MaterialApp(
            theme: RafTheme.lightTheme,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: InvoiceEditorPage(
              invoicesRepo: observer,
              inventoryRepo: inventory,
              partiesRepo: parties,
              existingInvoice: draft,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('اعتماد وترحيل'));
        // SQLite isolate responses must be allowed to arrive in real time, then
        // fake-async microtasks/frames are pumped so the UI callback can finish.
        for (
          var attempt = 0;
          attempt < 200 && !observer.finished.isCompleted;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(
          observer.finished.isCompleted,
          isTrue,
          reason: 'SQLite submission must finish',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('نوع الطرف غير متوافق'), findsOneWidget);
        expect(
          find.text('تم اعتماد وترحيل الفاتورة وتحديث المخزون بنجاح'),
          findsNothing,
        );
        expect(find.byType(InvoiceEditorPage), findsOneWidget);
        expect(await real(snapshot), before);
      },
    );
  }
}
