import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:m3/core/licensing/license_gate.dart';
import 'package:m3/core/licensing/license_platform.dart';
import 'package:m3/core/licensing/license_service.dart';
import 'package:m3/core/licensing/license_state.dart';
import 'package:m3/core/licensing/licensed_database.dart';
import 'package:m3/core/licensing/trial_code_verifier.dart';
import 'package:sqflite/sqflite.dart';

class _TestClock implements LicenseClock {
  DateTime utc = DateTime.utc(2026, 1, 31, 12);
  int elapsed = 1000;
  String boot = 'qa-boot';
  void advance(Duration duration) {
    utc = utc.add(duration);
    elapsed += duration.inMilliseconds;
  }

  @override
  Future<LicenseTime> now() async => LicenseTime(utc, elapsed, boot);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Real Android licensing, expiry, resume and atomic transactions',
    (tester) async {
      if (kReleaseMode) throw StateError('QA entrypoint is Debug only');
      const platform = AndroidLicensePlatform();
      final clock = _TestClock();
      // Public fixture only. Never uses or replaces the owner's configuration.
      const code = 'PUBLIC-ANDROID-LICENSE-TEST';
      final salt = List<int>.generate(32, (i) => i);
      final verifier = TrialCodeVerifier(
        saltBase64: base64Encode(salt),
        verifierBase64: base64Encode(
          deriveTrialVerifier(utf8.encode(code), salt, 120000),
        ),
        iterations: 120000,
      );
      final service = TemporaryTrialLicenseService(
        storage: platform,
        clock: clock,
        verifier: verifier,
      );
      final passed = <String>[];
      void record(String name) {
        passed.add(name);
        debugPrint('LICENSE_QA_PASS: $name');
      }

      Database? raw;
      try {
        await tester.runAsync(() async {
          final nativeTime = await platform.now();
          expect(nativeTime.elapsedMs, greaterThan(0));
          expect((await platform.read()).record, isNull);
          expect(
            (await service.refresh()).status,
            LicenseStatus.activationRequired,
          );
          record('fresh_install_requires_activation');
          expect((await service.activate('QA-WRONG-CODE')).isActive, false);
          expect((await platform.read()).record, isNull);
          record('real_verifier_rejects_wrong_code_without_storage_write');
          expect((await service.activate(code)).isActive, true);
          expect(service.state.expiresAt, DateTime.utc(2026, 4, 30, 12));
          record('real_verifier_accepts_public_fixture_three_calendar_months');
          final reopened = TemporaryTrialLicenseService(
            storage: platform,
            clock: clock,
            verifier: verifier,
          );
          expect((await reopened.refresh()).isActive, true);
          expect(reopened.state.activatedAt, service.state.activatedAt);
          reopened.dispose();
          record('native_keystore_activation_survives_service_recreation');
          clock.advance(const Duration(days: 1));
          await service.refresh();
          final correct = clock.utc;
          clock.utc = clock.utc.subtract(const Duration(hours: 1));
          expect((await service.refresh()).status, LicenseStatus.clockChanged);
          clock.utc = correct;
          expect((await service.refresh()).isActive, true);
          record('test_clock_rollback_blocks_then_recovers');
          raw = await openDatabase(inMemoryDatabasePath);
          await raw!.execute(
            'CREATE TABLE license_qa (id INTEGER PRIMARY KEY)',
          );
        });
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) =>
                LicenseGate(service: service, child: child!),
            home: const Scaffold(body: Text('Protected QA operations')),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Protected QA operations'), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        // A live Android binding cannot pump frames while paused.
        final licensed = LicensedDatabase(raw!, LicenseGuard(service));
        await tester.runAsync(() async {
          await licensed.transaction((txn) async {
            await txn.insert('license_qa', {'id': 1});
            clock.advance(const Duration(days: 100));
            await txn.insert('license_qa', {'id': 2});
          });
          expect((await raw!.query('license_qa')).length, 2);
        });
        record('native_sqlite_accepted_transaction_completes_across_expiry');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 15));
          while (service.state.status != LicenseStatus.expired &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          expect(service.state.status, LicenseStatus.expired);
        });
        await tester.pumpAndSettle();
        expect(find.text('انتهت الفترة التجريبية'), findsOneWidget);
        expect(find.text('Protected QA operations'), findsNothing);
        record('resume_expiry_removes_protected_ui_and_displays_expiry_screen');
        await tester.runAsync(() async {
          await expectLater(
            licensed.insert('license_qa', {'id': 3}),
            throwsA(isA<LicenseRequiredException>()),
          );
          expect((await raw!.query('license_qa')).length, 2);
          record(
            'expired_license_blocks_new_native_sqlite_operation_preserves_data',
          );
          clock.utc = DateTime.utc(2026, 2, 1);
          clock.boot = 'qa-reboot';
          clock.elapsed = 100;
          expect((await service.refresh()).status, LicenseStatus.expired);
          record(
            'observed_expiry_persists_across_test_reboot_and_time_rollback',
          );
        });
        binding.reportData = {
          'passed_checks': passed,
          'owner_code_used': false,
        };
      } finally {
        if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          // Drain a refresh already queued by the gate before disposing it.
          await service.refresh();
          await raw?.close();
        });
        service.dispose();
      }
    },
  );
}
