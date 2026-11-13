enum LicenseStatus {
  checking,
  activationRequired,
  active,
  expired,
  clockChanged,
  unavailable,
}

class LicenseState {
  final LicenseStatus status;
  final DateTime? activatedAt;
  final DateTime? expiresAt;
  final DateTime? observedAt;
  final String? message;

  const LicenseState(
    this.status, {
    this.activatedAt,
    this.expiresAt,
    this.observedAt,
    this.message,
  });

  bool get isActive => status == LicenseStatus.active;
  int get remainingDays {
    if (!isActive || expiresAt == null || observedAt == null) return 0;
    return (expiresAt!.difference(observedAt!).inMilliseconds /
            Duration.millisecondsPerDay)
        .ceil()
        .clamp(0, 1000);
  }
}

/// Calendar at the activation offset, fixed thereafter; clamp target month-end.
DateTime trialExpiry(DateTime activation, {int offsetMinutes = 0}) {
  final offset = Duration(minutes: offsetMinutes);
  final t = activation.toUtc().add(offset);
  final target = DateTime.utc(t.year, t.month + 3);
  final lastDay = DateTime.utc(target.year, target.month + 1, 0).day;
  return DateTime.utc(
    target.year,
    target.month,
    t.day.clamp(1, lastDay),
    t.hour,
    t.minute,
    t.second,
    t.millisecond,
    t.microsecond,
  ).subtract(offset);
}
