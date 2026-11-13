import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../models/item_model.dart';

/// Clean visual stock status indicator badge following the RAF design tokens.
class StockBadge extends StatelessWidget {
  final ItemModel item;
  final String? unitSymbol;
  final DateTime? referenceDate;

  const StockBadge({
    super.key,
    required this.item,
    this.unitSymbol,
    this.referenceDate,
  });

  @override
  Widget build(BuildContext context) {
    final String label;
    final BoxDecoration decoration;
    final Color textColor;
    final IconData icon;

    final String unitText = unitSymbol != null ? ' $unitSymbol' : '';

    if (item.isExpiredAt(referenceDate)) {
      label = 'منتهي الصلاحية';
      decoration = RafDecorations.badgeDanger;
      textColor = RafColors.danger;
      icon = Icons.error_outline;
    } else if (item.isOutOfStock) {
      label = 'نفد المخزون';
      decoration = RafDecorations.badgeDanger;
      textColor = RafColors.danger;
      icon = Icons.highlight_off;
    } else if (item.isLowStock) {
      label = 'منخفض (${item.stockQuantity}$unitText)';
      decoration = RafDecorations.badgeWarning;
      textColor = RafColors.warning;
      icon = Icons.warning_amber_rounded;
    } else {
      label = '${item.stockQuantity}$unitText';
      decoration = RafDecorations.badgeSuccess;
      textColor = RafColors.success;
      icon = Icons.check_circle_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RafSpacing.sm + 2,
        vertical: RafSpacing.xs,
      ),
      decoration: decoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: RafSpacing.xs),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: RafTypography.fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}
