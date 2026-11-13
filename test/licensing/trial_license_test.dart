import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/licensing/license_service.dart';
import 'package:m3/core/licensing/license_state.dart';
import 'package:m3/core/licensing/trial_code_verifier.dart';
import 'fakes.dart';

void main() {
  late MemoryLicenseStorage storage;
  late FakeLicenseClock clock;
  late FakeCodeVerifier verifier;
  late TemporaryTrialLicenseService service;
  setUp(() {
    storage = MemoryLicenseStorage();
    clock = FakeLicenseClock(DateTime.utc(2026, 1, 31, 12, 34, 56, 123));
    verifier = FakeCodeVerifier();
    service = TemporaryTrialLicenseService(
      storage: storage,
      clock: clock,
      verifier: verifier,
    );
  });

  test(
    'Fresh install has no grace period and never starts or persists a trial',
    () async {
      expect(
        (await service.refresh()).status,
        LicenseStatus.activationRequired,
      );
      clock.advance(const Duration(days: 100));
      expect(
        (await service.refresh()).status,
        LicenseStatus.activationRequired,
      );
      expect(storage.data, isNull);
      expect(storage.writes, 0);
    },
  );
  test('Incorrect or empty code cannot activate or write storage', () async {
    for (final code in ['', 'wrong', ' $testOnlyCode']) {
      expect((await service.activate(code)).isActive, false);
    }
    expect(storage.writes, 0);
  });
  test(
    'Correct code starts at successful verification and clamps calendar months',
    () async {
      final state = await service.activate(testOnlyCode);
      expect(state.activatedAt, clock.utc);
      expect(state.expiresAt, DateTime.utc(2026, 4, 30, 12, 34, 56, 123));
      expect(state.isActive, true);
      expect(storage.data!.containsValue(testOnlyCode), false);
    },
  );
  for (final row in [
    (DateTime.utc(2024, 2, 29, 9), DateTime.utc(2024, 5, 29, 9)),
    (DateTime.utc(2023, 11, 30, 9), DateTime.utc(2024, 2, 29, 9)),
    (DateTime.utc(2024, 11, 30, 9), DateTime.utc(2025, 2, 28, 9)),
    (DateTime.utc(2026, 8, 31, 9), DateTime.utc(2026, 11, 30, 9)),
    (DateTime.utc(2026, 12, 31, 9), DateTime.utc(2027, 3, 31, 9)),
    (DateTime.utc(2026, 2, 28, 9), DateTime.utc(2026, 5, 28, 9)),
  ]) {
    test(
      'Calendar boundary ${row.$1} => ${row.$2}',
      () => expect(trialExpiry(row.$1), row.$2),
    );
  }
  test(
    'Local midnight month-end uses activation timezone, later timezone changes cannot extend trial',
    () async {
      clock.utc = DateTime.utc(2026, 1, 30, 21, 30);
      clock.offsetMinutes = 180;
      final state = await service.activate(testOnlyCode);
      expect(state.expiresAt, DateTime.utc(2026, 4, 29, 21, 30));
      clock.offsetMinutes = -480;
      expect((await service.refresh()).expiresAt, state.expiresAt);
    },
  );
  test(
    'Last day and final microsecond stay active, exact expiry locks',
    () async {
      final expires = (await service.activate(testOnlyCode)).expiresAt!;
      clock.advance(expires.difference(clock.utc) - const Duration(days: 1));
      expect((await service.refresh()).isActive, true);
      expect(service.state.remainingDays, 1);
      clock.advance(const Duration(days: 1) - const Duration(microseconds: 1));
      expect((await service.refresh()).isActive, true);
      clock.advance(const Duration(microseconds: 1));
      expect((await service.refresh()).status, LicenseStatus.expired);
    },
  );
  test('Reopen and same-code retry cannot restart an expired trial', () async {
    await service.activate(testOnlyCode);
    final original = storage.data!['activatedMs'];
    clock.advance(const Duration(days: 100));
    final reopened = TemporaryTrialLicenseService(
      storage: storage,
      clock: clock,
      verifier: verifier,
    );
    expect((await reopened.refresh()).status, LicenseStatus.expired);
    expect(
      (await reopened.activate(testOnlyCode)).status,
      LicenseStatus.expired,
    );
    expect((await reopened.renew(testOnlyCode)).status, LicenseStatus.expired);
    expect(storage.data!['activatedMs'], original);
  });
  for (final boundary in [
    (const Duration(days: -1), LicenseStatus.active, 1),
    (const Duration(minutes: -1), LicenseStatus.active, 1),
    (Duration.zero, LicenseStatus.expired, 0),
    (const Duration(minutes: 1), LicenseStatus.expired, 0),
    (const Duration(days: 1), LicenseStatus.expired, 0),
  ]) {
    test(
      'Expiry boundary ${boundary.$1} survives restart and update',
      () async {
        final initial = await service.activate(testOnlyCode);
        clock.advance(initial.expiresAt!.difference(clock.utc) + boundary.$1);
        for (var restart = 0; restart < 2; restart++) {
          final updated = TemporaryTrialLicenseService(
            storage: storage,
            clock: clock,
            verifier:
                FakeCodeVerifier(), // Same configuration in an app update.
          );
          final state = await updated.refresh();
          expect(state.status, boundary.$2);
          expect(state.remainingDays, boundary.$3);
          expect(state.activatedAt, initial.activatedAt);
          expect(state.expiresAt, initial.expiresAt);
          await updated.activate(testOnlyCode);
          await updated.renew(testOnlyCode);
          expect(updated.state.status, boundary.$2);
          expect(updated.state.activatedAt, initial.activatedAt);
          expect(updated.state.expiresAt, initial.expiresAt);
          expect(
            storage.data!['activatedMs'],
            initial.activatedAt!.millisecondsSinceEpoch,
          );
          expect(
            storage.data!['expiresMs'],
            initial.expiresAt!.millisecondsSinceEpoch,
          );
          updated.dispose();
        }
      },
    );
  }
  test(
    'Update and normal reboot retain original activation and expiry',
    () async {
      final original = await service.activate(testOnlyCode);
      clock.advance(const Duration(days: 10));
      clock.bootId = 'boot-2';
      clock.elapsedMs = 2000;
      final update = TemporaryTrialLicenseService(
        storage: storage,
        clock: clock,
        verifier: verifier,
      );
      expect((await update.refresh()).isActive, true);
      expect(update.state.activatedAt, original.activatedAt);
      expect(update.state.expiresAt, original.expiresAt);
    },
  );
  test('New installation storage requires the correct code again', () async {
    await service.activate(testOnlyCode);
    final fresh = TemporaryTrialLicenseService(
      storage: MemoryLicenseStorage(),
      clock: clock,
      verifier: verifier,
    );
    expect((await fresh.refresh()).status, LicenseStatus.activationRequired);
    expect((await fresh.activate('wrong')).isActive, false);
    expect((await fresh.activate(testOnlyCode)).isActive, true);
  });
  test(
    'Storage read failure locks access without rewriting or restarting activation',
    () async {
      final activated = await service.activate(testOnlyCode);
      final before = Map.of(storage.data!);
      storage.failReads = true;
      expect((await service.refresh()).status, LicenseStatus.unavailable);
      expect((await service.activate(testOnlyCode)).isActive, false);
      expect(storage.data, before);
      storage.failReads = false;
      expect((await service.refresh()).isActive, true);
      expect(service.state.activatedAt, activated.activatedAt);
      expect(service.state.expiresAt, activated.expiresAt);
    },
  );
  test(
    'Unbound or corrupt restored record fails closed without resetting trial',
    () async {
      await service.activate(testOnlyCode);
      final before = Map.of(storage.data!);
      storage.corrupt = true;
      expect((await service.refresh()).status, LicenseStatus.unavailable);
      expect((await service.activate(testOnlyCode)).isActive, false);
      expect(storage.data, before);
    },
  );
  test(
    'Another verifier configuration cannot reuse QA or copied activation',
    () async {
      await service.activate(testOnlyCode);
      verifier.configurationId = 'different-owner-config';
      expect((await service.refresh()).status, LicenseStatus.unavailable);
    },
  );
  test(
    'Clock rollback beyond two minutes blocks and never moves high-water backward',
    () async {
      await service.activate(testOnlyCode);
      clock.advance(const Duration(days: 1));
      await service.refresh();
      final high = storage.data!['lastSeenMs'] as int;
      clock.utc = clock.utc.subtract(const Duration(hours: 1));
      expect((await service.refresh()).status, LicenseStatus.clockChanged);
      expect(storage.data!['lastSeenMs'], greaterThanOrEqualTo(high));
      clock.utc = DateTime.fromMillisecondsSinceEpoch(high, isUtc: true);
      expect((await service.refresh()).isActive, true);
    },
  );
  test(
    'Small backward adjustment is clamped without extending expiry',
    () async {
      final active = await service.activate(testOnlyCode);
      clock.utc = clock.utc.subtract(const Duration(seconds: 60));
      expect((await service.refresh()).isActive, true);
      expect(service.state.expiresAt, active.expiresAt);
      expect(service.state.observedAt, active.activatedAt);
    },
  );
  test(
    'Monotonic clock detects rollback even without a prior foreground refresh',
    () async {
      await service.activate(testOnlyCode);
      clock.elapsedMs += const Duration(days: 10).inMilliseconds;
      expect((await service.refresh()).status, LicenseStatus.clockChanged);
    },
  );
  test(
    'Expiry observed once remains expired after reboot and time rollback',
    () async {
      await service.activate(testOnlyCode);
      clock.advance(const Duration(days: 100));
      await service.refresh();
      clock.utc = DateTime.utc(2026, 2, 1);
      clock.bootId = 'new-boot';
      clock.elapsedMs = 200;
      expect((await service.refresh()).status, LicenseStatus.expired);
    },
  );
  test(
    'Unconfigured build and failed persistence never grant access',
    () async {
      verifier.configured = false;
      expect((await service.activate(testOnlyCode)).isActive, false);
      verifier.configured = true;
      storage.failWrites = true;
      expect((await service.activate(testOnlyCode)).isActive, false);
    },
  );
  test('Concurrent activation does not create multiple start dates', () async {
    await Future.wait([
      service.activate(testOnlyCode),
      service.activate(testOnlyCode),
      service.refresh(),
    ]);
    expect(service.state.activatedAt, clock.utc);
    expect(service.state.isActive, true);
  });
  test('PBKDF2 matches independent SHA256 test vectors', () {
    String hex(List<int> v) =>
        v.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    expect(
      hex(deriveTrialVerifier(utf8.encode('password'), utf8.encode('salt'), 1)),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      hex(deriveTrialVerifier(utf8.encode('password'), utf8.encode('salt'), 2)),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
  });
  test(
    'Real verifier accepts exact test input and rejects changed input',
    () async {
      final salt = List<int>.generate(16, (i) => i);
      final v = TrialCodeVerifier(
        saltBase64: base64Encode(salt),
        verifierBase64: base64Encode(
          deriveTrialVerifier(utf8.encode('PUBLIC-TEST-VECTOR'), salt, 120000),
        ),
        iterations: 120000,
      );
      expect(v.configured, true);
      expect(await v.verify('PUBLIC-TEST-VECTOR'), true);
      expect(await v.verify('PUBLIC-TEST-VECTOR '), false);
      expect(const TrialCodeVerifier.fromEnvironment().configured, false);
    },
  );
}
