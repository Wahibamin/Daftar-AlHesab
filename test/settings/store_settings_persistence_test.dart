import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/features/settings/pages/store_settings_page.dart';
import 'package:path/path.dart' hide equals;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late String testDbPath;

  setUp(() async {
    final tempDir = Directory.systemTemp.createTempSync('raf_settings_test_');
    testDbPath = join(tempDir.path, 'settings_test.db');
    AppDatabase.instance.configureForTesting(
      factory: databaseFactoryFfi,
      path: testDbPath,
    );
    StoreSettingsManager.resetForTesting();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    StoreSettingsManager.resetForTesting();
    try {
      final f = File(testDbPath);
      if (f.existsSync()) f.deleteSync();
      final dir = Directory(dirname(testDbPath));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Store Settings SQLite Persistence Tests', () {
    test(
      '1. Default settings are provided prior to any database write',
      () async {
        final manager = StoreSettingsManager.instance;
        expect(manager.isLoaded, isFalse);

        final settings = await manager.loadSettings();
        expect(manager.isLoaded, isTrue);

        expect(settings.storeName, 'مؤسسة دفتر الحساب للتجارة والتوريدات');
        expect(settings.taxNumber, '');
        expect(settings.phone, '0501234567');
        expect(settings.address, 'المملكة العربية السعودية - الرياض');
        expect(
          settings.invoiceFooterNote,
          contains('البضاعة المباعة ترد وتستبدل'),
        );
      },
    );

    test(
      '2. Saves store settings into SQLite and loads them accurately with all fields',
      () async {
        final manager = StoreSettingsManager.instance;

        const custom = StoreSettingsModel(
          storeName: 'شركة النجم الساطع التجارية',
          taxNumber: '310987654300003',
          phone: '0559988776',
          address: 'جدة - حي البلد',
          invoiceFooterNote:
              'شكراً لزيارتكم. يرجى إبراز أصل الفاتورة عند الاستبدال.',
        );

        await manager.saveSettings(custom);
        expect(manager.settings, equals(custom));

        // Query raw database directly to confirm physical SQLite storage
        final db = await AppDatabase.instance.database;
        final rows = await db.query(AppTables.appSettings);
        expect(rows.length, 5);

        final rowMap = {
          for (var r in rows) r['key'] as String: r['value'] as String,
        };
        expect(rowMap['store_name'], 'شركة النجم الساطع التجارية');
        expect(rowMap['tax_number'], '310987654300003');
        expect(rowMap['phone'], '0559988776');
        expect(rowMap['address'], 'جدة - حي البلد');
        expect(
          rowMap['invoice_footer_note'],
          'شكراً لزيارتكم. يرجى إبراز أصل الفاتورة عند الاستبدال.',
        );
      },
    );

    test(
      '3. Settings persist across closing and reopening database (Simulated App Restart)',
      () async {
        final manager1 = StoreSettingsManager.instance;

        const savedSettings = StoreSettingsModel(
          storeName: 'مؤسسة الرواد المتقدمة',
          taxNumber: '300999888777003',
          phone: '0500112233',
          address: 'الدمام - شارع الملك سعود',
          invoiceFooterNote: 'فاتورة ضريبية مبسطة. شكراً لاختياركم لنا.',
        );

        await manager1.saveSettings(savedSettings);

        // Simulate full app shutdown: Close database connection & reset in-memory manager
        await AppDatabase.instance.close();
        StoreSettingsManager.resetForTesting();

        // Configure new connection to the same physical SQLite file
        AppDatabase.instance.configureForTesting(
          factory: databaseFactoryFfi,
          path: testDbPath,
        );

        final manager2 = StoreSettingsManager.instance;
        // Before load, manager has in-memory defaults
        expect(manager2.isLoaded, isFalse);

        // Perform boot load as done in main()
        final reloaded = await manager2.loadSettings();

        expect(manager2.isLoaded, isTrue);
        expect(reloaded.storeName, 'مؤسسة الرواد المتقدمة');
        expect(reloaded.taxNumber, '300999888777003');
        expect(reloaded.phone, '0500112233');
        expect(reloaded.address, 'الدمام - شارع الملك سعود');
        expect(
          reloaded.invoiceFooterNote,
          'فاتورة ضريبية مبسطة. شكراً لاختياركم لنا.',
        );
        expect(reloaded, equals(savedSettings));
      },
    );

    test(
      '4. Loading settings does not overwrite user data with defaults',
      () async {
        final manager = StoreSettingsManager.instance;

        const userConfigured = StoreSettingsModel(
          storeName: 'متجر التوفير الذكي',
          taxNumber: '300777666555003',
          phone: '0544332211',
          address: 'المدينة المنورة',
          invoiceFooterNote: 'تذييل مخصص من المستخدم',
        );

        await manager.saveSettings(userConfigured);

        // Multiple calls to loadSettings must never revert to default
        final load1 = await manager.loadSettings();
        expect(load1.storeName, 'متجر التوفير الذكي');
        expect(load1.invoiceFooterNote, 'تذييل مخصص من المستخدم');

        final load2 = await manager.loadSettings();
        expect(load2.storeName, 'متجر التوفير الذكي');
        expect(load2.invoiceFooterNote, 'تذييل مخصص من المستخدم');
      },
    );
  });
}
