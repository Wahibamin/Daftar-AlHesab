import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/inventory/widgets/expiry_badge.dart';
import 'package:m3/features/inventory/widgets/stock_badge.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/pages/invoice_editor_page.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';

void main() {
  final date = DateTime(2040, 3, 10, 23, 59);
  late FakeInvoicesRepository invoices;
  late FakeInventoryRepository inventory;
  late FakePartiesRepository parties;
  late InvoiceModel draft;

  setUp(() async {
    invoices = FakeInvoicesRepository();
    inventory = FakeInventoryRepository();
    parties = FakePartiesRepository();
    await inventory.insertItem(
      ItemModel(
        id: 1,
        code: 'TEST',
        name: 'صنف',
        unitId: 1,
        costPrice: const Money(10000),
        sellingPrice: const Money(200000),
        stockQuantity: 20,
        createdAt: date,
        updatedAt: date,
      ),
    );
    await parties.insertParty(
      PartyModel(
        id: 1,
        name: 'عميل',
        phone: '0500000000',
        type: PartyType.customer,
        createdAt: date,
        updatedAt: date,
      ),
    );
    draft = InvoiceModel.buildWithItems(
      invoiceNumber: 'TEST-UI',
      partyId: 1,
      invoiceType: InvoiceType.sale,
      paymentType: PaymentType.partial,
      paidAmount: const Money(10000),
      items: [
        InvoiceItemModel.create(
          itemId: 1,
          quantity: 1,
          unitPrice: const Money(200000),
        ),
      ],
      invoiceDate: date,
      createdAt: date,
      updatedAt: date,
    );
  });

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

  Future<int> open(
    WidgetTester tester, {
    InvoiceStatus status = InvoiceStatus.draft,
  }) async {
    tester.view.physicalSize = const Size(432, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final id = await invoices.createInvoice(draft);
    if (status == InvoiceStatus.approved) await invoices.finalizeInvoice(id);
    if (status == InvoiceStatus.cancelled) await invoices.cancelInvoice(id);
    await tester.pumpWidget(
      wrap(
        InvoiceEditorPage(
          invoicesRepo: invoices,
          inventoryRepo: inventory,
          partiesRepo: parties,
          existingInvoice: await invoices.getInvoiceById(id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return id;
  }

  for (final status in [InvoiceStatus.approved, InvoiceStatus.cancelled]) {
    testWidgets('FIN-01 $status is read only', (tester) async {
      await open(tester, status: status);
      expect(find.text('عرض فاتورة'), findsOneWidget);
      expect(find.text('اعتماد وترحيل'), findsNothing);
      expect(find.text('مسودة'), findsNothing);
      final input = tester.widget<TextField>(
        find.byKey(const Key('partial_paid_input')),
      );
      expect(input.enabled, isFalse);
      await tester.tap(find.byKey(const Key('edit_discount_button')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  }

  final samples = {
    '100': 10000,
    '١٠٠': 10000,
    '1,000': 100000,
    '100.25': 10025,
    '١٠٠٫٢٥': 10025,
    '١٬٠٠٠٫٥٠': 100050,
  };
  for (final sample in samples.entries) {
    testWidgets('UX-01 payment ${sample.key} persists exact minor units', (
      tester,
    ) async {
      final id = await open(tester);
      await tester.enterText(
        find.byKey(const Key('partial_paid_input')),
        sample.key,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('مسودة'));
      await tester.pumpAndSettle();
      final saved = (await invoices.getInvoiceById(id))!;
      expect(saved.paidAmountInt, sample.value);
      expect(saved.remainingAmountInt, 200000 - sample.value);
    });
  }

  for (final invalid in ['abc', '1,,000', '-5', '2001']) {
    testWidgets('UX-01 invalid payment $invalid cannot be saved', (
      tester,
    ) async {
      final id = await open(tester);
      await tester.enterText(
        find.byKey(const Key('partial_paid_input')),
        invalid,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('مسودة'));
      await tester.pumpAndSettle();
      expect((await invoices.getInvoiceById(id))!.paidAmountInt, 10000);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  }

  testWidgets(
    'UX-01 discount validates malformed, negative and excessive values',
    (tester) async {
      final id = await open(tester);
      await tester.tap(find.byKey(const Key('edit_discount_button')));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      for (final invalid in ['abc', '-1', '2001']) {
        await tester.enterText(field, invalid);
        await tester.tap(find.text('تطبيق الخصم'));
        await tester.pumpAndSettle();
        expect(
          find.text('أدخل خصماً صحيحاً بين صفر وقيمة الفاتورة'),
          findsOneWidget,
        );
      }
      await tester.enterText(field, '١٬٠٠٠٫٥٠');
      await tester.tap(find.text('تطبيق الخصم'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('مسودة'));
      await tester.pumpAndSettle();
      expect((await invoices.getInvoiceById(id))!.discountInt, 100050);
    },
  );

  testWidgets(
    'FIN-05 opening and saving a draft preserves line discount once',
    (tester) async {
      final line = draft.items!.single.copyWith(
        discount: const Money(1000),
        totalPrice: const Money(199000),
      );
      draft = InvoiceModel.buildWithItems(
        invoiceNumber: draft.invoiceNumber,
        invoiceType: draft.invoiceType,
        items: [line],
        additionalDiscount: const Money(500),
        invoiceDate: date,
        createdAt: date,
        updatedAt: date,
      );
      final id = await open(tester);
      await tester.tap(find.text('مسودة'));
      await tester.pumpAndSettle();
      expect((await invoices.getInvoiceById(id))!.discountInt, 1500);
      expect((await invoices.getInvoiceById(id))!.totalInt, 198500);
    },
  );

  test('QA-01 calendar policy is independent of current wall clock', () {
    final item = ItemModel(
      code: 'EXPIRY',
      name: 'صنف',
      unitId: 1,
      costPrice: Money.zero,
      sellingPrice: Money.zero,
      expiryDate: DateTime(2040, 3, 10),
      createdAt: date,
      updatedAt: date,
    );
    expect(item.remainingExpiryDays(date), 0);
    expect(item.isExpiredAt(date), isFalse);
    expect(item.isExpiredAt(DateTime(2040, 3, 11)), isTrue);
    expect(item.remainingExpiryDays(DateTime(2040, 3, 9)), 1);
    expect(ExpiryBadge.calculateRemainingDays(item.expiryDate, date), 0);
  });

  testWidgets('QA-01 stock badge uses injected historical reference day', (
    tester,
  ) async {
    final historical = DateTime(2000, 1, 1, 23);
    final item = ItemModel(
      code: 'HISTORY',
      name: 'صنف',
      unitId: 1,
      costPrice: Money.zero,
      sellingPrice: Money.zero,
      stockQuantity: 10,
      expiryDate: DateTime(2000, 1, 1),
      createdAt: date,
      updatedAt: date,
    );
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: StockBadge(item: item, referenceDate: historical),
        ),
      ),
    );
    expect(find.text('10'), findsOneWidget);
    expect(find.text('منتهي الصلاحية'), findsNothing);
  });
}
