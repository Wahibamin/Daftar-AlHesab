import 'package:flutter/material.dart';
import '../../../core/database/business_data_wiper.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../accounting/pages/voucher_editor_page.dart';
import '../../accounting/pages/vouchers_list_page.dart';
import '../../accounting/repositories/vouchers_repository.dart';
import '../../inventory/pages/item_editor_page.dart';
import '../../inventory/repositories/inventory_repository.dart';
import '../../parties/pages/parties_page.dart';
import '../../parties/repositories/parties_repository.dart';
import '../../reports/repositories/reports_repository.dart';
import '../../sales/models/invoice_model.dart';
import '../../sales/pages/invoice_editor_page.dart';
import '../../sales/repositories/invoices_repository.dart';
import '../../settings/pages/store_settings_page.dart';
import '../widgets/metric_card.dart';
import '../widgets/quick_action_button.dart';

/// Clean White Executive Dashboard Page displaying real-time financial health,
/// key performance indicators, quick shortcuts, and weekly sales trends.
class DashboardPage extends StatefulWidget {
  final ReportsRepository reportsRepo;
  final InvoicesRepository invoicesRepo;
  final InventoryRepository inventoryRepo;
  final PartiesRepository partiesRepo;
  final VouchersRepository vouchersRepo;

  DashboardPage({
    super.key,
    ReportsRepository? reportsRepo,
    InvoicesRepository? invoicesRepo,
    InventoryRepository? inventoryRepo,
    PartiesRepository? partiesRepo,
    VouchersRepository? vouchersRepo,
  }) : reportsRepo = reportsRepo ?? SqliteReportsRepository(),
       invoicesRepo = invoicesRepo ?? SqliteInvoicesRepository(),
       inventoryRepo = inventoryRepo ?? SqliteInventoryRepository(),
       partiesRepo = partiesRepo ?? SqlitePartiesRepository(),
       vouchersRepo = vouchersRepo ?? SqliteVouchersRepository();

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DashboardMetricsModel _metrics = DashboardMetricsModel.zero;
  List<DailySalesPoint> _trend = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    BusinessDataNotifier.instance.addListener(_loadDashboardData);
    _loadDashboardData();
  }

  @override
  void dispose() {
    BusinessDataNotifier.instance.removeListener(_loadDashboardData);
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final metrics = await widget.reportsRepo.getDashboardMetrics();
      final trend = await widget.reportsRepo.getWeeklySalesTrend();

      if (mounted) {
        setState(() {
          _metrics = metrics;
          _trend = trend;
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'لوحة التحكم التنفيذية',
              style: RafTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'دفتر الحساب لإدارة المبيعات والمخزون',
              style: RafTypography.bodySmall.copyWith(
                color: RafColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        backgroundColor: RafColors.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.settings_outlined,
              color: RafColors.textSecondary,
            ),
            tooltip: 'إعدادات المنشأة',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StoreSettingsPage()),
              );
              if (mounted) _loadDashboardData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: RafColors.textSecondary),
            tooltip: 'تحديث البيانات',
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: RafColors.primary),
            )
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              color: RafColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(RafSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Quick Shortcuts Bar
                    _buildSectionHeader('إجراءات سريعة'),
                    const SizedBox(height: RafSpacing.xs),
                    _buildQuickActionsRow(),
                    const SizedBox(height: RafSpacing.sm),
                    OutlinedButton.icon(
                      key: const Key('open_treasury_vouchers'),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('السندات والخزينة'),
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => VouchersListPage(
                              vouchersRepo: widget.vouchersRepo,
                              partiesRepo: widget.partiesRepo,
                            ),
                          ),
                        );
                        if (mounted) await _loadDashboardData();
                      },
                    ),

                    const SizedBox(height: RafSpacing.lg),

                    // 2. Main Executive Financial Metrics
                    _buildSectionHeader('المؤشرات المالية والمخزون'),
                    const SizedBox(height: RafSpacing.xs),
                    _buildMetricsGrid(),

                    const SizedBox(height: RafSpacing.lg),

                    // 3. Weekly Sales Trend Chart
                    _buildSectionHeader('حركة المبيعات (آخر 7 أيام)'),
                    const SizedBox(height: RafSpacing.xs),
                    _buildWeeklyTrendCard(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: RafTypography.titleSmall.copyWith(
        fontWeight: FontWeight.w700,
        color: RafColors.textPrimary,
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 600 ? 2 : 4;
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final childAspectRatio = (textScale > 1.2 || constraints.maxWidth < 360)
            ? 1.85
            : 2.4;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: RafSpacing.sm,
          crossAxisSpacing: RafSpacing.sm,
          childAspectRatio: childAspectRatio,
          children: [
            QuickActionButton(
              label: 'فاتورة جديدة',
              icon: Icons.add_shopping_cart_rounded,
              color: RafColors.primary,
              onTap: () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InvoiceEditorPage(
                      invoicesRepo: widget.invoicesRepo,
                      inventoryRepo: widget.inventoryRepo,
                      partiesRepo: widget.partiesRepo,
                      initialType: InvoiceType.sale,
                    ),
                  ),
                );
                if (result == true) _loadDashboardData();
              },
            ),
            QuickActionButton(
              label: 'سند قبض',
              icon: Icons.call_received_rounded,
              color: RafColors.success,
              onTap: () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VoucherEditorPage(
                      vouchersRepo: widget.vouchersRepo,
                      partiesRepo: widget.partiesRepo,
                    ),
                  ),
                );
                if (result == true) _loadDashboardData();
              },
            ),
            QuickActionButton(
              label: 'إضافة صنف',
              icon: Icons.inventory_2_outlined,
              color: const Color(0xFF2563EB),
              onTap: () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ItemEditorPage(repository: widget.inventoryRepo),
                  ),
                );
                if (result == true) _loadDashboardData();
              },
            ),
            QuickActionButton(
              label: 'الأطراف والديون',
              icon: Icons.people_outline_rounded,
              color: RafColors.warning,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PartiesPage(repository: widget.partiesRepo),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 600 ? 2 : 3;
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final metricAspectRatio = (textScale >= 1.5)
            ? 1.05
            : (textScale >= 1.2 || constraints.maxWidth < 360)
            ? 1.25
            : 1.45;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: RafSpacing.sm,
          crossAxisSpacing: RafSpacing.sm,
          childAspectRatio: metricAspectRatio,
          children: [
            MetricCard(
              title: 'مبيعات اليوم',
              value: CurrencyFormatter.format(_metrics.todaySales),
              icon: Icons.today_rounded,
              accentColor: RafColors.primary,
              subtitle: '${_metrics.totalInvoicesToday} فواتير معتمدة',
            ),
            MetricCard(
              title: 'مبيعات الشهر',
              value: CurrencyFormatter.format(_metrics.monthSales),
              icon: Icons.calendar_month_rounded,
              accentColor: const Color(0xFF2563EB),
              subtitle: 'الشهر الحالي',
            ),
            MetricCard(
              title: 'صافي الربح التقديري',
              value: CurrencyFormatter.format(_metrics.estimatedNetProfit),
              icon: Icons.trending_up_rounded,
              accentColor: _metrics.estimatedNetProfit.isNegative
                  ? RafColors.danger
                  : RafColors.success,
              subtitle: 'المبيعات - التكلفة - المصروفات',
            ),
            MetricCard(
              title: 'ديون العملاء (لنا)',
              value: CurrencyFormatter.format(_metrics.totalReceivables),
              icon: Icons.arrow_downward_rounded,
              accentColor: RafColors.warning,
              subtitle: 'مستحقات آجلة طرف العملاء',
            ),
            MetricCard(
              title: 'مستحقات الموردين (علينا)',
              value: CurrencyFormatter.format(_metrics.totalPayables),
              icon: Icons.arrow_upward_rounded,
              accentColor: RafColors.danger,
              subtitle: 'التزامات آجلة للموردين',
            ),
            MetricCard(
              title: 'تنبيهات المخزون',
              value: '${_metrics.lowStockCount} أصناف',
              icon: Icons.warning_amber_rounded,
              accentColor: _metrics.lowStockCount > 0
                  ? RafColors.danger
                  : RafColors.success,
              subtitle: _metrics.lowStockCount > 0
                  ? 'وصلت لحد إعادة الطلب'
                  : 'المخزون متوازن',
            ),
          ],
        );
      },
    );
  }

  Widget _buildWeeklyTrendCard() {
    if (_trend.isEmpty) return const SizedBox.shrink();

    // Determine max sales for normalized bar scaling
    int maxAmount = 1;
    for (final point in _trend) {
      if (point.amount.rawUnits > maxAmount) {
        maxAmount = point.amount.rawUnits;
      }
    }

    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final chartHeight = (120 * textScale).clamp(120.0, 160.0);

    return Container(
      padding: const EdgeInsets.all(RafSpacing.md),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'الرسم البياني اليومي للمبيعات',
                  style: RafTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: RafColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: RafSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: RafColors.primarySubtle,
                  borderRadius: RafRadius.roundedXs,
                ),
                child: const Text(
                  'أسبوعي',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: RafColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: RafSpacing.lg),

          // Bars Row
          SizedBox(
            height: chartHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _trend.map((point) {
                final ratio = maxAmount > 0
                    ? (point.amount.rawUnits / maxAmount)
                    : 0.0;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            point.amount.isZero
                                ? '0'
                                : CurrencyFormatter.format(
                                    point.amount,
                                    includeSymbol: false,
                                  ),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: RafColors.textSecondary,
                            ),
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: ratio.clamp(0.06, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: point.amount.isZero
                                      ? RafColors.surfaceSecondary
                                      : RafColors.primary,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            point.dayName,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: RafColors.textMuted,
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
