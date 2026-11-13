import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import '../licensing/license_service.dart';
import '../licensing/licensed_database.dart';

/// Database table name constants.
abstract final class AppTables {
  static const String categories = 'categories';
  static const String units = 'units';
  static const String items = 'items';
  static const String parties = 'parties';
  static const String inventoryMovements = 'inventory_movements';
  static const String invoices = 'invoices';
  static const String invoiceItems = 'invoice_items';
  static const String vouchers = 'vouchers';
  static const String appSettings = 'app_settings';
  static const String cheques = 'cheques';
  static const String receiptAllocations = 'receipt_allocations';
}

/// Core local database manager for RAF ERP.
///
/// **Architectural Principles:**
/// - Offline-First architecture.
/// - Strict integer arithmetic: NO `REAL` or `FLOAT` data types anywhere.
/// - Explicit Foreign Key constraints with cascades and restrictions.
/// - Optimized composite and single-column indexes for rapid barcode and financial queries.
class AppDatabase {
  static const String _databaseName = 'raf_erp.db';
  static const int _databaseVersion = 6;

  AppDatabase._internal();
  static final AppDatabase instance = AppDatabase._internal();

  Database? _database;
  DatabaseFactory? _customFactory;
  String? _customPath;
  bool _testing = false;
  LicenseGuard? _testGuard;
  Database? _licensedDatabase;

  LicenseGuard? get _guard =>
      _testing ? _testGuard : LicenseGuard(LicenseRuntime.service);

  /// Allows setting custom factory or path (primarily for unit tests and FFI).
  void configureForTesting({
    DatabaseFactory? factory,
    String? path,
    LicenseGuard? licenseGuard,
  }) {
    if (kReleaseMode) {
      throw StateError('Test database configuration is unavailable in Release');
    }
    _testing = true;
    _testGuard = licenseGuard;
    _licensedDatabase = null;
    _customFactory = factory;
    _customPath = path;
    _database = null;
  }

  /// Returns the singleton [Database] instance, initializing it if needed.
  Future<Database> get database async {
    final guard = _guard;
    if (guard != null) await guard.check();
    if (_database != null && _database!.isOpen) {
      return guard == null
          ? _database!
          : (_licensedDatabase ??= LicensedDatabase(_database!, guard));
    }
    _database = await _initDatabase();
    _licensedDatabase = null;
    return guard == null
        ? _database!
        : (_licensedDatabase = LicensedDatabase(_database!, guard));
  }

  Future<Database> _initDatabase() async {
    final String dbPath;
    if (_customPath != null) {
      dbPath = _customPath!;
    } else {
      final databasesPath = await getDatabasesPath();
      dbPath = join(databasesPath, _databaseName);
    }

    final factory = _customFactory ?? databaseFactory;

    return await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  /// Enforces Foreign Key constraints on SQLite connection.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
  }

  /// Creates schema tables and indexes.
  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      // 1. Categories Table
      await txn.execute('''
        CREATE TABLE ${AppTables.categories} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          description TEXT,
          created_at INTEGER NOT NULL
        );
      ''');

      // 2. Units Table
      await txn.execute('''
        CREATE TABLE ${AppTables.units} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          symbol TEXT NOT NULL,
          base_unit_id INTEGER,
          conversion_factor_int INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL,
          FOREIGN KEY (base_unit_id) REFERENCES ${AppTables.units}(id) ON DELETE SET NULL
        );
      ''');

      // 3. Items Table (Products & Inventory)
      await txn.execute('''
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
          updated_at INTEGER NOT NULL,
          FOREIGN KEY (unit_id) REFERENCES ${AppTables.units}(id) ON DELETE RESTRICT,
          FOREIGN KEY (category_id) REFERENCES ${AppTables.categories}(id) ON DELETE SET NULL
        );
      ''');

