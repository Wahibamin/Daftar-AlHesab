import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/models/movement_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late String dbPath;
  late Directory tempDir;
  late SqliteInvoicesRepository invoicesRepo;
  late SqliteInventoryRepository inventoryRepo;
  late SqlitePartiesRepository partiesRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('raf_inv_test_');
    dbPath = p.join(tempDir.path, 'invoices_test.db');
    AppDatabase.instance.configureForTesting(
      factory: databaseFactoryFfi,
      path: dbPath,
    );
    invoicesRepo = SqliteInvoicesRepository(AppDatabase.instance);
    inventoryRepo = SqliteInventoryRepository(AppDatabase.instance);
    partiesRepo = SqlitePartiesRepository(AppDatabase.instance);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<int> setupItem({required String code, required int stock}) async {
    final unitId = await inventoryRepo.insertUnit(
      UnitModel(
        name: 'قطعة',
        symbol: 'حبة',
        conversionFactor: 1,
        createdAt: DateTime.now(),
      ),
    );
    return await inventoryRepo.insertItem(
      ItemModel(
        code: code,
        name: 'منتج تجريبي $code',
        unitId: unitId,
        costPrice: const Money(1000), // 10.00
        sellingPrice: const Money(2000), // 20.00
        stockQuantity: stock,
        minAlertLimit: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      initialStock: stock,
    );
  }

  Future<int> setupParty({
    required String name,
    required PartyType type,
    int initialBalance = 0,
  }) async {
    return await partiesRepo.insertParty(
      PartyModel(
        name: name,
        phone: '0500000000',
        type: type,
        currentBalance: Money(initialBalance),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  group('Invoice Lifecycle, Ledger, & Transaction Integrity Tests', () {
    test(
      '1. Sale invoice approval decreases stock and customer balance; cancellation cleanly reverses both with auditable movement',
      () async {
        final itemId = await setupItem(code: 'SALE_01', stock: 100);
        final customerId = await setupParty(
          name: 'عميل آجل',
          type: PartyType.customer,
          initialBalance: 0,
        );

        final now = DateTime.now();
        final line = InvoiceItemModel.create(
          itemId: itemId,
          quantity: 20,
          unitPrice: const Money(2000), // 20.00 * 20 = 400.00 SAR
        );

        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-SALE-001',
          partyId: customerId,
          invoiceType: InvoiceType.sale,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.credit,
          items: [line],
          paidAmount: Money.zero, // 400.00 remaining
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
        );

        // --- APPROVE ---
        final invoiceId = await invoicesRepo.saveAndFinalizeInvoice(invoice);
        expect(invoiceId, isPositive);

        // Verify stock: 100 - 20 = 80
        var item = await inventoryRepo.getItemById(itemId);
        expect(item!.stockQuantity, equals(80));

        // Verify customer balance: 0 - 400.00 = -400.00 (-40000 subunits)
        var customer = await partiesRepo.getPartyById(customerId);
        expect(customer!.currentBalance.rawUnits, equals(-40000));

        // Verify movements
        var movements = await inventoryRepo.getItemMovements(itemId);
        expect(
          movements.any(
            (m) => m.movementType == MovementType.sale && m.quantity == 20,
          ),
          isTrue,
        );

        // --- CANCEL ---
        await invoicesRepo.cancelInvoice(invoiceId);

        // Verify invoice status
        final cancelledInv = await invoicesRepo.getInvoiceById(invoiceId);
        expect(cancelledInv!.status, equals(InvoiceStatus.cancelled));

        // Verify stock restored: 80 + 20 = 100
        item = await inventoryRepo.getItemById(itemId);
        expect(item!.stockQuantity, equals(100));

        // Verify customer balance restored: -460.00 + 460.00 = 0
        customer = await partiesRepo.getPartyById(customerId);
        expect(customer!.currentBalance.rawUnits, equals(0));

        // Verify reverse movement created
        movements = await inventoryRepo.getItemMovements(itemId);
        final cancelMovement = movements.firstWhere(
          (m) => m.movementType == MovementType.cancellation,
        );
        expect(cancelMovement.quantity, equals(20));
        expect(cancelMovement.increasesStock, isTrue);
        expect(cancelMovement.effectiveQuantityDelta, equals(20));
        expect(cancelMovement.referenceId, equals(invoiceId));
        expect(cancelMovement.referenceType, equals('invoice_cancellation'));
      },
    );

    test(
      '2. Purchase invoice approval increases stock and supplier balance; cancellation reverses both',
      () async {
        final itemId = await setupItem(code: 'PUR_01', stock: 50);
        final supplierId = await setupParty(
          name: 'مورد معتمد',
          type: PartyType.supplier,
          initialBalance: 0,
        );

        final now = DateTime.now();
        final line = InvoiceItemModel.create(
          itemId: itemId,
          quantity: 30,
          unitPrice: const Money(1000), // 300.00 SAR
        );

        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-PUR-001',
          partyId: supplierId,
          invoiceType: InvoiceType.purchase,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.credit,
          items: [line],
          paidAmount: Money.zero, // 300.00 remaining
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
        );

        final invoiceId = await invoicesRepo.saveAndFinalizeInvoice(invoice);

        // Stock increased: 50 + 30 = 80
        var item = await inventoryRepo.getItemById(itemId);
        expect(item!.stockQuantity, equals(80));

        // Supplier balance increased (+30000)
        var supplier = await partiesRepo.getPartyById(supplierId);
        expect(supplier!.currentBalance.rawUnits, equals(30000));

        // Cancel purchase
        await invoicesRepo.cancelInvoice(invoiceId);

        // Stock reduced back: 80 - 30 = 50
        item = await inventoryRepo.getItemById(itemId);
        expect(item!.stockQuantity, equals(50));

        // Supplier balance restored to 0
        supplier = await partiesRepo.getPartyById(supplierId);
        expect(supplier!.currentBalance.rawUnits, equals(0));

        // Reverse movement recorded with negative quantity
        final movements = await inventoryRepo.getItemMovements(itemId);
        final cancelMovement = movements.firstWhere(
          (m) => m.movementType == MovementType.cancellation,
        );
        expect(cancelMovement.quantity, equals(-30));
        expect(cancelMovement.increasesStock, isFalse);
        expect(cancelMovement.effectiveQuantityDelta, equals(-30));
      },
    );

    test(
      '3. Sale Return approval increases stock and customer balance; cancellation reverses both',
      () async {
        final itemId = await setupItem(code: 'SRET_01', stock: 40);
        final customerId = await setupParty(
          name: 'عميل مرتجع',
          type: PartyType.customer,
          initialBalance: -50000, // -500.00
        );

        final now = DateTime.now();
        final line = InvoiceItemModel.create(
          itemId: itemId,
          quantity: 5,
          unitPrice: const Money(2000), // 100.00 SAR
        );

        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-SRET-001',
          partyId: customerId,
          invoiceType: InvoiceType.saleReturn,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.credit,
          items: [line],
          paidAmount: Money.zero,
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
        );

        final invoiceId = await invoicesRepo.saveAndFinalizeInvoice(invoice);

        // Stock increased (returned to store): 40 + 5 = 45
        var item = await inventoryRepo.getItemById(itemId);
        expect(item!.stockQuantity, equals(45));

        // Customer owed less: -50000 + 10000 = -40000
        var customer = await partiesRepo.getPartyById(customerId);
        expect(customer!.currentBalance.rawUnits, equals(-40000));

        // Cancel return
        await invoicesRepo.cancelInvoice(invoiceId);

        // Stock reduced: 45 - 5 = 40
        item = await inventoryRepo.getItemById(itemId);
        expect(item!.stockQuantity, equals(40));

        // Customer balance restored: -40000 - 10000 = -50000
        customer = await partiesRepo.getPartyById(customerId);
        expect(customer!.currentBalance.rawUnits, equals(-50000));

        final movements = await inventoryRepo.getItemMovements(itemId);
        final cancelMovement = movements.firstWhere(
          (m) => m.movementType == MovementType.cancellation,
        );
        expect(cancelMovement.quantity, equals(-5));
        expect(cancelMovement.effectiveQuantityDelta, equals(-5));
      },
    );

    test(
      '4. Purchase Return approval decreases stock and supplier balance; cancellation reverses both',
      () async {
        final itemId = await setupItem(code: 'PRET_01', stock: 60);
        final supplierId = await setupParty(
          name: 'مورد مرتجع',
          type: PartyType.supplier,
          initialBalance: 100000, // 1,000.00
        );

        final now = DateTime.now();
        final line = InvoiceItemModel.create(
          itemId: itemId,
          quantity: 10,
          unitPrice: const Money(1000), // 100.00 SAR
        );

        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-PRET-001',
          partyId: supplierId,
          invoiceType: InvoiceType.purchaseReturn,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.credit,
          items: [line],
          paidAmount: Money.zero,
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
        );

        final invoiceId = await invoicesRepo.saveAndFinalizeInvoice(invoice);

        // Stock decreased (sent back to supplier): 60 - 10 = 50
        var item = await inventoryRepo.getItemById(itemId);
        expect(item!.stockQuantity, equals(50));

        // We owe supplier less: 100000 - 10000 = 90000
        var supplier = await partiesRepo.getPartyById(supplierId);
        expect(supplier!.currentBalance.rawUnits, equals(90000));

        // Cancel purchase return
        await invoicesRepo.cancelInvoice(invoiceId);

        // Stock restored: 50 + 10 = 60
        item = await inventoryRepo.getItemById(itemId);
        expect(item!.stockQuantity, equals(60));

        // Supplier balance restored: 90000 + 10000 = 100000
        supplier = await partiesRepo.getPartyById(supplierId);
        expect(supplier!.currentBalance.rawUnits, equals(100000));

        final movements = await inventoryRepo.getItemMovements(itemId);
        final cancelMovement = movements.firstWhere(
          (m) => m.movementType == MovementType.cancellation,
        );
        expect(cancelMovement.quantity, equals(10));
        expect(cancelMovement.effectiveQuantityDelta, equals(10));
      },
    );

    test(
      '5. Repeated cancellation attempts are strictly idempotent and do not double-reverse',
      () async {
        final itemId = await setupItem(code: 'IDEMP_CANCEL', stock: 100);
        final customerId = await setupParty(
          name: 'عميل تكرار الإلغاء',
          type: PartyType.customer,
        );

        final line = InvoiceItemModel.create(
          itemId: itemId,
          quantity: 25,
          unitPrice: const Money(1000),
        );

        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-REPEAT-001',
          partyId: customerId,
          invoiceType: InvoiceType.sale,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.credit,
          items: [line],
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final id = await invoicesRepo.saveAndFinalizeInvoice(invoice);

        // First cancellation
        await invoicesRepo.cancelInvoice(id);

        var item = await inventoryRepo.getItemById(itemId);
        expect(item!.stockQuantity, equals(100)); // Restored

        var movementsCount = (await inventoryRepo.getItemMovements(
          itemId,
        )).length;

        // Second cancellation attempt
        await invoicesRepo.cancelInvoice(id);

        // Third cancellation attempt
        await invoicesRepo.cancelInvoice(id);

        // Verify stock was NOT incremented again
        item = await inventoryRepo.getItemById(itemId);
        expect(item!.stockQuantity, equals(100));

        // Verify movements were NOT duplicated
        final movementsAfter = await inventoryRepo.getItemMovements(itemId);
        expect(movementsAfter.length, equals(movementsCount));
      },
    );

    test(
      '6. Intentional failure mid-transaction triggers 100% atomic rollback of all touched tables',
      () async {
        final itemId = await setupItem(code: 'ROLLBACK_ITEM', stock: 100);
        final customerId = await setupParty(
          name: 'عميل رولباك',
          type: PartyType.customer,
          initialBalance: 0,
        );

        // Line 1 is valid, Line 2 references a NON-EXISTENT item id (999999)
        final validLine = InvoiceItemModel.create(
          itemId: itemId,
          quantity: 15,
          unitPrice: const Money(1000),
        );
        final invalidLine = InvoiceItemModel.create(
          itemId: 999999, // Does not exist
          quantity: 10,
          unitPrice: const Money(1000),
        );

        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-FAIL-001',
          partyId: customerId,
          invoiceType: InvoiceType.sale,
          status: InvoiceStatus.approved,
          items: [validLine, invalidLine],
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Expect execution to fail and throw
        expect(
          () async => await invoicesRepo.saveAndFinalizeInvoice(invoice),
          throwsA(anything),
        );

        // Verify complete rollback:
        // 1. Invoice must NOT exist
        final fetchedInvoice = await invoicesRepo.getInvoiceByNumber(
          'INV-FAIL-001',
        );
        expect(fetchedInvoice, isNull);

        // 2. Item stock must be completely unchanged (still 100)
        final item = await inventoryRepo.getItemById(itemId);
        expect(item!.stockQuantity, equals(100));

        // 3. Customer balance must be completely unchanged (still 0)
        final customer = await partiesRepo.getPartyById(customerId);
        expect(customer!.currentBalance.rawUnits, equals(0));

        // 4. No sale movements should be created
        final movements = await inventoryRepo.getItemMovements(itemId);
        expect(movements.any((m) => m.referenceType == 'invoice'), isFalse);
      },
    );

    test(
      '7. Repeated saveAndFinalize retry is idempotent and does not duplicate invoices or movements',
      () async {
        final itemId = await setupItem(code: 'RETRY_ITEM', stock: 100);
        final customerId = await setupParty(
          name: 'عميل إعادة المحاولة',
          type: PartyType.customer,
          initialBalance: 0,
        );

        final line = InvoiceItemModel.create(
          itemId: itemId,
          quantity: 10,
          unitPrice: const Money(1000),
        );

        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-RETRY-001',
          partyId: customerId,
          invoiceType: InvoiceType.sale,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.credit,
          items: [line],
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // First call
        final id1 = await invoicesRepo.saveAndFinalizeInvoice(invoice);

        // Stock reduced to 90
        var item = await inventoryRepo.getItemById(itemId);
        expect(item!.stockQuantity, equals(90));

        // A retry must identify the persisted invoice, not just its number.
        final id2 = await invoicesRepo.saveAndFinalizeInvoice(
          invoice.copyWith(id: id1),
        );
        expect(id2, equals(id1));

        // Stock must still be 90, NOT 80
        item = await inventoryRepo.getItemById(itemId);
        expect(item!.stockQuantity, equals(90));

        // Invoices count must be 1
        final invoices = await invoicesRepo.getInvoices(
          searchQuery: 'INV-RETRY-001',
        );
        expect(invoices, hasLength(1));

        // Movements count must be initial(100) + 1 sale(10) = 2
        final movements = await inventoryRepo.getItemMovements(itemId);
        expect(movements, hasLength(2));
      },
    );

    test(
      '8. Reopening SQLite database verifies exact item stock reconciliation with full movement ledger',
      () async {
        final itemId = await setupItem(code: 'FULL_LIFECYCLE', stock: 50);
        final partyId = await setupParty(
          name: 'طرف دورة المخزون',
          type: PartyType.both,
        );

        // 1. Purchase of 30 units (Stock becomes 80)
        final pLine = InvoiceItemModel.create(
          itemId: itemId,
          quantity: 30,
          unitPrice: const Money(1000),
        );
        final pInv = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-LC-PUR',
          partyId: partyId,
          invoiceType: InvoiceType.purchase,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.credit,
          items: [pLine],
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await invoicesRepo.saveAndFinalizeInvoice(pInv);

        // 2. Sale of 15 units (Stock becomes 65)
        final sLine = InvoiceItemModel.create(
          itemId: itemId,
          quantity: 15,
          unitPrice: const Money(2000),
        );
        final sInv = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-LC-SALE',
          partyId: partyId,
          invoiceType: InvoiceType.sale,
          status: InvoiceStatus.approved,
          paymentType: PaymentType.credit,
          items: [sLine],
          invoiceDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final sInvId = await invoicesRepo.saveAndFinalizeInvoice(sInv);

        // 3. Cancel the sale (Stock returns to 80)
        await invoicesRepo.cancelInvoice(sInvId);

        // Close SQLite database completely
        await AppDatabase.instance.close();

        // Reopen connection
        AppDatabase.instance.configureForTesting(
          factory: databaseFactoryFfi,
          path: dbPath,
        );
        final freshInventoryRepo = SqliteInventoryRepository(
          AppDatabase.instance,
        );

        final reloadedItem = await freshInventoryRepo.getItemById(itemId);
        expect(reloadedItem!.stockQuantity, equals(80));

        final movements = await freshInventoryRepo.getItemMovements(itemId);
        // initial(50), purchase(30), sale(-15), cancel(+15)
        expect(movements, hasLength(4));

        final netMovementQuantity = movements.fold<int>(
          0,
          (sum, m) => sum + m.effectiveQuantityDelta,
        );
        expect(netMovementQuantity, equals(80));
        expect(reloadedItem.stockQuantity, equals(netMovementQuantity));
      },
    );
  });
}
