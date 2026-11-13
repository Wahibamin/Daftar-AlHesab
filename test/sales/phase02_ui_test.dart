import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/inventory/pages/item_editor_page.dart';
import 'package:m3/features/inventory/widgets/expiry_badge.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/pages/invoice_editor_page.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';

class CollisionInvoicesRepository extends FakeInvoicesRepository {
  @override
  Future<String> generateNextInvoiceNumber(InvoiceType type) async => 'INV-001';
}

Widget wrap(Widget child) => MaterialApp(
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

void main() {
  testWidgets(
    'DH-NEW-03 clear expiry saves and stays absent after editor reopen',
    (tester) async {
      tester.view.physicalSize = const Size(432, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeInventoryRepository();
      final date = DateTime(2026, 11, 5);
      final unit = await repository.insertUnit(
        UnitModel(name: 'قطعة', symbol: 'حبة', createdAt: date),
      );
      final id = await repository.insertItem(
        ItemModel(
          code: 'EXPIRY-UI',
          name: 'صنف الصلاحية',
          unitId: unit,
          costPrice: const Money(6000),
          sellingPrice: const Money(10000),
          stockQuantity: 20,
          expiryDate: DateTime(2030, 1, 1),
          createdAt: date,
          updatedAt: date,
        ),
      );
      await tester.pumpWidget(
        wrap(
          ItemEditorPage(
            repository: repository,
            itemToEdit: await repository.getItemById(id),
            initialUnits: await repository.getUnits(),
            initialCategories: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('clear_expiry_date')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clear_expiry_date')));
      await tester.pumpAndSettle();
      expect(find.text('حدد تاريخ الصلاحية إن وجد'), findsOneWidget);
      await tester.tap(find.byKey(const Key('appbar_save_item_button')));
      await tester.pumpAndSettle();
      final saved = (await repository.getItemById(id))!;
      expect(saved.expiryDate, isNull);
      expect(saved.stockQuantity, 20);
      expect(saved.costPriceInt, 6000);
      expect(saved.sellingPriceInt, 10000);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        wrap(
          ItemEditorPage(
            repository: repository,
            itemToEdit: saved,
            initialUnits: await repository.getUnits(),
            initialCategories: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('حدد تاريخ الصلاحية إن وجد'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.clear), findsNothing);
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: ExpiryBadge(
              expiryDate: saved.expiryDate,
              referenceDate: date,
            ),
          ),
        ),
      );
      expect(find.byType(ExpiryBadge), findsOneWidget);
      expect(find.byIcon(Icons.access_time_rounded), findsNothing);
    },
  );
  testWidgets(
    'DH-NEW-01 number collision shows Arabic refusal and no success',
    (tester) async {
      tester.view.physicalSize = const Size(432, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final invoices = CollisionInvoicesRepository();
      final inventory = FakeInventoryRepository();
      final parties = FakePartiesRepository();
      final date = DateTime(2026, 11, 5);
      final unit = await inventory.insertUnit(
        UnitModel(name: 'قطعة', symbol: 'حبة', createdAt: date),
      );
      final item = await inventory.insertItem(
        ItemModel(
          code: 'PHASE02-UI',
          name: 'صنف المرحلة الثانية',
          unitId: unit,
          costPrice: const Money(6000),
          sellingPrice: const Money(10000),
          stockQuantity: 20,
          createdAt: date,
          updatedAt: date,
        ),
      );
      await invoices.saveAndFinalizeInvoice(
        InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-001',
          invoiceType: InvoiceType.sale,
          items: [
            InvoiceItemModel.create(
              itemId: item,
              quantity: 1,
              unitPrice: const Money(5000),
            ),
          ],
          paidAmount: const Money(5000),
          invoiceDate: date,
          createdAt: date,
          updatedAt: date,
        ),
      );
      await tester.pumpWidget(
        wrap(
          InvoiceEditorPage(
            invoicesRepo: invoices,
            inventoryRepo: inventory,
            partiesRepo: parties,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'صنف');
      await tester.pumpAndSettle();
      await tester.tap(find.text('صنف المرحلة الثانية'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('اعتماد وترحيل'));
      await tester.pumpAndSettle();
      expect(find.textContaining('رقم الفاتورة مستخدم بالفعل'), findsOneWidget);
      expect(
        find.text('تم اعتماد وترحيل الفاتورة وتحديث المخزون بنجاح'),
        findsNothing,
      );
      expect(find.byType(InvoiceEditorPage), findsOneWidget);
      expect((await invoices.getInvoices()).length, 1);
      expect((await invoices.getInvoices()).single.totalInt, 5000);
    },
  );
}