      // Indexes for Items
      await txn.execute(
        'CREATE INDEX idx_items_code ON ${AppTables.items}(code);',
      );
      await txn.execute(
        'CREATE INDEX idx_items_name ON ${AppTables.items}(name);',
      );
      await txn.execute(
        'CREATE INDEX idx_items_category ON ${AppTables.items}(category_id);',
      );
      await txn.execute(
        'CREATE INDEX idx_items_active_updated ON ${AppTables.items}(is_active, updated_at DESC, id DESC);',
      );
      await txn.execute(
        'CREATE INDEX idx_items_active_cat ON ${AppTables.items}(is_active, category_id, updated_at DESC);',
      );
      await txn.execute(
        'CREATE INDEX idx_items_active_stock ON ${AppTables.items}(is_active, stock_quantity_int, min_alert_limit_int);',
      );

      // 4. Parties Table (Customers & Suppliers)
      await txn.execute('''
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

      // Indexes for Parties
      await txn.execute(
        'CREATE INDEX idx_parties_name ON ${AppTables.parties}(name);',
      );
      await txn.execute(
        'CREATE INDEX idx_parties_phone ON ${AppTables.parties}(phone);',
      );
      await txn.execute(
        'CREATE INDEX idx_parties_type ON ${AppTables.parties}(type);',
      );
      await txn.execute(
        'CREATE INDEX idx_parties_active_name ON ${AppTables.parties}(is_active, name);',
      );
      await txn.execute(
        'CREATE INDEX idx_parties_active_type_name ON ${AppTables.parties}(is_active, type, name ASC);',
      );
      await txn.execute(
        'CREATE INDEX idx_parties_active_balance ON ${AppTables.parties}(is_active, current_balance_int);',
      );

      // 5. Invoices Table
      await txn.execute('''
        CREATE TABLE ${AppTables.invoices} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_number TEXT NOT NULL UNIQUE,
          party_id INTEGER,
          invoice_type TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'draft',
          payment_type TEXT NOT NULL DEFAULT 'cash',
          payment_method TEXT NOT NULL DEFAULT 'cash',
          subtotal_int INTEGER NOT NULL DEFAULT 0,
          discount_int INTEGER NOT NULL DEFAULT 0,
          tax_int INTEGER NOT NULL DEFAULT 0,
          total_int INTEGER NOT NULL DEFAULT 0,
          paid_amount_int INTEGER NOT NULL DEFAULT 0,
          remaining_amount_int INTEGER NOT NULL DEFAULT 0,
          invoice_date INTEGER NOT NULL,
          notes TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY (party_id) REFERENCES ${AppTables.parties}(id) ON DELETE RESTRICT
        );
      ''');

      // Indexes for Invoices
      await txn.execute(
        'CREATE INDEX idx_invoices_number ON ${AppTables.invoices}(invoice_number);',
      );
      await txn.execute(
        'CREATE INDEX idx_invoices_date ON ${AppTables.invoices}(invoice_date);',
      );
      await txn.execute(
        'CREATE INDEX idx_invoices_party ON ${AppTables.invoices}(party_id);',
      );
      await txn.execute(
        'CREATE INDEX idx_invoices_type ON ${AppTables.invoices}(invoice_type);',
      );
      await txn.execute(
        'CREATE INDEX idx_invoices_party_status_date ON ${AppTables.invoices}(party_id, status, invoice_date ASC, id ASC);',
      );
      await txn.execute(
        'CREATE INDEX idx_invoices_type_date ON ${AppTables.invoices}(invoice_type, invoice_date DESC, id DESC);',
      );
      await txn.execute(
        'CREATE INDEX idx_invoices_type_status_date ON ${AppTables.invoices}(invoice_type, status, invoice_date DESC, id DESC);',
      );
      await txn.execute(
        'CREATE INDEX idx_invoices_status_paid ON ${AppTables.invoices}(status, paid_amount_int, invoice_type, invoice_date);',
      );

      // 6. Invoice Items Table
      await txn.execute('''
        CREATE TABLE ${AppTables.invoiceItems} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_id INTEGER NOT NULL,
          item_id INTEGER NOT NULL,
          quantity_int INTEGER NOT NULL,
          unit_price_int INTEGER NOT NULL,
          unit_cost_int INTEGER NOT NULL DEFAULT 0,
          discount_int INTEGER NOT NULL DEFAULT 0,
          tax_rate_percent INTEGER NOT NULL DEFAULT 0,
          tax_amount_int INTEGER NOT NULL DEFAULT 0,
          total_price_int INTEGER NOT NULL,
          FOREIGN KEY (invoice_id) REFERENCES ${AppTables.invoices}(id) ON DELETE CASCADE,
          FOREIGN KEY (item_id) REFERENCES ${AppTables.items}(id) ON DELETE RESTRICT
        );
      ''');

      await txn.execute(
        'CREATE INDEX idx_invoice_items_invoice ON ${AppTables.invoiceItems}(invoice_id);',
      );
      await txn.execute(
        'CREATE INDEX idx_invoice_items_item ON ${AppTables.invoiceItems}(item_id);',
      );

      // 7. Inventory Movements Table
      await txn.execute('''
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
          created_at INTEGER NOT NULL,
          FOREIGN KEY (item_id) REFERENCES ${AppTables.items}(id) ON DELETE RESTRICT
        );
      ''');

      await txn.execute(
        'CREATE INDEX idx_movements_item_date ON ${AppTables.inventoryMovements}(item_id, movement_date);',
      );
      await txn.execute(
        'CREATE INDEX idx_movements_type ON ${AppTables.inventoryMovements}(movement_type);',
      );

      // 8. Vouchers Table (Financial Receipts & Payments)
      await txn.execute('''
        CREATE TABLE ${AppTables.vouchers} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          voucher_number TEXT NOT NULL UNIQUE,
          voucher_type TEXT NOT NULL,
          party_id INTEGER,
          amount_int INTEGER NOT NULL,
          payment_method TEXT NOT NULL,
          purpose TEXT NOT NULL DEFAULT 'general',
          expense_category TEXT,
          reference_number TEXT,
          statement TEXT,
          status TEXT NOT NULL DEFAULT 'approved',
          voucher_date INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY (party_id) REFERENCES ${AppTables.parties}(id) ON DELETE RESTRICT
        );
      ''');

      await txn.execute(
        'CREATE INDEX idx_vouchers_number ON ${AppTables.vouchers}(voucher_number);',
      );
      await txn.execute(
        'CREATE INDEX idx_vouchers_party_date ON ${AppTables.vouchers}(party_id, voucher_date);',
      );
      await txn.execute(
        'CREATE INDEX idx_vouchers_type ON ${AppTables.vouchers}(voucher_type);',
      );
      await txn.execute(
        'CREATE INDEX idx_vouchers_party_status_date ON ${AppTables.vouchers}(party_id, status, voucher_date ASC, id ASC);',
      );
      await txn.execute(
        'CREATE INDEX idx_vouchers_type_date ON ${AppTables.vouchers}(voucher_type, voucher_date DESC, id DESC);',
      );
      await txn.execute(
        'CREATE INDEX idx_vouchers_type_status_date ON ${AppTables.vouchers}(voucher_type, status, voucher_date DESC, id DESC);',
      );

      // App Settings (Persistent Key-Value Store)
      await txn.execute('''
        CREATE TABLE ${AppTables.appSettings} (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
      ''');
      await _createSettlementSchema(txn, importLegacy: false);
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE ${AppTables.parties} ADD COLUMN opening_balance_int INTEGER NOT NULL DEFAULT 0;',
      );
      await db.execute(
        'ALTER TABLE ${AppTables.invoiceItems} ADD COLUMN unit_cost_int INTEGER NOT NULL DEFAULT 0;',
      );
      await db.execute(
        "ALTER TABLE ${AppTables.vouchers} ADD COLUMN status TEXT NOT NULL DEFAULT 'approved';",
      );
      // Backfill historical unit_cost_int from inventory movements or items
      await db.execute('''
        UPDATE ${AppTables.invoiceItems}
        SET unit_cost_int = COALESCE(
          (SELECT im.unit_cost_int FROM ${AppTables.inventoryMovements} im
           WHERE im.reference_id = ${AppTables.invoiceItems}.invoice_id
             AND im.item_id = ${AppTables.invoiceItems}.item_id
           LIMIT 1),
          (SELECT it.cost_price_int FROM ${AppTables.items} it
           WHERE it.id = ${AppTables.invoiceItems}.item_id),
          0
        );
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${AppTables.appSettings} (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
      ''');
    }
    if (oldVersion < 4) {
      // Version 4: Composite indexes for large datasets and rapid financial / catalog queries
      Future<bool> hasTable(String table) async {
        final res = await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?",
          [table],
        );
        return res.isNotEmpty;
      }

      Future<bool> hasColumn(String table, String col) async {
        if (!await hasTable(table)) return false;
        final res = await db.rawQuery('PRAGMA table_info($table);');
        return res.any((r) => r['name'] == col);
      }

      if (await hasTable(AppTables.items)) {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_items_active_updated ON ${AppTables.items}(is_active, updated_at DESC);',
        );
        if (await hasColumn(AppTables.items, 'category_id')) {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_items_active_cat ON ${AppTables.items}(is_active, category_id, updated_at DESC);',
          );
        }
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_items_active_stock ON ${AppTables.items}(is_active, stock_quantity_int, min_alert_limit_int);',
        );
      }

      if (await hasTable(AppTables.parties)) {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_parties_active_name ON ${AppTables.parties}(is_active, name);',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_parties_active_type_name ON ${AppTables.parties}(is_active, type, name ASC);',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_parties_active_balance ON ${AppTables.parties}(is_active, current_balance_int);',
        );
      }

      if (await hasTable(AppTables.invoices)) {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoices_party_status_date ON ${AppTables.invoices}(party_id, status, invoice_date ASC, id ASC);',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoices_type_date ON ${AppTables.invoices}(invoice_type, invoice_date DESC, id DESC);',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoices_type_status_date ON ${AppTables.invoices}(invoice_type, status, invoice_date);',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoices_status_paid ON ${AppTables.invoices}(status, paid_amount_int, invoice_type, invoice_date);',
        );
      }

      if (await hasTable(AppTables.vouchers)) {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_vouchers_party_status_date ON ${AppTables.vouchers}(party_id, status, voucher_date ASC, id ASC);',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_vouchers_type_date ON ${AppTables.vouchers}(voucher_type, voucher_date DESC, id DESC);',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_vouchers_type_status_date ON ${AppTables.vouchers}(voucher_type, status, voucher_date);',
        );
      }
    }
    if (oldVersion < 5) {
      Future<Set<String>> columns(String table) async {
        final rows = await db.rawQuery('PRAGMA table_info($table)');
        return rows.map((row) => row['name'] as String).toSet();
      }

      final invoiceColumns = await columns(AppTables.invoices);
      if (invoiceColumns.isNotEmpty &&
          !invoiceColumns.contains('payment_method')) {
        await db.execute(
          "ALTER TABLE ${AppTables.invoices} ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash'",
        );
        if (invoiceColumns.contains('payment_type')) {
          await db.execute(
            "UPDATE ${AppTables.invoices} SET payment_method = 'transfer' WHERE payment_type = 'transfer'",
          );
        }
      }
      final voucherColumns = await columns(AppTables.vouchers);
      if (voucherColumns.isNotEmpty && !voucherColumns.contains('purpose')) {
        await db.execute(
          "ALTER TABLE ${AppTables.vouchers} ADD COLUMN purpose TEXT NOT NULL DEFAULT 'general'",
        );
      }
      if (voucherColumns.isNotEmpty &&
          !voucherColumns.contains('expense_category')) {
        await db.execute(
          'ALTER TABLE ${AppTables.vouchers} ADD COLUMN expense_category TEXT',
        );
      }
    }
    if (oldVersion < 6) {
      await _createSettlementSchema(db, importLegacy: true);
    }
  }

  Future<void> _createSettlementSchema(
    DatabaseExecutor db, {
    required bool importLegacy,
  }) async {
    for (final table in [AppTables.invoices, AppTables.vouchers]) {
      final cols = await db.rawQuery('PRAGMA table_info($table)');
      if (cols.isNotEmpty && !cols.any((c) => c['name'] == 'cheque_account')) {
        await db.execute('ALTER TABLE $table ADD COLUMN cheque_account TEXT');
      }
    }
    await db.execute('''CREATE TABLE cheques (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      voucher_id INTEGER UNIQUE REFERENCES vouchers(id) ON DELETE CASCADE,
      invoice_id INTEGER UNIQUE REFERENCES invoices(id) ON DELETE CASCADE,
      amount_int INTEGER NOT NULL CHECK(amount_int > 0),
      direction INTEGER NOT NULL CHECK(direction IN (-1,1)),
      state TEXT NOT NULL CHECK(state IN ('pending','cleared','legacy_review')),
      account TEXT CHECK(account IN ('cash','bank','transfers')),
      effective_at INTEGER,
      is_legacy INTEGER NOT NULL DEFAULT 0 CHECK(is_legacy IN (0,1)),
      reviewed_at INTEGER,
      created_at INTEGER NOT NULL,
      CHECK((voucher_id IS NULL) != (invoice_id IS NULL)),
      CHECK(state != 'cleared' OR (account IS NOT NULL AND effective_at IS NOT NULL)),
      CHECK(state != 'pending' OR direction != -1 OR account IS NOT NULL)
    )''');
    await db.execute(
      'CREATE INDEX idx_cheques_state ON cheques(state,direction)',
    );
    await db.execute('''CREATE TABLE receipt_allocations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      voucher_id INTEGER NOT NULL REFERENCES vouchers(id) ON DELETE CASCADE,
      invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
      amount_int INTEGER NOT NULL CHECK(amount_int > 0),
      request_key TEXT NOT NULL UNIQUE CHECK(length(trim(request_key)) > 0),
      created_at INTEGER NOT NULL,
      released_at INTEGER
    )''');
    await db.execute(
      'CREATE INDEX idx_allocations_invoice ON receipt_allocations(invoice_id,released_at)',
    );
    await db.execute(
      'CREATE INDEX idx_allocations_voucher ON receipt_allocations(voucher_id,released_at)',
    );
    if (importLegacy) {
      // Old records have no collection evidence. Preserve all old financial
      // columns and require explicit review instead of guessing settlement.
      final vcols = (await db.rawQuery(
        'PRAGMA table_info(vouchers)',
      )).map((r) => r['name']).toSet();
      if (vcols.containsAll({
        'id',
        'payment_method',
        'amount_int',
        'voucher_type',
        'created_at',
      })) {
        await db.execute(
          '''INSERT INTO cheques(voucher_id,amount_int,direction,state,is_legacy,created_at)
          SELECT id,amount_int,CASE voucher_type WHEN 'receipt' THEN 1 ELSE -1 END,
            'legacy_review',1,created_at FROM vouchers WHERE payment_method='cheque' AND amount_int>0''',
        );
      }
      final icols = (await db.rawQuery(
        'PRAGMA table_info(invoices)',
      )).map((r) => r['name']).toSet();
      if (icols.containsAll({
        'id',
        'payment_method',
        'paid_amount_int',
        'invoice_type',
        'status',
        'created_at',
      })) {
        await db.execute(
          '''INSERT INTO cheques(invoice_id,amount_int,direction,state,is_legacy,created_at)
          SELECT id,paid_amount_int,CASE WHEN invoice_type IN ('sale','purchase_return') THEN 1 ELSE -1 END,
            'legacy_review',1,created_at FROM invoices WHERE payment_method='cheque' AND paid_amount_int>0 AND status!='draft' ''',
        );
      }
    }
  }

  /// Closes the database connection.
  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }
}
