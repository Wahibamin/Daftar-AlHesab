import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';
import '../models/item_model.dart';
import '../models/movement_model.dart';

/// Abstract contract for inventory management repository in RAF ERP.
abstract class InventoryRepository {
  Future<List<UnitModel>> getUnits();
  Future<int> insertUnit(UnitModel unit);
  Future<int> updateUnit(UnitModel unit);
  Future<int> deleteUnit(int id);
  Future<int> getUnitItemCount(int unitId);
  Future<int> archiveUnit(int id, {bool unarchive = false});
  Future<List<CategoryModel>> getCategories();
  Future<int> insertCategory(CategoryModel category);
  Future<int> updateCategory(CategoryModel category);
  Future<int> deleteCategory(int id);
  Future<int> getCategoryItemCount(int categoryId);
  Future<int> archiveCategory(int id, {bool unarchive = false});
  Future<List<ItemModel>> getItems({
    String? searchQuery,
    int? categoryId,
    bool? lowStockOnly,
    int? limit,
    int? offset,
  });
  Future<ItemModel?> getItemById(int id);
  Future<ItemModel?> getItemByCode(String code);
  Future<int> insertItem(ItemModel item, {int initialStock = 0});
  Future<int> updateItem(ItemModel item);
  Future<int> deleteItem(int id);
  Future<void> recordStockAdjustment({
    required int itemId,
    required int actualStock,
    String? notes,
  });
  Future<List<InventoryMovementModel>> getItemMovements(
    int itemId, {
    int? limit,
    int? offset,
  });
  Future<void> seedDefaultDataIfEmpty();
  Future<int> safeSeedMasterData();
}

/// SQLite-backed persistent implementation of [InventoryRepository].
class SqliteInventoryRepository implements InventoryRepository {
  final AppDatabase _dbManager;

  SqliteInventoryRepository([AppDatabase? dbManager])
    : _dbManager = dbManager ?? AppDatabase.instance;

  @override
  Future<List<UnitModel>> getUnits() async {
    final db = await _dbManager.database;
    final rows = await db.query(AppTables.units, orderBy: 'id ASC');
    return rows.map(UnitModel.fromMap).toList();
  }

  @override
  Future<int> insertUnit(UnitModel unit) async {
    final db = await _dbManager.database;
    final cleanName = unit.cleanName.toLowerCase();
    final cleanSymbol = unit.cleanSymbol.toLowerCase();
    final existing = await db.rawQuery(
      'SELECT id FROM ${AppTables.units} WHERE LOWER(name) = ? OR LOWER(symbol) = ? LIMIT 1',
      [cleanName, cleanSymbol],
    );
    if (existing.isNotEmpty) {
      throw StateError('توجد وحدة قياس أخرى بنفس الاسم أو الرمز بالفعل.');
    }
    return await db.insert(AppTables.units, unit.toMap());
  }

  @override
  Future<int> updateUnit(UnitModel unit) async {
    if (unit.id == null) {
      throw ArgumentError('Unit id cannot be null for update');
    }
    final db = await _dbManager.database;
    final cleanName = unit.cleanName.toLowerCase();
    final cleanSymbol = unit.cleanSymbol.toLowerCase();
    final existing = await db.rawQuery(
      'SELECT id FROM ${AppTables.units} WHERE id != ? AND (LOWER(name) = ? OR LOWER(symbol) = ?) LIMIT 1',
      [unit.id, cleanName, cleanSymbol],
    );
    if (existing.isNotEmpty) {
      throw StateError('توجد وحدة قياس أخرى بنفس الاسم أو الرمز بالفعل.');
    }
    return await db.update(
      AppTables.units,
      unit.toMap(),
      where: 'id = ?',
      whereArgs: [unit.id],
    );
  }

