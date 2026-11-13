import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/reports/repositories/reports_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final manager = AppDatabase.instance;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'daftar_final_regression_',
    );
    manager.configureForTesting(
      factory: databaseFactoryFfi,
      path: '${directory.path}/qa.db',
    );
  });
  tearDown(() async {
    await manager.close();
    await directory.delete(recursive: true);
  });
  test(
    'QA-001 fresh production repositories never seed demonstration parties or debt',
    () async {
      final db = await manager.database;
      await SqlitePartiesRepository().seedDefaultDataIfEmpty();
      expect(await db.query(AppTables.parties), isEmpty);
      final dashboard = await SqliteReportsRepository().getDashboardMetrics();
      expect(dashboard.totalReceivables, Money.zero);
      expect(dashboard.totalPayables, Money.zero);
    },
  );
  test(
    'QA-001 production invoice and voucher seed APIs never manufacture transactions',
    () async {
      final db = await manager.database;
      await SqliteVouchersRepository().seedDefaultVouchersIfEmpty();
      await SqliteInvoicesRepository().seedDefaultInvoicesIfEmpty();
      expect(await db.query(AppTables.vouchers), isEmpty);
      expect(await db.query(AppTables.invoices), isEmpty);
      expect(await db.query(AppTables.inventoryMovements), isEmpty);
    },
  );
  test(
    'QA-002 a posted zero-cost sale retains historical zero COGS after catalog cost changes',
    () async {
      final now = DateTime.now();
      final inventory = SqliteInventoryRepository();
      final unit = await inventory.insertUnit(
        UnitModel(name: 'QA', symbol: 'q', createdAt: now),
      );
      final item = await inventory.insertItem(
        ItemModel(
          code: 'ZERO-COST',
          name: 'Zero acquisition cost',
          unitId: unit,
          stockQuantity: 5,
          costPrice: Money.zero,
          sellingPrice: const Money(1000),
          createdAt: now,
          updatedAt: now,
        ),
        initialStock: 5,
      );
      await SqliteInvoicesRepository().saveAndFinalizeInvoice(
        InvoiceModel.buildWithItems(
          invoiceNumber: 'QA-ZERO-COST',
          invoiceType: InvoiceType.sale,
          paymentType: PaymentType.cash,
          paidAmount: const Money(1000),
          items: [
            InvoiceItemModel.create(
              itemId: item,
              quantity: 1,
              unitPrice: const Money(1000),
            ),
          ],
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final reports = SqliteReportsRepository();
      final before = await reports.getProfitLossReport(
        startDate: DateTime(2000),
        endDate: DateTime(2100),
      );
      expect(before.costOfGoodsSold, Money.zero);
      final saved = (await inventory.getItemById(item))!;
      await inventory.updateItem(saved.copyWith(costPrice: const Money(500)));
      final after = await reports.getProfitLossReport(
        startDate: DateTime(2000),
        endDate: DateTime(2100),
      );
      expect(after.costOfGoodsSold, before.costOfGoodsSold);
      expect(after.netProfit, before.netProfit);
    },
  );
}
