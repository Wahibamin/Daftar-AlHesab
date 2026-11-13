import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../core/theme/raf_design_system.dart';
import '../models/item_model.dart';
import '../services/barcode_label_service.dart';

/// Modal dialog for configuring, previewing, and printing barcode labels.
class BarcodeLabelDialog extends StatefulWidget {
  final ItemModel item;
  final String? unitSymbol;
  final String? storeName;

  const BarcodeLabelDialog({
    super.key,
    required this.item,
    this.unitSymbol,
    this.storeName,
  });

  static Future<void> show(
    BuildContext context, {
    required ItemModel item,
    String? unitSymbol,
    String? storeName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => BarcodeLabelDialog(
        item: item,
        unitSymbol: unitSymbol,
        storeName: storeName,
      ),
    );
  }

  @override
  State<BarcodeLabelDialog> createState() => _BarcodeLabelDialogState();
}

class _BarcodeLabelDialogState extends State<BarcodeLabelDialog> {
  BarcodeLabelSize _selectedSize = BarcodeLabelSize.standard50x30;
  int _copies = 1;
  bool _showPrice = true;
  bool _showUnit = true;
  bool _showStoreName = false;
  bool _isGenerating = false;

  Future<void> _printOrShare() async {
    setState(() => _isGenerating = true);
    try {
      final pdfBytes = await BarcodeLabelService.generateLabelsPdf(
        item: widget.item,
        unitSymbol: widget.unitSymbol,
        storeName: widget.storeName,
        size: _selectedSize,
        copies: _copies,
        showPrice: _showPrice,
        showUnit: _showUnit,
        showStoreName: _showStoreName,
      );

      if (mounted) {
        setState(() => _isGenerating = false);
        await Printing.layoutPdf(
          onLayout: (_) async => pdfBytes,
          name: 'ملصق_${widget.item.code}.pdf',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر إنشاء ملصق الطباعة: $e'),
            backgroundColor: RafColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: RafColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: RafRadius.roundedMd,
          side: BorderSide(color: RafColors.border),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.print_outlined,
              color: RafColors.primary,
              size: 22,
            ),
            const SizedBox(width: RafSpacing.sm),
            const Expanded(
              child: Text(
                'طباعة ملصق الباركود',
                style: RafTypography.titleMedium,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Visual Label Preview Box
              Container(
                padding: const EdgeInsets.all(RafSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: RafRadius.roundedMd,
                  border: Border.all(color: RafColors.borderStrong),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showStoreName &&
                        widget.storeName != null &&
                        widget.storeName!.isNotEmpty) ...[
                      Text(
                        widget.storeName!,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: RafColors.textMuted,
                          fontFamily: RafTypography.fontFamily,
                        ),
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      widget.item.name,
                      style: RafTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: RafSpacing.xs),
                    // Barcode illustration
                    Container(
                      height: 48,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.view_column_rounded,
                            size: 28,
                            color: Colors.black87,
                          ),
                          Text(
                            widget.item.code,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_showPrice) ...[
                      const SizedBox(height: RafSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'السعر: ${widget.item.sellingPrice.format(includeSymbol: true)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: RafColors.textPrimary,
                            ),
                          ),
                          if (_showUnit &&
                              widget.unitSymbol != null &&
                              widget.unitSymbol!.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              '/ ${widget.unitSymbol}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: RafColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: RafSpacing.md),

              // Size Picker
              const Text('مقاس الملصق', style: RafTypography.label),
              const SizedBox(height: RafSpacing.xs),
              DropdownButtonFormField<BarcodeLabelSize>(
                initialValue: _selectedSize,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: BarcodeLabelSize.values.map((s) {
                  return DropdownMenuItem(
                    value: s,
                    child: Text(s.name, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedSize = val);
                },
              ),

              const SizedBox(height: RafSpacing.sm),

              // Number of copies
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('عدد النسخ', style: RafTypography.label),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          size: 22,
                          color: RafColors.textSecondary,
                        ),
                        onPressed: _copies > 1
                            ? () => setState(() => _copies--)
                            : null,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: RafColors.surfaceSecondary,
                          borderRadius: RafRadius.roundedSm,
                          border: Border.all(color: RafColors.border),
                        ),
                        child: Text(
                          '$_copies',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle_outline,
                          size: 22,
                          color: RafColors.primary,
                        ),
                        onPressed: () => setState(() => _copies++),
                      ),
                    ],
                  ),
                ],
              ),

              const Divider(height: 16),

              // Toggles
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'عرض السعر على الملصق',
                  style: TextStyle(fontSize: 13),
                ),
                value: _showPrice,
                activeColor: RafColors.primary,
                onChanged: (v) => setState(() => _showPrice = v ?? true),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'عرض وحدة القياس',
                  style: TextStyle(fontSize: 13),
                ),
                value: _showUnit,
                activeColor: RafColors.primary,
                onChanged: (v) => setState(() => _showUnit = v ?? true),
              ),
              if (widget.storeName != null && widget.storeName!.isNotEmpty)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'عرض اسم المتجر',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: _showStoreName,
                  activeColor: RafColors.primary,
                  onChanged: (v) => setState(() => _showStoreName = v ?? false),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            key: const Key('print_barcode_confirm_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: RafColors.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: RafSpacing.md,
                vertical: 10,
              ),
            ),
            icon: _isGenerating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.print, size: 18),
            label: Text(_isGenerating ? 'جاري التجهيز...' : 'طباعة الملصق'),
            onPressed: _isGenerating ? null : _printOrShare,
          ),
        ],
      ),
    );
  }
}
