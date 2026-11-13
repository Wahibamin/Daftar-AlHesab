import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/pages/voucher_editor_page.dart';
import 'package:m3/features/accounting/pages/vouchers_list_page.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/dashboard/pages/dashboard_page.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/pages/item_editor_page.dart';
import 'package:m3/features/inventory/pages/items_page.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/inventory/widgets/stock_adjustment_dialog.dart';
import 'package:m3/features/parties/pages/account_statement_page.dart';
import 'package:m3/features/parties/pages/parties_page.dart';
import 'package:m3/features/parties/pages/party_editor_page.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/reports/pages/profit_loss_page.dart';
import 'package:m3/features/reports/pages/reports_hub_page.dart';
import 'package:m3/features/reports/repositories/reports_repository.dart';
import 'package:m3/features/sales/pages/invoice_editor_page.dart';
import 'package:m3/features/sales/pages/invoices_list_page.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:m3/features/settings/pages/store_settings_page.dart';

Widget buildTestApp(
  Widget child, {
  required Size size,
  required double textScale,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(
      theme: RafTheme.lightTheme,
      locale: const Locale('ar'),
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    ),
  );
}

void main() {
  final testSizes = [
    const Size(320, 568),
    const Size(360, 640),
    const Size(393, 873),
    const Size(432, 932),
  ];

  final textScales = [1.0, 1.3, 1.6];

  late FakeReportsRepository fakeReports;
  late FakeInventoryRepository fakeInventory;
  late FakePartiesRepository fakeParties;
  late FakeInvoicesRepository fakeInvoices;
  late FakeVouchersRepository fakeVouchers;

  setUp(() async {
    fakeReports = FakeReportsRepository();
    fakeInventory = FakeInventoryRepository();
    fakeParties = FakePartiesRepository();
    fakeInvoices = FakeInvoicesRepository();
    fakeVouchers = FakeVouchersRepository();

    await fakeInventory.seedDefaultDataIfEmpty();
    await fakeParties.seedDefaultDataIfEmpty();
    await fakeInventory.insertItem(
      ItemModel(
        id: 1,
        name: 'ماء أروى 330 مل',
        code: '62810001',
        costPrice: Money(100),
        sellingPrice: Money(150),
        stockQuantity: 50,
        minAlertLimit: 10,
        unitId: 1,
        categoryId: 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  });

  group('Responsive Layout Matrix Tests', () {
    for (final size in testSizes) {
      for (final scale in textScales) {
        testWidgets(
          'DashboardPage at ${size.width}x${size.height} scale $scale',
          (tester) async {
            tester.view.physicalSize = size * 2.0;
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              buildTestApp(
                DashboardPage(
                  reportsRepo: fakeReports,
                  invoicesRepo: fakeInvoices,
                  inventoryRepo: fakeInventory,
                  partiesRepo: fakeParties,
                  vouchersRepo: fakeVouchers,
                ),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(DashboardPage), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          'ItemsPage and ItemEditorPage at ${size.width}x${size.height} scale $scale',
          (tester) async {
            tester.view.physicalSize = size * 2.0;
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              buildTestApp(
                ItemsPage(repository: fakeInventory),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(ItemsPage), findsOneWidget);
            expect(tester.takeException(), isNull);

            await tester.pumpWidget(
              buildTestApp(
                ItemEditorPage(repository: fakeInventory),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(ItemEditorPage), findsOneWidget);
            expect(
              find.byKey(const Key('appbar_save_item_button')),
              findsOneWidget,
            );
            expect(find.byKey(const Key('save_item_button')), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          'StockAdjustmentDialog at ${size.width}x${size.height} scale $scale',
          (tester) async {
            tester.view.physicalSize = size * 2.0;
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            final items = await fakeInventory.getItems();
            await tester.pumpWidget(
              buildTestApp(
                Scaffold(
                  body: StockAdjustmentDialog(
                    item: items.first,
                    repository: fakeInventory,
                  ),
                ),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(StockAdjustmentDialog), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          'AccountStatementPage at ${size.width}x${size.height} scale $scale',
          (tester) async {
            tester.view.physicalSize = size * 2.0;
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            final parties = await fakeParties.getParties();
            await tester.pumpWidget(
              buildTestApp(
                AccountStatementPage(
                  party: parties.first,
                  repository: fakeParties,
                ),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(AccountStatementPage), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          'InvoiceEditorPage & InvoicesListPage at ${size.width}x${size.height} scale $scale',
          (tester) async {
            tester.view.physicalSize = size * 2.0;
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              buildTestApp(
                InvoiceEditorPage(
                  invoicesRepo: fakeInvoices,
                  inventoryRepo: fakeInventory,
                  partiesRepo: fakeParties,
                ),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(InvoiceEditorPage), findsOneWidget);
            expect(tester.takeException(), isNull);

            await tester.pumpWidget(
              buildTestApp(
                InvoicesListPage(
                  invoicesRepo: fakeInvoices,
                  inventoryRepo: fakeInventory,
                  partiesRepo: fakeParties,
                ),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(InvoicesListPage), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          'VoucherEditorPage & VouchersListPage at ${size.width}x${size.height} scale $scale',
          (tester) async {
            tester.view.physicalSize = size * 2.0;
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              buildTestApp(
                VoucherEditorPage(
                  vouchersRepo: fakeVouchers,
                  partiesRepo: fakeParties,
                ),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(VoucherEditorPage), findsOneWidget);
            expect(tester.takeException(), isNull);

            await tester.pumpWidget(
              buildTestApp(
                VouchersListPage(
                  vouchersRepo: fakeVouchers,
                  partiesRepo: fakeParties,
                ),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(VouchersListPage), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          'PartiesPage & PartyEditorPage at ${size.width}x${size.height} scale $scale',
          (tester) async {
            tester.view.physicalSize = size * 2.0;
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              buildTestApp(
                PartiesPage(repository: fakeParties),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(PartiesPage), findsOneWidget);
            expect(tester.takeException(), isNull);

            await tester.pumpWidget(
              buildTestApp(
                PartyEditorPage(repository: fakeParties),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(PartyEditorPage), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          'ReportsHubPage & ProfitLoss at ${size.width}x${size.height} scale $scale',
          (tester) async {
            tester.view.physicalSize = size * 2.0;
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              buildTestApp(
                ReportsHubPage(reportsRepo: fakeReports),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(ReportsHubPage), findsOneWidget);
            expect(tester.takeException(), isNull);

            // Switch to Tab 2: تقييم المخزون
            await tester.tap(find.text('تقييم المخزون'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            // Switch to Tab 3: حركة الخزينة
            await tester.tap(find.text('حركة الخزينة'));
            await tester.pumpAndSettle();
            expect(
              find.text('كشف السيولة والتدفق النقدي للخزينة'),
              findsOneWidget,
            );
            expect(find.text('الشهر الحالي'), findsOneWidget);
            expect(tester.takeException(), isNull);

            await tester.pumpWidget(
              buildTestApp(
                ProfitLossPage(reportsRepo: fakeReports),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(ProfitLossPage), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          'StoreSettingsPage at ${size.width}x${size.height} scale $scale',
          (tester) async {
            tester.view.physicalSize = size * 2.0;
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              buildTestApp(
                StoreSettingsPage(inventoryRepo: fakeInventory),
                size: size,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(StoreSettingsPage), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
