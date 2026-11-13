import 'package:flutter/foundation.dart';
import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../../core/accounting/treasury_ledger.dart';
export '../../../core/accounting/financial_accounts.dart';
import '../../sales/models/invoice_model.dart';
import '../../accounting/models/voucher_model.dart';

// -----------------------------------------------------------------------------
// Financial Reports Data Models (Strict Integer Fixed-Point Arithmetic)
// -----------------------------------------------------------------------------

/// Aggregated executive metrics displayed on the top dashboard.
@immutable
class DashboardMetricsModel {
  final Money todaySales;
  final Money monthSales;
  final Money estimatedNetProfit;
  final Money totalReceivables; // ديون العملاء لنا (أرصدة مدينة)
  final Money totalPayables; // مستحقات الموردين علينا (أرصدة دائنة)
  final int lowStockCount;
  final int totalInvoicesToday;

  const DashboardMetricsModel({
    required this.todaySales,
    required this.monthSales,
    required this.estimatedNetProfit,
    required this.totalReceivables,
    required this.totalPayables,
    required this.lowStockCount,
    this.totalInvoicesToday = 0,
  });

  static const DashboardMetricsModel zero = DashboardMetricsModel(
    todaySales: Money.zero,
    monthSales: Money.zero,
    estimatedNetProfit: Money.zero,
    totalReceivables: Money.zero,
    totalPayables: Money.zero,
    lowStockCount: 0,
    totalInvoicesToday: 0,
  );
}

/// Single daily sales aggregate point for charts and trends.
@immutable
class DailySalesPoint {
  final String dayName; // السبت، الأحد...
  final DateTime date;
  final Money amount;
  final int invoiceCount;

  const DailySalesPoint({
    required this.dayName,
    required this.date,
    required this.amount,
    this.invoiceCount = 0,
  });
}

/// Profit & Loss statement model (P&L / الأرباح والخسائر).
@immutable
class ProfitLossReportModel {
  final DateTime startDate;
  final DateTime endDate;
  final Money totalRevenues; // إجمالي المبيعات الصافية
  final Money costOfGoodsSold; // تكلفة البضاعة المباعة COGS
  final Money grossProfit; // مجمل الربح = المبيعات - COGS
  final Money operatingExpenses; // سندات المصروفات التشغيلية المعتمدة فقط
  final Money netProfit; // صافي الربح = مجمل الربح - المصروفات

  const ProfitLossReportModel({
    required this.startDate,
    required this.endDate,
    required this.totalRevenues,
    required this.costOfGoodsSold,
    required this.grossProfit,
    required this.operatingExpenses,
    required this.netProfit,
  });

  /// Percentage of Gross Profit over Revenues (Integer percentage 0-100%).
  int get grossProfitMarginPercent {
    if (totalRevenues.isZero || totalRevenues.isNegative) return 0;
    return (grossProfit.rawUnits * 100) ~/ totalRevenues.rawUnits;
  }

  /// Percentage of Net Profit over Revenues (Integer percentage).
  int get netProfitMarginPercent {
    if (totalRevenues.isZero || totalRevenues.isNegative) return 0;
    return (netProfit.rawUnits * 100) ~/ totalRevenues.rawUnits;
  }
}

/// Inventory valuation and stock health audit model.
@immutable
class InventoryValuationReportModel {
  final int totalItemsCount;
  final int totalStockUnits;
  final Money totalCostValuation; // القيمة بسعر التكلفة
  final Money totalRetailValuation; // القيمة بسعر البيع
  final Money potentialGrossProfit; // الربح المتوقع بالجرد = Retail - Cost
  final int lowStockItemsCount;

  const InventoryValuationReportModel({
    required this.totalItemsCount,
    required this.totalStockUnits,
    required this.totalCostValuation,
    required this.totalRetailValuation,
    required this.potentialGrossProfit,
    required this.lowStockItemsCount,
  });
}

