import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../test_support/production_scenarios.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late ProductionScenarios scenarios;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daftar_policy_');
    scenarios = ProductionScenarios(
      factory: databaseFactoryFfi,
      directory: directory,
      fixturePath:
          'audit/final_release_acceptance/sqlite_snapshots/AFTER_CAMERA_FIX/raf_erp.db',
    );
  });
  tearDown(() async {
    await scenarios.manager.close();
    await directory.delete(recursive: true);
  });
  final names = ProductionScenarios(
    factory: databaseFactoryFfi,
    directory: Directory.systemTemp,
    fixturePath: '',
  ).cases.keys.toList();
  for (final name in names) {
    test('Production policy: $name', () async {
      await scenarios.reset(name);
      await scenarios.cases[name]!();
    });
  }
}