  @override
  Future<int> getUnitItemCount(int unitId) async {
    final db = await _dbManager.database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${AppTables.items} WHERE unit_id = ?',
      [unitId],
    );
    return Sqflite.firstIntValue(res) ?? 0;
  }

  @override
  Future<int> deleteUnit(int id) async {
    final count = await getUnitItemCount(id);
    if (count > 0) {
      throw StateError(
        'لا يمكن حذف وحدة القياس لوجود $count صنف مرتبط بها. يرجى أرشفة الوحدة بدلاً من حذفها لحماية السجلات.',
      );
    }
    final db = await _dbManager.database;
    final childUnits = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${AppTables.units} WHERE base_unit_id = ?',
      [id],
    );
    final childCount = Sqflite.firstIntValue(childUnits) ?? 0;
    if (childCount > 0) {
      throw StateError(
        'لا يمكن حذف وحدة القياس لوجود $childCount وحدة تابعة مرتبطة بها.',
      );
    }
    return await db.delete(AppTables.units, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<int> archiveUnit(int id, {bool unarchive = false}) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      AppTables.units,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    final unit = UnitModel.fromMap(rows.first);
    final String newName = unarchive
        ? unit.cleanName
        : (unit.isArchived ? unit.name : '[مؤرشف] ${unit.cleanName}');
    return await updateUnit(unit.copyWith(name: newName));
  }

  @override
  Future<List<CategoryModel>> getCategories() async {
    final db = await _dbManager.database;
    final rows = await db.query(AppTables.categories, orderBy: 'name ASC');
    return rows.map(CategoryModel.fromMap).toList();
  }

  @override
  Future<int> insertCategory(CategoryModel category) async {
    final db = await _dbManager.database;
    final cleanName = category.cleanName.toLowerCase();
    final existing = await db.rawQuery(
      'SELECT id FROM ${AppTables.categories} WHERE LOWER(name) = ? LIMIT 1',
      [cleanName],
    );
    if (existing.isNotEmpty) {
      throw StateError('يوجد تصنيف آخر بنفس الاسم بالفعل.');
    }
    return await db.insert(AppTables.categories, category.toMap());
  }

  @override
  Future<int> updateCategory(CategoryModel category) async {
    if (category.id == null) {
      throw ArgumentError('Category id cannot be null for update');
    }
    final db = await _dbManager.database;
    final cleanName = category.cleanName.toLowerCase();
    final existing = await db.rawQuery(
      'SELECT id FROM ${AppTables.categories} WHERE id != ? AND LOWER(name) = ? LIMIT 1',
      [category.id, cleanName],
    );
    if (existing.isNotEmpty) {
      throw StateError('يوجد تصنيف آخر بنفس الاسم بالفعل.');
    }
    return await db.update(
      AppTables.categories,
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  @override
  Future<int> getCategoryItemCount(int categoryId) async {
    final db = await _dbManager.database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${AppTables.items} WHERE category_id = ?',
      [categoryId],
    );
    return Sqflite.firstIntValue(res) ?? 0;
  }

  @override
  Future<int> deleteCategory(int id) async {
    final count = await getCategoryItemCount(id);
    if (count > 0) {
      throw StateError(
        'لا يمكن حذف التصنيف لوجود $count صنف مرتبط به. يرجى أرشفة التصنيف بدلاً من حذفه لحماية السجلات.',
      );
    }
    final db = await _dbManager.database;
    return await db.delete(
      AppTables.categories,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<int> archiveCategory(int id, {bool unarchive = false}) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      AppTables.categories,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    final cat = CategoryModel.fromMap(rows.first);
    String newDesc;
    if (unarchive) {
      newDesc = (cat.description ?? '').replaceAll('[مؤرشف]', '').trim();
    } else {
      final existing = (cat.description ?? '').replaceAll('[مؤرشف]', '').trim();
      newDesc = existing.isEmpty ? '[مؤرشف]' : '[مؤرشف] $existing';
    }
    return await updateCategory(
      cat.copyWith(description: newDesc.isEmpty ? null : newDesc),
    );
  }

  @override
  Future<List<ItemModel>> getItems({
    String? searchQuery,
    int? categoryId,
    bool? lowStockOnly,
    int? limit,
    int? offset,
  }) async {
    final db = await _dbManager.database;
    final whereClauses = <String>['is_active = 1'];
    final whereArgs = <dynamic>[];

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = '%${searchQuery.trim()}%';
      whereClauses.add('(name LIKE ? OR code LIKE ?)');
      whereArgs.add(query);
      whereArgs.add(query);
    }

    if (categoryId != null) {
      whereClauses.add('category_id = ?');
      whereArgs.add(categoryId);
    }

    if (lowStockOnly == true) {
      whereClauses.add('stock_quantity_int <= min_alert_limit_int');
    }

    final whereString = whereClauses.join(' AND ');

    final rows = await db.query(
      AppTables.items,
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'updated_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );

    return rows.map(ItemModel.fromMap).toList();
  }

  @override
  Future<ItemModel?> getItemById(int id) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      AppTables.items,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ItemModel.fromMap(rows.first);
  }

  @override
  Future<ItemModel?> getItemByCode(String code) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      AppTables.items,
      where: 'code = ?',
      whereArgs: [code.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ItemModel.fromMap(rows.first);
  }

  @override
  Future<int> insertItem(ItemModel item, {int initialStock = 0}) async {
    final db = await _dbManager.database;
    return await db.transaction<int>((txn) async {
      final qty = initialStock > 0 ? initialStock : item.stockQuantity;
      final itemToInsert = item.copyWith(stockQuantity: qty);

      final itemId = await txn.insert(AppTables.items, itemToInsert.toMap());

      if (qty > 0) {
        final movement = InventoryMovementModel(
          itemId: itemId,
          movementType: MovementType.initial,
          quantity: qty,
          unitCost: item.costPrice,
          referenceType: 'initial_balance',
          movementDate: DateTime.now(),
          notes: 'رصيد مخزني افتتاحي عند تعريف الصنف',
          createdAt: DateTime.now(),
        );
        await txn.insert(AppTables.inventoryMovements, movement.toMap());
      }

      return itemId;
    });
  }

  @override
  Future<int> updateItem(ItemModel item) async {
    if (item.id == null) {
      throw ArgumentError('Cannot update item without id');
    }
    final db = await _dbManager.database;
    // Quantities are owned by invoice posting and auditable stock adjustments.
    final metadata = item.copyWith(updatedAt: DateTime.now()).toMap()
      ..remove('id')
      ..remove('created_at')
      ..remove('is_active')
      ..remove('stock_quantity_int');
    return await db.update(
      AppTables.items,
      metadata,
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  @override
  Future<int> deleteItem(int id) async {
    final db = await _dbManager.database;
    return await db.update(
      AppTables.items,
      {'is_active': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> recordStockAdjustment({
    required int itemId,
    required int actualStock,
    String? notes,
  }) async {
    final db = await _dbManager.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        AppTables.items,
        where: 'id = ?',
        whereArgs: [itemId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw ArgumentError('Item not found for id $itemId');
      }

      final item = ItemModel.fromMap(rows.first);
      final int variance = actualStock - item.stockQuantity;

      if (variance == 0) return;

      final now = DateTime.now();
      final movement = InventoryMovementModel(
        itemId: itemId,
        movementType: MovementType.adjustment,
        quantity: variance,
        unitCost: item.costPrice,
        referenceType: 'stock_adjustment',
        movementDate: now,
        notes: notes ?? 'تسوية جردية - فارق: $variance',
        createdAt: now,
      );

      await txn.insert(AppTables.inventoryMovements, movement.toMap());

      await txn.update(
        AppTables.items,
        {
          'stock_quantity_int': actualStock,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );
    });
  }

  @override
  Future<List<InventoryMovementModel>> getItemMovements(
    int itemId, {
    int? limit,
    int? offset,
  }) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      AppTables.inventoryMovements,
      where: 'item_id = ?',
      whereArgs: [itemId],
      orderBy: 'movement_date DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(InventoryMovementModel.fromMap).toList();
  }

  @override
  Future<void> seedDefaultDataIfEmpty() async {
    final db = await _dbManager.database;
    final setting = await db.query(
      AppTables.appSettings,
      where: 'key = ?',
      whereArgs: ['inventory_seed_completed'],
    );
    if (setting.isNotEmpty && setting.first['value'] == 'true') {
      return;
    }

    final unitsResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM ${AppTables.units}',
    );
    final unitsCount = (unitsResult.first['cnt'] as int?) ?? 0;

    if (unitsCount == 0) {
      final now = DateTime.now();
      await db.insert(AppTables.units, {
        'name': 'قطعة',
        'symbol': 'حبة',
        'conversion_factor_int': 1,
        'created_at': now.millisecondsSinceEpoch,
      });
      await db.insert(AppTables.units, {
        'name': 'كرتون',
        'symbol': 'ctn',
        'conversion_factor_int': 12,
        'created_at': now.millisecondsSinceEpoch,
      });
      await db.insert(AppTables.units, {
        'name': 'كيلوجرام',
        'symbol': 'كجم',
        'conversion_factor_int': 1,
        'created_at': now.millisecondsSinceEpoch,
      });
      await db.insert(AppTables.units, {
        'name': 'لتر',
        'symbol': 'لتر',
        'conversion_factor_int': 1,
        'created_at': now.millisecondsSinceEpoch,
      });
    }

    final catResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM ${AppTables.categories}',
    );
    final catCount = (catResult.first['cnt'] as int?) ?? 0;

    if (catCount == 0) {
      final now = DateTime.now();
      await db.insert(AppTables.categories, {
        'name': 'عام',
        'description': 'تصنيف عام للمنتجات',
        'created_at': now.millisecondsSinceEpoch,
      });
      await db.insert(AppTables.categories, {
        'name': 'مشروبات وعصائر',
        'description': 'المشروبات الباردة والساخنة',
        'created_at': now.millisecondsSinceEpoch,
      });
      await db.insert(AppTables.categories, {
        'name': 'أغذية ومعلبات',
        'description': 'المواد التموينية والمعلبة',
        'created_at': now.millisecondsSinceEpoch,
      });
      await db.insert(AppTables.categories, {
        'name': 'منظفات وعناية',
        'description': 'مواد التنظيف والاستهلاك اليومي',
        'created_at': now.millisecondsSinceEpoch,
      });
    }

    await db.insert(AppTables.appSettings, {
      'key': 'inventory_seed_completed',
      'value': 'true',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<int> safeSeedMasterData() async {
    final db = await _dbManager.database;
    int addedCount = 0;
    final now = DateTime.now();

    final defaultUnits = [
      {'name': 'قطعة', 'symbol': 'حبة', 'conversion_factor_int': 1},
      {'name': 'كرتون', 'symbol': 'ctn', 'conversion_factor_int': 12},
      {'name': 'كيلوجرام', 'symbol': 'كجم', 'conversion_factor_int': 1},
      {'name': 'لتر', 'symbol': 'لتر', 'conversion_factor_int': 1},
      {'name': 'متر', 'symbol': 'م', 'conversion_factor_int': 1},
      {'name': 'باكت', 'symbol': 'باكت', 'conversion_factor_int': 1},
      {'name': 'طرد', 'symbol': 'طرد', 'conversion_factor_int': 1},
      {'name': 'درزن', 'symbol': 'درزن', 'conversion_factor_int': 12},
    ];

    for (final u in defaultUnits) {
      final existing = await db.query(
        AppTables.units,
        where: 'name = ? OR symbol = ?',
        whereArgs: [u['name'], u['symbol']],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert(AppTables.units, {
          ...u,
          'created_at': now.millisecondsSinceEpoch,
        });
        addedCount++;
      }
    }

    final defaultCategories = [
      {'name': 'عام', 'description': 'تصنيف عام للمنتجات'},
      {'name': 'مشروبات وعصائر', 'description': 'المشروبات الباردة والساخنة'},
      {'name': 'أغذية ومعلبات', 'description': 'المواد التموينية والمعلبة'},
      {
        'name': 'منظفات وعناية',
        'description': 'مواد التنظيف والاستهلاك اليومي',
      },
      {'name': 'خضروات وفواكه', 'description': 'الخضار والفواكه الطازجة'},
      {'name': 'أدوات وقرطاسية', 'description': 'المستلزمات والأدوات'},
    ];

    for (final c in defaultCategories) {
      final existing = await db.query(
        AppTables.categories,
        where: 'name = ?',
        whereArgs: [c['name']],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert(AppTables.categories, {
          ...c,
          'created_at': now.millisecondsSinceEpoch,
        });
        addedCount++;
      }
    }

    return addedCount;
  }
}

/// In-memory mock implementation of [InventoryRepository] for fast, reliable testing.
class FakeInventoryRepository implements InventoryRepository {
  final List<UnitModel> _units = [];
  final List<CategoryModel> _categories = [];
  final List<ItemModel> _items = [];
  final List<InventoryMovementModel> _movements = [];
  bool seedCompleted = false;
  int _nextUnitId = 100;
  int _nextCategoryId = 100;
  int _nextItemId = 100;

  @override
  Future<void> seedDefaultDataIfEmpty() async {
    if (seedCompleted) return;
    if (_units.isEmpty) {
      final now = DateTime.now();
      _units.addAll([
        UnitModel(
          id: 1,
          name: 'قطعة',
          symbol: 'حبة',
          conversionFactor: 1,
          createdAt: now,
        ),
        UnitModel(
          id: 2,
          name: 'كرتون',
          symbol: 'ctn',
          conversionFactor: 12,
          createdAt: now,
        ),
        UnitModel(
          id: 3,
          name: 'كيلوجرام',
          symbol: 'كجم',
          conversionFactor: 1,
          createdAt: now,
        ),
        UnitModel(
          id: 4,
          name: 'لتر',
          symbol: 'لتر',
          conversionFactor: 1,
          createdAt: now,
        ),
      ]);
    }
    if (_categories.isEmpty) {
      final now = DateTime.now();
      _categories.addAll([
        CategoryModel(id: 1, name: 'عام', createdAt: now),
        CategoryModel(id: 2, name: 'مشروبات وعصائر', createdAt: now),
        CategoryModel(id: 3, name: 'أغذية ومعلبات', createdAt: now),
        CategoryModel(id: 4, name: 'منظفات وعناية', createdAt: now),
      ]);
    }
    seedCompleted = true;
  }

  @override
  Future<int> safeSeedMasterData() async {
    final before = _units.length + _categories.length;
    final defaultUnits = [
      UnitModel(
        name: 'قطعة',
        symbol: 'حبة',
        conversionFactor: 1,
        createdAt: DateTime.now(),
      ),
      UnitModel(
        name: 'كرتون',
        symbol: 'ctn',
        conversionFactor: 12,
        createdAt: DateTime.now(),
      ),
      UnitModel(
        name: 'كيلوجرام',
        symbol: 'كجم',
        conversionFactor: 1,
        createdAt: DateTime.now(),
      ),
      UnitModel(
        name: 'لتر',
        symbol: 'لتر',
        conversionFactor: 1,
        createdAt: DateTime.now(),
      ),
      UnitModel(
        name: 'متر',
        symbol: 'م',
        conversionFactor: 1,
        createdAt: DateTime.now(),
      ),
      UnitModel(
        name: 'باكت',
        symbol: 'باكت',
        conversionFactor: 1,
        createdAt: DateTime.now(),
      ),
      UnitModel(
        name: 'طرد',
        symbol: 'طرد',
        conversionFactor: 1,
        createdAt: DateTime.now(),
      ),
      UnitModel(
        name: 'درزن',
        symbol: 'درزن',
        conversionFactor: 12,
        createdAt: DateTime.now(),
      ),
    ];
    for (final u in defaultUnits) {
      if (!_units.any((x) => x.name == u.name || x.symbol == u.symbol)) {
        await insertUnit(u);
      }
    }

    final defaultCategories = [
      CategoryModel(
        name: 'عام',
        description: 'تصنيف عام للمنتجات',
        createdAt: DateTime.now(),
      ),
      CategoryModel(
        name: 'مشروبات وعصائر',
        description: 'المشروبات الباردة والساخنة',
        createdAt: DateTime.now(),
      ),
      CategoryModel(
        name: 'أغذية ومعلبات',
        description: 'المواد التموينية والمعلبة',
        createdAt: DateTime.now(),
      ),
      CategoryModel(
        name: 'منظفات وعناية',
        description: 'مواد التنظيف والاستهلاك اليومي',
        createdAt: DateTime.now(),
      ),
      CategoryModel(
        name: 'خضروات وفواكه',
        description: 'الخضار والفواكه الطازجة',
        createdAt: DateTime.now(),
      ),
      CategoryModel(
        name: 'أدوات وقرطاسية',
        description: 'المستلزمات والأدوات',
        createdAt: DateTime.now(),
      ),
    ];
    for (final c in defaultCategories) {
      if (!_categories.any((x) => x.name == c.name)) {
        await insertCategory(c);
      }
    }
    return (_units.length + _categories.length) - before;
  }

  @override
  Future<List<UnitModel>> getUnits() async => List.of(_units);

  @override
  Future<int> insertUnit(UnitModel unit) async {
    final cleanName = unit.cleanName.toLowerCase();
    final cleanSymbol = unit.cleanSymbol.toLowerCase();
    if (_units.any(
      (u) =>
          u.cleanName.toLowerCase() == cleanName ||
          u.cleanSymbol.toLowerCase() == cleanSymbol,
    )) {
      throw StateError('توجد وحدة قياس أخرى بنفس الاسم أو الرمز بالفعل.');
    }
    final id = unit.id ?? _nextUnitId++;
    _units.add(unit.copyWith(id: id));
    return id;
  }

  @override
  Future<int> updateUnit(UnitModel unit) async {
    if (unit.id == null) {
      throw ArgumentError('Unit id cannot be null for update');
    }
    final cleanName = unit.cleanName.toLowerCase();
    final cleanSymbol = unit.cleanSymbol.toLowerCase();
    if (_units.any(
      (u) =>
          u.id != unit.id &&
          (u.cleanName.toLowerCase() == cleanName ||
              u.cleanSymbol.toLowerCase() == cleanSymbol),
    )) {
      throw StateError('توجد وحدة قياس أخرى بنفس الاسم أو الرمز بالفعل.');
    }
    final idx = _units.indexWhere((u) => u.id == unit.id);
    if (idx != -1) {
      _units[idx] = unit;
      return 1;
    }
    return 0;
  }

  @override
  Future<int> getUnitItemCount(int unitId) async {
    return _items.where((i) => i.unitId == unitId).length;
  }

  @override
  Future<int> deleteUnit(int id) async {
    final count = await getUnitItemCount(id);
    if (count > 0) {
      throw StateError(
        'لا يمكن حذف وحدة القياس لوجود $count صنف مرتبط بها. يرجى أرشفة الوحدة بدلاً من حذفها لحماية السجلات.',
      );
    }
    final childCount = _units.where((u) => u.baseUnitId == id).length;
    if (childCount > 0) {
      throw StateError(
        'لا يمكن حذف وحدة القياس لوجود $childCount وحدة تابعة مرتبطة بها.',
      );
    }
    final before = _units.length;
    _units.removeWhere((u) => u.id == id);
    return before - _units.length;
  }

  @override
  Future<int> archiveUnit(int id, {bool unarchive = false}) async {
    final idx = _units.indexWhere((u) => u.id == id);
    if (idx == -1) return 0;
    final unit = _units[idx];
    final String newName = unarchive
        ? unit.cleanName
        : (unit.isArchived ? unit.name : '[مؤرشف] ${unit.cleanName}');
    return await updateUnit(unit.copyWith(name: newName));
  }

  @override
  Future<List<CategoryModel>> getCategories() async => List.of(_categories);

  @override
  Future<int> insertCategory(CategoryModel category) async {
    final cleanName = category.cleanName.toLowerCase();
    if (_categories.any((c) => c.cleanName.toLowerCase() == cleanName)) {
      throw StateError('يوجد تصنيف آخر بنفس الاسم بالفعل.');
    }
    final id = category.id ?? _nextCategoryId++;
    _categories.add(category.copyWith(id: id));
    return id;
  }

  @override
  Future<int> updateCategory(CategoryModel category) async {
    if (category.id == null) {
      throw ArgumentError('Category id cannot be null for update');
    }
    final cleanName = category.cleanName.toLowerCase();
    if (_categories.any(
      (c) => c.id != category.id && c.cleanName.toLowerCase() == cleanName,
    )) {
      throw StateError('يوجد تصنيف آخر بنفس الاسم بالفعل.');
    }
    final idx = _categories.indexWhere((c) => c.id == category.id);
    if (idx != -1) {
      _categories[idx] = category;
      return 1;
    }
    return 0;
  }

  @override
  Future<int> getCategoryItemCount(int categoryId) async {
    return _items.where((i) => i.categoryId == categoryId).length;
  }

  @override
  Future<int> deleteCategory(int id) async {
    final count = await getCategoryItemCount(id);
    if (count > 0) {
      throw StateError('لا يمكن حذف التصنيف لوجود $count صنف مرتبط به.');
    }
    final before = _categories.length;
    _categories.removeWhere((c) => c.id == id);
    return before - _categories.length;
  }

  @override
  Future<int> archiveCategory(int id, {bool unarchive = false}) async {
    final idx = _categories.indexWhere((c) => c.id == id);
    if (idx == -1) return 0;
    final cat = _categories[idx];
    String newDesc;
    if (unarchive) {
      newDesc = (cat.description ?? '').replaceAll('[مؤرشف]', '').trim();
    } else {
      final existing = (cat.description ?? '').replaceAll('[مؤرشف]', '').trim();
      newDesc = existing.isEmpty ? '[مؤرشف]' : '[مؤرشف] $existing';
    }
    _categories[idx] = cat.copyWith(
      description: newDesc.isEmpty ? null : newDesc,
    );
    return 1;
  }

  @override
  Future<List<ItemModel>> getItems({
    String? searchQuery,
    int? categoryId,
    bool? lowStockOnly,
    int? limit,
    int? offset,
  }) async {
    var results = _items.where((item) {
      if (!item.isActive) return false;
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        final match =
            item.name.toLowerCase().contains(q) ||
            item.code.toLowerCase().contains(q);
        if (!match) return false;
      }
      if (categoryId != null && item.categoryId != categoryId) {
        return false;
      }
      if (lowStockOnly == true && !item.isLowStock) {
        return false;
      }
      return true;
    }).toList();

    if (offset != null) {
      if (offset >= results.length) return [];
      results = results.sublist(offset);
    }
    if (limit != null && results.length > limit) {
      results = results.sublist(0, limit);
    }
    return results;
  }

  @override
  Future<ItemModel?> getItemById(int id) async {
    try {
      return _items.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ItemModel?> getItemByCode(String code) async {
    try {
      return _items.firstWhere((i) => i.code == code.trim());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> insertItem(ItemModel item, {int initialStock = 0}) async {
    final id = item.id ?? _nextItemId++;
    final qty = initialStock > 0 ? initialStock : item.stockQuantity;
    final itemWithId = item.copyWith(id: id, stockQuantity: qty);
    _items.add(itemWithId);

    if (qty > 0) {
      _movements.add(
        InventoryMovementModel(
          itemId: id,
          movementType: MovementType.initial,
          quantity: qty,
          unitCost: item.costPrice,
          referenceType: 'initial_balance',
          movementDate: DateTime.now(),
          notes: 'رصيد مخزني افتتاحي',
          createdAt: DateTime.now(),
        ),
      );
    }

    return id;
  }

  @override
  Future<int> updateItem(ItemModel item) async {
    final idx = _items.indexWhere((i) => i.id == item.id);
    if (idx != -1) {
      _items[idx] = item.copyWith(
        stockQuantity: _items[idx].stockQuantity,
        isActive: _items[idx].isActive,
        createdAt: _items[idx].createdAt,
        updatedAt: DateTime.now(),
      );
      return 1;
    }
    return 0;
  }

  @override
  Future<int> deleteItem(int id) async {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx != -1) {
      _items[idx] = _items[idx].copyWith(isActive: false);
      return 1;
    }
    return 0;
  }

  @override
  Future<void> recordStockAdjustment({
    required int itemId,
    required int actualStock,
    String? notes,
  }) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx != -1) {
      final current = _items[idx];
      final variance = actualStock - current.stockQuantity;
      if (variance != 0) {
        _items[idx] = current.copyWith(stockQuantity: actualStock);
        _movements.add(
          InventoryMovementModel(
            itemId: itemId,
            movementType: MovementType.adjustment,
            quantity: variance,
            unitCost: current.costPrice,
            referenceType: 'stock_adjustment',
            movementDate: DateTime.now(),
            notes: notes ?? 'تسوية جردية - فارق: $variance',
            createdAt: DateTime.now(),
          ),
        );
      }
    }
  }

  @override
  Future<List<InventoryMovementModel>> getItemMovements(
    int itemId, {
    int? limit,
    int? offset,
  }) async {
    var results = _movements.where((m) => m.itemId == itemId).toList();
    if (offset != null) {
      if (offset >= results.length) return [];
      results = results.sublist(offset);
    }
    if (limit != null && results.length > limit) {
      results = results.sublist(0, limit);
    }
    return results;
  }
}