/// Treasury cash flow statement model (المقبوضات والمدفوعات).
@immutable
class TreasuryCashFlowReportModel {
  final DateTime startDate;
  final DateTime endDate;
  final Money totalReceipts;
  final Money totalPayments;
  final Money netCashFlow;
  final Money currentTreasuryBalance;
  final TreasurySnapshot accounts;

  const TreasuryCashFlowReportModel({
    required this.startDate,
    required this.endDate,
    required this.totalReceipts,
    required this.totalPayments,
    required this.netCashFlow,
    required this.currentTreasuryBalance,
    this.accounts = const TreasurySnapshot(),
  });
}

// -----------------------------------------------------------------------------
// Abstract Repository Contract
// -----------------------------------------------------------------------------

/// Abstract contract for executive dashboard metrics and financial reporting.
abstract class ReportsRepository {
  Future<DashboardMetricsModel> getDashboardMetrics({DateTime? now});
  Future<List<DailySalesPoint>> getWeeklySalesTrend({DateTime? now});
  Future<ProfitLossReportModel> getProfitLossReport({
    required DateTime startDate,
    required DateTime endDate,
  });
  Future<InventoryValuationReportModel> getInventoryValuationReport();
  Future<TreasuryCashFlowReportModel> getTreasuryCashFlowReport({
    required DateTime startDate,
    required DateTime endDate,
  });
}

// -----------------------------------------------------------------------------
// SQLite Production Implementation
// -----------------------------------------------------------------------------

class SqliteReportsRepository implements ReportsRepository {
  final AppDatabase _dbManager;

  SqliteReportsRepository([AppDatabase? dbManager])
    : _dbManager = dbManager ?? AppDatabase.instance;

  @override
  Future<DashboardMetricsModel> getDashboardMetrics({DateTime? now}) async {
    final db = await _dbManager.database;
    final targetDate = now ?? DateTime.now();

    final startOfToday = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    final endOfToday = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      23,
      59,
      59,
      999,
    );
    final startOfMonth = DateTime(targetDate.year, targetDate.month, 1);

    // 1. Today Sales
    final todaySalesRows = await db.rawQuery(
      'SELECT SUM(total_int) as total, COUNT(*) as cnt FROM ${AppTables.invoices} '
      'WHERE invoice_type = ? AND status = ? AND invoice_date >= ? AND invoice_date <= ?',
      [
        InvoiceType.sale.dbValue,
        InvoiceStatus.approved.dbValue,
        startOfToday.millisecondsSinceEpoch,
        endOfToday.millisecondsSinceEpoch,
      ],
    );
    final todaySalesInt = (todaySalesRows.first['total'] as int?) ?? 0;
    final todayCount = (todaySalesRows.first['cnt'] as int?) ?? 0;

    // 2. Month Sales
    final monthSalesRows = await db.rawQuery(
      'SELECT SUM(total_int) as total FROM ${AppTables.invoices} '
      'WHERE invoice_type = ? AND status = ? AND invoice_date >= ? AND invoice_date <= ?',
      [
        InvoiceType.sale.dbValue,
        InvoiceStatus.approved.dbValue,
        startOfMonth.millisecondsSinceEpoch,
        endOfToday.millisecondsSinceEpoch,
      ],
    );
    final monthSalesInt = (monthSalesRows.first['total'] as int?) ?? 0;

