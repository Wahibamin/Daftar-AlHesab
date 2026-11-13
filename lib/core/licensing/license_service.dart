import 'dart:async';
import 'package:flutter/foundation.dart';
import 'license_platform.dart';
import 'license_state.dart';
import 'trial_code_verifier.dart';

abstract class LicenseService extends ChangeNotifier {
  LicenseState get state;
  Future<LicenseState> refresh();
  Future<LicenseState> activate(String code);

  /// Temporary trials cannot extend themselves. A future provider implements renewal.
  Future<LicenseState> renew(String credential);
}

class TemporaryTrialLicenseService extends LicenseService {
  final LicenseStorage storage;
  final LicenseClock clock;
  final LicenseCodeVerifier verifier;
  static const rollbackTolerance = Duration(minutes: 2);
  LicenseState _state = const LicenseState(LicenseStatus.checking);
  Future<void>? _queue;

  TemporaryTrialLicenseService({
    required this.storage,
    required this.clock,
    required this.verifier,
  });

  @override
  LicenseState get state => _state;

  Future<LicenseState> _serial(Future<LicenseState> Function() action) {
    final result = (_queue ?? Future<void>.value()).then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  LicenseState _publish(LicenseState value) {
    _state = value;
    notifyListeners();
    return value;
  }

  Future<LicenseState> _read({String? code}) async {
    try {
      if (!verifier.configured) {
        return _publish(
          const LicenseState(
            LicenseStatus.unavailable,
            message: 'هذه النسخة لم تُجهّز للتفعيل. يرجى مراجعة مالك التطبيق.',
          ),
        );
      }
      final saved = await storage.read();
      if (saved.corrupt) {
        return _publish(
          const LicenseState(
            LicenseStatus.unavailable,
            message:
                'تعذر التحقق من بيانات التفعيل لهذا التثبيت. يرجى التواصل مع مالك التطبيق.',
          ),
        );
      }
      final now = await clock.now();
      var record = saved.record;
      if (record == null) {
        if (code == null) {
          return _publish(const LicenseState(LicenseStatus.activationRequired));
        }
        if (!await verifier.verify(code)) {
          return _publish(
            const LicenseState(
              LicenseStatus.activationRequired,
              message: 'رمز التفعيل غير صحيح.',
            ),
          );
        }
        // The activation instant is sampled AFTER a successful verification.
        final activated = await clock.now();
        record = {
          'version': 1,
          'configurationId': verifier.configurationId,
          'activatedMs': activated.utc.millisecondsSinceEpoch,
          'offsetMinutes': activated.offsetMinutes,
          'expiresMs': trialExpiry(
            activated.utc,
            offsetMinutes: activated.offsetMinutes,
          ).millisecondsSinceEpoch,
          'lastSeenMs': activated.utc.millisecondsSinceEpoch,
          'elapsedMs': activated.elapsedMs,
          'bootId': activated.bootId,
          'expired': false,
        };
        await storage.write(record);
        return _publish(
          LicenseState(
            LicenseStatus.active,
            activatedAt: activated.utc,
            expiresAt: trialExpiry(
              activated.utc,
              offsetMinutes: activated.offsetMinutes,
            ),
            observedAt: activated.utc,
          ),
        );
      }
      final activated = DateTime.fromMillisecondsSinceEpoch(
        record['activatedMs'] as int,
        isUtc: true,
      );
      final expires = DateTime.fromMillisecondsSinceEpoch(
        record['expiresMs'] as int,
        isUtc: true,
      );
      final last = DateTime.fromMillisecondsSinceEpoch(
        record['lastSeenMs'] as int,
        isUtc: true,
      );
      final offset = record['offsetMinutes'] as int;
      if (offset < -840 ||
          offset > 840 ||
          record['version'] != 1 ||
          record['configurationId'] != verifier.configurationId ||
          expires != trialExpiry(activated, offsetMinutes: offset) ||
          last.isBefore(activated)) {
        throw const FormatException('Invalid license record');
      }
      var floor = last;
      if (record['bootId'] == now.bootId) {
        final delta = now.elapsedMs - (record['elapsedMs'] as int);
        if (delta < 0) throw const FormatException('Invalid monotonic clock');
        floor = last.add(Duration(milliseconds: delta));
      }
      final effective = now.utc.isAfter(floor) ? now.utc : floor;
      final expired = record['expired'] == true || !effective.isBefore(expires);
      final rollback = now.utc.isBefore(floor.subtract(rollbackTolerance));
      await storage.write({
        ...record,
        'lastSeenMs': effective.millisecondsSinceEpoch,
        'elapsedMs': now.elapsedMs,
        'bootId': now.bootId,
        'expired': expired,
      });
      return _publish(
        LicenseState(
          expired
              ? LicenseStatus.expired
              : rollback
              ? LicenseStatus.clockChanged
              : LicenseStatus.active,
          activatedAt: activated,
          expiresAt: expires,
          observedAt: effective,
          message: rollback && !expired
              ? 'وقت الهاتف أقدم من آخر وقت مسجل. صحح التاريخ والوقت ثم أعد التحقق؛ لم تبدأ فترة جديدة.'
              : null,
        ),
      );
    } catch (_) {
      return _publish(
        const LicenseState(
          LicenseStatus.unavailable,
          message:
              'تعذر التحقق من الترخيص محلياً. لم تتغير بيانات الحسابات. أعد المحاولة أو تواصل مع مالك التطبيق.',
        ),
      );
    }
  }

  @override
  Future<LicenseState> refresh() => _serial(() => _read());
  @override
  Future<LicenseState> activate(String code) =>
      _serial(() => _read(code: code));
  @override
  Future<LicenseState> renew(String credential) => refresh();
}

abstract final class LicenseRuntime {
  static final LicenseService service = TemporaryTrialLicenseService(
    storage: const AndroidLicensePlatform(),
    clock: const AndroidLicensePlatform(),
    verifier: const TrialCodeVerifier.fromEnvironment(),
  );
}

class LicenseRequiredException implements Exception {
  const LicenseRequiredException();
  @override
  String toString() =>
      'الترخيص غير صالح لبدء عملية جديدة. يرجى التحقق من التفعيل.';
}

class LicenseGuard {
  final LicenseService service;
  const LicenseGuard(this.service);
  Future<void> check() async {
    if (!(await service.refresh()).isActive) {
      throw const LicenseRequiredException();
    }
  }
}
