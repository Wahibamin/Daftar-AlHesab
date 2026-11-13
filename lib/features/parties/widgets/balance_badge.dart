import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../models/party_model.dart';

/// Clean visual balance status indicator badge following the RAF design tokens.
class BalanceBadge extends StatelessWidget {
  final PartyModel party;
  final bool compact;

  const BalanceBadge({super.key, required this.party, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final String label;
    final BoxDecoration decoration;
    final Color textColor;
    final IconData icon;

    if (party.isDebtor) {
      // Debtor: owes us money (عليه)
      label = compact
          ? 'عليه: ${party.absoluteBalance.format()}'
          : 'مدين (عليه): ${party.absoluteBalance.format()}';
      decoration = RafDecorations.badgeDanger;
      textColor = RafColors.danger;
      icon = Icons.arrow_outward_rounded;
    } else if (party.isCreditor) {
      // Creditor: we owe them money (له)
      label = compact
          ? 'له: ${party.absoluteBalance.format()}'
          : 'دائن (له): ${party.absoluteBalance.format()}';
      decoration = RafDecorations.badgeSuccess;
      textColor = RafColors.success;
      icon = Icons.arrow_downward_rounded;
    } else {
      // Settled (خالص / 0.00)
      label = 'خالص (0.00)';
      decoration = RafDecorations.badgeNeutral;
      textColor = RafColors.textSecondary;
      icon = Icons.check_circle_outline;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? RafSpacing.xs + 2 : RafSpacing.sm + 2,
        vertical: compact ? 2 : RafSpacing.xs,
      ),
      decoration: decoration,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 12 : 14, color: textColor),
            const SizedBox(width: RafSpacing.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: RafTypography.fontFamily,
                ),
              ),
            ),
            if (party.exceedsCreditLimit) ...[
              const SizedBox(width: RafSpacing.xs),
              Tooltip(
                message: 'تجاوز سقف الائتمان!',
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 13,
                  color: RafColors.warning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