    // 3. Receivables & Payables from Parties directly in SQLite
    // Negative balance = Debtor customer (owes us money) -> ABS()
    // Positive balance = Creditor supplier (we owe money)
    final partiesAggRows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN current_balance_int < 0 THEN ABS(current_balance_int) ELSE 0 END), 0) as receivables,
        COALESCE(SUM(CASE WHEN current_balance_int > 0 THEN current_balance_int ELSE 0 END), 0) as payables
      FROM ${AppTables.parties}
    ''');
    final receivablesInt = (partiesAggRows.first['receivables'] as int?) ?? 0;
    final payablesInt = (partiesAggRows.first['payables'] as int?) ?? 0;

    // 4. Low stock count
    final lowStockRows = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM ${AppTables.items} '
      'WHERE is_active = 1 AND stock_quantity_int <= min_alert_limit_int',
    );
    final lowStockCount = (lowStockRows.first['cnt'] as int?) ?? 0;

    // 5. Estimated Month Net Profit (Month Sales - COGS - Expenses)
    final pnl = await getProfitLossReport(
      startDate: startOfMonth,
      endDate: endOfToday,
    );

    return DashboardMetricsModel(
      todaySales: Money(todaySalesInt),
      monthSales: Money(monthSalesInt),
      estimatedNetProfit: pnl.netProfit,
      totalReceivables: Money(receivablesInt),
      totalPayables: Money(payablesInt),
      lowStockCount: lowStockCount,
      totalInvoicesToday: todayCount,
    );
  }

  @override
  Future<List<DailySalesPoint>> getWeeklySalesTrend({DateTime? now}) async {
    final db = await _dbManager.database;
    final targetDate = now ?? DateTime.now();

    final result = <DailySalesPoint>[];
    const arabicDays = [
      'الأحد',
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
    ];

    for (int i = 6; i >= 0; i--) {
      final day = targetDate.subtract(Duration(days: i));
      final dayStart = DateTime(day.year, day.month, day.day);
      final dayEnd = DateTime(day.year, day.month, day.day, 23, 59, 59, 999);

      final rows = await db.rawQuery(
        'SELECT SUM(total_int) as total, COUNT(*) as cnt FROM ${AppTables.invoices} '
        'WHERE invoice_type = ? AND status = ? AND invoice_date >= ? AND invoice_date <= ?',
        [
          InvoiceType.sale.dbValue,
          InvoiceStatus.approved.dbValue,
          dayStart.millisecondsSinceEpoch,
          dayEnd.millisecondsSinceEpoch,
        ],
      );

      final total = (rows.first['total'] as int?) ?? 0;
      final cnt = (rows.first['cnt'] as int?) ?? 0;
      final dayName = arabicDays[day.weekday % 7];

      result.add(
        DailySalesPoint(
          dayName: dayName,
          date: dayStart,
          amount: Money(total),
          invoiceCount: cnt,
        ),
      );
    }

    return result;
  }

  @override
  Future<ProfitLossReportModel> getProfitLossReport({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await _dbManager.database;
    final startMs = startDate.millisecondsSinceEpoch;
    final endMs = endDate.millisecondsSinceEpoch;

    // 1. Gross Sales Revenues (Sales minus Sale Returns)
    final salesRows = await db.rawQuery(
      'SELECT SUM(total_int) as total FROM ${AppTables.invoices} '
      'WHERE invoice_type = ? AND status = ? AND invoice_date >= ? AND invoice_date <= ?',
      [
        InvoiceType.sale.dbValue,
        InvoiceStatus.approved.dbValue,
        startMs,
        endMs,
      ],
    );
    final saleReturnsRows = await db.rawQuery(
      'SELECT SUM(total_int) as total FROM ${AppTables.invoices} '
      'WHERE invoice_type = ? AND status = ? AND invoice_date >= ? AND invoice_date <= ?',
      [
        InvoiceType.saleReturn.dbValue,
        InvoiceStatus.approved.dbValue,
        startMs,
        endMs,
      ],
    );

    final totalSales = (salesRows.first['total'] as int?) ?? 0;
    final totalReturns = (saleReturnsRows.first['total'] as int?) ?? 0;
    final netRevenuesInt = totalSales - totalReturns;

    // 2. Cost of Goods Sold (COGS) aggregated directly inside SQLite
    // Uses frozen historical unit_cost_int from invoice_items, deducting sale returns
    final cogsRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(
        CASE
          WHEN inv.invoice_type = ? THEN ii.quantity_int * ii.unit_cost_int
          WHEN inv.invoice_type = ? THEN - (ii.quantity_int * ii.unit_cost_int)
          ELSE 0
        END
      ), 0) as total_cogs
      FROM ${AppTables.invoiceItems} ii
      JOIN ${AppTables.invoices} inv ON ii.invoice_id = inv.id
      WHERE (inv.invoice_type = ? OR inv.invoice_type = ?)
        AND inv.status = ?
        AND inv.invoice_date >= ?
        AND inv.invoice_date <= ?
    ''',
      [
        InvoiceType.sale.dbValue,
        InvoiceType.saleReturn.dbValue,
        InvoiceType.sale.dbValue,
        InvoiceType.saleReturn.dbValue,
        InvoiceStatus.approved.dbValue,
        startMs,
        endMs,
      ],
    );

    final cogsInt = (cogsRows.first['total_cogs'] as int?) ?? 0;

    // 3. Only explicitly classified operating expenses affect profit.
    final expensesRows = await db.rawQuery(
      'SELECT SUM(amount_int) as total FROM ${AppTables.vouchers} '
      'WHERE voucher_type = ? AND purpose = ? AND party_id IS NULL AND (status IS NULL OR status = ?) AND voucher_date >= ? AND voucher_date <= ?',
      [
        VoucherType.payment.dbValue,
        VoucherPurpose.expense.name,
        VoucherStatus.approved.dbValue,
        startMs,
        endMs,
      ],
    );
    final expensesInt = (expensesRows.first['total'] as int?) ?? 0;

    final grossProfitInt = netRevenuesInt - cogsInt;
    final netProfitInt = grossProfitInt - expensesInt;

    return ProfitLossReportModel(
      startDate: startDate,
      endDate: endDate,
      totalRevenues: Money(netRevenuesInt),
      costOfGoodsSold: Money(cogsInt),
      grossProfit: Money(grossProfitInt),
      operatingExpenses: Money(expensesInt),
      netProfit: Money(netProfitInt),
    );
  }

  @override
  Future<InventoryValuationReportModel> getInventoryValuationReport() async {
    final db = await _dbManager.database;
    // Single-row SQL aggregation instead of loading all items into memory
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) as total_items,
        COALESCE(SUM(stock_quantity_int), 0) as total_units,
        COALESCE(SUM(stock_quantity_int * cost_price_int), 0) as total_cost,
        COALESCE(SUM(stock_quantity_int * selling_price_int), 0) as total_retail,
        COALESCE(SUM(CASE WHEN stock_quantity_int <= min_alert_limit_int THEN 1 ELSE 0 END), 0) as low_stock_count
      FROM ${AppTables.items}
      WHERE is_active = 1
    ''');

    final first = rows.first;
    final totalItems = (first['total_items'] as int?) ?? 0;
    final totalUnits = (first['total_units'] as int?) ?? 0;
    final totalCost = (first['total_cost'] as int?) ?? 0;
    final totalRetail = (first['total_retail'] as int?) ?? 0;
    final lowStockCount = (first['low_stock_count'] as int?) ?? 0;
    final potentialProfit = totalRetail - totalCost;

    return InventoryValuationReportModel(
      totalItemsCount: totalItems,
      totalStockUnits: totalUnits,
      totalCostValuation: Money(totalCost),
      totalRetailValuation: Money(totalRetail),
      potentialGrossProfit: Money(potentialProfit),
      lowStockItemsCount: lowStockCount,
    );
  }

  @override
  Future<TreasuryCashFlowReportModel> getTreasuryCashFlowReport({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final snapshot = await TreasuryLedger.read(
      await _dbManager.database,
      startDate: startDate,
      endDate: endDate,
    );
    return TreasuryCashFlowReportModel(
      startDate: startDate,
      endDate: endDate,
      totalReceipts: snapshot.total.receipts,
      totalPayments: snapshot.total.payments,
      netCashFlow: snapshot.total.net,
      currentTreasuryBalance: snapshot.total.available,
      accounts: snapshot,
    );
  }
}

// -----------------------------------------------------------------------------
// In-Memory Mock Implementation for High-Speed Tests
// -----------------------------------------------------------------------------

class FakeReportsRepository implements ReportsRepository {
  DashboardMetricsModel mockMetrics;
  List<DailySalesPoint> mockTrend;
  ProfitLossReportModel? mockProfitLoss;
  InventoryValuationReportModel? mockValuation;
  TreasuryCashFlowReportModel? mockCashFlow;

  FakeReportsRepository({
    DashboardMetricsModel? metrics,
    List<DailySalesPoint>? trend,
  }) : mockMetrics =
           metrics ??
           const DashboardMetricsModel(
             todaySales: Money(350000), // 3,500.00 SAR
             monthSales: Money(4500000), // 45,000.00 SAR
             estimatedNetProfit: Money(1250000), // 12,500.00 SAR
             totalReceivables: Money(850000), // 8,500.00 SAR
             totalPayables: Money(1400000), // 14,000.00 SAR
             lowStockCount: 3,
             totalInvoicesToday: 12,
           ),
       mockTrend = trend ?? _buildDefaultTrend();

  static List<DailySalesPoint> _buildDefaultTrend() {
    final now = DateTime.now();
    const days = [
      'السبت',
      'الأحد',
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
    ];
    return List.generate(7, (i) {
      final date = now.subtract(Duration(days: 6 - i));
      return DailySalesPoint(
        dayName: days[(date.weekday) % 7],
        date: date,
        amount: Money((i + 1) * 50000), // 500.00 -> 3,500.00 SAR
        invoiceCount: i + 2,
      );
    });
  }

  @override
  Future<DashboardMetricsModel> getDashboardMetrics({DateTime? now}) async =>
      mockMetrics;

  @override
  Future<List<DailySalesPoint>> getWeeklySalesTrend({DateTime? now}) async =>
      mockTrend;

  @override
  Future<ProfitLossReportModel> getProfitLossReport({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    return mockProfitLoss ??
        ProfitLossReportModel(
          startDate: startDate,
          endDate: endDate,
          totalRevenues: const Money(5000000), // 50,000.00 SAR
          costOfGoodsSold: const Money(3200000), // 32,000.00 SAR
          grossProfit: const Money(1800000), // 18,000.00 SAR
          operatingExpenses: const Money(450000), // 4,500.00 SAR
          netProfit: const Money(1350000), // 13,500.00 SAR
        );
  }

  @override
  Future<InventoryValuationReportModel> getInventoryValuationReport() async {
    return mockValuation ??
        const InventoryValuationReportModel(
          totalItemsCount: 45,
          totalStockUnits: 820,
          totalCostValuation: Money(4100000), // 41,000.00 SAR
          totalRetailValuation: Money(6150000), // 61,500.00 SAR
          potentialGrossProfit: Money(2050000), // 20,500.00 SAR
          lowStockItemsCount: 3,
        );
  }

  @override
  Future<TreasuryCashFlowReportModel> getTreasuryCashFlowReport({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    return mockCashFlow ??
        TreasuryCashFlowReportModel(
          startDate: startDate,
          endDate: endDate,
          totalReceipts: const Money(3500000), // 35,000.00 SAR
          totalPayments: const Money(1800000), // 18,000.00 SAR
          netCashFlow: const Money(1700000), // 17,000.00 SAR
          currentTreasuryBalance: const Money(2200000),
          accounts: const TreasurySnapshot(
            cash: AccountCashFlow(
              receipts: Money(3500000),
              payments: Money(1800000),
              balance: Money(2200000),
            ),
          ), // 22,000.00 SAR
        );
  }
}
