import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'app_database.dart';

/// Holds detailed counts of deleted records and preserved settings
/// resulting from a successful business data wipe operation.
class WipeSummary {
  final int invoiceItemsDeleted;
  final int inventoryMovementsDeleted;
  final int invoicesDeleted;
  final int vouchersDeleted;
  final int itemsDeleted;
  final int partiesDeleted;
  final int unitsDeleted;
  final int categoriesDeleted;
  final int settingsPreserved;

  const WipeSummary({
    required this.invoiceItemsDeleted,
    required this.inventoryMovementsDeleted,
    required this.invoicesDeleted,
    required this.vouchersDeleted,
    required this.itemsDeleted,
    required this.partiesDeleted,
    int? unitsDeleted,
    int? categoriesDeleted,
    int? customUnitsDeleted,
    int? customCategoriesDeleted,
    required this.settingsPreserved,
  }) : unitsDeleted = unitsDeleted ?? customUnitsDeleted ?? 0,
       categoriesDeleted = categoriesDeleted ?? customCategoriesDeleted ?? 0;

  int get customUnitsDeleted => unitsDeleted;
  int get customCategoriesDeleted => categoriesDeleted;

  int get totalDeletedRecords =>
      invoiceItemsDeleted +
      inventoryMovementsDeleted +
      invoicesDeleted +
      vouchersDeleted +
      itemsDeleted +
      partiesDeleted +
      unitsDeleted +
      categoriesDeleted;
}

/// Global notifier for in-memory and UI state synchronizations across modules
/// whenever business data is cleared or re-initialized.
class BusinessDataNotifier extends ChangeNotifier {
  static final BusinessDataNotifier instance = BusinessDataNotifier._();
  BusinessDataNotifier._();

  int _wipeCounter = 0;
  int get wipeCounter => _wipeCounter;

  void notifyDataCleared() {
    _wipeCounter++;
    notifyListeners();
  }
}

/// Service dedicated to safely and atomically clearing all local business data
/// from the SQLite database while preserving:
/// 1. Establishment and store configuration (`app_settings`).
/// 2. Database schema, indexes, migrations, version, and structure.
class BusinessDataWiper {
  static final BusinessDataWiper instance = BusinessDataWiper();

  final AppDatabase _dbManager;

  BusinessDataWiper({AppDatabase? dbManager})
    : _dbManager = dbManager ?? AppDatabase.instance;

  /// Required exact confirmation phrase that the user must enter before deletion.
  static const String confirmationPhrase = 'مسح جميع البيانات';

  /// Canonical definition of standard master measurement units.
  static const List<({String name, String symbol, int factor})> standardUnits =
      [
        (name: 'قطعة', symbol: 'حبة', factor: 1),
        (name: 'كرتون', symbol: 'ctn', factor: 12),
        (name: 'كيلوجرام', symbol: 'كجم', factor: 1),
        (name: 'لتر', symbol: 'لتر', factor: 1),
        (name: 'متر', symbol: 'م', factor: 1),
        (name: 'باكت', symbol: 'باكت', factor: 1),
        (name: 'طرد', symbol: 'طرد', factor: 1),
        (name: 'درزن', symbol: 'درزن', factor: 12),
      ];

  /// Canonical definition of standard master product categories.
  static const List<String> standardCategories = [
    'عام',
    'مشروبات وعصائر',
    'أغذية ومعلبات',
    'منظفات وعناية',
    'خضروات وفواكه',
    'أدوات وقرطاسية',
  ];

  /// Validates whether a unit record matches a canonical standard unit by full identity
  /// (exact match of name, symbol, and conversion factor).
  /// Partial matches (e.g. matching symbol only or name only with altered factor)
  /// are treated as custom user units and are not considered standard.
  static bool isStandardUnit(String? name, String? symbol, int? factor) {
    if (name == null || symbol == null) return false;
    final trimmedName = name.trim();
    final trimmedSymbol = symbol.trim();

    return standardUnits.any(
      (u) =>
          u.name == trimmedName &&
          u.symbol == trimmedSymbol &&
          (factor == null || u.factor == factor),
    );
  }

  /// Validates whether a category name matches a canonical standard category.
  static bool isStandardCategory(String? name) {
    if (name == null) return false;
    final trimmed = name.trim();
    return standardCategories.contains(trimmed);
  }

  /// Safely wipes all operational business data in a single atomic SQLite transaction.
  ///
  /// **Integrity Guarantees:**
  /// - Deletes in strict relational dependency order respecting `PRAGMA foreign_keys = ON`.
  /// - Executes `PRAGMA foreign_key_check` before commit; throws and rolls back if any violation is found.
  /// - Leaves `app_settings` intact and marks `parties_seed_completed = 'true'` and
  ///   `inventory_seed_completed = 'true'` to prevent automatic sample data re-creation.
  /// - Deletes ALL operational records including all units and all categories (both standard and custom).
  /// - Emits notification through [BusinessDataNotifier] to clear any in-memory state.
  Future<WipeSummary> clearAllBusinessData() async {
    final db = await _dbManager.database;

    final summary = await db.transaction<WipeSummary>((txn) async {
      // 1. Delete invoice items (child records of invoices & items)
      final invoiceItemsDeleted = await txn.delete(AppTables.invoiceItems);

      // 2. Delete inventory movements (child records of items)
      final inventoryMovementsDeleted = await txn.delete(
        AppTables.inventoryMovements,
      );

      // 3. Delete invoices (child records of parties)
      final invoicesDeleted = await txn.delete(AppTables.invoices);

      // 4. Delete vouchers (child records of parties)
      final vouchersDeleted = await txn.delete(AppTables.vouchers);

      // 5. Delete items (child records of units & categories)
      final itemsDeleted = await txn.delete(AppTables.items);

      // 6. Delete parties (customers & suppliers)
      final partiesDeleted = await txn.delete(AppTables.parties);

      // 7. Delete ALL units (both standard and custom)
      final unitsDeleted = await txn.delete(AppTables.units);

      // 8. Delete ALL categories (both standard and custom)
      final categoriesDeleted = await txn.delete(AppTables.categories);

      // 9. Prevent automatic sample parties and inventory re-seeding on future page visits
      await txn.insert(AppTables.appSettings, {
        'key': 'parties_seed_completed',
        'value': 'true',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert(AppTables.appSettings, {
        'key': 'inventory_seed_completed',
        'value': 'true',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // 10. Perform strict Foreign Key Check and read output.
      // If any violation exists, throw StateError to force complete atomic rollback.
      final fkViolations = await txn.rawQuery('PRAGMA foreign_key_check;');
      if (fkViolations.isNotEmpty) {
        throw StateError(
          'Foreign key constraint violation detected after wipe: $fkViolations',
        );
      }

      // 11. Count preserved settings records
      final settingsRows = await txn.query(AppTables.appSettings);
      final settingsPreserved = settingsRows.length;

      return WipeSummary(
        invoiceItemsDeleted: invoiceItemsDeleted,
        inventoryMovementsDeleted: inventoryMovementsDeleted,
        invoicesDeleted: invoicesDeleted,
        vouchersDeleted: vouchersDeleted,
        itemsDeleted: itemsDeleted,
        partiesDeleted: partiesDeleted,
        unitsDeleted: unitsDeleted,
        categoriesDeleted: categoriesDeleted,
        settingsPreserved: settingsPreserved,
      );
    });

    // Notify listeners so open screens and repositories refresh their state
    BusinessDataNotifier.instance.notifyDataCleared();

    return summary;
  }
}
