import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/licensing/license_gate.dart';
import 'package:m3/core/licensing/license_service.dart';
import 'package:m3/core/licensing/license_state.dart';
import 'fakes.dart';

void main() {
  late MemoryLicenseStorage storage;
  late FakeLicenseClock clock;
  late TemporaryTrialLicenseService service;
  setUp(() {
    storage = MemoryLicenseStorage();
    clock = FakeLicenseClock(DateTime.utc(2026, 1, 31, 12));
    service = TemporaryTrialLicenseService(
      storage: storage,
      clock: clock,
      verifier: FakeCodeVerifier(),
    );
  });
  Widget app({
    GlobalKey<NavigatorState>? nav,
    Widget? home,
    LicenseService? provider,
  }) => MaterialApp(
    navigatorKey: nav,
    builder: (context, child) =>
        LicenseGate(service: provider ?? service, child: child!),
    home: home ?? const Scaffold(body: Text('Protected business app')),
    routes: {'/internal': (_) => const Scaffold(body: Text('Internal route'))},
  );
  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets(
    'Unactivated gate never mounts Navigator, alternative routes, or business widgets',
    (t) async {
      final nav = GlobalKey<NavigatorState>();
      int businessBuilds = 0;
      await t.pumpWidget(
        app(
          nav: nav,
          home: Builder(
            builder: (_) {
              businessBuilds++;
              return const Text('Sensitive');
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('تفعيل دفتر الحساب'), findsOneWidget);
      expect(businessBuilds, 0);
      expect(nav.currentState, isNull);
      expect(find.text('Sensitive'), findsNothing);
      final field = t.widget<TextField>(find.byKey(const Key('license_code')));
      expect(field.obscureText, true);
      await disposeApp(t);
    },
  );
  testWidgets(
    'Wrong code stays locked, correct code mounts app and clears input',
    (t) async {
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('license_code')), 'wrong');
      await t.tap(find.text('تفعيل التطبيق'));
      await t.pumpAndSettle();
      expect(find.text('رمز التفعيل غير صحيح.'), findsOneWidget);
      expect(find.text('Protected business app'), findsNothing);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('license_code')))
            .controller!
            .text,
        isEmpty,
      );
      await t.enterText(find.byKey(const Key('license_code')), testOnlyCode);
      await t.tap(find.text('تفعيل التطبيق'));
      await t.pumpAndSettle();
      expect(find.text('Protected business app'), findsOneWidget);
      await disposeApp(t);
    },
  );
  testWidgets('Expiry removes an already pushed internal route', (t) async {
    await service.activate(testOnlyCode);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(app(nav: nav));
    await t.pumpAndSettle();
    nav.currentState!.pushNamed('/internal');
    await t.pumpAndSettle();
    expect(find.text('Internal route'), findsOneWidget);
    clock.advance(const Duration(days: 100));
    await service.refresh();
    await t.pumpAndSettle();
    expect(find.text('انتهت الفترة التجريبية'), findsOneWidget);
    expect(find.text('Internal route'), findsNothing);
    expect(nav.currentState, isNull);
    expect(storage.data, isNotNull);
    await disposeApp(t);
  });
  for (final offset in [
    const Duration(days: -1),
    const Duration(minutes: -1),
    Duration.zero,
    const Duration(minutes: 1),
    const Duration(days: 1),
  ]) {
    testWidgets('Navigation permission at expiry offset $offset', (t) async {
      final initial = await service.activate(testOnlyCode);
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(app(nav: nav));
      await t.pumpAndSettle();
      clock.advance(initial.expiresAt!.difference(clock.utc) + offset);
      await service.refresh();
      await t.pumpAndSettle();
      if (offset.isNegative) {
        expect(find.text('Protected business app'), findsOneWidget);
        expect(nav.currentState, isNotNull);
      } else {
        expect(find.text('انتهت الفترة التجريبية'), findsOneWidget);
        expect(find.text('Protected business app'), findsNothing);
        expect(nav.currentState, isNull);
      }
      expect(
        storage.data!['activatedMs'],
        initial.activatedAt!.millisecondsSinceEpoch,
      );
      expect(
        storage.data!['expiresMs'],
        initial.expiresAt!.millisecondsSinceEpoch,
      );
      await disposeApp(t);
    });
  }
  testWidgets('Settings card reads persisted expiry and days without writing', (
    t,
  ) async {
    final initial = await service.activate(testOnlyCode);
    clock.advance(
      initial.expiresAt!.difference(clock.utc) - const Duration(days: 1),
    );
    await service.refresh();
    final before = Map.of(storage.data!);
    final writes = storage.writes;
    final expiry = initial.expiresAt!.toLocal();
    await t.pumpWidget(
      MaterialApp(
        home: LicenseScope(
          service: service,
          child: const Scaffold(body: TrialLicenseInfo()),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.textContaining(
        'ينتهي التفعيل: ${expiry.year}/${expiry.month}/${expiry.day}',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('الأيام المتبقية: 1'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(storage.writes, writes);
    expect(storage.data, before);
    await disposeApp(t);
  });
  testWidgets('Resume after expiry locks before operational UI is exposed', (
    t,
  ) async {
    await service.activate(testOnlyCode);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    clock.advance(const Duration(days: 100));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('انتهت الفترة التجريبية'), findsOneWidget);
    expect(find.text('Protected business app'), findsNothing);
    await disposeApp(t);
  });
  testWidgets('Normal pause and resume preserve the current navigation route', (
    t,
  ) async {
    await service.activate(testOnlyCode);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(app(nav: nav));
    await t.pumpAndSettle();
    nav.currentState!.pushNamed('/internal');
    await t.pumpAndSettle();
    final before = nav.currentState;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    clock.advance(const Duration(minutes: 1));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(nav.currentState, same(before));
    expect(find.text('Internal route'), findsOneWidget);
    await disposeApp(t);
  });
  testWidgets('A single foreground expiry timer locks an idle app', (t) async {
    await service.activate(testOnlyCode);
    final delta =
        service.state.expiresAt!.difference(clock.utc) -
        const Duration(seconds: 2);
    clock.advance(delta);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    clock.advance(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.text('انتهت الفترة التجريبية'), findsOneWidget);
    await disposeApp(t);
  });
  testWidgets(
    'No refresh timers run in background, including after a late service notification',
    (t) async {
      final fake = FakeLicenseService();
      await t.pumpWidget(app(provider: fake));
      await t.pumpAndSettle();
      final calls = fake.refreshCount;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      fake.set(fake.state);
      await t.pump(const Duration(days: 2));
      expect(fake.refreshCount, calls);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(fake.refreshCount, calls + 1);
      await disposeApp(t);
    },
  );
  testWidgets(
    'Settings shows expiry and days and accepts a future service implementation',
    (t) async {
      final replacement = FakeLicenseService();
      await t.pumpWidget(
        app(
          provider: replacement,
          home: const Scaffold(body: TrialLicenseInfo()),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('النسخة التجريبية'), findsOneWidget);
      expect(find.textContaining('الأيام المتبقية: 90'), findsOneWidget);
      replacement.set(const LicenseState(LicenseStatus.expired));
      await t.pumpAndSettle();
      expect(find.text('انتهت الفترة التجريبية'), findsOneWidget);
      await disposeApp(t);
    },
  );
}
