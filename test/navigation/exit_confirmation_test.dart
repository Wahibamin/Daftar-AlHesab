import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/app_shell.dart';
import 'package:m3/features/inventory/pages/item_editor_page.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/reports/repositories/reports_repository.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';

Widget _wrap(Widget child) {
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
  late FakeReportsRepository fakeReports;
  late FakeInvoicesRepository fakeInvoices;
  late FakeInventoryRepository fakeInventory;
  late FakePartiesRepository fakeParties;
  late FakeVouchersRepository fakeVouchers;

  setUp(() async {
    fakeReports = FakeReportsRepository();
    fakeInvoices = FakeInvoicesRepository();
    fakeInventory = FakeInventoryRepository();
    fakeParties = FakePartiesRepository();
    fakeVouchers = FakeVouchersRepository();

    await fakeInventory.seedDefaultDataIfEmpty();
    await fakeParties.seedDefaultDataIfEmpty();
  });

  Widget buildShell({int initialIndex = 0}) {
    return _wrap(
      RafNavigationShell(
        initialIndex: initialIndex,
        reportsRepo: fakeReports,
        invoicesRepo: fakeInvoices,
        inventoryRepo: fakeInventory,
        partiesRepo: fakeParties,
        vouchersRepo: fakeVouchers,
      ),
    );
  }

  group('Exit Confirmation & Back Navigation Tests', () {
    testWidgets(
      'Non-home tab back press returns to Home (Dashboard) without exit dialog',
      (tester) async {
        await tester.pumpWidget(
          buildShell(initialIndex: 4),
        ); // Starts on Reports tab
        await tester.pumpAndSettle();

        expect(find.text('مركز التقارير المحاسبية والإدارية'), findsOneWidget);

        // Simulate Android Back Button press
        final popped = await tester.binding.handlePopRoute();
        expect(popped, isTrue); // Intercepted by PopScope
        await tester.pumpAndSettle();

        // No exit dialog shown
        expect(find.text('هل تريد الخروج من التطبيق؟'), findsNothing);

        // Successfully switched back to Home (Dashboard)
        expect(find.text('لوحة التحكم التنفيذية'), findsOneWidget);
      },
    );

    testWidgets('Home tab back press prompts exit confirmation dialog', (
      tester,
    ) async {
      await tester.pumpWidget(buildShell(initialIndex: 0));
      await tester.pumpAndSettle();

      expect(find.text('لوحة التحكم التنفيذية'), findsOneWidget);

      // Simulate Android Back Button press on Home tab
      final popped = await tester.binding.handlePopRoute();
      expect(popped, isTrue);
      await tester.pumpAndSettle();

      // Exit confirmation dialog is visible with Arabic copy
      expect(find.text('هل تريد الخروج من التطبيق؟'), findsOneWidget);
      expect(
        find.text('هل أنت متأكد من أنك تريد إغلاق التطبيق؟'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('stay_in_app_button')), findsOneWidget);
      expect(find.byKey(const Key('exit_app_button')), findsOneWidget);

      // Tap 'البقاء في التطبيق'
      await tester.tap(find.byKey(const Key('stay_in_app_button')));
      await tester.pumpAndSettle();

      // Dialog dismissed, user remains in app
      expect(find.text('هل تريد الخروج من التطبيق؟'), findsNothing);
      expect(find.text('لوحة التحكم التنفيذية'), findsOneWidget);
    });

    testWidgets(
      'Sub-screen back press pops back to previous route without showing exit dialog',
      (tester) async {
        await tester.pumpWidget(buildShell(initialIndex: 0));
        await tester.pumpAndSettle();

        // Push ItemEditorPage onto the navigator
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav.push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                ItemEditorPage(repository: fakeInventory),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ItemEditorPage), findsOneWidget);

        // Press Android Back button while inside sub-screen
        final popped = await tester.binding.handlePopRoute();
        expect(popped, isTrue);
        await tester.pumpAndSettle();

        // Sub-screen is popped, back on Home, NO exit dialog shown
        expect(find.byType(ItemEditorPage), findsNothing);
        expect(find.text('هل تريد الخروج من التطبيق؟'), findsNothing);
        expect(find.text('لوحة التحكم التنفيذية'), findsOneWidget);
      },
    );
  });
}
