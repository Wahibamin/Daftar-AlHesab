import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';

/// Clean minimalist financial metric card for the Executive Dashboard.
class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color accentColor;
  final String? subtitle;
  final VoidCallback? onTap;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.accentColor = RafColors.primary,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
            padding: const EdgeInsets.all(RafSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Row: Title & Icon Pill
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: RafTypography.bodySmall.copyWith(
                          color: RafColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.08),
                        borderRadius: RafRadius.roundedSm,
                      ),
                      child: Icon(icon, size: 18, color: accentColor),
                    ),
                  ],
                ),

                const SizedBox(height: RafSpacing.xs),

                // Main Metric Value
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    style: RafTypography.financialAmount.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: RafColors.textPrimary,
                    ),
                    maxLines: 1,
                  ),
                ),

                if (subtitle != null) ...[
                  const SizedBox(height: RafSpacing.xxs),
                  Text(
                    subtitle!,
                    style: RafTypography.labelSmall.copyWith(
                      color: RafColors.textMuted,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
