import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
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
  late SqliteInventoryRepository inventoryRepo;
  late SqlitePartiesRepository partiesRepo;
  late SqliteInvoicesRepository invoicesRepo;
  late SqliteVouchersRepository vouchersRepo;
  late SqliteReportsRepository reportsRepo;

  final Map<String, dynamic> benchmarkMetrics = {};

  setUpAll(() async {
    AppDatabase.instance.configureForTesting(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    db = await AppDatabase.instance.database;
    inventoryRepo = SqliteInventoryRepository(AppDatabase.instance);
    partiesRepo = SqlitePartiesRepository(AppDatabase.instance);
    invoicesRepo = SqliteInvoicesRepository(AppDatabase.instance);
    vouchersRepo = SqliteVouchersRepository(AppDatabase.instance);
    reportsRepo = SqliteReportsRepository(AppDatabase.instance);

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Seed master reference data
    final units = [
      {'name': 'حبة', 'symbol': 'حبة', 'created_at': nowMs},
      {'name': 'كرتون', 'symbol': 'كرتون', 'created_at': nowMs},
      {'name': 'كيلو', 'symbol': 'كجم', 'created_at': nowMs},
      {'name': 'لتر', 'symbol': 'لتر', 'created_at': nowMs},
      {'name': 'كيس', 'symbol': 'كيس', 'created_at': nowMs},
    ];
    for (final u in units) {
      await db.insert(AppTables.units, u);
    }

    final categories = [
      {'name': 'ألبان وأجبان', 'created_at': nowMs},
      {'name': 'معلبات غذائية', 'created_at': nowMs},
      {'name': 'مشروبات وعصائر', 'created_at': nowMs},
      {'name': 'بهارات وتوابل', 'created_at': nowMs},
      {'name': 'زيوت وسمن', 'created_at': nowMs},
      {'name': 'بقوليات وحبوب', 'created_at': nowMs},
      {'name': 'مخبوزات', 'created_at': nowMs},
      {'name': 'حلويات وبسكويت', 'created_at': nowMs},
      {'name': 'منظفات منزلية', 'created_at': nowMs},
      {'name': 'خضار وفواكه', 'created_at': nowMs},
    ];
    for (final c in categories) {
      await db.insert(AppTables.categories, c);
    }

    // Seed 10,000 synthetic items in batches of 1,000
    final itemSeedStopwatch = Stopwatch()..start();

    const totalItems = 10000;
    const batchSize = 1000;
    for (var b = 0; b < totalItems / batchSize; b++) {
      final batch = db.batch();
      for (var i = b * batchSize + 1; i <= (b + 1) * batchSize; i++) {
        final isOil = i % 10 == 0;
        final name = isOil
            ? 'زيت طعام نقي رقم $i ممتاز 1.5 لتر'
            : 'صنف استهلاكي قياسي رقم $i تعبئة فاخرة';
        batch.insert(AppTables.items, {
          'id': i,
          'code': 'ITEM_${i.toString().padLeft(6, '0')}',
          'name': name,
          'unit_id': (i % 5) + 1,
          'category_id': (i % 10) + 1,
          'cost_price_int': 1000 + (i % 50) * 100, // 10.00 to 59.00 SAR
          'selling_price_int': 1500 + (i % 50) * 150, // 15.00 to 88.50 SAR
          'stock_quantity_int': 50 + (i % 200),
          'min_alert_limit_int': 10,
          'is_active': 1,
          'created_at': nowMs - (10000 - i) * 60000,
          'updated_at': nowMs - (10000 - i) * 60000,
        });
      }
      await batch.commit(noResult: true);
    }
    itemSeedStopwatch.stop();
    benchmarkMetrics['items_seeding_ms'] =
        itemSeedStopwatch.elapsedMilliseconds;

    // Seed 1,000 Parties (500 customers, 500 suppliers)
    const totalParties = 1000;
    final partiesBatch = db.batch();
    for (var p = 1; p <= totalParties; p++) {
      final isCustomer = p <= 500;
      partiesBatch.insert(AppTables.parties, {
        'id': p,
        'name': isCustomer
            ? 'عميل تجاري مسجل رقم $p'
            : 'مورد مواد غذائية رقم $p',
        'phone': isCustomer
            ? '050${p.toString().padLeft(7, '0')}'
            : '056${p.toString().padLeft(7, '0')}',
        'type': isCustomer
            ? PartyType.customer.dbValue
            : PartyType.supplier.dbValue,
        'current_balance_int': isCustomer ? -250000 : 500000,
        'opening_balance_int': 0,
        'credit_limit_int': 1000000,
        'is_active': 1,
        'created_at': nowMs - (1000 - p) * 60000,
        'updated_at': nowMs - (1000 - p) * 60000,
      });
    }
    await partiesBatch.commit(noResult: true);

    // Seed 10,000 Invoices + 30,000 Invoice Items
    const totalInvoices = 10000;
    var lineId = 1;
    for (var b = 0; b < totalInvoices / batchSize; b++) {
      final invBatch = db.batch();
      for (var i = b * batchSize + 1; i <= (b + 1) * batchSize; i++) {
        final partyId = (i % totalParties) + 1;
        final isSale = i % 5 != 0;
        final invType = isSale ? InvoiceType.sale : InvoiceType.saleReturn;
        final subtotal = 30000; // 300.00
        final tax = 4500; // 45.00
        final total = 34500; // 345.00
        final paid = isSale ? 34500 : 0;

        invBatch.insert(AppTables.invoices, {
          'id': i,
          'invoice_number': 'INV-${i.toString().padLeft(6, '0')}',
          'party_id': partyId,
          'invoice_type': invType.dbValue,
          'status': InvoiceStatus.approved.dbValue,
          'payment_type': 'cash',
          'invoice_date': nowMs - (totalInvoices - i) * 120000,
          'subtotal_int': subtotal,
          'discount_int': 0,
          'tax_int': tax,
          'total_int': total,
          'paid_amount_int': paid,
          'remaining_amount_int': total - paid,
          'created_at': nowMs - (totalInvoices - i) * 120000,
          'updated_at': nowMs - (totalInvoices - i) * 120000,
        });

        // 3 items per invoice
        for (var l = 1; l <= 3; l++) {
          final itemId = ((i * 3 + l) % totalItems) + 1;
          invBatch.insert(AppTables.invoiceItems, {
            'id': lineId++,
            'invoice_id': i,
            'item_id': itemId,
            'quantity_int': 2,
            'unit_price_int': 5000, // 50.00
            'unit_cost_int': 3500, // 35.00
            'discount_int': 0,
            'tax_rate_percent': 15,
            'tax_amount_int': 1500,
            'total_price_int': 11500,
          });
        }
      }
      await invBatch.commit(noResult: true);
    }

    // Seed 10,000 Inventory Movements
    for (var b = 0; b < totalInvoices / batchSize; b++) {
      final movBatch = db.batch();
      for (var m = b * batchSize + 1; m <= (b + 1) * batchSize; m++) {
        final itemId = (m % totalItems) + 1;
        movBatch.insert(AppTables.inventoryMovements, {
          'id': m,
          'item_id': itemId,
          'movement_type': 'sale',
          'quantity_int': -2,
          'unit_cost_int': 3500,
          'reference_type': 'invoice',
          'reference_id': m,
          'notes': 'حركة بيع مسجلة تلقائياً',
          'movement_date': nowMs - (totalInvoices - m) * 120000,
          'created_at': nowMs - (totalInvoices - m) * 120000,
        });
      }
      await movBatch.commit(noResult: true);
    }

    // Seed 5,000 Vouchers (Receipts and Payments)
    const totalVouchers = 5000;
    for (var b = 0; b < totalVouchers / batchSize; b++) {
      final vBatch = db.batch();
      for (var v = b * batchSize + 1; v <= (b + 1) * batchSize; v++) {
        final partyId = (v % totalParties) + 1;
        final isReceipt = v % 2 == 0;
        vBatch.insert(AppTables.vouchers, {
          'id': v,
          'voucher_number': 'VCH-${v.toString().padLeft(6, '0')}',
          'party_id': partyId,
          'voucher_type': isReceipt
              ? VoucherType.receipt.dbValue
              : VoucherType.payment.dbValue,
          'status': VoucherStatus.approved.dbValue,
          'voucher_date': nowMs - (totalVouchers - v) * 180000,
          'amount_int': 25000, // 250.00 SAR
          'statement': isReceipt ? 'دفعة نقدية مقبوضة' : 'دفعة نقدية مسددة',
          'payment_method': 'cash',
          'created_at': nowMs - (totalVouchers - v) * 180000,
        });
      }
      await vBatch.commit(noResult: true);
    }
  });

  tearDownAll(() async {
    await AppDatabase.instance.close();
  });

  int firstIntValue(List<Map<String, Object?>> rows) =>
      (rows.first.values.first as int?) ?? 0;

  group('Scalability & Large Dataset Performance Benchmarks (66,000+ Records)', () {
    test(
      '1. Total record counts match required scale (>= 50,000 records)',
      () async {
        final itemsCount = firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.items}'),
        );
        final partiesCount = firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.parties}'),
        );
        final invoicesCount = firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.invoices}'),
        );
        final invoiceItemsCount = firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.invoiceItems}'),
        );
        final movementsCount = firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM ${AppTables.inventoryMovements}',
          ),
        );
        final vouchersCount = firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.vouchers}'),
        );

        final totalRecords =
            itemsCount +
            partiesCount +
            invoicesCount +
            invoiceItemsCount +
            movementsCount +
            vouchersCount;

        expect(itemsCount, 10000);
        expect(partiesCount, 1000);
        expect(invoicesCount, 10000);
        expect(invoiceItemsCount, 30000);
        expect(movementsCount, 10000);
        expect(vouchersCount, 5000);
        expect(totalRecords, greaterThanOrEqualTo(50000));
      },
    );

    test(
      '2. Search query performance: existing item vs non-existing item',
      () async {
        // Existing item search
        final swExist = Stopwatch()..start();
        final existResults = await inventoryRepo.getItems(
          searchQuery: 'زيت',
          limit: 30,
          offset: 0,
        );
        swExist.stop();
        benchmarkMetrics['item_search_existing_ms'] =
            swExist.elapsedMilliseconds;

        expect(existResults, isNotEmpty);
        expect(
          existResults.every(
            (item) => item.name.contains('زيت') || item.code.contains('زيت'),
          ),
          isTrue,
        );
        expect(swExist.elapsedMilliseconds, lessThan(50));

        // Non-existing item search
        final swNonExist = Stopwatch()..start();
        final nonExistResults = await inventoryRepo.getItems(
          searchQuery: 'منتج_مستحيل_وجوده_99999',
          limit: 30,
          offset: 0,
        );
        swNonExist.stop();
        benchmarkMetrics['item_search_non_existing_ms'] =
            swNonExist.elapsedMilliseconds;

        expect(nonExistResults, isEmpty);
        expect(swNonExist.elapsedMilliseconds, lessThan(50));
      },
    );

    test(
      '3. Pagination: First page load and sequential batch navigation',
      () async {
        final swPage1 = Stopwatch()..start();
        final page1 = await inventoryRepo.getItems(limit: 30, offset: 0);
        swPage1.stop();
        benchmarkMetrics['items_page_1_load_ms'] = swPage1.elapsedMilliseconds;

        expect(page1.length, 30);
        expect(swPage1.elapsedMilliseconds, lessThan(50));

        final swPage2 = Stopwatch()..start();
        final page2 = await inventoryRepo.getItems(limit: 30, offset: 30);
        swPage2.stop();
        benchmarkMetrics['items_page_2_load_ms'] = swPage2.elapsedMilliseconds;

        expect(page2.length, 30);
        expect(swPage2.elapsedMilliseconds, lessThan(50));

        final swPage3 = Stopwatch()..start();
        final page3 = await inventoryRepo.getItems(limit: 30, offset: 60);
        swPage3.stop();

        expect(page3.length, 30);
      },
    );

    test(
      '4. Deterministic pagination: No duplicate or skipped records across batches',
      () async {
        final page1 = await inventoryRepo.getItems(limit: 30, offset: 0);
        final page2 = await inventoryRepo.getItems(limit: 30, offset: 30);
        final page3 = await inventoryRepo.getItems(limit: 30, offset: 60);
        final page4 = await inventoryRepo.getItems(limit: 30, offset: 90);
        final page5 = await inventoryRepo.getItems(limit: 30, offset: 120);

        final all150Items = [...page1, ...page2, ...page3, ...page4, ...page5];
        final uniqueIds = all150Items.map((e) => e.id).toSet();

        expect(all150Items.length, 150);
        expect(
          uniqueIds.length,
          150,
          reason: 'Zero duplicate items across adjacent pages',
        );

        // Verify deterministic sorting (updated_at DESC, id DESC)
        for (var i = 0; i < all150Items.length - 1; i++) {
          final current = all150Items[i];
          final next = all150Items[i + 1];
          final currentMs = current.updatedAt.millisecondsSinceEpoch;
          final nextMs = next.updatedAt.millisecondsSinceEpoch;

          if (currentMs == nextMs) {
            expect(
              current.id!,
              greaterThan(next.id!),
              reason: 'Ties resolved deterministically by id DESC',
            );
          } else {
            expect(
              currentMs,
              greaterThan(nextMs),
              reason: 'Ordered by updatedAt DESC',
            );
          }
        }
      },
    );

    test('5. Invoices N+1 query elimination and pagination', () async {
      final swInvoicesList = Stopwatch()..start();
      final invoices = await invoicesRepo.getInvoices(
        includeItems: false,
        limit: 30,
        offset: 0,
      );
      swInvoicesList.stop();
      benchmarkMetrics['invoices_page_load_ms'] =
          swInvoicesList.elapsedMilliseconds;

      expect(invoices.length, 30);
      expect(swInvoicesList.elapsedMilliseconds, lessThan(50));
      for (final inv in invoices) {
        expect(
          inv.items,
          isEmpty,
          reason: 'List items omitted for listing cards',
        );
      }

      // Single invoice detailed fetch loads items
      final singleInv = await invoicesRepo.getInvoiceById(invoices.first.id!);
      expect(singleInv, isNotNull);
      expect(
        singleInv!.items,
        hasLength(3),
        reason: 'Items fetched on detailed view',
      );

      // Vouchers pagination check
      final pagedVouchers = await vouchersRepo.getVouchers(
        limit: 30,
        offset: 0,
      );
      expect(
        pagedVouchers.length,
        30,
        reason: 'Vouchers paginated via SQLite limit/offset',
      );
    });

    test(
      '6. Account Statement generation for party with large number of transactions',
      () async {
        // Party #1 has multiple invoices and vouchers
        final swStmt = Stopwatch()..start();
        final stmt = await partiesRepo.getAccountStatement(1);
        swStmt.stop();
        benchmarkMetrics['statement_generation_ms'] =
            swStmt.elapsedMilliseconds;

        expect(stmt.entries, isNotEmpty);
        expect(swStmt.elapsedMilliseconds, lessThan(100));

        // Verify running balance consistency
        Money running = stmt.openingBalance;
        for (final e in stmt.entries) {
          running = running + e.credit - e.debit;
          expect(
            e.runningBalance,
            equals(running),
            reason: 'Running balance invariant preserved',
          );
        }
        expect(stmt.entries.last.runningBalance, equals(running));
      },
    );

    test(
      '7. Push aggregations: Inventory valuation report across 10,000 items',
      () async {
        final swValuation = Stopwatch()..start();
        final report = await reportsRepo.getInventoryValuationReport();
        swValuation.stop();
        benchmarkMetrics['inventory_valuation_ms'] =
            swValuation.elapsedMilliseconds;

        expect(report.totalItemsCount, 10000);
        expect(report.totalStockUnits, greaterThan(0));
        expect(report.totalCostValuation, greaterThan(Money.zero));
        expect(swValuation.elapsedMilliseconds, lessThan(100));
      },
    );

    test(
      '8. Push aggregations: Profit & Loss report across 10,000 invoices',
      () async {
        final now = DateTime.now();
        final swPl = Stopwatch()..start();
        final plReport = await reportsRepo.getProfitLossReport(
          startDate: now.subtract(const Duration(days: 365)),
          endDate: now.add(const Duration(days: 1)),
        );
        swPl.stop();
        benchmarkMetrics['profit_loss_ms'] = swPl.elapsedMilliseconds;

        expect(plReport.totalRevenues, greaterThan(Money.zero));
        expect(plReport.costOfGoodsSold, greaterThan(Money.zero));
        expect(
          plReport.grossProfit,
          equals(plReport.totalRevenues - plReport.costOfGoodsSold),
        );
        expect(
          plReport.netProfit,
          equals(plReport.grossProfit - plReport.operatingExpenses),
        );
        expect(swPl.elapsedMilliseconds, lessThan(100));
      },
    );

    test(
      '9. Transaction safety & rollback: Unfinished operations roll back cleanly',
      () async {
        final itemsCountBefore = firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.items}'),
        );

        bool caughtError = false;
        try {
          await db.transaction((txn) async {
            // Insert one item
            await txn.insert(AppTables.items, {
              'code': 'TX_ROLLBACK_TEST',
              'name': 'صنف اختبار التراجع',
              'unit_id': 1,
              'cost_price_int': 1000,
              'selling_price_int': 2000,
              'stock_quantity_int': 10,
              'min_alert_limit_int': 5,
              'is_active': 1,
              'created_at': DateTime.now().millisecondsSinceEpoch,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            });

            // Deliberate constraint violation: duplicate UNIQUE code
            await txn.insert(AppTables.items, {
              'code': 'TX_ROLLBACK_TEST', // Will fail UNIQUE constraint
              'name': 'صنف مكرر يجب أن يفشل',
              'unit_id': 1,
              'cost_price_int': 1000,
              'selling_price_int': 2000,
              'stock_quantity_int': 10,
              'min_alert_limit_int': 5,
              'is_active': 1,
              'created_at': DateTime.now().millisecondsSinceEpoch,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            });
          });
        } catch (_) {
          caughtError = true;
        }

        expect(caughtError, isTrue);

        final itemsCountAfter = firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppTables.items}'),
        );
        expect(
          itemsCountAfter,
          equals(itemsCountBefore),
          reason: 'Transaction completely rolled back on error',
        );

        final rolledBackItem = await db.query(
          AppTables.items,
          where: 'code = ?',
          whereArgs: ['TX_ROLLBACK_TEST'],
        );
        expect(
          rolledBackItem,
          isEmpty,
          reason: 'Zero uncommitted records leaked into database',
        );
      },
    );

    test(
      '10. EXPLAIN QUERY PLAN confirms composite index usage on 66k dataset',
      () async {
        // Items query plan
        final itemsPlan = await db.rawQuery(
          'EXPLAIN QUERY PLAN SELECT * FROM ${AppTables.items} WHERE is_active = 1 ORDER BY updated_at DESC, id DESC LIMIT 30;',
        );
        final itemsPlanDetails = itemsPlan
            .map((r) => r['detail'].toString())
            .join(' | ');
        expect(itemsPlanDetails, contains('idx_items_active_updated'));
        expect(itemsPlanDetails.contains('USE TEMP B-TREE'), isFalse);

        // Invoices query plan
        final invoicesPlan = await db.rawQuery(
          'EXPLAIN QUERY PLAN SELECT * FROM ${AppTables.invoices} WHERE invoice_type = ? AND status = ? ORDER BY invoice_date DESC, id DESC LIMIT 30;',
          ['sale', 'approved'],
        );
        final invoicesPlanDetails = invoicesPlan
            .map((r) => r['detail'].toString())
            .join(' | ');
        expect(invoicesPlanDetails, contains('idx_invoices_type_status_date'));
        expect(invoicesPlanDetails.contains('USE TEMP B-TREE'), isFalse);

        // Parties statement invoices query plan
        final partyStmtInvoicesPlan = await db.rawQuery(
          'EXPLAIN QUERY PLAN SELECT * FROM ${AppTables.invoices} WHERE party_id = ? AND status = ? ORDER BY invoice_date ASC, id ASC;',
          [1, 'approved'],
        );
        final partyStmtDetails = partyStmtInvoicesPlan
            .map((r) => r['detail'].toString())
            .join(' | ');
        expect(partyStmtDetails, contains('idx_invoices_party_status_date'));
        expect(partyStmtDetails.contains('USE TEMP B-TREE'), isFalse);

        // Print summary benchmarks for documentation
        // ignore: avoid_print
        print(
          '\n================ BENCHMARK MEASUREMENTS (66,000+ Records) ================',
        );
        benchmarkMetrics.forEach((k, v) {
          // ignore: avoid_print
          print('$k: $v ms');
        });
        // ignore: avoid_print
        print(
          '==========================================================================\n',
        );
      },
    );
  });
}
