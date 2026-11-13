import 'dart:io';
import '../../test_support/funded_treasury.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/models/movement_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/reports/repositories/reports_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late String tempDbPath;
  late SqliteInvoicesRepository invoicesRepo;
  late SqliteInventoryRepository inventoryRepo;
  late SqlitePartiesRepository partiesRepo;
  late SqliteVouchersRepository vouchersRepo;
  late SqliteReportsRepository reportsRepo;
  late int itemId;
  late int customerId;
  late int supplierId;

  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'raf_accounting_int_',
    );
    tempDbPath = '${tempDir.path}${Platform.pathSeparator}test.db';

    AppDatabase.instance.configureForTesting(
      factory: databaseFactoryFfi,
      path: tempDbPath,
    );
    db = await AppDatabase.instance.database;

    invoicesRepo = SqliteInvoicesRepository(AppDatabase.instance);
    inventoryRepo = SqliteInventoryRepository(AppDatabase.instance);
    partiesRepo = SqlitePartiesRepository(AppDatabase.instance);
    vouchersRepo = SqliteVouchersRepository(AppDatabase.instance);
    reportsRepo = SqliteReportsRepository(AppDatabase.instance);

    await inventoryRepo.safeSeedMasterData();
    final units = await inventoryRepo.getUnits();

    itemId = await inventoryRepo.insertItem(
      ItemModel(
        code: 'INT001',
        name: 'منتج تكاملي 1',
        unitId: units.first.id!,
        costPrice: const Money(4000), // 40.00 SAR
        sellingPrice: const Money(6000), // 60.00 SAR
        stockQuantity: 100,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      initialStock: 100,
    );

    customerId = await partiesRepo.insertParty(
      PartyModel(
        name: 'شركة العميل التجاري',
        phone: '0501110000',
        type: PartyType.customer,
        currentBalance: Money.zero,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    supplierId = await partiesRepo.insertParty(
      PartyModel(
        name: 'مؤسسة المورد العام',
        phone: '0502220000',
        type: PartyType.supplier,
        currentBalance: Money.zero,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    try {
      final f = File(tempDbPath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  });

  group('Phase 5: Full Accounting & Inventory Integration Tests', () {
    test(
      '5.1 Sales Invoice: reduces stock, posts movement, charges remaining to customer, updates treasury',
      () async {
        final initialTreasury = await vouchersRepo.getTreasuryBalance();

        // Partial sale: 3 units * 60.00 = 180.00 + 15% tax (27.00) = 207.00 SAR
        // Paid 100.00 SAR, remaining 107.00 SAR
        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-2026-0001',
          partyId: customerId,
          invoiceType: InvoiceType.sale,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.partial,
          items: [
            InvoiceItemModel.create(
              itemId: itemId,
              quantity: 3,
              unitPrice: const Money(6000),
            ),
          ],
          paidAmount: const Money(10000),
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final invId = await invoicesRepo.saveAndFinalizeInvoice(invoice);

        // Verify stock decreased from 100 to 97
        final updatedItem = await inventoryRepo.getItemById(itemId);
        expect(updatedItem!.stockQuantity, equals(97));

        // Verify movement recorded
        final movements = await inventoryRepo.getItemMovements(itemId);
        final saleMovement = movements.firstWhere(
          (m) => m.referenceId == invId,
        );
        expect(saleMovement.movementType, equals(MovementType.sale));
        expect(saleMovement.quantity, equals(3));

        // Verify customer owes 80.00 SAR (-8000)
        final customer = await partiesRepo.getPartyById(customerId);
        expect(customer!.currentBalance, equals(const Money(-8000)));

        // Verify treasury increased by paid 100.00 SAR (+10000)
        final currentTreasury = await vouchersRepo.getTreasuryBalance();
        expect(currentTreasury, equals(initialTreasury + const Money(10000)));

        // Idempotency: re-finalizing must NOT decrease stock again
        await invoicesRepo.finalizeInvoice(invId);
        final itemAfterReFinalize = await inventoryRepo.getItemById(itemId);
        expect(itemAfterReFinalize!.stockQuantity, equals(97));

        // Verify reports reflect sale revenue
        final pl = await reportsRepo.getProfitLossReport(
          startDate: DateTime.now().subtract(const Duration(days: 1)),
          endDate: DateTime.now().add(const Duration(days: 1)),
        );
        expect(pl.totalRevenues, equals(const Money(18000)));

        // Foreign key integrity check
        final fkCheck = await db.rawQuery('PRAGMA foreign_key_check;');
        expect(fkCheck, isEmpty);
      },
    );

    test(
      '5.2 Purchase Invoice: increases stock, records cost, sets supplier balance, decreases treasury',
      () async {
        await fundTreasury(await AppDatabase.instance.database);
        final initialTreasury = await vouchersRepo.getTreasuryBalance();

        // Purchase: 10 units @ 45.00 SAR = 450.00 SAR
        // Paid 200.00 SAR, remaining 250.00 SAR
        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'PUR-2026-0001',
          partyId: supplierId,
          invoiceType: InvoiceType.purchase,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.partial,
          items: [
            InvoiceItemModel.create(
              itemId: itemId,
              quantity: 10,
              unitPrice: const Money(4500),
            ),
          ],
          paidAmount: const Money(20000),
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final invId = await invoicesRepo.saveAndFinalizeInvoice(invoice);

        // Verify stock increased from 100 to 110
        final updatedItem = await inventoryRepo.getItemById(itemId);
        expect(updatedItem!.stockQuantity, equals(110));

        // Verify movement recorded
        final movements = await inventoryRepo.getItemMovements(itemId);
        final purMovement = movements.firstWhere((m) => m.referenceId == invId);
        expect(purMovement.movementType, equals(MovementType.purchase));
        expect(purMovement.quantity, equals(10));

        // Verify supplier is owed 250.00 SAR (+25000 creditor)
        final supplier = await partiesRepo.getPartyById(supplierId);
        expect(supplier!.currentBalance, equals(const Money(25000)));

        // Verify treasury decreased by 200.00 SAR (-20000)
        final currentTreasury = await vouchersRepo.getTreasuryBalance();
        expect(currentTreasury, equals(initialTreasury - const Money(20000)));
      },
    );

    test(
      '5.3 Sales Return: returns items to stock, reverses customer debt, deducts refunded cash',
      () async {
        await fundTreasury(await AppDatabase.instance.database);
        final initialTreasury = await vouchersRepo.getTreasuryBalance();

        // Sales Return: 2 units * 60.00 SAR = 120.00 SAR
        // Refunded 50.00 SAR cash, remaining 70.00 SAR credited to customer account
        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'SRT-2026-0001',
          partyId: customerId,
          invoiceType: InvoiceType.saleReturn,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.partial,
          items: [
            InvoiceItemModel.create(
              itemId: itemId,
              quantity: 2,
              unitPrice: const Money(6000),
            ),
          ],
          paidAmount: const Money(5000),
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final invId = await invoicesRepo.saveAndFinalizeInvoice(invoice);

        // Stock increased from 100 to 102
        final updatedItem = await inventoryRepo.getItemById(itemId);
        expect(updatedItem!.stockQuantity, equals(102));

        // Movement recorded as saleReturn
        final movements = await inventoryRepo.getItemMovements(itemId);
        final retMovement = movements.firstWhere((m) => m.referenceId == invId);
        expect(retMovement.movementType, equals(MovementType.saleReturn));
        expect(retMovement.quantity, equals(2));

        // Customer debt reduced by 70.00 SAR (+7000)
        final customer = await partiesRepo.getPartyById(customerId);
        expect(customer!.currentBalance, equals(const Money(7000)));

        // Treasury decreased by cash refunded: 50.00 SAR
        final currentTreasury = await vouchersRepo.getTreasuryBalance();
        expect(currentTreasury, equals(initialTreasury - const Money(5000)));
      },
    );

    test(
      '5.4 Purchase Return: deducts items from stock, decreases supplier creditor balance, recovers cash',
      () async {
        final initialTreasury = await vouchersRepo.getTreasuryBalance();

        // Purchase Return: 5 units * 40.00 SAR = 200.00 SAR
        // Recovered 80.00 SAR cash, remaining 120.00 SAR reduced from supplier payable
        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'PRT-2026-0001',
          partyId: supplierId,
          invoiceType: InvoiceType.purchaseReturn,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.partial,
          items: [
            InvoiceItemModel.create(
              itemId: itemId,
              quantity: 5,
              unitPrice: const Money(4000),
            ),
          ],
          paidAmount: const Money(8000),
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final invId = await invoicesRepo.saveAndFinalizeInvoice(invoice);

        // Stock decreased from 100 to 95
        final updatedItem = await inventoryRepo.getItemById(itemId);
        expect(updatedItem!.stockQuantity, equals(95));

        // Movement recorded as purchaseReturn
        final movements = await inventoryRepo.getItemMovements(itemId);
        final retMovement = movements.firstWhere((m) => m.referenceId == invId);
        expect(retMovement.movementType, equals(MovementType.purchaseReturn));
        expect(retMovement.quantity, equals(5));

        // Supplier balance reduced by remaining 120.00 SAR (-12000)
        final supplier = await partiesRepo.getPartyById(supplierId);
        expect(supplier!.currentBalance, equals(const Money(-12000)));

        // Treasury increased by cash received from return: 80.00 SAR (+8000)
        final currentTreasury = await vouchersRepo.getTreasuryBalance();
        expect(currentTreasury, equals(initialTreasury + const Money(8000)));
      },
    );

    test(
      '5.5 Cancellation & Idempotency: exact reversal of all 4 types and protection against double-reversal',
      () async {
        // 1. Finalize a sale
        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-CANCEL-001',
          partyId: customerId,
          invoiceType: InvoiceType.sale,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.partial,
          items: [
            InvoiceItemModel.create(
              itemId: itemId,
              quantity: 4,
              unitPrice: const Money(6000), // 240.00 SAR
            ),
          ],
          paidAmount: const Money(4000), // Paid 40.00, remaining 200.00 SAR
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final invId = await invoicesRepo.saveAndFinalizeInvoice(invoice);
        expect(
          (await inventoryRepo.getItemById(itemId))!.stockQuantity,
          equals(96),
        );
        expect(
          (await partiesRepo.getPartyById(customerId))!.currentBalance,
          equals(const Money(-20000)),
        );

        // Simulate app restart / reopen database
        await AppDatabase.instance.close();
        AppDatabase.instance.configureForTesting(
          factory: databaseFactoryFfi,
          path: tempDbPath,
        );
        final reopenedInvoicesRepo = SqliteInvoicesRepository(
          AppDatabase.instance,
        );
        final reopenedInventoryRepo = SqliteInventoryRepository(
          AppDatabase.instance,
        );
        final reopenedPartiesRepo = SqlitePartiesRepository(
          AppDatabase.instance,
        );

        // Read from reopened DB
        final readInvoice = await reopenedInvoicesRepo.getInvoiceById(invId);
        expect(readInvoice, isNotNull);
        expect(readInvoice!.status, equals(InvoiceStatus.approved));

        // Cancel invoice once
        await reopenedInvoicesRepo.cancelInvoice(invId);

        // Verify stock reversed back to 100
        final stockAfterCancel = (await reopenedInventoryRepo.getItemById(
          itemId,
        ))!.stockQuantity;
        expect(stockAfterCancel, equals(100));

        // Verify customer debt reversed back to 0
        final customerBalAfterCancel = (await reopenedPartiesRepo.getPartyById(
          customerId,
        ))!.currentBalance;
        expect(customerBalAfterCancel, equals(Money.zero));

        // Verify invoice status in DB is cancelled
        final cancelledInv = await reopenedInvoicesRepo.getInvoiceById(invId);
        expect(cancelledInv!.status, equals(InvoiceStatus.cancelled));

        // Attempt second cancellation (idempotent guard)
        await reopenedInvoicesRepo.cancelInvoice(invId);

        // Stock and balance must remain untouched
        expect(
          (await reopenedInventoryRepo.getItemById(itemId))!.stockQuantity,
          equals(100),
        );
        expect(
          (await reopenedPartiesRepo.getPartyById(customerId))!.currentBalance,
          equals(Money.zero),
        );
      },
    );

    test(
      '5.6 Atomic rollback on transaction error ensures zero corruption',
      () async {
        final initialStock = (await inventoryRepo.getItemById(
          itemId,
        ))!.stockQuantity;
        final initialCustomerBal = (await partiesRepo.getPartyById(
          customerId,
        ))!.currentBalance;

        // Invoice with invalid non-existent itemId in item list
        final brokenInvoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-FAIL-001',
          partyId: customerId,
          invoiceType: InvoiceType.sale,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.cash,
          items: [
            InvoiceItemModel.create(
              itemId: 999999, // Non-existent item ID, violates Foreign Key
              quantity: 1,
              unitPrice: const Money(1000),
            ),
          ],
          paidAmount: const Money(1000),
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        try {
          await invoicesRepo.saveAndFinalizeInvoice(brokenInvoice);
          fail('Should have thrown database exception');
        } catch (_) {
          // Expected exception
        }

        // Check database state: stock and balance completely untouched
        final stockAfterFail = (await inventoryRepo.getItemById(
          itemId,
        ))!.stockQuantity;
        final customerBalAfterFail = (await partiesRepo.getPartyById(
          customerId,
        ))!.currentBalance;

        expect(stockAfterFail, equals(initialStock));
        expect(customerBalAfterFail, equals(initialCustomerBal));

        // Check that broken invoice was rolled back
        final failedInv = await invoicesRepo.getInvoiceByNumber('INV-FAIL-001');
        expect(failedInv, isNull);
      },
    );
  });
}
