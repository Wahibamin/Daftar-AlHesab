import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final manager = AppDatabase.instance;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daftar_production_');
    manager.configureForTesting(
      factory: databaseFactoryFfi,
      path: '${directory.path}/test.db',
    );
  });
  tearDown(() async {
    await manager.close();
    await directory.delete(recursive: true);
  });

  for (final originalCost in [0, 600]) {
    test(
      'PR-001 reversal preserves frozen cost $originalCost after catalog change and restart',
      () async {
        final now = DateTime.now();
        final inventory = SqliteInventoryRepository();
        final unit = await inventory.insertUnit(
          UnitModel(name: 'unit', symbol: 'u', createdAt: now),
        );
        final item = await inventory.insertItem(
          ItemModel(
            code: 'PR-$originalCost',
            name: 'Synthetic item',
            unitId: unit,
            stockQuantity: 5,
            costPrice: Money(originalCost),
            sellingPrice: const Money(1000),
            createdAt: now,
            updatedAt: now,
          ),
          initialStock: 5,
        );
        final repo = SqliteInvoicesRepository();
        final invoice = await repo.saveAndFinalizeInvoice(
          InvoiceModel.buildWithItems(
            invoiceNumber: 'PR-COST-$originalCost',
            invoiceType: InvoiceType.sale,
            paymentType: PaymentType.cash,
            paidAmount: const Money(2000),
            items: [
              InvoiceItemModel.create(
                itemId: item,
                quantity: 2,
                unitPrice: const Money(1000),
              ),
            ],
            invoiceDate: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final stored = (await inventory.getItemById(item))!;
        await inventory.updateItem(
          stored.copyWith(costPrice: const Money(900)),
        );
        await manager.close();
        await repo.cancelInvoice(invoice);
        await repo.cancelInvoice(invoice);
        final db = await manager.database;
        final movements = await db.query(
          AppTables.inventoryMovements,
          where: 'reference_id = ? AND reference_type IN (?,?)',
          whereArgs: [invoice, 'invoice', 'invoice_cancellation'],
          orderBy: 'id',
        );
        expect(movements.length, 2);
        expect(movements.first['unit_cost_int'], originalCost);
        expect(
          movements.last['unit_cost_int'],
          originalCost,
          reason:
              'Cancellation must reverse historical cost, including legitimate zero.',
        );
        expect((await inventory.getItemById(item))!.stockQuantity, 5);
        expect(
          (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
          'ok',
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      },
    );
  }
}
