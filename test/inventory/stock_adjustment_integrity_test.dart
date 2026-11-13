import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/models/movement_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late String dbPath;
  late Directory tempDir;
  late SqliteInventoryRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('raf_stock_test_');
    dbPath = p.join(tempDir.path, 'stock_test.db');
    AppDatabase.instance.configureForTesting(
      factory: databaseFactoryFfi,
      path: dbPath,
    );
    repo = SqliteInventoryRepository(AppDatabase.instance);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Stock Adjustment Data Integrity & Ledger Tests', () {
    test(
      'Adjustment from higher to lower quantity records negative signed variance and reduces stock',
      () async {
        // 1. Setup master unit and item with 50 initial units
        final unitId = await repo.insertUnit(
          UnitModel(
            name: 'حبة',
            symbol: 'حبة',
            conversionFactor: 1,
            createdAt: DateTime.now(),
          ),
        );

        final itemId = await repo.insertItem(
          ItemModel(
            code: 'ADJ_TEST_01',
            name: 'صنف تجريبي للتسوية السالبة',
            unitId: unitId,
            costPrice: const Money(1000), // 10.00
            sellingPrice: const Money(1500),
            stockQuantity: 50,
            minAlertLimit: 5,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          initialStock: 50,
        );

        // Verify initial state
        var item = await repo.getItemById(itemId);
        expect(item, isNotNull);
        expect(item!.stockQuantity, equals(50));

        // 2. Perform adjustment: physical count is 35 (shortage of 15 units)
        await repo.recordStockAdjustment(
          itemId: itemId,
          actualStock: 35,
          notes: 'تسوية عجز جردي',
        );

        // 3. Verify item stock updated
        item = await repo.getItemById(itemId);
        expect(item!.stockQuantity, equals(35));

        // 4. Verify movement entry in inventory ledger
        final movements = await repo.getItemMovements(itemId);
        // We expect 2 movements: initial (50) and adjustment (-15)
        expect(movements, hasLength(2));

        final adjMovement = movements.firstWhere(
          (m) => m.movementType == MovementType.adjustment,
        );
        expect(adjMovement.quantity, equals(-15));
        expect(adjMovement.increasesStock, isFalse);
        expect(adjMovement.effectiveQuantityDelta, equals(-15));
        expect(adjMovement.referenceType, equals('stock_adjustment'));

        // 5. Total ledger calculation
        final totalStockFromMovements = movements.fold<int>(
          0,
          (sum, m) => sum + m.effectiveQuantityDelta,
        );
        expect(totalStockFromMovements, equals(35));
        expect(item.stockQuantity, equals(totalStockFromMovements));
      },
    );

    test(
      'Adjustment from lower to higher quantity records positive signed variance and increases stock',
      () async {
        final unitId = await repo.insertUnit(
          UnitModel(
            name: 'حبة',
            symbol: 'حبة',
            conversionFactor: 1,
            createdAt: DateTime.now(),
          ),
        );

        final itemId = await repo.insertItem(
          ItemModel(
            code: 'ADJ_TEST_02',
            name: 'صنف تجريبي للتسوية الموجبة',
            unitId: unitId,
            costPrice: const Money(2000),
            sellingPrice: const Money(3000),
            stockQuantity: 20,
            minAlertLimit: 5,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          initialStock: 20,
        );

        // Perform adjustment: physical count is 32 (surplus of 12 units)
        await repo.recordStockAdjustment(
          itemId: itemId,
          actualStock: 32,
          notes: 'تسوية فائض جردي',
        );

        final item = await repo.getItemById(itemId);
        expect(item!.stockQuantity, equals(32));

        final movements = await repo.getItemMovements(itemId);
        expect(movements, hasLength(2));

        final adjMovement = movements.firstWhere(
          (m) => m.movementType == MovementType.adjustment,
        );
        expect(adjMovement.quantity, equals(12));
        expect(adjMovement.increasesStock, isTrue);
        expect(adjMovement.effectiveQuantityDelta, equals(12));

        final totalStockFromMovements = movements.fold<int>(
          0,
          (sum, m) => sum + m.effectiveQuantityDelta,
        );
        expect(totalStockFromMovements, equals(32));
        expect(item.stockQuantity, equals(totalStockFromMovements));
      },
    );

    test(
      'Adjustment with zero variance does not insert spurious movements and leaves stock unchanged',
      () async {
        final unitId = await repo.insertUnit(
          UnitModel(
            name: 'حبة',
            symbol: 'حبة',
            conversionFactor: 1,
            createdAt: DateTime.now(),
          ),
        );

        final itemId = await repo.insertItem(
          ItemModel(
            code: 'ADJ_TEST_03',
            name: 'صنف متطابق الجرد',
            unitId: unitId,
            costPrice: const Money(1000),
            sellingPrice: const Money(1500),
            stockQuantity: 40,
            minAlertLimit: 5,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          initialStock: 40,
        );

        final movementsBefore = await repo.getItemMovements(itemId);
        expect(movementsBefore, hasLength(1));

        // Actual stock equals current stock (variance = 0)
        await repo.recordStockAdjustment(
          itemId: itemId,
          actualStock: 40,
          notes: 'جرد مطابق تماماً',
        );

        final item = await repo.getItemById(itemId);
        expect(item!.stockQuantity, equals(40));

        final movementsAfter = await repo.getItemMovements(itemId);
        expect(movementsAfter, hasLength(1)); // No new movement added
      },
    );

    test(
      'Ledger balance perfectly reconciles with item stock after closing and reopening database',
      () async {
        final unitId = await repo.insertUnit(
          UnitModel(
            name: 'حبة',
            symbol: 'حبة',
            conversionFactor: 1,
            createdAt: DateTime.now(),
          ),
        );

        final itemId = await repo.insertItem(
          ItemModel(
            code: 'REOPEN_TEST_01',
            name: 'صنف اختبار إغلاق وإعادة فتح القاعدة',
            unitId: unitId,
            costPrice: const Money(5000),
            sellingPrice: const Money(7000),
            stockQuantity: 100,
            minAlertLimit: 10,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          initialStock: 100,
        );

        // Downward adjustment: -30 (stock becomes 70)
        await repo.recordStockAdjustment(itemId: itemId, actualStock: 70);

        // Upward adjustment: +15 (stock becomes 85)
        await repo.recordStockAdjustment(itemId: itemId, actualStock: 85);

        // Zero adjustment: stock remains 85
        await repo.recordStockAdjustment(itemId: itemId, actualStock: 85);

        // Now officially CLOSE the database
        await AppDatabase.instance.close();

        // Configure a new repository pointing to the same persistent SQLite file
        AppDatabase.instance.configureForTesting(
          factory: databaseFactoryFfi,
          path: dbPath,
        );
        final newRepo = SqliteInventoryRepository(AppDatabase.instance);

        // Re-read item and movements from fresh connection
        final reloadedItem = await newRepo.getItemById(itemId);
        expect(reloadedItem, isNotNull);
        expect(reloadedItem!.stockQuantity, equals(85));

        final reloadedMovements = await newRepo.getItemMovements(itemId);
        expect(
          reloadedMovements,
          hasLength(3),
        ); // initial(100), adj(-30), adj(15)

        final sumMovements = reloadedMovements.fold<int>(
          0,
          (sum, m) => sum + m.effectiveQuantityDelta,
        );
        expect(sumMovements, equals(85));
        expect(reloadedItem.stockQuantity, equals(sumMovements));
      },
    );
  });
}
