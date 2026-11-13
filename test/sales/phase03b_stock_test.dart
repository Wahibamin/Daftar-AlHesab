import 'dart:io';
import '../../test_support/funded_treasury.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final manager = AppDatabase.instance;
  final invoices = SqliteInvoicesRepository();
  final inventory = SqliteInventoryRepository();
  final date = DateTime(2026, 11, 5);
  late Directory directory;
  late Database db;
  late int item;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daftar_phase03b_stock_');
    manager.configureForTesting(
      factory: databaseFactoryFfi,
      path: '${directory.path}/isolated.db',
    );
    db = await manager.database;
    final unit = await inventory.insertUnit(
      UnitModel(name: 'قطعة', symbol: 'حبة', createdAt: date),
    );
    item = await inventory.insertItem(
      ItemModel(
        code: 'STOCK-B',
        name: 'صنف المخزون',
        unitId: unit,
        stockQuantity: 3,
        costPrice: const Money(600),
        sellingPrice: const Money(1000),
        createdAt: date,
        updatedAt: date,
      ),
    );
  });
  tearDown(() async {
    await manager.close();
    await directory.delete(recursive: true);
  });
  InvoiceModel request({
    String number = 'SALE-B',
    int quantity = 4,
    InvoiceType type = InvoiceType.sale,
    List<InvoiceItemModel>? lines,
  }) {
    final items =
        lines ??
        [
          InvoiceItemModel.create(
            itemId: item,
            quantity: quantity,
            unitPrice: const Money(1000),
          ),
        ];
    final total = items.fold<Money>(
      Money.zero,
      (sum, line) => sum + line.totalPrice,
    );
    return InvoiceModel.buildWithItems(
      invoiceNumber: number,
      invoiceType: type,
      items: items,
      paidAmount: total,
      invoiceDate: date,
      createdAt: date,
      updatedAt: date,
    );
  }

  Future<Map<String, Object?>> snapshot() async => {
    for (final table in [
      AppTables.invoices,
      AppTables.invoiceItems,
      AppTables.inventoryMovements,
      AppTables.items,
      AppTables.parties,
    ])
      table: await db.query(table, orderBy: 'id'),
    'treasury':
        (await SqliteVouchersRepository().getTreasuryBalance()).rawUnits,
  };
  for (final type in [InvoiceType.sale, InvoiceType.purchaseReturn]) {
    for (final path in ['save', 'finalize', 'create']) {
      test(
        'Phase03B $type insufficient stock via $path leaves every ledger unchanged',
        () async {
          final draft = request(type: type);
          final id = path == 'finalize'
              ? await invoices.createInvoice(draft)
              : null;
          final before = await snapshot();
          await expectLater(
            switch (path) {
              'finalize' => invoices.finalizeInvoice(id!),
              'create' => invoices.createInvoice(
                draft.copyWith(status: InvoiceStatus.approved),
              ),
              _ => invoices.saveAndFinalizeInvoice(draft),
            },
            throwsA(
              predicate(
                (error) => error.toString().contains('المخزون غير كاف'),
              ),
            ),
          );
          expect(await snapshot(), before);
        },
      );
    }
  }
  test('Phase03B duplicate lines are checked as a combined quantity', () async {
    final before = await snapshot();
    final line = InvoiceItemModel.create(
      itemId: item,
      quantity: 2,
      unitPrice: const Money(1000),
    );
    await expectLater(
      invoices.saveAndFinalizeInvoice(request(lines: [line, line])),
      throwsA(anything),
    );
    expect(await snapshot(), before);
  });
  test(
    'Phase03B insufficient partial sale preserves existing party debt and all account balances',
    () async {
      final party = await SqlitePartiesRepository().insertParty(
        PartyModel(
          name: 'عميل الاختبار',
          phone: '',
          type: PartyType.customer,
          currentBalance: const Money(-9000),
          createdAt: date,
          updatedAt: date,
        ),
      );
      final draft = request().copyWith(
        partyId: party,
        paymentType: PaymentType.partial,
        paymentMethod: PaymentMethod.bank,
        paidAmount: const Money(1000),
        remainingAmount: const Money(3000),
      );
      final before = await snapshot();
      final accounts = await SqliteVouchersRepository().getTreasuryBalances();
      await expectLater(
        invoices.saveAndFinalizeInvoice(draft),
        throwsA(
          predicate((error) => error.toString().contains('المخزون غير كاف')),
        ),
      );
      expect(await snapshot(), before);
      final after = await SqliteVouchersRepository().getTreasuryBalances();
      expect(after.cash.balance, accounts.cash.balance);
      expect(after.bank.balance, accounts.bank.balance);
      expect(after.transfers.balance, accounts.transfers.balance);
    },
  );
  test(
    'Phase03B exact available stock posts once and cancellation restores it once',
    () async {
      final original = request(quantity: 3);
      final id = await invoices.saveAndFinalizeInvoice(original);
      expect((await inventory.getItemById(item))!.stockQuantity, 0);
      await invoices.saveAndFinalizeInvoice(original.copyWith(id: id));
      await invoices.cancelInvoice(id);
      await invoices.cancelInvoice(id);
      expect((await inventory.getItemById(item))!.stockQuantity, 3);
      expect((await inventory.getItemMovements(item)).length, 3);
    },
  );
  test(
    'Phase03B concurrent sales cannot both consume the same available quantity',
    () async {
      final results = await Future.wait(
        [
          request(number: 'A', quantity: 2),
          request(number: 'B', quantity: 2),
        ].map((value) async {
          try {
            return await invoices.saveAndFinalizeInvoice(value);
          } catch (error) {
            return error;
          }
        }),
      );
      expect(results.whereType<int>().length, 1);
      expect((await inventory.getItemById(item))!.stockQuantity, 1);
      expect((await invoices.getInvoices()).length, 1);
    },
  );
  test(
    'Phase03B purchase cancellation cannot remove units already consumed by sales',
    () async {
      await fundTreasury(await manager.database);
      final purchase = await invoices.saveAndFinalizeInvoice(
        request(type: InvoiceType.purchase, quantity: 2),
      );
      await invoices.saveAndFinalizeInvoice(
        request(number: 'SELL', quantity: 5),
      );
      final before = await snapshot();
      await expectLater(invoices.cancelInvoice(purchase), throwsA(anything));
      expect(await snapshot(), before);
    },
  );
}
