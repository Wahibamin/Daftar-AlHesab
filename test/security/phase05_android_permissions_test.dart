import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PH05 app does not request unused call contacts or broad storage permissions',
    () {
      final text = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      for (final permission in [
        'CALL_PHONE',
        'READ_CONTACTS',
        'READ_EXTERNAL_STORAGE',
        'WRITE_EXTERNAL_STORAGE',
      ]) {
        expect(text, isNot(contains('android.permission.$permission')));
      }
      expect(text, contains('android.permission.CAMERA'));
      expect(text, contains('android.permission.INTERNET'));
      expect(text, isNot(contains('requestLegacyExternalStorage')));
    },
  );
  test(
    'Trial license is excluded while accounting backup remains eligible',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android:allowBackup="true"'));
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      final rules = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();
      for (final section in ['cloud-backup', 'device-transfer']) {
        final body = RegExp(
          '<$section>([\\s\\S]*?)</$section>',
        ).firstMatch(rules)!.group(1)!;
        expect(body, contains('domain="root" path="no_backup/"'));
        expect(body, isNot(contains('domain="database"')));
      }
      final legacy = File(
        'android/app/src/main/res/xml/backup_rules.xml',
      ).readAsStringSync();
      expect(legacy, contains('path="no_backup/"'));
      expect(legacy, isNot(contains('domain="database"')));
    },
  );
}
