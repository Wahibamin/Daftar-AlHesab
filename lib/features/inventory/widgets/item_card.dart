import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../models/item_model.dart';
import 'expiry_badge.dart';
import 'stock_badge.dart';

/// Clean minimalist item card widget for inventory lists.
class ItemCard extends StatelessWidget {
  final ItemModel item;
  final String? unitName;
  final String? categoryName;
  final DateTime? referenceDate;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onAdjustStock;
  final VoidCallback? onPrintBarcode;
  final VoidCallback? onDelete;

  const ItemCard({
    super.key,
    required this.item,
    this.unitName,
    this.categoryName,
    this.referenceDate,
    this.onTap,
    this.onEdit,
    this.onAdjustStock,
    this.onPrintBarcode,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: RafSpacing.sm + 2),
      decoration: RafDecorations.cardFlat,
      child: Material(
        color: Colors.transparent,
        borderRadius: RafRadius.roundedMd,
        child: InkWell(
          borderRadius: RafRadius.roundedMd,
          onTap: onTap ?? onEdit,
          child: Padding(
            padding: const EdgeInsets.all(RafSpacing.md + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Name and Menu
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: RafTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: RafSpacing.xs),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: RafSpacing.xs,
                            runSpacing: 2,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.qr_code_2,
                                      size: 14,
                                      color: RafColors.textMuted,
                                    ),
                                    const SizedBox(width: RafSpacing.xs),
                                    Text(
                                      item.code,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: RafTypography.fontFamily,
                                        color: RafColors.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (categoryName != null) ...[
                                const Text(
                                  '•',
                                  style: TextStyle(
                                    color: RafColors.borderStrong,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  categoryName!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: RafTypography.fontFamily,
                                    color: RafColors.textMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (item.expiryDate != null) ...[
                            const SizedBox(height: RafSpacing.xs + 2),
                            ExpiryBadge(
                              key: const Key('item_expiry_badge'),
                              expiryDate: item.expiryDate,
                              referenceDate: referenceDate,
                            ),
                          ],
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        size: 18,
                        color: RafColors.secondary,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 140),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: RafRadius.roundedMd,
                        side: const BorderSide(color: RafColors.border),
                      ),
                      color: RafColors.surface,
                      onSelected: (val) {
                        if (val == 'edit') onEdit?.call();
                        if (val == 'adjust') onAdjustStock?.call();
                        if (val == 'print_barcode') onPrintBarcode?.call();
                        if (val == 'delete') onDelete?.call();
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: RafColors.secondary,
                              ),
                              SizedBox(width: RafSpacing.sm),
                              Text(
                                'تعديل البيانات',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'adjust',
                          child: Row(
                            children: [
                              Icon(
                                Icons.tune,
                                size: 16,
                                color: RafColors.primary,
                              ),
                              SizedBox(width: RafSpacing.sm),
                              Text(
                                'تسوية جردية',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: RafColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'print_barcode',
                          child: Row(
                            children: [
                              Icon(
                                Icons.print_outlined,
                                size: 16,
                                color: RafColors.primary,
                              ),
                              SizedBox(width: RafSpacing.sm),
                              Text(
                                'طباعة ملصق الباركود',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: RafColors.danger,
                              ),
                              SizedBox(width: RafSpacing.sm),
                              Text(
                                'أرشفة / حذف',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: RafColors.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const Divider(height: RafSpacing.lg, color: RafColors.border),

                // Bottom Row: Selling Price and Stock Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'سعر البيع',
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: RafTypography.fontFamily,
                              color: RafColors.textMuted,
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              item.sellingPrice.format(),
                              style: RafTypography.financialAmount.copyWith(
                                fontSize: 16,
                                color: RafColors.primary,
                              ),
                            ),
                          ),
                          Text(
                            'التكلفة: ${item.costPrice.format()}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: RafTypography.fontFamily,
                              color: RafColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: RafSpacing.sm),
                    StockBadge(
                      item: item,
                      unitSymbol: unitName,
                      referenceDate: referenceDate,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
