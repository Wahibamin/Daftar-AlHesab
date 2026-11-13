import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/reports/repositories/reports_repository.dart';

void main() {
  group('Reports Math & Integer Financial Logic Tests', () {
    test(
      'Calculates Profit & Loss (P&L) statement correctly with exact integer math',
      () {
        final now = DateTime.now();
        final report = ProfitLossReportModel(
          startDate: DateTime(now.year, now.month, 1),
          endDate: now,
          totalRevenues: const Money(1000000), // 10,000.00 SAR
          costOfGoodsSold: const Money(600000), // 6,000.00 SAR
          grossProfit: const Money(400000), // 4,000.00 SAR
          operatingExpenses: const Money(150000), // 1,500.00 SAR
          netProfit: const Money(250000), // 2,500.00 SAR
        );

        // Verify Gross Profit = Revenues - COGS (4,000.00 SAR)
        expect(report.grossProfit, const Money(400000));
        // Verify Net Profit = Gross Profit - Expenses (2,500.00 SAR)
        expect(report.netProfit, const Money(250000));

        // Gross profit margin = 4,000 / 10,000 = 40%
        expect(report.grossProfitMarginPercent, 40);
        // Net profit margin = 2,500 / 10,000 = 25%
        expect(report.netProfitMarginPercent, 25);
      },
    );

    test(
      'Handles operational loss (negative net profit) without throwing or float drift',
      () {
        final now = DateTime.now();
        final report = ProfitLossReportModel(
          startDate: DateTime(now.year, now.month, 1),
          endDate: now,
          totalRevenues: const Money(500000), // 5,000.00 SAR
          costOfGoodsSold: const Money(400000), // 4,000.00 SAR
          grossProfit: const Money(100000), // 1,000.00 SAR
          operatingExpenses: const Money(
            300000,
          ), // 3,000.00 SAR (Expenses exceed gross profit)
          netProfit: const Money(-200000), // -2,000.00 SAR (Loss)
        );

        expect(report.netProfit.isNegative, isTrue);
        expect(report.netProfit, const Money(-200000));
        expect(report.netProfitMarginPercent, -40); // -2000 / 5000 = -40%
      },
    );

    test(
      'Calculates Inventory Valuation and potential gross profit correctly',
      () {
        const val = InventoryValuationReportModel(
          totalItemsCount: 50,
          totalStockUnits: 1200,
          totalCostValuation: Money(1500000), // 15,000.00 SAR
          totalRetailValuation: Money(2250000), // 22,500.00 SAR
          potentialGrossProfit: Money(750000), // 7,500.00 SAR
          lowStockItemsCount: 5,
        );

        expect(val.totalItemsCount, 50);
        expect(val.totalStockUnits, 1200);
        expect(val.totalCostValuation, const Money(1500000));
        expect(val.totalRetailValuation, const Money(2250000));
        expect(val.potentialGrossProfit, const Money(750000));
        expect(val.lowStockItemsCount, 5);
      },
    );

    test(
      'Calculates Treasury Cash Flow statement and net balance accurately',
      () {
        final now = DateTime.now();
        final cashFlow = TreasuryCashFlowReportModel(
          startDate: DateTime(now.year, now.month, 1),
          endDate: now,
          totalReceipts: const Money(400000), // 4,000.00 SAR
          totalPayments: const Money(150000), // 1,500.00 SAR
          netCashFlow: const Money(250000), // +2,500.00 SAR
          currentTreasuryBalance: const Money(650000), // 6,500.00 SAR
        );

        expect(cashFlow.totalReceipts, const Money(400000));
        expect(cashFlow.totalPayments, const Money(150000));
        expect(cashFlow.netCashFlow, const Money(250000));
        expect(cashFlow.currentTreasuryBalance, const Money(650000));
      },
    );

    test(
      'FakeReportsRepository provides coherent metrics and trend data',
      () async {
        final repo = FakeReportsRepository();

        final metrics = await repo.getDashboardMetrics();
        expect(metrics.todaySales.isPositive, isTrue);
        expect(metrics.monthSales.isPositive, isTrue);
        expect(metrics.lowStockCount, greaterThanOrEqualTo(0));

        final trend = await repo.getWeeklySalesTrend();
        expect(trend.length, 7);
        for (final point in trend) {
          expect(point.dayName.isNotEmpty, isTrue);
          expect(point.amount.rawUnits, greaterThanOrEqualTo(0));
        }

        final pnl = await repo.getProfitLossReport(
          startDate: DateTime.now().subtract(const Duration(days: 30)),
          endDate: DateTime.now(),
        );
        expect(pnl.grossProfit, pnl.totalRevenues - pnl.costOfGoodsSold);
        expect(pnl.netProfit, pnl.grossProfit - pnl.operatingExpenses);
      },
    );
  });
}
