import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/widgets/expiry_badge.dart';
import 'package:m3/features/inventory/widgets/item_card.dart';

Widget _wrapWithRtlApp(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    theme: RafTheme.lightTheme,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('ExpiryBadge & ItemModel Boundary Tests', () {
    final referenceDate = DateTime(
      2026,
      10,
      16,
      14,
      30,
    ); // Calendar date: 2026-10-16

    test('12. Item without expiry date returns null and renders no badge', () {
      final item = ItemModel(
        code: 'NO-EXP-01',
        name: 'منتج بدون صلاحية',
        unitId: 1,
        costPrice: const Money(100),
        sellingPrice: const Money(200),
        stockQuantity: 10,
        minAlertLimit: 2,
        expiryDate: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(item.remainingExpiryDays(referenceDate), isNull);
      expect(ExpiryBadge.calculateRemainingDays(null, referenceDate), isNull);
    });

    test('Calendar calculation ignores hours and minutes of the day', () {
      final todayMorning = DateTime(2026, 10, 16, 8, 0);
      final todayEvening = DateTime(2026, 10, 16, 23, 59);

      // Same calendar day must equal 0 days
      expect(
        ExpiryBadge.calculateRemainingDays(todayEvening, todayMorning),
        equals(0),
      );
      expect(
        ExpiryBadge.calculateRemainingDays(todayMorning, todayEvening),
        equals(0),
      );
    });

    test('Arabic phrasing formatting rules', () {
      expect(ExpiryBadge.formatRemainingDaysText(-5), equals('منتهي الصلاحية'));
      expect(ExpiryBadge.formatRemainingDaysText(-1), equals('منتهي الصلاحية'));
      expect(ExpiryBadge.formatRemainingDaysText(0), equals('ينتهي اليوم'));
      expect(ExpiryBadge.formatRemainingDaysText(1), equals('باقي يوم واحد'));
      expect(ExpiryBadge.formatRemainingDaysText(2), equals('باقي يومين'));
      expect(ExpiryBadge.formatRemainingDaysText(5), equals('باقي 5 أيام'));
      expect(ExpiryBadge.formatRemainingDaysText(10), equals('باقي 10 أيام'));
      expect(ExpiryBadge.formatRemainingDaysText(15), equals('باقي 15 يومًا'));
      expect(ExpiryBadge.formatRemainingDaysText(30), equals('باقي 30 يومًا'));
      expect(ExpiryBadge.formatRemainingDaysText(31), equals('باقي 31 يومًا'));
      expect(ExpiryBadge.formatRemainingDaysText(60), equals('باقي 60 يومًا'));
      expect(ExpiryBadge.formatRemainingDaysText(61), equals('باقي 61 يومًا'));
      expect(
        ExpiryBadge.formatRemainingDaysText(120),
        equals('باقي 120 يومًا'),
      );
    });
  });

  group('ExpiryBadge Widget Rendering & Strict Color Threshold Tests', () {
    final referenceDate = DateTime(2026, 10, 16, 12, 0);

    testWidgets('12. Renders nothing when expiryDate is null', (tester) async {
      await tester.pumpWidget(
        _wrapWithRtlApp(const ExpiryBadge(expiryDate: null)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Container), findsNothing);
    });

    testWidgets(
      '13. 120 days remaining: natural/green color and correct text',
      (tester) async {
        final date120 = DateTime(2026, 10, 16).add(const Duration(days: 120));
        await tester.pumpWidget(
          _wrapWithRtlApp(
            ExpiryBadge(expiryDate: date120, referenceDate: referenceDate),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('باقي 120 يومًا'), findsOneWidget);
        final textWidget = tester.widget<Text>(find.text('باقي 120 يومًا'));
        expect(textWidget.style?.color, equals(RafColors.success));
      },
    );

    testWidgets('14. 61 days remaining: natural/green color boundary', (
      tester,
    ) async {
      final date61 = DateTime(2026, 10, 16).add(const Duration(days: 61));
      await tester.pumpWidget(
        _wrapWithRtlApp(
          ExpiryBadge(expiryDate: date61, referenceDate: referenceDate),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('باقي 61 يومًا'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('باقي 61 يومًا'));
      expect(textWidget.style?.color, equals(RafColors.success));
    });

    testWidgets('15. 60 days remaining: yellow/amber warning boundary', (
      tester,
    ) async {
      final date60 = DateTime(2026, 10, 16).add(const Duration(days: 60));
      await tester.pumpWidget(
        _wrapWithRtlApp(
          ExpiryBadge(expiryDate: date60, referenceDate: referenceDate),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('باقي 60 يومًا'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('باقي 60 يومًا'));
      expect(textWidget.style?.color, equals(RafColors.warning));
    });

    testWidgets('16. 31 days remaining: yellow/amber warning boundary', (
      tester,
    ) async {
      final date31 = DateTime(2026, 10, 16).add(const Duration(days: 31));
      await tester.pumpWidget(
        _wrapWithRtlApp(
          ExpiryBadge(expiryDate: date31, referenceDate: referenceDate),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('باقي 31 يومًا'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('باقي 31 يومًا'));
      expect(textWidget.style?.color, equals(RafColors.warning));
    });

    testWidgets('17. 30 days remaining: red urgent warning boundary', (
      tester,
    ) async {
      final date30 = DateTime(2026, 10, 16).add(const Duration(days: 30));
      await tester.pumpWidget(
        _wrapWithRtlApp(
          ExpiryBadge(expiryDate: date30, referenceDate: referenceDate),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('باقي 30 يومًا'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('باقي 30 يومًا'));
      expect(textWidget.style?.color, equals(RafColors.danger));
    });

    testWidgets('18. 1 day remaining: red text "باقي يوم واحد"', (
      tester,
    ) async {
      final date1 = DateTime(2026, 10, 16).add(const Duration(days: 1));
      await tester.pumpWidget(
        _wrapWithRtlApp(
          ExpiryBadge(expiryDate: date1, referenceDate: referenceDate),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('باقي يوم واحد'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('باقي يوم واحد'));
      expect(textWidget.style?.color, equals(RafColors.danger));
    });

    testWidgets(
      '19. 0 days remaining (expires today): red text "ينتهي اليوم"',
      (tester) async {
        final todayDate = DateTime(2026, 10, 16);
        await tester.pumpWidget(
          _wrapWithRtlApp(
            ExpiryBadge(expiryDate: todayDate, referenceDate: referenceDate),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('ينتهي اليوم'), findsOneWidget);
        final textWidget = tester.widget<Text>(find.text('ينتهي اليوم'));
        expect(textWidget.style?.color, equals(RafColors.danger));
      },
    );

    testWidgets('20. Past date: red text "منتهي الصلاحية"', (tester) async {
      final pastDate = DateTime(2026, 10, 10);
      await tester.pumpWidget(
        _wrapWithRtlApp(
          ExpiryBadge(expiryDate: pastDate, referenceDate: referenceDate),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('منتهي الصلاحية'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('منتهي الصلاحية'));
      expect(textWidget.style?.color, equals(RafColors.danger));
    });

    testWidgets(
      '21. Changing expiry date updates badge without changing stock or prices',
      (tester) async {
        final initialItem = ItemModel(
          code: 'PROD-EXP-VAR',
          name: 'منتج اختبار تحديث الصلاحية',
          unitId: 1,
          costPrice: const Money(300),
          sellingPrice: const Money(450),
          stockQuantity: 25,
          minAlertLimit: 5,
          expiryDate: DateTime(2026, 10, 16).add(const Duration(days: 120)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          _wrapWithRtlApp(
            ItemCard(
              item: initialItem,
              unitName: 'حبة',
              referenceDate: referenceDate,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('باقي 120 يومًا'), findsOneWidget);
        expect(find.text('25 حبة'), findsOneWidget);
        expect(find.text(initialItem.sellingPrice.format()), findsOneWidget);

        // Change expiry date to 20 days remaining
        final updatedItem = initialItem.copyWith(
          expiryDate: DateTime(2026, 10, 16).add(const Duration(days: 20)),
        );

        await tester.pumpWidget(
          _wrapWithRtlApp(
            ItemCard(
              item: updatedItem,
              unitName: 'حبة',
              referenceDate: referenceDate,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Badge updated to new days
        expect(find.text('باقي 20 يومًا'), findsOneWidget);
        // Stock quantity and price remain completely identical
        expect(find.text('25 حبة'), findsOneWidget);
        expect(find.text(initialItem.sellingPrice.format()), findsOneWidget);
        expect(updatedItem.stockQuantity, equals(initialItem.stockQuantity));
        expect(updatedItem.costPrice, equals(initialItem.costPrice));
        expect(updatedItem.sellingPrice, equals(initialItem.sellingPrice));
      },
    );
  });

  group(
    'ItemCard with ExpiryBadge Responsive Layout & Non-Collision Tests',
    () {
      final referenceDate = DateTime(2026, 10, 16, 12, 0);

      final itemWithExpiry = ItemModel(
        code: 'PROD-EXP-001',
        name: 'حليب كامل الدسم طويل الأجل 1 لتر',
        unitId: 1,
        costPrice: const Money(450),
        sellingPrice: const Money(650),
        stockQuantity: 40,
        minAlertLimit: 10,
        expiryDate: DateTime(2026, 10, 16).add(const Duration(days: 15)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      for (final size in [
        const Size(320, 568), // Smallest mobile (iPhone SE 1st gen)
        const Size(360, 640), // Standard Android
        const Size(393, 873), // Modern Android / Pixel
        const Size(432, 932), // Large phone
      ]) {
        for (final scale in [1.0, 1.3, 1.6]) {
          testWidgets(
            'No overflow on ${size.width}x${size.height} at scale $scale',
            (tester) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1.0;
              addTearDown(() {
                tester.view.resetPhysicalSize();
                tester.view.resetDevicePixelRatio();
              });

              await tester.pumpWidget(
                _wrapWithRtlApp(
                  ItemCard(
                    item: itemWithExpiry,
                    unitName: 'حبة',
                    categoryName: 'ألبان وأجبان',
                    referenceDate: referenceDate,
                  ),
                  textScale: scale,
                ),
              );
              await tester.pumpAndSettle();

              // Verify all elements are found and distinct
              expect(find.text(itemWithExpiry.name), findsOneWidget);
              expect(find.text('باقي 15 يومًا'), findsOneWidget);
              expect(find.text('سعر البيع'), findsOneWidget);
              expect(
                find.text(itemWithExpiry.sellingPrice.format()),
                findsOneWidget,
              );
              expect(find.text('40 حبة'), findsOneWidget);

              // Zero RenderFlex overflow exceptions
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    },
  );
}
