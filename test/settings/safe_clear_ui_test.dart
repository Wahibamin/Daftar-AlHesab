import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/database/business_data_wiper.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/settings/pages/store_settings_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget _wrapWithRtlApp(Widget child) {
  return MaterialApp(
    theme: RafTheme.lightTheme,
    locale: const Locale('ar'),
    home: child,
  );
}

class FakeBusinessDataWiper extends BusinessDataWiper {
  bool wipeCalled = false;
  bool shouldThrow = false;

  @override
  Future<WipeSummary> clearAllBusinessData() async {
    wipeCalled = true;
    if (shouldThrow) {
      throw Exception('Simulated wipe error');
    }
    return const WipeSummary(
      invoiceItemsDeleted: 5,
      inventoryMovementsDeleted: 5,
      invoicesDeleted: 2,
      vouchersDeleted: 2,
      itemsDeleted: 4,
      partiesDeleted: 2,
      customUnitsDeleted: 1,
      customCategoriesDeleted: 1,
      settingsPreserved: 5,
    );
  }
}

void main() {
  sqfliteFfiInit();

  late String testDbPath;
  late FakeInventoryRepository fakeRepo;
  late FakeBusinessDataWiper fakeWiper;

  setUp(() async {
    final tempDir = Directory.systemTemp.createTempSync('raf_clear_ui_test_');
    testDbPath = '${tempDir.path}${Platform.pathSeparator}test.db';
    AppDatabase.instance.configureForTesting(
      factory: databaseFactoryFfi,
      path: testDbPath,
    );
    StoreSettingsManager.resetForTesting();
    await AppDatabase.instance.database;
    await StoreSettingsManager.instance.loadSettings();
    fakeRepo = FakeInventoryRepository();
    fakeWiper = FakeBusinessDataWiper();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    StoreSettingsManager.resetForTesting();
    try {
      final f = File(testDbPath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  });

  group('Safe Clear Business Data UI & Double Confirmation Widget Tests', () {
    testWidgets(
      '1. Danger Zone card renders with clear warning and dedicated wipe button',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithRtlApp(
            StoreSettingsPage(inventoryRepo: fakeRepo, wiper: fakeWiper),
          ),
        );
        await tester.pumpAndSettle();

        // Scroll to bottom to view Danger Zone
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();

        expect(find.text('منطقة العمليات الإدارية الحساسة'), findsOneWidget);
        expect(
          find.byKey(const Key('clear_business_data_button')),
          findsOneWidget,
        );
        expect(find.text('مسح جميع بيانات العمل المحلية'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Clicking wipe button opens confirmation dialog explaining deleted and preserved data',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithRtlApp(
            StoreSettingsPage(inventoryRepo: fakeRepo, wiper: fakeWiper),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();

        // Tap wipe button
        await tester.tap(find.byKey(const Key('clear_business_data_button')));
        await tester.pumpAndSettle();

        // Dialog is open
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('ما سيتم حذفه نهائياً:'), findsOneWidget);
        expect(find.text('ما سيتم الحفاظ عليه بالكامل:'), findsOneWidget);
        expect(find.text('مسح جميع البيانات'), findsWidgets);

        // Confirm button is disabled initially
        final confirmBtn = tester.widget<ElevatedButton>(
          find.byKey(const Key('confirm_clear_button')),
        );
        expect(confirmBtn.onPressed, isNull);
      },
    );

    testWidgets(
      '3. Cancel button in dialog closes dialog without calling wiper',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithRtlApp(
            StoreSettingsPage(inventoryRepo: fakeRepo, wiper: fakeWiper),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('clear_business_data_button')));
        await tester.pumpAndSettle();

        // Tap cancel
        await tester.tap(find.byKey(const Key('cancel_clear_button')));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(fakeWiper.wipeCalled, isFalse);
      },
    );

    testWidgets(
      '4. Typing incorrect or partial confirmation phrase leaves confirm button disabled',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithRtlApp(
            StoreSettingsPage(inventoryRepo: fakeRepo, wiper: fakeWiper),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('clear_business_data_button')));
        await tester.pumpAndSettle();

        final phraseField = find.byKey(
          const Key('clear_business_data_phrase_field'),
        );

        // Partial phrase
        await tester.enterText(phraseField, 'مسح البيانات');
        await tester.pumpAndSettle();

        var confirmBtn = tester.widget<ElevatedButton>(
          find.byKey(const Key('confirm_clear_button')),
        );
        expect(confirmBtn.onPressed, isNull);

        // Typo
        await tester.enterText(phraseField, 'مسح جميع البيانت');
        await tester.pumpAndSettle();

        confirmBtn = tester.widget<ElevatedButton>(
          find.byKey(const Key('confirm_clear_button')),
        );
        expect(confirmBtn.onPressed, isNull);
        expect(fakeWiper.wipeCalled, isFalse);
      },
    );

    testWidgets(
      '5. Typing exact confirmation phrase enables confirm button and successfully triggers wipe',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithRtlApp(
            StoreSettingsPage(inventoryRepo: fakeRepo, wiper: fakeWiper),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('clear_business_data_button')));
        await tester.pumpAndSettle();

        final phraseField = find.byKey(
          const Key('clear_business_data_phrase_field'),
        );

        // Enter exact phrase
        await tester.enterText(phraseField, 'مسح جميع البيانات');
        await tester.pumpAndSettle();

        final confirmBtnFinder = find.byKey(const Key('confirm_clear_button'));
        final confirmBtn = tester.widget<ElevatedButton>(confirmBtnFinder);
        expect(confirmBtn.onPressed, isNotNull);

        // Tap confirm
        await tester.tap(confirmBtnFinder);
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();

        // Wiper was called!
        expect(fakeWiper.wipeCalled, isTrue);
        // Dialog closed
        expect(find.byType(AlertDialog), findsNothing);
        // Success snackbar shown
        expect(
          find.text(
            'تم مسح جميع بيانات العمل بنجاح مع الحفاظ الكامل على إعدادات المنشأة.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '6. Handles failure during wipe gracefully and displays error alert',
      (tester) async {
        fakeWiper.shouldThrow = true;

        await tester.pumpWidget(
          _wrapWithRtlApp(
            StoreSettingsPage(inventoryRepo: fakeRepo, wiper: fakeWiper),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('clear_business_data_button')));
        await tester.pumpAndSettle();

        final phraseField = find.byKey(
          const Key('clear_business_data_phrase_field'),
        );
        await tester.enterText(phraseField, 'مسح جميع البيانات');
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('confirm_clear_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Error message rendered inside dialog
        expect(
          find.textContaining('تعذر إتمام عملية المسح بسبب خطأ أثناء المعاملة'),
          findsOneWidget,
        );
        // Dialog remains open for user awareness
        expect(find.byType(AlertDialog), findsOneWidget);
      },
    );
  });
}
