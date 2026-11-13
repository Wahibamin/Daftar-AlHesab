import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../repositories/reports_repository.dart';
import '../services/pdf_report_service.dart';

/// Detailed Profit and Loss (P&L) financial statement page.
class ProfitLossPage extends StatefulWidget {
  final ReportsRepository reportsRepo;

  ProfitLossPage({super.key, ReportsRepository? reportsRepo})
    : reportsRepo = reportsRepo ?? SqliteReportsRepository();

  @override
  State<ProfitLossPage> createState() => _ProfitLossPageState();
}

class _ProfitLossPageState extends State<ProfitLossPage> {
  late DateTime _startDate;
  late DateTime _endDate;
  int _selectedFilterIndex = 2; // 0: Today, 1: Week, 2: Month, 3: Custom

  ProfitLossReportModel? _report;
  bool _isLoading = true;
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    _applyDateFilter(_selectedFilterIndex);
  }

  void _applyDateFilter(int index) {
    final now = DateTime.now();
    _selectedFilterIndex = index;

    switch (index) {
      case 0: // Today
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 1: // This week (last 7 days)
        _startDate = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6));
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 2: // This month
      default:
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
    }

    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);
    try {
      final report = await widget.reportsRepo.getProfitLossReport(
        startDate: _startDate,
        endDate: _endDate,
      );
      if (mounted) {
        setState(() {
          _report = report;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_report == null) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final bytes = await PdfReportService.generateProfitLossPdf(
        report: _report!,
      );
      await PdfReportService.printOrSharePdf(
        pdfBytes: bytes,
        documentName: 'Profit_Loss_${DateFormatter.formatDate(_startDate)}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تصدير التقرير: $e'),
            backgroundColor: RafColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RafColors.surfaceSecondary,
      appBar: AppBar(
        title: Text(
          'قائمة الأرباح والخسائر (P&L)',
          style: RafTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: RafColors.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isGeneratingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: RafColors.primary,
                    ),
                  )
                : const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: RafColors.primary,
                  ),
            tooltip: 'تصدير وطباعة PDF',
            onPressed: _isGeneratingPdf ? null : _exportPdf,
          ),
        ],
      ),
      body: Column(
        children: [
          // Period Filter Selector Chips
          Container(
            color: RafColors.surface,
            padding: const EdgeInsets.symmetric(
              horizontal: RafSpacing.md,
              vertical: RafSpacing.sm,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPeriodChip('اليوم', 0),
                  _buildPeriodChip('آخر 7 أيام', 1),
                  _buildPeriodChip('الشهر الحالي', 2),
                ],
              ),
            ),
          ),

          const Divider(height: 1, color: RafColors.border),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: RafColors.primary),
                  )
                : _report == null
                ? const Center(child: Text('لا تتوفر بيانات للفترة المحددة'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(RafSpacing.md),
                    child: Column(
                      children: [
                        // 1. Revenues Card
                        _buildPnlCard(
                          title: '1. إيرادات المبيعات الصافية',
                          amount: CurrencyFormatter.format(
                            _report!.totalRevenues,
                          ),
                          subtitle:
                              'إجمالي المبيعات المعتمدة بعد خصم المرتجعات',
                          color: RafColors.primary,
                          icon: Icons.trending_up_rounded,
                        ),

                        const SizedBox(height: RafSpacing.sm),

                        // 2. Cost of Goods Sold Card
                        _buildPnlCard(
                          title: '2. تكلفة البضاعة المباعة (COGS)',
                          amount:
                              '- ${CurrencyFormatter.format(_report!.costOfGoodsSold)}',
                          subtitle:
                              'التكلفة الإجمالية للأصناف المباعة بسعر الشراء',
                          color: RafColors.textSecondary,
                          icon: Icons.inventory_2_outlined,
                        ),

                        const SizedBox(height: RafSpacing.sm),

                        // 3. Gross Profit Card
                        _buildPnlCard(
                          title: '3. مجمل الربح التجاري (Gross Profit)',
                          amount: CurrencyFormatter.format(
                            _report!.grossProfit,
                          ),
                          subtitle:
                              'هامش مجمل الربح: ${_report!.grossProfitMarginPercent}%',
                          color: _report!.grossProfit.isNegative
                              ? RafColors.danger
                              : const Color(0xFF2563EB),
                          icon: Icons.account_balance_wallet_outlined,
                          isHighlighted: true,
                        ),

                        const SizedBox(height: RafSpacing.sm),

                        // 4. Operating Expenses Card
                        _buildPnlCard(
                          title: '4. المصروفات التشغيلية والعمومية',
                          amount:
                              '- ${CurrencyFormatter.format(_report!.operatingExpenses)}',
                          subtitle: 'سندات الصرف والمصروفات العامة خلال الفترة',
                          color: RafColors.danger,
                          icon: Icons.money_off_rounded,
                        ),

                        const SizedBox(height: RafSpacing.md),

                        // 5. Net Profit Hero Card
                        _buildNetProfitHeroCard(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String label, int index) {
    final isSelected = _selectedFilterIndex == index;
    return Padding(
      padding: const EdgeInsets.only(left: RafSpacing.xs),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => _applyDateFilter(index),
        selectedColor: RafColors.primarySubtle,
        backgroundColor: RafColors.surfaceSecondary,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? RafColors.primary : RafColors.textSecondary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: RafRadius.roundedSm,
          side: BorderSide(
            color: isSelected ? RafColors.primary : RafColors.border,
          ),
        ),
      ),
    );
  }

  Widget _buildPnlCard({
    required String title,
    required String amount,
    required String subtitle,
    required Color color,
    required IconData icon,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(RafSpacing.md),
      decoration: BoxDecoration(
        color: isHighlighted
            ? color.withValues(alpha: 0.04)
            : RafColors.surface,
        borderRadius: RafRadius.roundedMd,
        border: Border.all(
          color: isHighlighted
              ? color.withValues(alpha: 0.4)
              : RafColors.border,
        ),
        boxShadow: RafShadows.subtle,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: RafRadius.roundedSm,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: RafSpacing.md),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: RafTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: RafTypography.bodySmall.copyWith(
                    color: RafColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: RafSpacing.xs),
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                amount,
                style: RafTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetProfitHeroCard() {
    final netProfit = _report!.netProfit;
    final isProfitable = !netProfit.isNegative;
    final color = isProfitable ? RafColors.success : RafColors.danger;

    return Container(
      padding: const EdgeInsets.all(RafSpacing.lg),
      decoration: BoxDecoration(
        color: RafColors.surface,
        borderRadius: RafRadius.roundedMd,
        border: Border.all(color: color, width: 1.5),
        boxShadow: RafShadows.elevated,
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1.0);
              final isNarrow = constraints.maxWidth < 280 || textScale > 1.2;

              final marginBadge = Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: RafRadius.roundedPill,
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'هامش الصافي: ${_report!.netProfitMarginPercent}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              );

              final titleRow = Row(
                children: [
                  Icon(
                    isProfitable
                        ? Icons.verified_rounded
                        : Icons.warning_rounded,
                    color: color,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'صافي الربح (Net Profit)',
                      style: RafTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: RafColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [titleRow, const SizedBox(height: 8), marginBadge],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: titleRow),
                  const SizedBox(width: 8),
                  Flexible(child: marginBadge),
                ],
              );
            },
          ),
          const SizedBox(height: RafSpacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              CurrencyFormatter.format(netProfit),
              style: RafTypography.financialHero.copyWith(
                fontSize: 32,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: RafSpacing.xs),
          Text(
            isProfitable
                ? 'تحقق للمنشأة فائض ربحي تشغيلي صافي خلال الفترة المحددة'
                : 'تسجل المنشأة عجزاً أو خسارة تشغيلية صافية خلال الفترة المحددة',
            style: RafTypography.bodySmall.copyWith(color: RafColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
