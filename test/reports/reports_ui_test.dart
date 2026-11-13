import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/app_shell.dart';
import 'package:m3/features/dashboard/pages/dashboard_page.dart';
import 'package:m3/features/dashboard/widgets/metric_card.dart';
import 'package:m3/features/dashboard/widgets/quick_action_button.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/reports/pages/profit_loss_page.dart';
import 'package:m3/features/reports/pages/reports_hub_page.dart';
import 'package:m3/features/reports/repositories/reports_repository.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:m3/features/settings/pages/store_settings_page.dart';

Widget _wrap(Widget child, {Size size = const Size(800, 1000)}) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: RafColors.primary,
        surface: RafColors.surface,
      ),
      scaffoldBackgroundColor: RafColors.surfaceSecondary,
      fontFamily: 'Roboto',
    ),
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(textDirection: TextDirection.rtl, child: child),
    ),
  );
}

void main() {
  group('MetricCard & QuickActionButton Widget Tests', () {
    testWidgets(
      'MetricCard renders title, value and subtitle without overflow',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const MetricCard(
              title: 'مبيعات اليوم',
              value: '3,500.00',
              icon: Icons.today_rounded,
              subtitle: '12 فواتير معتمدة',
            ),
            size: const Size(360, 640),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('مبيعات اليوم'), findsOneWidget);
        expect(find.text('3,500.00'), findsOneWidget);
        expect(find.text('12 فواتير معتمدة'), findsOneWidget);
      },
    );

    testWidgets('QuickActionButton renders label and fires callback on tap', (
      tester,
    ) async {
      bool tapped = false;

      await tester.pumpWidget(
        _wrap(
          QuickActionButton(
            label: 'فاتورة جديدة',
            icon: Icons.add_shopping_cart,
            onTap: () => tapped = true,
          ),
        ),
      );

      expect(find.text('فاتورة جديدة'), findsOneWidget);
      expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);

      await tester.tap(find.byType(QuickActionButton));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('DashboardPage Integration UI Tests', () {
    late FakeReportsRepository fakeReports;
    late FakeInvoicesRepository fakeInvoices;
    late FakeInventoryRepository fakeInventory;
    late FakePartiesRepository fakeParties;
    late FakeVouchersRepository fakeVouchers;

    setUp(() {
      fakeReports = FakeReportsRepository();
      fakeInvoices = FakeInvoicesRepository();
      fakeInventory = FakeInventoryRepository();
      fakeParties = FakePartiesRepository();
      fakeVouchers = FakeVouchersRepository();
    });

    testWidgets(
      'DashboardPage renders quick actions, financial metrics, and weekly trend',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            DashboardPage(
              reportsRepo: fakeReports,
              invoicesRepo: fakeInvoices,
              inventoryRepo: fakeInventory,
              partiesRepo: fakeParties,
              vouchersRepo: fakeVouchers,
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify Page Title
        expect(find.text('لوحة التحكم التنفيذية'), findsOneWidget);

        // Verify Quick Action shortcuts
        expect(find.text('فاتورة جديدة'), findsOneWidget);
        expect(find.text('سند قبض'), findsOneWidget);
        expect(find.text('إضافة صنف'), findsOneWidget);
        expect(find.text('الأطراف والديون'), findsOneWidget);

        // Verify Financial Metrics
        expect(find.text('مبيعات اليوم'), findsOneWidget);
        expect(find.text('مبيعات الشهر'), findsOneWidget);
        expect(find.text('صافي الربح التقديري'), findsOneWidget);
        expect(find.text('ديون العملاء (لنا)'), findsOneWidget);
        expect(find.text('مستحقات الموردين (علينا)'), findsOneWidget);

        // Verify Weekly trend section
        expect(find.text('حركة المبيعات (آخر 7 أيام)'), findsOneWidget);
      },
    );
  });

  group('ReportsHubPage & ProfitLossPage Integration UI Tests', () {
    late FakeReportsRepository fakeReports;

    setUp(() {
      fakeReports = FakeReportsRepository();
    });

    testWidgets(
      'ReportsHubPage renders tabs and allows viewing valuation and cash flow',
      (tester) async {
        await tester.pumpWidget(
          _wrap(ReportsHubPage(reportsRepo: fakeReports)),
        );

        await tester.pumpAndSettle();

        expect(find.text('مركز التقارير المحاسبية والإدارية'), findsOneWidget);
        expect(find.text('الأرباح والخسائر'), findsOneWidget);
        expect(find.text('تقييم المخزون'), findsOneWidget);
        expect(find.text('حركة الخزينة'), findsOneWidget);

        // Switch to Inventory Valuation tab
        await tester.tap(find.text('تقييم المخزون'));
        await tester.pumpAndSettle();

        expect(find.text('تقييم المخزون ورأس المال السلعي'), findsOneWidget);
        expect(find.text('القيمة بسعر التكلفة'), findsOneWidget);
        expect(find.text('القيمة بسعر البيع'), findsOneWidget);

        // Switch to Treasury Cash Flow tab
        await tester.tap(find.text('حركة الخزينة'));
        await tester.pumpAndSettle();

        expect(find.text('كشف السيولة والتدفق النقدي للخزينة'), findsOneWidget);
        expect(find.text('إجمالي المقبوضات'), findsOneWidget);
        expect(find.text('إجمالي المدفوعات'), findsOneWidget);
      },
    );

    testWidgets(
      'ProfitLossPage renders breakdown cards and switches date filters',
      (tester) async {
        await tester.pumpWidget(
          _wrap(ProfitLossPage(reportsRepo: fakeReports)),
        );

        await tester.pumpAndSettle();

        expect(find.text('قائمة الأرباح والخسائر (P&L)'), findsOneWidget);
        expect(find.text('1. إيرادات المبيعات الصافية'), findsOneWidget);
        expect(find.text('2. تكلفة البضاعة المباعة (COGS)'), findsOneWidget);
        expect(
          find.text('3. مجمل الربح التجاري (Gross Profit)'),
          findsOneWidget,
        );
        expect(find.text('4. المصروفات التشغيلية والعمومية'), findsOneWidget);
        expect(find.textContaining('صافي الربح'), findsWidgets);

        // Switch period to Today
        await tester.tap(find.text('اليوم'));
        await tester.pumpAndSettle();

        expect(find.text('اليوم'), findsOneWidget);
      },
    );
  });

  group('StoreSettingsPage & RafNavigationShell Tests', () {
    testWidgets('StoreSettingsPage renders store fields and saves changes', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const StoreSettingsPage()));

      await tester.pumpAndSettle();

      expect(find.text('بيانات وإعدادات المنشأة'), findsOneWidget);
      expect(find.text('اسم المتجر / المنشأة'), findsOneWidget);
      expect(find.text('الرقم الضريبي (VAT ID - 15 رقم)'), findsNothing);
      expect(find.text('رقم الجوال / التواصل'), findsOneWidget);

      final saveBtn = find.text('حفظ التعديلات');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
    });

    testWidgets('RafNavigationShell renders 5 bottom tabs and switches pages', (
      tester,
    ) async {
      final fakeReports = FakeReportsRepository();
      final fakeInvoices = FakeInvoicesRepository();
      final fakeInventory = FakeInventoryRepository();
      final fakeParties = FakePartiesRepository();
      final fakeVouchers = FakeVouchersRepository();

      await fakeInventory.seedDefaultDataIfEmpty();
      await fakeParties.seedDefaultDataIfEmpty();

      await tester.pumpWidget(
        _wrap(
          RafNavigationShell(
            reportsRepo: fakeReports,
            invoicesRepo: fakeInvoices,
            inventoryRepo: fakeInventory,
            partiesRepo: fakeParties,
            vouchersRepo: fakeVouchers,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify bottom nav items
      expect(find.text('الرئيسية'), findsOneWidget);
      expect(find.text('الفواتير'), findsOneWidget);
      expect(find.text('المخزون'), findsOneWidget);
      expect(find.text('الأطراف'), findsOneWidget);
      expect(find.text('التقارير'), findsOneWidget);

      // Switch to Inventory
      await tester.tap(find.text('المخزون'));
      await tester.pumpAndSettle();
      expect(find.text('دليل المخزون والأصناف'), findsOneWidget);

      // Switch to Parties
      await tester.tap(find.text('الأطراف'));
      await tester.pumpAndSettle();
      expect(find.text('دليل العملاء والموردين'), findsOneWidget);

      // Switch to Reports
      await tester.tap(find.text('التقارير'));
      await tester.pumpAndSettle();
      expect(find.text('مركز التقارير المحاسبية والإدارية'), findsOneWidget);
    });
  });
}
