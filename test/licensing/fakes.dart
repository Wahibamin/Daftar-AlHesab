import 'package:m3/core/licensing/license_platform.dart';
import 'package:m3/core/licensing/license_service.dart';
import 'package:m3/core/licensing/license_state.dart';
import 'package:m3/core/licensing/trial_code_verifier.dart';

class FakeLicenseClock implements LicenseClock {
  DateTime utc;
  int elapsedMs = 10000;
  String bootId = 'boot-1';
  int offsetMinutes = 0;
  FakeLicenseClock(this.utc);
  void advance(Duration d) {
    utc = utc.add(d);
    elapsedMs += d.inMilliseconds;
  }

  @override
  Future<LicenseTime> now() async =>
      LicenseTime(utc, elapsedMs, bootId, offsetMinutes: offsetMinutes);
}

class MemoryLicenseStorage implements LicenseStorage {
  Map<String, dynamic>? data;
  bool corrupt = false;
  bool failWrites = false;
  bool failReads = false;
  int writes = 0;
  @override
  Future<StoredLicense> read() async {
    if (failReads) throw StateError('Injected read failure');
    return StoredLicense(
      record: data == null ? null : Map.of(data!),
      corrupt: corrupt,
    );
  }

  @override
  Future<void> write(Map<String, dynamic> record) async {
    if (failWrites) throw StateError('Injected I/O failure');
    writes++;
    data = Map.of(record);
  }
}

class FakeCodeVerifier implements LicenseCodeVerifier {
  @override
  bool configured = true;
  @override
  String configurationId = 'isolated-test-verifier';
  @override
  Future<bool> verify(String code) async =>
      code == 'TEST-ONLY-NOT-A-DISTRIBUTION-CODE';
}

const testOnlyCode = 'TEST-ONLY-NOT-A-DISTRIBUTION-CODE';

class FakeLicenseService extends LicenseService {
  int refreshCount = 0;
  LicenseState value;
  FakeLicenseService({LicenseState? initial})
    : value =
          initial ??
          LicenseState(
            LicenseStatus.active,
            activatedAt: DateTime.utc(2026, 1, 1),
            expiresAt: DateTime.utc(2026, 4, 1),
            observedAt: DateTime.utc(2026, 1, 1),
          );
  void set(LicenseState state) {
    value = state;
    notifyListeners();
  }

  @override
  LicenseState get state => value;
  @override
  Future<LicenseState> refresh() async {
    refreshCount++;
    return value;
  }

  @override
  Future<LicenseState> activate(String code) async => value;
  @override
  Future<LicenseState> renew(String credential) async => value;
}
