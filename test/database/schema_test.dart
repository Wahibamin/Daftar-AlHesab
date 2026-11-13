import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/models/movement_model.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Initialize FFI for headless desktop SQLite testing
  sqfliteFfiInit();

  late Database db;
  final now = DateTime.now();

  setUp(() async {
    AppDatabase.instance.configureForTesting(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    db = await AppDatabase.instance.database;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  group('RAF Database - Structural & Financial Schema Integrity', () {
    test('All tables exist and have ZERO float or real columns', () async {
      final tables = [
        AppTables.categories,
        AppTables.units,
        AppTables.items,
        AppTables.parties,
        AppTables.inventoryMovements,
        AppTables.invoices,
        AppTables.invoiceItems,
        AppTables.vouchers,
        AppTables.appSettings,
      ];

      for (final table in tables) {
        final columns = await db.rawQuery('PRAGMA table_info($table);');
        expect(columns, isNotEmpty, reason: 'Table $table must exist');

        for (final col in columns) {
          final type = (col['type'] as String).toUpperCase();
          expect(
            type.contains('REAL') ||
                type.contains('FLOAT') ||
                type.contains('DOUBLE'),
            isFalse,
            reason:
                'Forbidden floating-point type found in $table.${col['name']}: $type',
          );
        }
      }
    });

    test('Enforces Foreign Key constraint integrity', () async {
      // Inserting an item with non-existent unit_id MUST fail
      expect(() async {
        await db.insert(AppTables.items, {
          'code': 'INVALID_UNIT_ITEM',
          'name': 'Test Item',
          'unit_id': 99999, // Does not exist
          'cost_price_int': 1000,
          'selling_price_int': 1500,
          'stock_quantity_int': 10,
          'min_alert_limit_int': 2,
          'is_active': 1,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        });
      }, throwsA(isA<DatabaseException>()));
    });

    test(
      'Enforces UNIQUE constraints on barcode, invoices, and vouchers',
      () async {
        // Setup a valid unit
        final unitId = await db.insert(AppTables.units, {
          'name': 'قطعة',
          'symbol': 'حبة',
          'conversion_factor_int': 1,
          'created_at': now.millisecondsSinceEpoch,
        });

        // Insert first item
        await db.insert(AppTables.items, {
          'code': 'UNIQUE_BARCODE_001',
          'name': 'عصير برتقال',
          'unit_id': unitId,
          'cost_price_int': 350,
          'selling_price_int': 500,
          'stock_quantity_int': 100,
          'min_alert_limit_int': 10,
          'is_active': 1,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        });

        // Attempt duplicate code insertion MUST fail
        expect(() async {
          await db.insert(AppTables.items, {
            'code': 'UNIQUE_BARCODE_001',
            'name': 'عصير برتقال مكرر',
            'unit_id': unitId,
            'cost_price_int': 350,
            'selling_price_int': 500,
            'stock_quantity_int': 50,
            'min_alert_limit_int': 10,
            'is_active': 1,
            'created_at': now.millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          });
        }, throwsA(isA<DatabaseException>()));
      },
    );
  });

  group('RAF Financial Models Persistence & Integer Arithmetic', () {
    test('Persists and retrieves Items with exact Money values', () async {
      final unitId = await db.insert(AppTables.units, {
        'name': 'كرتون',
        'symbol': 'ctn',
        'conversion_factor_int': 12,
        'created_at': now.millisecondsSinceEpoch,
      });

      final categoryId = await db.insert(AppTables.categories, {
        'name': 'مشروبات غازية',
        'description': 'عصائر ومشروبات',
        'created_at': now.millisecondsSinceEpoch,
      });

      final item = ItemModel(
        code: '6281001234567',
        name: 'مياه معدنية 330 مل',
        unitId: unitId,
        categoryId: categoryId,
        costPrice: const Money(125050), // 1,250.50 SAR
        sellingPrice: const Money(150000), // 1,500.00 SAR
        stockQuantity: 45,
        minAlertLimit: 10,
        expiryDate: now.add(const Duration(days: 365)),
        createdAt: now,
        updatedAt: now,
      );

      final insertedId = await db.insert(AppTables.items, item.toMap());
      expect(insertedId, isPositive);

      final rows = await db.query(
        AppTables.items,
        where: 'id = ?',
        whereArgs: [insertedId],
      );
      expect(rows, hasLength(1));

      final retrievedItem = ItemModel.fromMap(rows.first);
      expect(retrievedItem.code, equals('6281001234567'));
      expect(retrievedItem.costPrice.rawUnits, equals(125050));
      expect(
        retrievedItem.costPrice.format(includeSymbol: false),
        equals('1,250.50'),
      );
      expect(retrievedItem.sellingPrice.rawUnits, equals(150000));
      expect(
        retrievedItem.sellingPrice.format(includeSymbol: false),
        equals('1,500.00'),
      );
      expect(retrievedItem.stockQuantity, equals(45));

      // Financial intelligence verification
      // 1250.50 * 45 = 56,272.50 SAR = 5627250 subunits
      expect(retrievedItem.totalCostValuation.rawUnits, equals(5627250));
      expect(
        retrievedItem.totalCostValuation.format(includeSymbol: false),
        equals('56,272.50'),
      );

      // Gross profit margin per unit: 1500.00 - 1250.50 = 249.50 SAR
      expect(retrievedItem.grossMarginPerUnit.rawUnits, equals(24950));
      expect(retrievedItem.isLowStock, isFalse);
      expect(retrievedItem.isOutOfStock, isFalse);
    });

    test(
      'Persists Parties with positive (creditor) and negative (debtor) balances',
      () async {
        // 1. Debtor customer (مدين / عليه مستحقات)
        final customer = PartyModel(
          name: 'مؤسسة الأفق للتجارة',
          phone: '0501234567',
          type: PartyType.customer,
          currentBalance: const Money(-450000), // -4,500.00 SAR
          creditLimit: const Money(1000000), // 10,000.00 SAR
          createdAt: now,
          updatedAt: now,
        );

        final customerId = await db.insert(AppTables.parties, customer.toMap());
        final customerRow = (await db.query(
          AppTables.parties,
          where: 'id = ?',
          whereArgs: [customerId],
        )).first;

        final fetchedCustomer = PartyModel.fromMap(customerRow);
        expect(fetchedCustomer.isDebtor, isTrue);
        expect(fetchedCustomer.isCreditor, isFalse);
        expect(fetchedCustomer.currentBalance.rawUnits, equals(-450000));
        expect(fetchedCustomer.balanceStatusArabic, equals('مدين (عليه)'));
        expect(fetchedCustomer.exceedsCreditLimit, isFalse);
        // Remaining credit: 10,000.00 - 4,500.00 = 5,500.00
        expect(
          fetchedCustomer.remainingCreditAvailable.rawUnits,
          equals(550000),
        );

        // 2. Creditor supplier (دائن / له مستحقات)
        final supplier = PartyModel(
          name: 'شركة التوزيع الكبرى',
          phone: '0559876543',
          type: PartyType.supplier,
          currentBalance: const Money(1200000), // 12,000.00 SAR
          createdAt: now,
          updatedAt: now,
        );

        final supplierId = await db.insert(AppTables.parties, supplier.toMap());
        final supplierRow = (await db.query(
          AppTables.parties,
          where: 'id = ?',
          whereArgs: [supplierId],
        )).first;

        final fetchedSupplier = PartyModel.fromMap(supplierRow);
        expect(fetchedSupplier.isCreditor, isTrue);
        expect(fetchedSupplier.isDebtor, isFalse);
        expect(fetchedSupplier.currentBalance.rawUnits, equals(1200000));
        expect(fetchedSupplier.balanceStatusArabic, equals('دائن (له)'));
      },
    );

    test(
      'Persists and aggregates Invoices and Invoice Items accurately',
      () async {
        // Prepare Unit and Items
        final unitId = await db.insert(AppTables.units, {
          'name': 'قطعة',
          'symbol': 'حبة',
          'conversion_factor_int': 1,
          'created_at': now.millisecondsSinceEpoch,
        });

        final itemAId = await db.insert(AppTables.items, {
          'code': 'ITEM_A',
          'name': 'منتج أ',
          'unit_id': unitId,
          'cost_price_int': 8000,
          'selling_price_int': 10000, // 100.00 SAR
          'stock_quantity_int': 50,
          'min_alert_limit_int': 5,
          'is_active': 1,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        });

        final itemBId = await db.insert(AppTables.items, {
          'code': 'ITEM_B',
          'name': 'منتج ب',
          'unit_id': unitId,
          'cost_price_int': 4000,
          'selling_price_int': 5000, // 50.00 SAR
          'stock_quantity_int': 50,
          'min_alert_limit_int': 5,
          'is_active': 1,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        });

        // Item 1: 2 x 100.00 SAR = 200.00 SAR
        final line1 = InvoiceItemModel.create(
          itemId: itemAId,
          quantity: 2,
          unitPrice: const Money(10000),
        );

        // Item 2: 3 x 50.00 SAR = 150.00 SAR - 10.00 discount = 140.00 SAR
        final line2 = InvoiceItemModel.create(
          itemId: itemBId,
          quantity: 3,
          unitPrice: const Money(5000),
          discount: const Money(1000),
        );

        // Total invoice:
        // Subtotal = 200.00 + 150.00 = 350.00 SAR (35000 raw)
        // Discount = 10.00 SAR (1000 raw)
        // Tax = 0.00 SAR (0 raw)
        // Net Total = 350.00 - 10.00 = 340.00 SAR (34000 raw)
        // Paid Amount = 200.00 SAR (20000 raw)
        // Remaining = 140.00 SAR (14000 raw)
        final invoice = InvoiceModel.buildWithItems(
          invoiceNumber: 'INV-2026-0001',
          invoiceType: InvoiceType.sale,
          paymentType: PaymentType.partial,
          items: [line1, line2],
          paidAmount: const Money(20000),
          invoiceDate: now,
          createdAt: now,
          updatedAt: now,
        );

        expect(invoice.subtotal.rawUnits, equals(35000));
        expect(invoice.discount.rawUnits, equals(1000));
        expect(invoice.tax.rawUnits, equals(0));
        expect(invoice.total.rawUnits, equals(34000));
        expect(invoice.remainingAmount.rawUnits, equals(14000));
        expect(invoice.isPartiallyPaid, isTrue);

        // Insert into SQLite
        final invoiceId = await db.insert(AppTables.invoices, invoice.toMap());
        for (final line in invoice.items!) {
          await db.insert(
            AppTables.invoiceItems,
            line.copyWith(invoiceId: invoiceId).toMap(),
          );
        }

        // Read back and verify persistence
        final invoiceRow = (await db.query(
          AppTables.invoices,
          where: 'id = ?',
          whereArgs: [invoiceId],
        )).first;

        final itemRows = await db.query(
          AppTables.invoiceItems,
          where: 'invoice_id = ?',
          whereArgs: [invoiceId],
        );

        final retrievedInvoice = InvoiceModel.fromMap(
          invoiceRow,
          items: itemRows.map(InvoiceItemModel.fromMap).toList(),
        );

        expect(retrievedInvoice.invoiceNumber, equals('INV-2026-0001'));
        expect(retrievedInvoice.total.rawUnits, equals(34000));
        expect(retrievedInvoice.total.format(), equals('340.00'));
        expect(retrievedInvoice.items, hasLength(2));
        expect(retrievedInvoice.items![0].totalPrice.rawUnits, equals(20000));
        expect(retrievedInvoice.items![1].totalPrice.rawUnits, equals(14000));
      },
    );

    test('Persists Inventory Movements with signed stock changes', () async {
      final unitId = await db.insert(AppTables.units, {
        'name': 'قطعة',
        'symbol': 'حبة',
        'conversion_factor_int': 1,
        'created_at': now.millisecondsSinceEpoch,
      });

      final itemId = await db.insert(AppTables.items, {
        'code': 'STK_ITEM',
        'name': 'صنف مخزني',
        'unit_id': unitId,
        'cost_price_int': 2000,
        'selling_price_int': 3000,
        'stock_quantity_int': 0,
        'min_alert_limit_int': 5,
        'is_active': 1,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      });

      final purchaseMovement = InventoryMovementModel(
        itemId: itemId,
        movementType: MovementType.purchase,
        quantity: 100,
        unitCost: const Money(2000),
        movementDate: now,
        createdAt: now,
      );

      final saleMovement = InventoryMovementModel(
        itemId: itemId,
        movementType: MovementType.sale,
        quantity: 25,
        unitCost: const Money(2000),
        movementDate: now,
        createdAt: now,
      );

      await db.insert(AppTables.inventoryMovements, purchaseMovement.toMap());
      await db.insert(AppTables.inventoryMovements, saleMovement.toMap());

      final movementRows = await db.query(
        AppTables.inventoryMovements,
        where: 'item_id = ?',
        whereArgs: [itemId],
      );

      final movements = movementRows
          .map(InventoryMovementModel.fromMap)
          .toList();
      expect(movements, hasLength(2));
      expect(movements[0].increasesStock, isTrue);
      expect(movements[0].effectiveQuantityDelta, equals(100));

      expect(movements[1].increasesStock, isFalse);
      expect(movements[1].effectiveQuantityDelta, equals(-25));

      // Net inventory change: +100 - 25 = 75 units
      final netChange = movements.fold<int>(
        0,
        (sum, m) => sum + m.effectiveQuantityDelta,
      );
      expect(netChange, equals(75));
    });

    test('Persists and retrieves Vouchers (Receipt & Payment)', () async {
      final receipt = VoucherModel(
        voucherNumber: 'RCT-2026-0001',
        voucherType: VoucherType.receipt,
        amount: const Money(500000), // 5,000.00 SAR
        paymentMethod: PaymentMethod.bank,
        referenceNumber: 'TXN-998877',
        statement: 'دفعة نقدية تحت الحساب',
        voucherDate: now,
        createdAt: now,
      );

      final payment = VoucherModel(
        voucherNumber: 'PAY-2026-0001',
        voucherType: VoucherType.payment,
        amount: const Money(250000), // 2,500.00 SAR
        paymentMethod: PaymentMethod.cash,
        statement: 'سداد مصروفات نثرية',
        voucherDate: now,
        createdAt: now,
      );

      final rId = await db.insert(AppTables.vouchers, receipt.toMap());
      final pId = await db.insert(AppTables.vouchers, payment.toMap());

      final rRow = (await db.query(
        AppTables.vouchers,
        where: 'id = ?',
        whereArgs: [rId],
      )).first;
      final pRow = (await db.query(
        AppTables.vouchers,
        where: 'id = ?',
        whereArgs: [pId],
      )).first;

      final fetchedReceipt = VoucherModel.fromMap(rRow);
      final fetchedPayment = VoucherModel.fromMap(pRow);

      expect(fetchedReceipt.isReceipt, isTrue);
      expect(fetchedReceipt.amount.rawUnits, equals(500000));
      expect(fetchedReceipt.amount.format(), equals('5,000.00'));
      expect(fetchedReceipt.paymentMethod, equals(PaymentMethod.bank));

      expect(fetchedPayment.isPayment, isTrue);
      expect(fetchedPayment.amount.rawUnits, equals(250000));
      expect(fetchedPayment.paymentMethod, equals(PaymentMethod.cash));
    });
  });
}
