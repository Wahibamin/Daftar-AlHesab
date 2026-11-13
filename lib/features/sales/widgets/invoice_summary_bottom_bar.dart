import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/money.dart';

/// Clean, floating summary bar at the bottom of the invoice/POS editor.
class InvoiceSummaryBottomBar extends StatelessWidget {
  final Money subtotal;
  final Money discount;
  final Money netTotal;
  final int itemCount;
  final VoidCallback? onFinalize;
  final VoidCallback? onSaveDraft;
  final VoidCallback? onEditDiscount;
  final bool isProcessing;
  final bool isReadOnly;

  const InvoiceSummaryBottomBar({
    super.key,
    required this.subtotal,
    required this.discount,
    required this.netTotal,
    this.itemCount = 0,
    this.onFinalize,
    this.onSaveDraft,
    this.onEditDiscount,
    this.isProcessing = false,
    this.isReadOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final isShort = MediaQuery.sizeOf(context).height < 650;

    return Container(
      decoration: BoxDecoration(
        color: RafColors.surface,
        border: const Border(
          top: BorderSide(color: RafColors.border, width: 1.5),
        ),
        boxShadow: RafShadows.elevated,
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: RafSpacing.md,
              vertical: isShort ? RafSpacing.xs + 2 : RafSpacing.sm + 2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Row 1: Detailed breakdown (Subtotal, Discount)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('المجموع', style: RafTypography.bodySmall),
                          Text(
                            CurrencyFormatter.format(subtotal),
                            style: RafTypography.bodySmall.copyWith(
                              fontWeight: FontWeight.w700,
                              color: RafColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (!discount.isZero || onEditDiscount != null)
                      Expanded(
                        child: InkWell(
                          key: const Key('edit_discount_button'),
                          onTap: isReadOnly ? null : onEditDiscount,
                          borderRadius: RafRadius.roundedXs,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'الخصم',
                                style: RafTypography.bodySmall.copyWith(
                                  color: RafColors.danger,
                                ),
                              ),
                              Text(
                                '-${CurrencyFormatter.format(discount)}',
                                style: RafTypography.bodySmall.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: RafColors.danger,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: RafSpacing.xs),
                  child: Divider(color: RafColors.border, height: 1),
                ),

                // Row 2: Net Total and Action Buttons (Adaptive layout)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final textScale = MediaQuery.textScalerOf(
                      context,
                    ).scale(1.0);
                    final isNarrow =
                        constraints.maxWidth < 480 || textScale > 1.1;

                    final netTotalDisplay = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'الصافي النهائي',
                                style: RafTypography.bodySmall.copyWith(
                                  color: RafColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (itemCount > 0) ...[
                              const SizedBox(width: RafSpacing.xs),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: RafColors.surfaceSecondary,
                                  borderRadius: RafRadius.roundedPill,
                                  border: Border.all(color: RafColors.border),
                                ),
                                child: Text(
                                  '$itemCount بنود',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: RafColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            CurrencyFormatter.format(netTotal),
                            style: RafTypography.titleLarge.copyWith(
                              fontWeight: FontWeight.w900,
                              color: RafColors.primary,
                            ),
                          ),
                        ),
                      ],
                    );

                    final actionButtons = <Widget>[
                      if (!isReadOnly) ...[
                        if (onSaveDraft != null)
                          OutlinedButton(
                            onPressed: isProcessing ? null : onSaveDraft,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: RafColors.textSecondary,
                              side: const BorderSide(
                                color: RafColors.borderStrong,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: RafSpacing.md,
                                vertical: RafSpacing.sm + 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: RafRadius.roundedMd,
                              ),
                            ),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('مسودة'),
                            ),
                          ),
                        ElevatedButton.icon(
                          onPressed: isProcessing || itemCount == 0
                              ? null
                              : onFinalize,
                          icon: isProcessing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 18,
                                ),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              isProcessing
                                  ? 'جاري الترحيل...'
                                  : 'اعتماد وترحيل',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: RafColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: RafSpacing.md,
                              vertical: RafSpacing.sm + 2,
                            ),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: RafRadius.roundedMd,
                            ),
                          ),
                        ),
                      ],
                    ];

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          netTotalDisplay,
                          if (actionButtons.isNotEmpty) ...[
                            const SizedBox(height: RafSpacing.sm),
                            Row(
                              children: [
                                for (
                                  int i = 0;
                                  i < actionButtons.length;
                                  i++
                                ) ...[
                                  if (i > 0)
                                    const SizedBox(width: RafSpacing.sm),
                                  Expanded(
                                    flex: (i == 0 && actionButtons.length > 1)
                                        ? 2
                                        : 3,
                                    child: actionButtons[i],
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: netTotalDisplay),
                        const SizedBox(width: RafSpacing.md),
                        for (int i = 0; i < actionButtons.length; i++) ...[
                          if (i > 0) const SizedBox(width: RafSpacing.sm),
                          actionButtons[i],
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
