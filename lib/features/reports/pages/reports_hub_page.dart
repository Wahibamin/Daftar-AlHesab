import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../repositories/reports_repository.dart';
import 'profit_loss_page.dart';
import '../../accounting/widgets/treasury_accounts_card.dart';

/// Central Financial & Management Reports Hub for RAF ERP.
class ReportsHubPage extends StatefulWidget {
  final ReportsRepository reportsRepo;

  ReportsHubPage({super.key, ReportsRepository? reportsRepo})
    : reportsRepo = reportsRepo ?? SqliteReportsRepository();

  @override
  State<ReportsHubPage> createState() => _ReportsHubPageState();
}

class _ReportsHubPageState extends State<ReportsHubPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  InventoryValuationReportModel? _valuation;
  TreasuryCashFlowReportModel? _cashFlow;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadHubData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHubData() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final val = await widget.reportsRepo.getInventoryValuationReport();
      final cf = await widget.reportsRepo.getTreasuryCashFlowReport(
        startDate: startOfMonth,
        endDate: endOfMonth,
      );

      if (mounted) {
        setState(() {
          _valuation = val;
          _cashFlow = cf;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RafColors.surfaceSecondary,
      appBar: AppBar(
        title: Text(
          'مركز التقارير المحاسبية والإدارية',
          style: RafTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: RafColors.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: RafColors.textSecondary),
            tooltip: 'تحديث التقارير',
            onPressed: _loadHubData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: RafColors.primary,
          indicatorWeight: 2.5,
          labelColor: RafColors.primary,
          unselectedLabelColor: RafColors.textSecondary,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          tabs: const [
            Tab(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('الأرباح والخسائر'),
              ),
            ),
            Tab(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('تقييم المخزون'),
              ),
            ),
            Tab(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('حركة الخزينة'),
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: RafColors.primary),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Profit & Loss Preview & Navigation
                _buildProfitLossTab(),

                // Tab 2: Inventory Valuation Report
                _buildInventoryValuationTab(),

                // Tab 3: Treasury Cash Flow Report
                _buildTreasuryCashFlowTab(),
              ],
            ),
    );
  }

  Widget _buildProfitLossTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RafSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(RafSpacing.lg),
            decoration: BoxDecoration(
              color: RafColors.surface,
              borderRadius: RafRadius.roundedMd,
              border: Border.all(color: RafColors.border),
              boxShadow: RafShadows.subtle,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: RafColors.primarySubtle,
                        borderRadius: RafRadius.roundedSm,
                      ),
                      child: const Icon(
                        Icons.analytics_outlined,
                        color: RafColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: RafSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'قائمة الأرباح والخسائر (P&L)',
                            style: RafTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'تقرير محاسبي يوضح الإيرادات وتكلفة المبيعات ومجمل الربح وصافي الأرباح التشغيلية بدقة متناهية.',
                            style: RafTypography.bodySmall.copyWith(
                              color: RafColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RafSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ProfitLossPage(reportsRepo: widget.reportsRepo),
                        ),
                      );
                    },
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text(
                      'فتح تقرير الأرباح والخسائر المفصل وتصدير PDF',
                      textAlign: TextAlign.center,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RafColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: RafRadius.roundedMd,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryValuationTab() {
    if (_valuation == null) {
      return const Center(child: Text('لا تتوفر بيانات تقييم المخزون'));
    }

    final val = _valuation!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(RafSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary Banner Card
          Container(
            padding: const EdgeInsets.all(RafSpacing.lg),
            decoration: BoxDecoration(
              color: RafColors.surface,
              borderRadius: RafRadius.roundedMd,
              border: Border.all(color: RafColors.border),
              boxShadow: RafShadows.subtle,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تقييم المخزون ورأس المال السلعي',
                  style: RafTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'إجمالي الأصناف: ${val.totalItemsCount} صنف | إجمالي الوحدات: ${val.totalStockUnits} وحدة',
                  style: RafTypography.bodySmall.copyWith(
                    color: RafColors.textSecondary,
                  ),
                ),
                const SizedBox(height: RafSpacing.md),
                const Divider(height: 1, color: RafColors.border),
                const SizedBox(height: RafSpacing.md),

                // Metrics Grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow =
                        constraints.maxWidth < 320 ||
                        MediaQuery.textScalerOf(context).scale(1.0) > 1.25;

                    final costTile = _buildMetricTile(
                      title: 'القيمة بسعر التكلفة',
                      amount: CurrencyFormatter.format(val.totalCostValuation),
                      color: RafColors.textSecondary,
                      subtitle: 'رأس المال المستثمر',
                    );

                    final retailTile = _buildMetricTile(
                      title: 'القيمة بسعر البيع',
                      amount: CurrencyFormatter.format(
                        val.totalRetailValuation,
                      ),
                      color: const Color(0xFF2563EB),
                      subtitle: 'القيمة السوقية بالجرد',
                    );

                    final profitTile = _buildMetricTile(
                      title: 'الربح المتوقع بالجرد',
                      amount: CurrencyFormatter.format(
                        val.potentialGrossProfit,
                      ),
                      color: RafColors.success,
                      subtitle: 'سعر البيع - سعر التكلفة',
                    );

                    final alertTile = _buildMetricTile(
                      title: 'تنبيهات انخفاض المخزون',
                      amount: '${val.lowStockItemsCount} أصناف',
                      color: val.lowStockItemsCount > 0
                          ? RafColors.danger
                          : RafColors.success,
                      subtitle: 'أصناف بلغت الحد الأدنى',
                    );

                    if (isNarrow) {
                      return Column(
                        children: [
                          costTile,
                          const SizedBox(height: RafSpacing.sm),
                          retailTile,
                          const SizedBox(height: RafSpacing.sm),
                          profitTile,
                          const SizedBox(height: RafSpacing.sm),
                          alertTile,
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: costTile),
                            const SizedBox(width: RafSpacing.sm),
                            Expanded(child: retailTile),
                          ],
                        ),
                        const SizedBox(height: RafSpacing.sm),
                        Row(
                          children: [
                            Expanded(child: profitTile),
                            const SizedBox(width: RafSpacing.sm),
                            Expanded(child: alertTile),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreasuryCashFlowTab() {
    if (_cashFlow == null) {
      return const Center(child: Text('لا تتوفر بيانات حركة الصندوق'));
    }

    final cf = _cashFlow!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(RafSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TreasuryAccountsCard(snapshot: cf.accounts, showFlows: true),
          Container(
            padding: const EdgeInsets.all(RafSpacing.lg),
            decoration: BoxDecoration(
              color: RafColors.surface,
              borderRadius: RafRadius.roundedMd,
              border: Border.all(color: RafColors.border),
              boxShadow: RafShadows.subtle,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow =
                        constraints.maxWidth < 340 ||
                        MediaQuery.textScalerOf(context).scale(1.0) > 1.15;

                    final badge = Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: RafColors.primarySubtle,
                        borderRadius: RafRadius.roundedPill,
                      ),
                      child: const Text(
                        'الشهر الحالي',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: RafColors.primary,
                        ),
                      ),
                    );

                    final title = Text(
                      'كشف السيولة والتدفق النقدي للخزينة',
                      style: RafTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [badge],
                          ),
                          const SizedBox(height: RafSpacing.xs),
                          title,
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: RafSpacing.sm),
                        badge,
                      ],
                    );
                  },
                ),
                const SizedBox(height: RafSpacing.md),
                const Divider(height: 1, color: RafColors.border),
                const SizedBox(height: RafSpacing.md),

                // Cash Flow Metrics
                _buildMetricTile(
                  title: 'إجمالي المقبوضات',
                  amount: '+ ${CurrencyFormatter.format(cf.totalReceipts)}',
                  color: RafColors.success,
                  subtitle: 'دفعات الفواتير وسندات القبض في جميع الحسابات',
                ),
                const SizedBox(height: RafSpacing.sm),
                _buildMetricTile(
                  title: 'إجمالي المدفوعات',
                  amount: '- ${CurrencyFormatter.format(cf.totalPayments)}',
                  color: RafColors.danger,
                  subtitle:
                      'دفعات الفواتير وسندات الصرف والمصروفات في جميع الحسابات',
                ),
                const SizedBox(height: RafSpacing.sm),
                _buildMetricTile(
                  title: 'صافي التدفق النقدي للفترة',
                  amount: CurrencyFormatter.format(cf.netCashFlow),
                  color: cf.netCashFlow.isNegative
                      ? RafColors.danger
                      : RafColors.primary,
                  subtitle: 'المقبوضات - المدفوعات',
                ),
                const SizedBox(height: RafSpacing.md),
                const Divider(height: 1, color: RafColors.border),
                const SizedBox(height: RafSpacing.md),

                // Current Total Treasury Balance
                Container(
                  padding: const EdgeInsets.all(RafSpacing.md),
                  decoration: BoxDecoration(
                    color: RafColors.surfaceSecondary,
                    borderRadius: RafRadius.roundedSm,
                    border: Border.all(color: RafColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إجمالي الأرصدة التراكمي',
                              style: RafTypography.bodySmall.copyWith(
                                color: RafColors.textSecondary,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                CurrencyFormatter.format(
                                  cf.currentTreasuryBalance,
                                ),
                                style: RafTypography.financialHero.copyWith(
                                  fontSize: 22,
                                  color: cf.currentTreasuryBalance.isNegative
                                      ? RafColors.danger
                                      : RafColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: RafSpacing.sm),
                      const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 32,
                        color: RafColors.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String amount,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(RafSpacing.md),
      decoration: BoxDecoration(
        color: RafColors.surfaceSecondary,
        borderRadius: RafRadius.roundedSm,
        border: Border.all(color: RafColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: RafTypography.bodySmall.copyWith(
              color: RafColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              amount,
              style: RafTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: RafTypography.labelSmall.copyWith(
              color: RafColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
