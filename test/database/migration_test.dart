import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late String testDbPath;

  setUp(() async {
    final tempDir = Directory.systemTemp.createTempSync('raf_migration_test_');
    testDbPath = join(tempDir.path, 'migration_test.db');
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    try {
      final f = File(testDbPath);
      if (f.existsSync()) f.deleteSync();
      final dir = Directory(dirname(testDbPath));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
    'Non-destructive SQLite migration from Version 1 to Version 2 preserves and backfills data',
    () async {
      final factory = databaseFactoryFfi;

      // 1. Manually create database at Version 1 (prior schema)
      final dbV1 = await factory.openDatabase(
        testDbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            // Version 1 parties schema (without opening_balance_int)
            await db.execute('''
            CREATE TABLE ${AppTables.parties} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              phone TEXT NOT NULL,
              type TEXT NOT NULL,
              current_balance_int INTEGER NOT NULL DEFAULT 0,
              credit_limit_int INTEGER NOT NULL DEFAULT 0,
              address TEXT,
              tax_number TEXT,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
          ''');

            // Version 1 items schema
            await db.execute('''
            CREATE TABLE ${AppTables.items} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              code TEXT NOT NULL UNIQUE,
              name TEXT NOT NULL,
              unit_id INTEGER NOT NULL DEFAULT 1,
              cost_price_int INTEGER NOT NULL DEFAULT 0,
              selling_price_int INTEGER NOT NULL DEFAULT 0,
              stock_quantity_int INTEGER NOT NULL DEFAULT 0,
              min_alert_limit_int INTEGER NOT NULL DEFAULT 0,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
          ''');

            // Version 1 invoices schema
            await db.execute('''
            CREATE TABLE ${AppTables.invoices} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              invoice_number TEXT NOT NULL UNIQUE,
              party_id INTEGER,
              invoice_type TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'draft',
              payment_type TEXT NOT NULL DEFAULT 'cash',
              subtotal_int INTEGER NOT NULL DEFAULT 0,
              discount_int INTEGER NOT NULL DEFAULT 0,
              tax_int INTEGER NOT NULL DEFAULT 0,
              total_int INTEGER NOT NULL DEFAULT 0,
              paid_amount_int INTEGER NOT NULL DEFAULT 0,
              remaining_amount_int INTEGER NOT NULL DEFAULT 0,
              invoice_date INTEGER NOT NULL,
              notes TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
          ''');

            // Version 1 invoice_items schema (without unit_cost_int)
            await db.execute('''
            CREATE TABLE ${AppTables.invoiceItems} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              invoice_id INTEGER NOT NULL,
              item_id INTEGER NOT NULL,
              quantity_int INTEGER NOT NULL,
              unit_price_int INTEGER NOT NULL,
              discount_int INTEGER NOT NULL DEFAULT 0,
              tax_rate_percent INTEGER NOT NULL DEFAULT 15,
              tax_amount_int INTEGER NOT NULL DEFAULT 0,
              total_price_int INTEGER NOT NULL
            );
          ''');

            // Version 1 inventory movements schema
            await db.execute('''
            CREATE TABLE ${AppTables.inventoryMovements} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              item_id INTEGER NOT NULL,
              movement_type TEXT NOT NULL,
              quantity_int INTEGER NOT NULL,
              unit_cost_int INTEGER NOT NULL DEFAULT 0,
              reference_id INTEGER,
              reference_type TEXT,
              movement_date INTEGER NOT NULL,
              notes TEXT,
              created_at INTEGER NOT NULL
            );
          ''');

            // Version 1 vouchers schema (without status column)
            await db.execute('''
            CREATE TABLE ${AppTables.vouchers} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              voucher_number TEXT NOT NULL UNIQUE,
              voucher_type TEXT NOT NULL,
              party_id INTEGER,
              amount_int INTEGER NOT NULL,
              payment_method TEXT NOT NULL,
              reference_number TEXT,
              statement TEXT,
              voucher_date INTEGER NOT NULL,
              created_at INTEGER NOT NULL
            );
          ''');
          },
        ),
      );

      final now = DateTime.now().millisecondsSinceEpoch;

      // 2. Populate Version 1 data
      final v1PartyId = await dbV1.insert(AppTables.parties, {
        'name': 'العميل التاريخي',
        'phone': '0501239999',
        'type': 'customer',
        'current_balance_int': -75000, // Debtor 750.00 SAR
        'credit_limit_int': 200000,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      final v1ItemId = await dbV1.insert(AppTables.items, {
        'code': 'LEGACY-001',
        'name': 'صنف مخزني قديم',
        'cost_price_int': 1800, // 18.00 SAR
        'selling_price_int': 2500, // 25.00 SAR
        'stock_quantity_int': 100,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      final v1InvId = await dbV1.insert(AppTables.invoices, {
        'invoice_number': 'INV-2025-0099',
        'party_id': v1PartyId,
        'invoice_type': 'sale',
        'status': 'approved',
        'payment_type': 'credit',
        'total_int': 75000,
        'paid_amount_int': 0,
        'remaining_amount_int': 75000,
        'invoice_date': now,
        'created_at': now,
        'updated_at': now,
      });

      await dbV1.insert(AppTables.invoiceItems, {
        'invoice_id': v1InvId,
        'item_id': v1ItemId,
        'quantity_int': 3,
        'unit_price_int': 2500,
        'total_price_int': 7500,
      });

      final v1VoucherId = await dbV1.insert(AppTables.vouchers, {
        'voucher_number': 'REC-2025-0044',
        'voucher_type': 'receipt',
        'party_id': v1PartyId,
        'amount_int': 35000,
        'payment_method': 'cash',
        'statement': 'سند تاريخي',
        'voucher_date': now,
        'created_at': now,
      });

      // Close Version 1 DB connection
      await dbV1.close();

      // 3. Open DB with AppDatabase (Version 2) to trigger migration!
      AppDatabase.instance.configureForTesting(
        factory: factory,
        path: testDbPath,
      );

      final dbV2 = await AppDatabase.instance.database;

      // 4. Verify Migration Integrity
      // Check Parties table
      final partyRows = await dbV2.query(
        AppTables.parties,
        where: 'id = ?',
        whereArgs: [v1PartyId],
      );
      expect(partyRows, isNotEmpty);
      final partyData = partyRows.first;
      expect(partyData['name'], 'العميل التاريخي');
      expect(partyData['current_balance_int'], -75000); // Preserved!
      expect(partyData['opening_balance_int'], 0); // Added column with default!

      // Check Invoice Items table
      final itemRows = await dbV2.query(
        AppTables.invoiceItems,
        where: 'invoice_id = ?',
        whereArgs: [v1InvId],
      );
      expect(itemRows, isNotEmpty);
      final itemData = itemRows.first;
      expect(
        itemData['unit_cost_int'],
        1800,
      ); // Backfilled from items.cost_price_int!

      // Check Vouchers table
      final voucherRows = await dbV2.query(
        AppTables.vouchers,
        where: 'id = ?',
        whereArgs: [v1VoucherId],
      );
      expect(voucherRows, isNotEmpty);
      final voucherData = voucherRows.first;
      expect(voucherData['voucher_number'], 'REC-2025-0044');
      expect(
        voucherData['status'],
        'approved',
      ); // Added column with default 'approved'!

      // 5. Verify app_settings table exists and accepts records (Version 3)
      await dbV2.insert(AppTables.appSettings, {
        'key': 'store_name',
        'value': 'متجر الترقية الآمنة',
      });
      final settingsRows = await dbV2.query(
        AppTables.appSettings,
        where: 'key = ?',
        whereArgs: ['store_name'],
      );
      expect(settingsRows, isNotEmpty);
      expect(settingsRows.first['value'], 'متجر الترقية الآمنة');

      // 6. Verify we can insert new records with new columns
      final newPartyId = await dbV2.insert(AppTables.parties, {
        'name': 'عميل النسخة 3',
        'phone': '0599998888',
        'type': 'customer',
        'current_balance_int': -20000,
        'opening_balance_int': -20000,
        'credit_limit_int': 50000,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      expect(newPartyId, greaterThan(0));

      final newPartyRow = await dbV2.query(
        AppTables.parties,
        where: 'id = ?',
        whereArgs: [newPartyId],
      );
      expect(newPartyRow.first['opening_balance_int'], -20000);
    },
  );

  test(
    'Non-destructive SQLite migration from Version 2 to Version 3 preserves existing data and creates app_settings',
    () async {
      final factory = databaseFactoryFfi;
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Manually create database at Version 2 schema
      final dbV2 = await factory.openDatabase(
        testDbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            // Minimal old fixture must still provide both referenced parent tables.
            await db.execute(
              'CREATE TABLE invoices (id INTEGER PRIMARY KEY, party_id INTEGER, status TEXT, invoice_date INTEGER, invoice_type TEXT, paid_amount_int INTEGER, payment_type TEXT, invoice_number TEXT, created_at INTEGER)',
            );
            await db.execute('''
            CREATE TABLE ${AppTables.parties} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              phone TEXT NOT NULL,
              type TEXT NOT NULL,
              current_balance_int INTEGER NOT NULL DEFAULT 0,
              opening_balance_int INTEGER NOT NULL DEFAULT 0,
              credit_limit_int INTEGER NOT NULL DEFAULT 0,
              address TEXT,
              tax_number TEXT,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
          ''');

            await db.execute('''
            CREATE TABLE ${AppTables.vouchers} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              voucher_number TEXT NOT NULL UNIQUE,
              voucher_type TEXT NOT NULL,
              party_id INTEGER,
              amount_int INTEGER NOT NULL,
              payment_method TEXT NOT NULL,
              reference_number TEXT,
              statement TEXT,
              status TEXT NOT NULL DEFAULT 'approved',
              voucher_date INTEGER NOT NULL,
              created_at INTEGER NOT NULL
            );
          ''');
          },
        ),
      );

      // 2. Populate Version 2 data
      final v2PartyId = await dbV2.insert(AppTables.parties, {
        'name': 'عميل النسخة 2 القائم',
        'phone': '0512345678',
        'type': 'customer',
        'current_balance_int': -15000,
        'opening_balance_int': -10000,
        'credit_limit_int': 50000,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      await dbV2.insert(AppTables.vouchers, {
        'voucher_number': 'REC-2026-0001',
        'voucher_type': 'receipt',
        'party_id': v2PartyId,
        'amount_int': 5000,
        'payment_method': 'cash',
        'statement': 'سند تسديد في النسخة 2',
        'status': 'approved',
        'voucher_date': now,
        'created_at': now,
      });

      await dbV2.close();

      // 3. Open DB with AppDatabase (Version 3) to trigger v2 -> v3 migration
      AppDatabase.instance.configureForTesting(
        factory: factory,
        path: testDbPath,
      );

      final dbV3 = await AppDatabase.instance.database;

      // 4. Verify v2 data is 100% preserved
      final partyRows = await dbV3.query(
        AppTables.parties,
        where: 'id = ?',
        whereArgs: [v2PartyId],
      );
      expect(partyRows, isNotEmpty);
      expect(partyRows.first['name'], 'عميل النسخة 2 القائم');
      expect(partyRows.first['opening_balance_int'], -10000);
      expect(partyRows.first['current_balance_int'], -15000);

      // 5. Verify app_settings table was created cleanly and is fully functional
      await dbV3.insert(AppTables.appSettings, {
        'key': 'store_name',
        'value': 'مؤسسة النسخة الثالثة',
      });
      await dbV3.insert(AppTables.appSettings, {
        'key': 'tax_number',
        'value': '310000000000003',
      });

      final settingsRows = await dbV3.query(AppTables.appSettings);
      expect(settingsRows.length, 2);
    },
  );

  test(
    'Non-destructive SQLite migration from Version 3 to Version 4 creates all composite indexes',
    () async {
      final factory = databaseFactoryFfi;
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Manually create database at Version 3
      final dbV3 = await factory.openDatabase(
        testDbPath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE ${AppTables.items} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              code TEXT NOT NULL UNIQUE,
              name TEXT NOT NULL,
              unit_id INTEGER NOT NULL DEFAULT 1,
              category_id INTEGER,
              cost_price_int INTEGER NOT NULL DEFAULT 0,
              selling_price_int INTEGER NOT NULL DEFAULT 0,
              stock_quantity_int INTEGER NOT NULL DEFAULT 0,
              min_alert_limit_int INTEGER NOT NULL DEFAULT 0,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
          ''');
            await db.execute('''
            CREATE TABLE ${AppTables.parties} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              phone TEXT NOT NULL,
              type TEXT NOT NULL,
              current_balance_int INTEGER NOT NULL DEFAULT 0,
              opening_balance_int INTEGER NOT NULL DEFAULT 0,
              credit_limit_int INTEGER NOT NULL DEFAULT 0,
              address TEXT,
              tax_number TEXT,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
          ''');
            await db.execute('''
            CREATE TABLE ${AppTables.invoices} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              invoice_number TEXT NOT NULL UNIQUE,
              party_id INTEGER,
              invoice_type TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'approved',
              payment_type TEXT NOT NULL DEFAULT 'cash',
              subtotal_int INTEGER NOT NULL DEFAULT 0,
              discount_int INTEGER NOT NULL DEFAULT 0,
              tax_int INTEGER NOT NULL DEFAULT 0,
              total_int INTEGER NOT NULL DEFAULT 0,
              paid_amount_int INTEGER NOT NULL DEFAULT 0,
              remaining_amount_int INTEGER NOT NULL DEFAULT 0,
              invoice_date INTEGER NOT NULL,
              notes TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
          ''');
            await db.execute('''
            CREATE TABLE ${AppTables.vouchers} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              voucher_number TEXT NOT NULL UNIQUE,
              voucher_type TEXT NOT NULL,
              party_id INTEGER,
              amount_int INTEGER NOT NULL,
              payment_method TEXT NOT NULL,
              reference_number TEXT,
              statement TEXT,
              status TEXT NOT NULL DEFAULT 'approved',
              voucher_date INTEGER NOT NULL,
              created_at INTEGER NOT NULL
            );
          ''');
            await db.execute('''
            CREATE TABLE ${AppTables.appSettings} (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
          ''');
          },
        ),
      );

      // Insert dummy record in v3
      await dbV3.insert(AppTables.items, {
        'code': 'V3_TEST_ITEM',
        'name': 'صنف اختبار النسخة 3',
        'unit_id': 1,
        'category_id': null,
        'cost_price_int': 100,
        'selling_price_int': 150,
        'stock_quantity_int': 20,
        'min_alert_limit_int': 5,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      await dbV3.close();

      // 2. Open DB with AppDatabase (Version 4)
      AppDatabase.instance.configureForTesting(
        factory: factory,
        path: testDbPath,
      );
      final dbV4 = await AppDatabase.instance.database;

      // 3. Verify data intact
      final itemRows = await dbV4.query(
        AppTables.items,
        where: 'code = ?',
        whereArgs: ['V3_TEST_ITEM'],
      );
      expect(itemRows, isNotEmpty);
      expect(itemRows.first['name'], 'صنف اختبار النسخة 3');

      // 4. Verify new composite indexes exist
      final indexRows = await dbV4.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index';",
      );
      final indexNames = indexRows.map((r) => r['name'] as String).toSet();

      expect(indexNames.contains('idx_items_active_updated'), isTrue);
      expect(indexNames.contains('idx_parties_active_type_name'), isTrue);
      expect(indexNames.contains('idx_invoices_type_date'), isTrue);
      expect(indexNames.contains('idx_vouchers_party_status_date'), isTrue);
    },
  );
}
