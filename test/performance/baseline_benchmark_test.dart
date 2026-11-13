import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('Inspect current EXPLAIN QUERY PLAN on AppDatabase v3', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          // Setup current v3 schema
          await db.execute('PRAGMA foreign_keys = ON;');
          await db.execute('''
            CREATE TABLE ${AppTables.items} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              code TEXT NOT NULL UNIQUE,
              name TEXT NOT NULL,
              unit_id INTEGER NOT NULL,
              category_id INTEGER,
              cost_price_int INTEGER NOT NULL DEFAULT 0,
              selling_price_int INTEGER NOT NULL DEFAULT 0,
              stock_quantity_int INTEGER NOT NULL DEFAULT 0,
              min_alert_limit_int INTEGER NOT NULL DEFAULT 0,
              expiry_date INTEGER,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
          ''');
          await db.execute(
            'CREATE INDEX idx_items_code ON ${AppTables.items}(code);',
          );
          await db.execute(
            'CREATE INDEX idx_items_name ON ${AppTables.items}(name);',
          );
          await db.execute(
            'CREATE INDEX idx_items_category ON ${AppTables.items}(category_id);',
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
          await db.execute(
            'CREATE INDEX idx_parties_name ON ${AppTables.parties}(name);',
          );
          await db.execute(
            'CREATE INDEX idx_parties_phone ON ${AppTables.parties}(phone);',
          );
          await db.execute(
            'CREATE INDEX idx_parties_type ON ${AppTables.parties}(type);',
          );

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
          await db.execute(
            'CREATE INDEX idx_invoices_number ON ${AppTables.invoices}(invoice_number);',
          );
          await db.execute(
            'CREATE INDEX idx_invoices_date ON ${AppTables.invoices}(invoice_date);',
          );
          await db.execute(
            'CREATE INDEX idx_invoices_party ON ${AppTables.invoices}(party_id);',
          );
          await db.execute(
            'CREATE INDEX idx_invoices_type ON ${AppTables.invoices}(invoice_type);',
          );

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
          await db.execute(
            'CREATE INDEX idx_vouchers_number ON ${AppTables.vouchers}(voucher_number);',
          );
          await db.execute(
            'CREATE INDEX idx_vouchers_party_date ON ${AppTables.vouchers}(party_id, voucher_date);',
          );
          await db.execute(
            'CREATE INDEX idx_vouchers_type ON ${AppTables.vouchers}(voucher_type);',
          );
        },
      ),
    );

    Future<void> explain(String sql, [List<Object?>? args]) async {
      final plan = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
      // ignore: avoid_print
      print('SQL: $sql');
      for (final p in plan) {
        // ignore: avoid_print
        print('  -> detail: ${p['detail']}');
      }
    }

    // 1. Items default query
    await explain(
      'SELECT * FROM items WHERE is_active = 1 ORDER BY updated_at DESC LIMIT 30',
    );

    // 2. Invoices statement query
    await explain(
      'SELECT * FROM invoices WHERE party_id = ? AND status = ? ORDER BY invoice_date ASC, id ASC',
      [1, 'approved'],
    );

    // 3. Invoices list query
    await explain(
      'SELECT * FROM invoices WHERE invoice_type = ? ORDER BY invoice_date DESC, id DESC LIMIT 30',
      ['sale'],
    );

    // 4. Vouchers statement query
    await explain(
      'SELECT * FROM vouchers WHERE party_id = ? AND (status IS NULL OR status = ?) ORDER BY voucher_date ASC, id ASC',
      [1, 'approved'],
    );

    // 5. Parties list query
    await explain(
      'SELECT * FROM parties WHERE is_active = 1 AND type = ? ORDER BY name ASC LIMIT 30',
      ['customer'],
    );

    // Create targeted composite indexes
    await db.execute(
      'CREATE INDEX idx_items_active_updated ON ${AppTables.items}(is_active, updated_at DESC);',
    );
    await db.execute(
      'CREATE INDEX idx_invoices_party_status_date ON ${AppTables.invoices}(party_id, status, invoice_date ASC, id ASC);',
    );
    await db.execute(
      'CREATE INDEX idx_invoices_type_date ON ${AppTables.invoices}(invoice_type, invoice_date DESC, id DESC);',
    );
    await db.execute(
      'CREATE INDEX idx_parties_active_type_name ON ${AppTables.parties}(is_active, type, name ASC);',
    );

    // ignore: avoid_print
    print('\n--- AFTER COMPOSITE INDEXES ---');
    await explain(
      'SELECT * FROM items WHERE is_active = 1 ORDER BY updated_at DESC LIMIT 30',
    );
    await explain(
      'SELECT * FROM invoices WHERE party_id = ? AND status = ? ORDER BY invoice_date ASC, id ASC',
      [1, 'approved'],
    );
    await explain(
      'SELECT * FROM invoices WHERE invoice_type = ? ORDER BY invoice_date DESC, id DESC LIMIT 30',
      ['sale'],
    );
    await explain(
      'SELECT * FROM parties WHERE is_active = 1 AND type = ? ORDER BY name ASC LIMIT 30',
      ['customer'],
    );

    await db.close();
  });
}
