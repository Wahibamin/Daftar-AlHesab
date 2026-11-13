import 'dart:convert';
import 'package:flutter/services.dart';

class LicenseTime {
  final DateTime utc;
  final int elapsedMs;
  final String bootId;
  final int offsetMinutes;
  const LicenseTime(
    this.utc,
    this.elapsedMs,
    this.bootId, {
    this.offsetMinutes = 0,
  });
}

abstract interface class LicenseClock {
  Future<LicenseTime> now();
}

/// A missing installation identity is distinct from corruption in this install.
class StoredLicense {
  final Map<String, dynamic>? record;
  final bool corrupt;
  const StoredLicense({this.record, this.corrupt = false});
}

abstract interface class LicenseStorage {
  Future<StoredLicense> read();
  Future<void> write(Map<String, dynamic> record);
}

class AndroidLicensePlatform implements LicenseStorage, LicenseClock {
  static const channel = MethodChannel('com.example.m3/licensing');
  const AndroidLicensePlatform();

  @override
  Future<LicenseTime> now() async {
    final map = (await channel.invokeMapMethod<String, dynamic>('clock'))!;
    return LicenseTime(
      DateTime.fromMillisecondsSinceEpoch(map['utcMs'] as int, isUtc: true),
      map['elapsedMs'] as int,
      map['bootId'] as String,
      offsetMinutes: map['offsetMinutes'] as int,
    );
  }

  @override
  Future<StoredLicense> read() async {
    final map = (await channel.invokeMapMethod<String, dynamic>('read'))!;
    switch (map['status']) {
      case 'empty':
        return const StoredLicense();
      case 'ok':
        return StoredLicense(
          record: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
        );
      default:
        return const StoredLicense(corrupt: true);
    }
  }

  @override
  Future<void> write(Map<String, dynamic> record) =>
      channel.invokeMethod<void>('write', jsonEncode(record));
}
