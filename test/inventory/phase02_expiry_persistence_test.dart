import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final date = DateTime(2026, 11, 5);
  ItemModel item() => ItemModel(
    code: 'EXPIRY-PHASE02',
    name: 'صنف اختبار الصلاحية',
    unitId: 1,
    categoryId: 7,
    costPrice: const Money(6000),
    sellingPrice: const Money(10000),
    stockQuantity: 20,
    expiryDate: DateTime(2030, 1, 1),
    createdAt: date,
    updatedAt: date,
  );

  group('DH-NEW-03 model', () {
    test('omitting expiryDate keeps the existing value', () {
      final original = item();
      expect(
        original.copyWith(name: 'اسم آخر').expiryDate,
        original.expiryDate,
      );
    });
    test('explicit date replaces the existing value', () {
      expect(
        item().copyWith(expiryDate: DateTime(2031, 2, 2)).expiryDate,
        DateTime(2031, 2, 2),
      );
    });
    test('explicit null clears only expiryDate', () {
      final cleared = item().copyWith(expiryDate: null, categoryId: null);
      expect(cleared.expiryDate, isNull);
      expect(
        cleared.categoryId,
        7,
        reason: 'Other optional copyWith semantics remain unchanged',
      );
      expect(cleared.stockQuantity, 20);
      expect(cleared.costPrice, const Money(6000));
      expect(cleared.sellingPrice, const Money(10000));
      expect(cleared.toMap()['expiry_date'], isNull);
      expect(cleared.isExpiredAt(DateTime(2040)), isFalse);
      expect(cleared.remainingExpiryDays(DateTime(2040)), isNull);
    });
  });

  sqfliteFfiInit();
  test(
    'DH-NEW-03 SQLite edit then clear persists NULL across database reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'daftar_phase02_expiry_',
      );
      final manager = AppDatabase.instance;
      manager.configureForTesting(
        factory: databaseFactoryFfi,
        path: '${directory.path}/isolated.db',
      );
      final repository = SqliteInventoryRepository(manager);
      try {
        final unit = await repository.insertUnit(
          UnitModel(name: 'قطعة', symbol: 'حبة', createdAt: date),
        );
        final id = await repository.insertItem(
          ItemModel(
            code: 'EXPIRY-DB',
            name: 'صنف صلاحية',
            unitId: unit,
            costPrice: const Money(6000),
            sellingPrice: const Money(10000),
            stockQuantity: 20,
            expiryDate: DateTime(2030, 1, 1),
            createdAt: date,
            updatedAt: date,
          ),
        );
        var saved = (await repository.getItemById(id))!;
        await repository.updateItem(
          saved.copyWith(expiryDate: DateTime(2031, 2, 2)),
        );
        saved = (await repository.getItemById(id))!;
        expect(saved.expiryDate, DateTime(2031, 2, 2));
        await repository.updateItem(saved.copyWith(expiryDate: null));
        final db = await manager.database;
        final row = (await db.query(
          AppTables.items,
          where: 'id = ?',
          whereArgs: [id],
        )).single;
        expect(row['expiry_date'], isNull);
        await manager.close();
        saved = (await repository.getItemById(id))!;
        expect(saved.expiryDate, isNull);
        expect(saved.stockQuantity, 20);
        expect(saved.costPriceInt, 6000);
        expect(saved.sellingPriceInt, 10000);
        expect((await repository.getItemMovements(id)).length, 1);
      } finally {
        await manager.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
