import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../models/party_model.dart';
import '../models/statement_model.dart';
import '../repositories/parties_repository.dart';
import '../services/communication_service.dart';
import '../widgets/balance_badge.dart';

/// Screen displaying a detailed statement of account for a customer or supplier.
class AccountStatementPage extends StatefulWidget {
  final PartyModel party;
  final PartiesRepository? repository;
  final PartyStatementSummary? initialSummary;

  const AccountStatementPage({
    super.key,
    required this.party,
    this.repository,
    this.initialSummary,
  });

  @override
  State<AccountStatementPage> createState() => _AccountStatementPageState();
}

class _AccountStatementPageState extends State<AccountStatementPage> {
  late final PartiesRepository _repo;
  PartyStatementSummary? _summary;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? SqlitePartiesRepository();
    if (widget.initialSummary != null) {
      _summary = widget.initialSummary;
      _isLoading = false;
    } else {
      _loadStatement();
    }
  }

  Future<void> _loadStatement() async {
    setState(() => _isLoading = true);
    try {
      final summary = await _repo.getAccountStatement(widget.party.id!);
      if (mounted) {
        setState(() {
          _summary = summary;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _shareViaWhatsApp() {
    final msg = CommunicationService.formatBalanceMessage(
      partyName: widget.party.name,
      balance: _summary?.currentBalance ?? widget.party.currentBalance,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'معاينة فقط؛ مشاركة واتساب غير منفذة في هذه النسخة:\n$msg',
        ),
        backgroundColor: RafColors.secondary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatArabicDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final party = _summary?.party ?? widget.party;
    final currentBal = _summary?.currentBalance ?? party.currentBalance;
    final totalDebit = _summary?.totalDebit.format() ?? '0.00';
    final totalCredit = _summary?.totalCredit.format() ?? '0.00';
    final entries = _summary?.entries ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('كشف حساب الطرف'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'مشاركة كشف الحساب عبر واتساب',
            onPressed: _shareViaWhatsApp,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: _loadStatement,
          ),
          const SizedBox(width: RafSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: RafColors.primary),
              )
            : RefreshIndicator(
                color: RafColors.primary,
                onRefresh: _loadStatement,
                child: ListView(
                  padding: const EdgeInsets.all(RafSpacing.md),
                  children: [
                    // 1. Party Info Banner Card
                    Container(
                      padding: const EdgeInsets.all(RafSpacing.md),
                      decoration: RafDecorations.cardFlat,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  party.name,
                                  style: RafTypography.titleLarge.copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: RafSpacing.xs),
                                Text(
                                  'جوال: ${PhoneNumberFormatter.formatSaudi(party.phone)}',
                                  style: RafTypography.bodySecondary,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: RafSpacing.xs),
                          Flexible(child: BalanceBadge(party: party)),
                        ],
                      ),
                    ),

                    const SizedBox(height: RafSpacing.md),

                    // 2. Financial Overview Cards (Adaptive layout)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final textScale = MediaQuery.textScalerOf(
                          context,
                        ).scale(1.0);
                        final isNarrow =
                            constraints.maxWidth < 360 || textScale > 1.2;

                        final currentBalanceCard = Container(
                          padding: const EdgeInsets.all(RafSpacing.md),
                          decoration: BoxDecoration(
                            color: party.isDebtor
                                ? RafColors.dangerSubtle
                                : party.isCreditor
                                ? RafColors.successSubtle
                                : RafColors.surfaceSecondary,
                            borderRadius: RafRadius.roundedMd,
                            border: Border.all(
                              color: party.isDebtor
                                  ? RafColors.dangerBorder
                                  : party.isCreditor
                                  ? RafColors.successBorder
                                  : RafColors.border,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'الرصيد الحالي',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: RafColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  currentBal.abs.format(),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: RafTypography.fontFamily,
                                    color: party.isDebtor
                                        ? RafColors.danger
                                        : party.isCreditor
                                        ? RafColors.success
                                        : RafColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );

                        final totalDebitsCard = Container(
                          padding: const EdgeInsets.all(RafSpacing.md),
                          decoration: RafDecorations.panelSecondary,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'إجمالي المدين',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: RafColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  totalDebit,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: RafColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );

                        final totalCreditsCard = Container(
                          padding: const EdgeInsets.all(RafSpacing.md),
                          decoration: RafDecorations.panelSecondary,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'إجمالي الدائن',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: RafColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  totalCredit,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: RafColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );

                        if (isNarrow) {
                          return Column(
                            children: [
                              currentBalanceCard,
                              const SizedBox(height: RafSpacing.sm),
                              Row(
                                children: [
                                  Expanded(child: totalDebitsCard),
                                  const SizedBox(width: RafSpacing.sm),
                                  Expanded(child: totalCreditsCard),
                                ],
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: currentBalanceCard),
                            const SizedBox(width: RafSpacing.sm),
                            Expanded(child: totalDebitsCard),
                            const SizedBox(width: RafSpacing.sm),
                            Expanded(child: totalCreditsCard),
                          ],
                        );
                      },
                    ),

                    if (!party.creditLimit.isZero) ...[
                      const SizedBox(height: RafSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: RafSpacing.md,
                          vertical: RafSpacing.sm,
                        ),
                        decoration: RafDecorations.cardFlat,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'سقف الائتمان: ${party.creditLimit.format()}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: RafColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: RafSpacing.xs),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'المتاح: ${party.remainingCreditAvailable.format()}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: party.exceedsCreditLimit
                                        ? RafColors.danger
                                        : RafColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: RafSpacing.lg),

                    // 3. Transactions Section Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Flexible(
                          child: Text(
                            'سجل الحركات التاريخية',
                            style: RafTypography.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: RafSpacing.sm),
                        Text(
                          '${entries.length} حركة',
                          style: RafTypography.bodySecondary,
                        ),
                      ],
                    ),

                    const SizedBox(height: RafSpacing.sm),

                    // 4. Movements List or Empty State
                    if (entries.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(RafSpacing.xl),
                        decoration: RafDecorations.cardFlat,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 48,
                              color: RafColors.borderStrong,
                            ),
                            const SizedBox(height: RafSpacing.sm),
                            const Text(
                              'لا توجد حركات مسجلة على هذا الحساب بعد',
                              style: RafTypography.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'ستظهر هنا فواتير المبيعات وسندات القبض والصرف تلقائياً',
                              style: RafTypography.bodySecondary,
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        decoration: RafDecorations.cardFlat,
                        child: ClipRRect(
                          borderRadius: RafRadius.roundedMd,
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: entries.length,
                            separatorBuilder: (context, index) => const Divider(
                              height: 1,
                              color: RafColors.border,
                            ),
                            itemBuilder: (context, index) {
                              final item = entries[index];
                              return Padding(
                                padding: const EdgeInsets.all(RafSpacing.md),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Transaction Date Box
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: RafColors.surfaceSecondary,
                                        borderRadius: RafRadius.roundedSm,
                                        border: Border.all(
                                          color: RafColors.border,
                                        ),
                                      ),
                                      child: Text(
                                        _formatArabicDate(item.date),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: RafColors.textSecondary,
                                        ),
                                      ),
                                    ),

                                    const SizedBox(width: RafSpacing.md),

                                    // Statement & Type
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.statement,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: RafColors.textPrimary,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            item.transactionType,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: RafColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(width: RafSpacing.xs),

                                    // Amount & Cumulative Balance
                                    Flexible(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          if (item.debit.isPositive)
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                '- ${item.debit.format()}',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: RafColors.danger,
                                                ),
                                              ),
                                            )
                                          else if (item.credit.isPositive)
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                '+ ${item.credit.format()}',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: RafColors.success,
                                                ),
                                              ),
                                            ),
                                          const SizedBox(height: 2),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'الرصيد: ${item.runningBalance.abs.format()}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: RafColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
