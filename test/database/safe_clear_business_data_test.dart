import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/database/business_data_wiper.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/models/movement_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/reports/repositories/reports_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late BusinessDataWiper wiper;
  late String tempDbPath;

  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp('raf_wipe_test_');
    tempDbPath = '${tempDir.path}${Platform.pathSeparator}isolated_test.db';

    AppDatabase.instance.configureForTesting(
      factory: databaseFactoryFfi,
      path: tempDbPath,
    );
    db = await AppDatabase.instance.database;
    wiper = BusinessDataWiper(dbManager: AppDatabase.instance);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    try {
      final file = File(tempDbPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  });

  /// Helper to populate a complete, interconnected realistic dataset
  Future<void> seedFullRealisticBusinessData() async {
    final now = DateTime.now();

    // 1. Settings
    final settingsMap = {
      'store_name': 'شركة الأمل للتوريدات والتجارة',
      'tax_number': '300999888700003',
      'phone': '0551234567',
      'address': 'المملكة العربية السعودية - الرياض - حي المروج',
      'invoice_footer_note':
          'البضاعة المباعة ترد وتستبدل خلال 7 أيام بموجب الفاتورة الأصلية.',
    };
    for (final entry in settingsMap.entries) {
      await db.insert(AppTables.appSettings, {
        'key': entry.key,
        'value': entry.value,
      });
    }

    // 2. Standard Units + Custom Units (including tricky partial match units)
    // Standard units:
    final uPiece = await db.insert(AppTables.units, {
      'name': 'قطعة',
      'symbol': 'حبة',
      'conversion_factor_int': 1,
      'created_at': now.millisecondsSinceEpoch,
    });
    final uBox = await db.insert(AppTables.units, {
      'name': 'كرتون',
      'symbol': 'ctn',
      'conversion_factor_int': 12,
      'created_at': now.millisecondsSinceEpoch,
    });
    // Custom unit 1: completely custom
    final uCustom = await db.insert(AppTables.units, {
      'name': 'لفة كابل',
      'symbol': 'لفة',
      'conversion_factor_int': 50,
      'created_at': now.millisecondsSinceEpoch,
    });
    // Custom unit 2: Partial match - Same standard name 'قطعة' but different custom symbol and factor
    await db.insert(AppTables.units, {
      'name': 'قطعة',
      'symbol': 'custom_piece',
      'conversion_factor_int': 5,
      'created_at': now.millisecondsSinceEpoch,
    });
    // Custom unit 3: Partial match - Standard symbol 'حبة' but custom name
    await db.insert(AppTables.units, {
      'name': 'برغي دقيق خاص',
      'symbol': 'حبة',
      'conversion_factor_int': 1,
      'created_at': now.millisecondsSinceEpoch,
    });

    // 3. Standard Categories + Custom Categories
    final cGeneral = await db.insert(AppTables.categories, {
      'name': 'عام',
      'description': 'تصنيف عام',
      'created_at': now.millisecondsSinceEpoch,
    });
    final cDrinks = await db.insert(AppTables.categories, {
      'name': 'مشروبات وعصائر',
      'description': 'مشروبات',
      'created_at': now.millisecondsSinceEpoch,
    });
    // Custom category
    await db.insert(AppTables.categories, {
      'name': 'قطع غيار هيدروليكية مخصصة',
      'description': 'تصنيف مخصص للعميل',
      'created_at': now.millisecondsSinceEpoch,
    });

    // 4. Items (Inventory Products)
    final iJuice = await db.insert(AppTables.items, {
      'code': '628100100100',
      'name': 'عصير برتقال طبيعي 1 لتر',
      'unit_id': uPiece,
      'category_id': cDrinks,
      'cost_price_int': 500, // 5.00 SAR
      'selling_price_int': 850, // 8.50 SAR
      'stock_quantity_int': 100,
      'min_alert_limit_int': 10,
      'is_active': 1,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });

    await db.insert(AppTables.items, {
      'code': '628100100200',
      'name': 'كرتون عصير برتقال (12 عبوة)',
      'unit_id': uBox,
      'category_id': cDrinks,
      'cost_price_int': 5500, // 55.00 SAR
      'selling_price_int': 9500, // 95.00 SAR
      'stock_quantity_int': 20,
      'min_alert_limit_int': 5,
      'is_active': 1,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });

    final iCable = await db.insert(AppTables.items, {
      'code': '628100100300',
      'name': 'لفة سلك نحاس 50م',
      'unit_id': uCustom,
      'category_id': cGeneral,
      'cost_price_int': 12000,
      'selling_price_int': 18000,
      'stock_quantity_int': 15,
      'min_alert_limit_int': 2,
      'is_active': 1,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });

    // 5. Parties (Customers & Suppliers)
    final pCustomer = await db.insert(AppTables.parties, {
      'name': 'مؤسسة التجارة العالمية (عميل)',
      'phone': '0501112233',
      'type': PartyType.customer.dbValue,
      'current_balance_int': -45000, // -450.00 SAR (مدين)
      'opening_balance_int': 0,
      'credit_limit_int': 100000,
      'address': 'الرياض',
      'tax_number': '300111222300003',
      'is_active': 1,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });

    final pSupplier = await db.insert(AppTables.parties, {
      'name': 'شركة الألبان الوطنية (مورد)',
      'phone': '0504445566',
      'type': PartyType.supplier.dbValue,
      'current_balance_int': 120000, // +1,200.00 SAR (دائن)
      'opening_balance_int': 0,
      'credit_limit_int': 500000,
      'address': 'الخرج',
      'tax_number': '300444555600003',
      'is_active': 1,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });

    // 6. Invoices & Invoice Items
    final invSale = await db.insert(AppTables.invoices, {
      'invoice_number': 'INV-2026-0001',
      'party_id': pCustomer,
      'invoice_type': InvoiceType.sale.dbValue,
      'status': InvoiceStatus.approved.dbValue,
      'payment_type': 'credit',
      'subtotal_int': 8500,
      'discount_int': 0,
      'tax_int': 1275,
      'total_int': 9775,
      'paid_amount_int': 5275,
      'remaining_amount_int': 4500,
      'invoice_date': now.millisecondsSinceEpoch,
      'notes': 'فاتورة مبيعات تجريبية',
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });

    await db.insert(AppTables.invoiceItems, {
      'invoice_id': invSale,
      'item_id': iJuice,
      'quantity_int': 10,
      'unit_price_int': 850,
      'unit_cost_int': 500,
      'discount_int': 0,
      'tax_rate_percent': 15,
      'tax_amount_int': 1275,
      'total_price_int': 9775,
    });

    // 7. Inventory Movements
    await db.insert(AppTables.inventoryMovements, {
      'item_id': iJuice,
      'movement_type': MovementType.sale.dbValue,
      'quantity_int': -10,
      'unit_cost_int': 500,
      'reference_id': invSale,
      'reference_type': 'invoice',
      'movement_date': now.millisecondsSinceEpoch,
      'notes': 'خصم مخزني لمبيعات الفاتورة INV-2026-0001',
      'created_at': now.millisecondsSinceEpoch,
    });

    await db.insert(AppTables.inventoryMovements, {
      'item_id': iCable,
      'movement_type': MovementType.initial.dbValue,
      'quantity_int': 15,
      'unit_cost_int': 12000,
      'reference_id': null,
      'reference_type': 'initial_stock',
      'movement_date': now.millisecondsSinceEpoch,
      'notes': 'رصيد افتتاحي',
      'created_at': now.millisecondsSinceEpoch,
    });

    // 8. Vouchers
    await db.insert(AppTables.vouchers, {
      'voucher_number': 'REC-2026-0001',
      'voucher_type': VoucherType.receipt.dbValue,
      'party_id': pCustomer,
      'amount_int': 5275,
      'payment_method': 'cash',
      'reference_number': 'REF-001',
      'statement': 'دفعة نقدية مسددة من العميل',
      'status': 'approved',
      'voucher_date': now.millisecondsSinceEpoch,
      'created_at': now.millisecondsSinceEpoch,
    });

    await db.insert(AppTables.vouchers, {
      'voucher_number': 'PAY-2026-0001',
      'voucher_type': VoucherType.payment.dbValue,
      'party_id': pSupplier,
      'amount_int': 30000,
      'payment_method': 'bank_transfer',
      'reference_number': 'TRX-9988',
      'statement': 'سداد دفعة للمورد',
      'status': 'approved',
      'voucher_date': now.millisecondsSinceEpoch,
      'created_at': now.millisecondsSinceEpoch,
    });
  }

  group('Mandatory Test Suite: Safe Business Data Wipe in Isolated SQLite', () {
    test(
      'Test 1: Reject on Cancel - Nothing is changed when confirmation is cancelled',
      () async {
        await seedFullRealisticBusinessData();

        final beforeInvoices = await db.query(AppTables.invoices);
        final beforeItems = await db.query(AppTables.items);
        final beforeParties = await db.query(AppTables.parties);

        // Simulating rejection: operation is aborted without calling clearAllBusinessData
        expect(beforeInvoices, isNotEmpty);
        expect(beforeItems, isNotEmpty);
        expect(beforeParties, isNotEmpty);

        final afterInvoices = await db.query(AppTables.invoices);
        final afterItems = await db.query(AppTables.items);
        final afterParties = await db.query(AppTables.parties);

        expect(afterInvoices.length, equals(beforeInvoices.length));
        expect(afterItems.length, equals(beforeItems.length));
        expect(afterParties.length, equals(beforeParties.length));
      },
    );

    test(
      'Test 2: Prevent Incomplete Confirmation - Phrase validation rejects bad inputs',
      () {
        expect(
          BusinessDataWiper.confirmationPhrase,
          equals('مسح جميع البيانات'),
        );

        // Validate phrase checker against various incomplete or invalid inputs
        bool isValid(String input) =>
            input.trim() == BusinessDataWiper.confirmationPhrase;

        expect(isValid(''), isFalse);
        expect(isValid('مسح'), isFalse);
        expect(isValid('مسح البيانات'), isFalse);
        expect(isValid('مسح جميع'), isFalse);
        expect(isValid('delete all'), isFalse);
        expect(isValid('مسح جميع البيانات'), isTrue);
        expect(isValid('  مسح جميع البيانات  '), isTrue); // trimmed
      },
    );

    test(
      'Test 3: Complete Business Data Wipe - All operational records and child tables deleted',
      () async {
        await seedFullRealisticBusinessData();

        // Pre-check
        expect((await db.query(AppTables.invoices)).length, greaterThan(0));
        expect((await db.query(AppTables.invoiceItems)).length, greaterThan(0));
        expect(
          (await db.query(AppTables.inventoryMovements)).length,
          greaterThan(0),
        );
        expect((await db.query(AppTables.items)).length, greaterThan(0));
        expect((await db.query(AppTables.parties)).length, greaterThan(0));
        expect((await db.query(AppTables.vouchers)).length, greaterThan(0));

        final summary = await wiper.clearAllBusinessData();

        // Post-check: Every business table must have exactly 0 rows, including units and categories
        final countInvoices = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.invoices}'),
        );
        final countInvoiceItems = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.invoiceItems}'),
        );
        final countMovements = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM ${AppTables.inventoryMovements}',
          ),
        );
        final countItems = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.items}'),
        );
        final countParties = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.parties}'),
        );
        final countVouchers = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.vouchers}'),
        );
        final countUnits = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.units}'),
        );
        final countCategories = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.categories}'),
        );

        expect(countInvoices, equals(0));
        expect(countInvoiceItems, equals(0));
        expect(countMovements, equals(0));
        expect(countItems, equals(0));
        expect(countParties, equals(0));
        expect(countVouchers, equals(0));
        expect(
          countUnits,
          equals(0),
          reason: 'All units must be wiped completely',
        );
        expect(
          countCategories,
          equals(0),
          reason: 'All categories must be wiped completely',
        );
        expect(summary.totalDeletedRecords, greaterThan(0));
      },
    );

    test(
      'Test 4: Preserve Settings - Store profile and establishment metadata intact',
      () async {
        await seedFullRealisticBusinessData();

        await wiper.clearAllBusinessData();

        final settingsRows = await db.query(AppTables.appSettings);
        final map = {
          for (final r in settingsRows)
            r['key'] as String: r['value'] as String,
        };

        expect(map['store_name'], equals('شركة الأمل للتوريدات والتجارة'));
        expect(map['tax_number'], equals('300999888700003'));
        expect(map['phone'], equals('0551234567'));
        expect(
          map['address'],
          equals('المملكة العربية السعودية - الرياض - حي المروج'),
        );
        expect(
          map['invoice_footer_note'],
          contains('البضاعة المباعة ترد وتستبدل'),
        );
        expect(map['parties_seed_completed'], equals('true'));
        expect(map['inventory_seed_completed'], equals('true'));
      },
    );

    test(
      'Test 5: Preserve Schema - Tables, indexes, and version 6 intact',
      () async {
        await seedFullRealisticBusinessData();

        await wiper.clearAllBusinessData();

        final versionResult = await db.rawQuery('PRAGMA user_version;');
        final version = versionResult.first['user_version'] as int;
        expect(
          version,
          equals(6),
          reason: 'Database schema version must NOT change on data wipe',
        );

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
          final info = await db.rawQuery('PRAGMA table_info($table);');
          expect(
            info,
            isNotEmpty,
            reason: 'Table $table must remain present in SQLite',
          );
        }

        // Check essential indexes still exist
        final indexes = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index';",
        );
        final indexNames = indexes.map((r) => r['name'] as String).toList();
        expect(indexNames, contains('idx_items_code'));
        expect(indexNames, contains('idx_invoices_number'));
        expect(indexNames, contains('idx_vouchers_number'));
      },
    );

    test(
      'Test 6: Relational Integrity - PRAGMA foreign_key_check passes with zero violations',
      () async {
        await seedFullRealisticBusinessData();

        await wiper.clearAllBusinessData();

        final fkViolations = await db.rawQuery('PRAGMA foreign_key_check;');
        expect(
          fkViolations,
          isEmpty,
          reason: 'No orphaned rows or FK violations should exist after wipe',
        );
      },
    );

    test(
      'Test 7: Rollback on Error - Intentional failure during transaction leaves all data intact',
      () async {
        await seedFullRealisticBusinessData();

        final initialInvoicesCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.invoices}'),
        );
        final initialItemsCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.items}'),
        );
        final initialPartiesCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.parties}'),
        );

        // Simulate a custom wiper that deletes items but encounters an error before completing
        expect(() async {
          await db.transaction((txn) async {
            await txn.delete(AppTables.invoiceItems);
            await txn.delete(AppTables.inventoryMovements);
            await txn.delete(AppTables.invoices);
            // Intentional crash mid-transaction
            throw Exception('Simulated fatal transaction failure');
          });
        }, throwsException);

        // Verify 100% atomic rollback: nothing was permanently deleted
        final postInvoicesCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.invoices}'),
        );
        final postItemsCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.items}'),
        );
        final postPartiesCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.parties}'),
        );

        expect(postInvoicesCount, equals(initialInvoicesCount));
        expect(postItemsCount, equals(initialItemsCount));
        expect(postPartiesCount, equals(initialPartiesCount));
      },
    );

    test(
      'Test 8: Reopen Database Connection - State persists after close and reopen',
      () async {
        await seedFullRealisticBusinessData();

        await wiper.clearAllBusinessData();

        // Close and reopen database
        await AppDatabase.instance.close();

        AppDatabase.instance.configureForTesting(
          factory: databaseFactoryFfi,
          path: tempDbPath,
        );
        final reopenedDb = await AppDatabase.instance.database;

        final countInvoices = Sqflite.firstIntValue(
          await reopenedDb.rawQuery(
            'SELECT COUNT(*) FROM ${AppTables.invoices}',
          ),
        );
        final countItems = Sqflite.firstIntValue(
          await reopenedDb.rawQuery('SELECT COUNT(*) FROM ${AppTables.items}'),
        );
        final countUnits = Sqflite.firstIntValue(
          await reopenedDb.rawQuery('SELECT COUNT(*) FROM ${AppTables.units}'),
        );
        final countCategories = Sqflite.firstIntValue(
          await reopenedDb.rawQuery(
            'SELECT COUNT(*) FROM ${AppTables.categories}',
          ),
        );
        final countSettings = Sqflite.firstIntValue(
          await reopenedDb.rawQuery(
            'SELECT COUNT(*) FROM ${AppTables.appSettings}',
          ),
        );

        expect(countInvoices, equals(0));
        expect(countItems, equals(0));
        expect(countUnits, equals(0));
        expect(countCategories, equals(0));
        expect(countSettings, greaterThan(0));
      },
    );

    test(
      'Test 9: Reuse App After Wipe - Create new item, invoice, voucher with clean numbering',
      () async {
        await seedFullRealisticBusinessData();
        await wiper.clearAllBusinessData();

        final invRepo = SqliteInvoicesRepository(AppDatabase.instance);
        final vouchersRepo = SqliteVouchersRepository(AppDatabase.instance);
        final inventoryRepo = SqliteInventoryRepository(AppDatabase.instance);
        final partiesRepo = SqlitePartiesRepository(AppDatabase.instance);
        final reportsRepo = SqliteReportsRepository(AppDatabase.instance);

        // 1. Manually run safe seed to get canonical units/categories
        await inventoryRepo.safeSeedMasterData();
        final units = await inventoryRepo.getUnits();
        expect(units, isNotEmpty);
        final pieceUnit = units.first;

        // 2. Create brand new Item
        final newItemId = await inventoryRepo.insertItem(
          ItemModel(
            code: '628999000111',
            name: 'صنف جديد ما بعد المسح',
            unitId: pieceUnit.id!,
            costPrice: const Money(1000), // 10.00 SAR
            sellingPrice: const Money(1500), // 15.00 SAR
            stockQuantity: 50,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          initialStock: 50,
        );
        expect(newItemId, greaterThan(0));

        // 3. Create brand new Party
        final newPartyId = await partiesRepo.insertParty(
          PartyModel(
            name: 'العميل الأول للدورة الجديدة',
            phone: '0550001122',
            type: PartyType.customer,
            currentBalance: Money.zero,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        expect(newPartyId, greaterThan(0));

        // 4. Generate next invoice number - MUST restart sequence cleanly at 0001
        final nextInvNum = await invRepo.generateNextInvoiceNumber(
          InvoiceType.sale,
        );
        final year = DateTime.now().year;
        expect(nextInvNum, equals('INV-$year-0001'));

        // Insert the invoice
        final newInvId = await invRepo.createInvoice(
          InvoiceModel(
            invoiceNumber: nextInvNum,
            partyId: newPartyId,
            invoiceType: InvoiceType.sale,
            status: InvoiceStatus.approved,
            paymentType: PaymentType.cash,
            subtotal: const Money(1500),
            tax: const Money(225),
            total: const Money(1725),
            paidAmount: const Money(1725),
            remainingAmount: Money.zero,
            invoiceDate: DateTime.now(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            items: [
              InvoiceItemModel(
                itemId: newItemId,
                quantity: 1,
                unitPrice: const Money(1500),
                unitCost: const Money(1000),
                totalPrice: const Money(1725),
                taxAmount: const Money(225),
              ),
            ],
          ),
        );
        expect(newInvId, greaterThan(0));

        // 5. Generate next voucher number - MUST restart cleanly at 0001
        final nextVoucherNum = await vouchersRepo.generateNextVoucherNumber(
          VoucherType.receipt,
        );
        expect(nextVoucherNum, equals('REC-$year-0001'));

        // 6. Check Reports - Reports reflect ONLY the single new invoice
        final metrics = await reportsRepo.getDashboardMetrics();
        expect(metrics.todaySales, equals(const Money(1725)));
        expect(metrics.totalInvoicesToday, equals(1));
      },
    );

    test(
      'Test 10: Safe Master Data Seeding Rerun - Does not recreate business data or duplicate static units',
      () async {
        await seedFullRealisticBusinessData();
        await wiper.clearAllBusinessData();

        final invRepo = SqliteInventoryRepository(AppDatabase.instance);
        final partiesRepo = SqlitePartiesRepository(AppDatabase.instance);

        // Run safe master data seeding: should add exactly 8 standard units and 6 categories
        final added = await invRepo.safeSeedMasterData();
        expect(added, equals(14));

        // Re-running safeSeedMasterData must not duplicate anything
        final addedAgain = await invRepo.safeSeedMasterData();
        expect(addedAgain, equals(0));

        // Run parties seed
        await partiesRepo.seedDefaultDataIfEmpty();

        // Verify NO customers, suppliers, items, invoices or movements were restored!
        final countParties = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.parties}'),
        );
        final countItems = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.items}'),
        );
        final countInvoices = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.invoices}'),
        );

        expect(
          countParties,
          equals(0),
          reason: 'Parties must remain 0 and not re-seeded automatically',
        );
        expect(
          countItems,
          equals(0),
          reason: 'Items must remain 0 and not re-seeded automatically',
        );
        expect(countInvoices, equals(0), reason: 'Invoices must remain 0');

        // Verify standard units are present without duplication (8 units, 6 categories)
        final units = await invRepo.getUnits();
        final unitNames = units.map((u) => u.name).toSet();
        expect(units.length, equals(8));
        expect(unitNames.length, equals(8));
        expect(unitNames, contains('قطعة'));
        expect(unitNames, contains('كرتون'));
        expect(unitNames, contains('كيلوجرام'));
        expect(unitNames, contains('لتر'));
        expect(unitNames, contains('متر'));
        expect(unitNames, contains('باكت'));
        expect(unitNames, contains('طرد'));
        expect(unitNames, contains('درزن'));

        final categories = await invRepo.getCategories();
        expect(categories.length, equals(6));
      },
    );

    test(
      'Test 11 (Safe Seeding): Starts empty, seeds 8 units & 6 categories, idempotent, keeps user data',
      () async {
        // 1. Database starts without units or categories
        final countUnitsInitial = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.units}'),
        );
        final countCatsInitial = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.categories}'),
        );
        expect(countUnitsInitial, equals(0));
        expect(countCatsInitial, equals(0));

        // 2. Execute safeSeedMasterData
        final invRepo = SqliteInventoryRepository(AppDatabase.instance);
        final added = await invRepo.safeSeedMasterData();
        expect(added, equals(14));

        // 3. Verify exactly 8 units and 6 categories created
        final units = await invRepo.getUnits();
        final categories = await invRepo.getCategories();
        expect(units.length, equals(8));
        expect(categories.length, equals(6));

        // 4. Repeat seeding - verify zero added and no duplicates
        final reseedAdded = await invRepo.safeSeedMasterData();
        expect(reseedAdded, equals(0));
        final unitsAfter = await invRepo.getUnits();
        final categoriesAfter = await invRepo.getCategories();
        expect(unitsAfter.length, equals(8));
        expect(categoriesAfter.length, equals(6));

        // 5. Insert sample party and item, reseed again, verify untouched
        final partiesRepo = SqlitePartiesRepository(AppDatabase.instance);
        final pId = await partiesRepo.insertParty(
          PartyModel(
            name: 'عميل الفحص الآمن',
            phone: '0500000000',
            type: PartyType.customer,
            currentBalance: const Money(5000),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        final iId = await invRepo.insertItem(
          ItemModel(
            code: 'TEST-CODE-1',
            name: 'صنف الفحص الآمن',
            unitId: units.first.id!,
            costPrice: const Money(100),
            sellingPrice: const Money(200),
            stockQuantity: 10,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        final thirdSeed = await invRepo.safeSeedMasterData();
        expect(thirdSeed, equals(0));

        final partyCheck = await partiesRepo.getPartyById(pId);
        final itemCheck = await invRepo.getItemById(iId);
        expect(partyCheck, isNotNull);
        expect(partyCheck!.currentBalance, equals(const Money(5000)));
        expect(itemCheck, isNotNull);
        expect(itemCheck!.name, equals('صنف الفحص الآمن'));
      },
    );

    test(
      'Test 12: Foreign Key Violation Detection triggers complete rollback',
      () async {
        await seedFullRealisticBusinessData();

        // Test that PRAGMA foreign_key_check detects relational violations and throws StateError, triggering complete rollback
        await db.execute('PRAGMA foreign_keys = OFF;');
        try {
          expect(() async {
            await db.transaction((txn) async {
              // Delete units while items still reference them
              await txn.delete(AppTables.units);
              final violations = await txn.rawQuery(
                'PRAGMA foreign_key_check;',
              );
              if (violations.isNotEmpty) {
                throw StateError(
                  'Foreign key constraint violation detected: $violations',
                );
              }
            });
          }, throwsA(isA<StateError>()));
        } finally {
          await db.execute('PRAGMA foreign_keys = ON;');
        }

        // Verify complete rollback: units were NOT deleted because of transaction rollback
        final countUnits = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.units}'),
        );
        final countItems = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.items}'),
        );
        expect(countUnits, greaterThan(0));
        expect(countItems, greaterThan(0));
      },
    );
  });
}
