import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';

/// Clean minimalist quick-action shortcut button for common POS and ERP tasks.
class QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const QuickActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.color = RafColors.primary,
    required this.onTap,
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
            padding: const EdgeInsets.symmetric(
              horizontal: RafSpacing.md,
              vertical: RafSpacing.sm + 2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: RafRadius.roundedSm,
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: RafSpacing.sm),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: RafTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: RafColors.textPrimary,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
