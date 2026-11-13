import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/features/dashboard/pages/dashboard_page.dart';
import 'package:m3/features/accounting/pages/vouchers_list_page.dart';
import 'package:m3/features/accounting/pages/expenses_page.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/reports/repositories/reports_repository.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';

void main() {
  testWidgets(
    'Phase04 real navigation reaches treasury and existing expenses from dashboard',
    (tester) async {
      final vouchers = FakeVouchersRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: DashboardPage(
              reportsRepo: FakeReportsRepository(),
              invoicesRepo: FakeInvoicesRepository(),
              inventoryRepo: FakeInventoryRepository(),
              partiesRepo: FakePartiesRepository(),
              vouchersRepo: vouchers,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final open = find.byKey(const Key('open_treasury_vouchers'));
      expect(open, findsOneWidget);
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(VouchersListPage), findsOneWidget);
      await tester.tap(find.byTooltip('دفتر المصروفات'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpensesPage), findsOneWidget);
      expect(
        identical(
          tester.widget<ExpensesPage>(find.byType(ExpensesPage)).repository,
          vouchers,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
