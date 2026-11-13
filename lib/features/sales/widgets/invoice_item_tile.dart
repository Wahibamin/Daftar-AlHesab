import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../models/invoice_model.dart';

/// Clean, horizontal white card tile representing a single line item within an invoice/POS.
class InvoiceItemTile extends StatelessWidget {
  final InvoiceItemModel item;
  final String itemName;
  final String? itemUnit;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  const InvoiceItemTile({
    super.key,
    required this.item,
    required this.itemName,
    this.itemUnit,
    this.onIncrement,
    this.onDecrement,
    this.onRemove,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: RafSpacing.sm),
      decoration: BoxDecoration(
        color: RafColors.surface,
        borderRadius: RafRadius.roundedMd,
        border: Border.all(color: RafColors.border),
        boxShadow: RafShadows.subtle,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: RafRadius.roundedMd,
        child: InkWell(
          borderRadius: RafRadius.roundedMd,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RafSpacing.md,
              vertical: RafSpacing.sm + 2,
            ),
            child: Row(
              children: [
                // 1. Item Name and Unit Price Column
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        itemName,
                        style: RafTypography.bodyLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          color: RafColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: RafSpacing.xxs),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${CurrencyFormatter.format(item.unitPrice)} ${itemUnit != null ? '/ $itemUnit' : ''}',
                              style: RafTypography.bodySmall.copyWith(
                                color: RafColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!item.discount.isZero) ...[
                            const SizedBox(width: RafSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: RafColors.dangerSubtle,
                                borderRadius: RafRadius.roundedXs,
                                border: Border.all(
                                  color: RafColors.dangerBorder,
                                ),
                              ),
                              child: Text(
                                'خصم: ${CurrencyFormatter.format(item.discount)}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: RafColors.danger,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: RafSpacing.sm),

                // 2. Quantity Counter Controls (- QTY +)
                Container(
                  decoration: BoxDecoration(
                    color: RafColors.surfaceSecondary,
                    borderRadius: RafRadius.roundedSm,
                    border: Border.all(color: RafColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildQuantityButton(
                        icon: Icons.remove,
                        onPressed: onDecrement,
                        tooltip: 'تقليل الكمية',
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: RafSpacing.sm,
                        ),
                        child: Text(
                          '${item.quantity}',
                          style: RafTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: RafColors.textPrimary,
                          ),
                        ),
                      ),
                      _buildQuantityButton(
                        icon: Icons.add,
                        onPressed: onIncrement,
                        tooltip: 'زيادة الكمية',
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: RafSpacing.md),

                // 3. Line Total Amount
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          CurrencyFormatter.format(item.totalPrice),
                          style: RafTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w800,
                            color: RafColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: RafSpacing.xs),

                // 4. Delete Action Button
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    color: RafColors.textMuted,
                    hoverColor: RafColors.dangerSubtle,
                    highlightColor: RafColors.dangerSubtle,
                    splashRadius: 18,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    tooltip: 'حذف البند',
                    onPressed: onRemove,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuantityButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: RafRadius.roundedSm,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Icon(
            icon,
            size: 16,
            color: onPressed != null
                ? RafColors.textPrimary
                : RafColors.textMuted,
          ),
        ),
      ),
    );
  }
}
