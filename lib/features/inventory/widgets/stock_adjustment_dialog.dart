import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/money.dart';
import '../data/inventory_repository.dart';
import '../models/item_model.dart';

/// Interactive modal dialog for physical stock audit and adjustment.
class StockAdjustmentDialog extends StatefulWidget {
  final ItemModel item;
  final InventoryRepository? repository;

  const StockAdjustmentDialog({super.key, required this.item, this.repository});

  static Future<bool?> show(
    BuildContext context, {
    required ItemModel item,
    InventoryRepository? repository,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          StockAdjustmentDialog(item: item, repository: repository),
    );
  }

  @override
  State<StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<StockAdjustmentDialog> {
  late final TextEditingController _actualStockController;
  late final TextEditingController _notesController;
  late final InventoryRepository _repo;

  int _actualCount = 0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? SqliteInventoryRepository();
    _actualCount = widget.item.stockQuantity;
    _actualStockController = TextEditingController(
      text: _actualCount.toString(),
    );
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _actualStockController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int get _variance => _actualCount - widget.item.stockQuantity;

  Money get _varianceFinancialImpact => widget.item.costPrice * _variance.abs();

  Future<void> _saveAdjustment() async {
    if (_variance == 0) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _repo.recordStockAdjustment(
        itemId: widget.item.id!,
        actualStock: _actualCount,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء حفظ التسوية: $e'),
            backgroundColor: RafColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final variance = _variance;
    final isShortage = variance < 0;
    final isSurplus = variance > 0;

    return Dialog(
      backgroundColor: RafColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: RafRadius.roundedLg,
        side: BorderSide(color: RafColors.border, width: 1.0),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: RafSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(RafSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          'تسوية جردية للمخزون',
                          style: RafTypography.titleMedium,
                        ),
                      ),
                    ),
                    const SizedBox(width: RafSpacing.sm),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(false),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: RafSpacing.xs),
                Text(
                  '${widget.item.name} (${widget.item.code})',
                  style: const TextStyle(
                    fontSize: 13,
                    color: RafColors.textSecondary,
                    fontFamily: RafTypography.fontFamily,
                  ),
                ),

                const Divider(height: RafSpacing.lg, color: RafColors.border),

                // Current Stock Box
                Container(
                  padding: const EdgeInsets.all(RafSpacing.md),
                  decoration: RafDecorations.panelSecondary,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'الرصيد الدفتري المسجل:',
                          style: TextStyle(
                            fontSize: 13,
                            color: RafColors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        '${widget.item.stockQuantity} وحدة',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: RafColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: RafSpacing.md),

                // Actual Physical Count Field
                const Text(
                  'الرصيد الفعلي بعد الجرد:',
                  style: RafTypography.label,
                ),
                const SizedBox(height: RafSpacing.xs),
                TextField(
                  controller: _actualStockController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    ThousandsSeparatorInputFormatter.integerOnly(),
                  ],
                  autofocus: true,
                  onChanged: (val) {
                    setState(() {
                      _actualCount =
                          ThousandsSeparatorInputFormatter.extractInteger(val);
                    });
                  },
                  decoration: const InputDecoration(
                    hintText: 'أدخل الكمية الفعلية',
                    prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
                  ),
                ),

                const SizedBox(height: RafSpacing.md),

                // Real-Time Variance Calculation Strip
                Container(
                  padding: const EdgeInsets.all(RafSpacing.md),
                  decoration: BoxDecoration(
                    color: isShortage
                        ? RafColors.dangerSubtle
                        : isSurplus
                        ? RafColors.successSubtle
                        : RafColors.surfaceSecondary,
                    borderRadius: RafRadius.roundedMd,
                    border: Border.all(
                      color: isShortage
                          ? RafColors.dangerBorder
                          : isSurplus
                          ? RafColors.successBorder
                          : RafColors.border,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'الفارق الجردي:',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            variance == 0
                                ? 'متطابق (0)'
                                : isShortage
                                ? 'عجز ($variance)'
                                : 'فائض (+$variance)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isShortage
                                  ? RafColors.danger
                                  : isSurplus
                                  ? RafColors.success
                                  : RafColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      if (variance != 0) ...[
                        const SizedBox(height: RafSpacing.xs),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'الأثر المالي بالتكلفة:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: RafColors.textSecondary,
                                ),
                              ),
                            ),
                            Text(
                              _varianceFinancialImpact.format(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isShortage
                                    ? RafColors.danger
                                    : RafColors.success,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: RafSpacing.md),

                // Notes / Reason
                const Text(
                  'ملاحظات / سبب التسوية:',
                  style: RafTypography.label,
                ),
                const SizedBox(height: RafSpacing.xs),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    hintText: 'مثال: جرد نصف سنوي / تالف',
                  ),
                ),

                const SizedBox(height: RafSpacing.lg),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('إلغاء'),
                        ),
                      ),
                    ),
                    const SizedBox(width: RafSpacing.md),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveAdjustment,
                        child: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('اعتماد التسوية'),
                              ),
                      ),
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
