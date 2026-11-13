import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../models/item_model.dart';

/// Clean visual expiry status indicator badge showing remaining duration.
///
/// Follows strict calendar day difference rules:
/// - null expiry date: does not render (returns SizedBox.shrink).
/// - past date (< 0 days): "منتهي الصلاحية" with red styling.
/// - 0 to 30 days: red styling with warning icon.
/// - 31 to 60 days: amber/yellow styling.
/// - > 60 days: natural/neutral styling.
class ExpiryBadge extends StatelessWidget {
  final DateTime? expiryDate;
  final DateTime? referenceDate;

  const ExpiryBadge({super.key, required this.expiryDate, this.referenceDate});

  /// Computes remaining calendar days ignoring time of day.
  static int? calculateRemainingDays(DateTime? expiry, [DateTime? reference]) {
    return ItemModel.calendarExpiryDays(expiry, reference);
  }

  /// Formats remaining days into natural Arabic phrasing as specified:
  /// - past (< 0): "منتهي الصلاحية"
  /// - 0: "ينتهي اليوم"
  /// - 1: "باقي يوم واحد"
  /// - 2: "باقي يومين"
  /// - 3..10: "باقي $days أيام"
  /// - > 10: "باقي $days يومًا"
  static String formatRemainingDaysText(int days) {
    if (days < 0) return 'منتهي الصلاحية';
    if (days == 0) return 'ينتهي اليوم';
    if (days == 1) return 'باقي يوم واحد';
    if (days == 2) return 'باقي يومين';
    if (days >= 3 && days <= 10) return 'باقي $days أيام';
    return 'باقي $days يومًا';
  }

  @override
  Widget build(BuildContext context) {
    if (expiryDate == null) {
      return const SizedBox.shrink();
    }

    final days = calculateRemainingDays(expiryDate, referenceDate)!;

    final String label = formatRemainingDaysText(days);
    final Color textColor;
    final Color bgColor;
    final Color borderColor;
    final IconData icon;

    if (days < 0) {
      // Past date: "منتهي الصلاحية" with red message
      textColor = RafColors.danger;
      bgColor = RafColors.dangerSubtle;
      borderColor = RafColors.dangerBorder;
      icon = Icons.error_outline;
    } else if (days <= 30) {
      // 0 to 30 days: red (urgent warning)
      textColor = RafColors.danger;
      bgColor = RafColors.dangerSubtle;
      borderColor = RafColors.dangerBorder;
      icon = Icons.access_time_rounded;
    } else if (days <= 60) {
      // 31 to 60 days: yellow / amber (warning)
      textColor = RafColors.warning;
      bgColor = RafColors.warningSubtle;
      borderColor = RafColors.warningBorder;
      icon = Icons.schedule_outlined;
    } else {
      // > 60 days: natural / green color
      textColor = RafColors.success;
      bgColor = RafColors.successSubtle;
      borderColor = RafColors.successBorder;
      icon = Icons.event_available_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RafSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: RafRadius.roundedSm,
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: textColor),
            const SizedBox(width: RafSpacing.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textColor,
                fontFamily: RafTypography.fontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
