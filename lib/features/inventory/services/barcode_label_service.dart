import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/item_model.dart';

/// Preset thermal label sizes for standard barcode printers (e.g. Xprinter, Zebra, Phomemo).
enum BarcodeLabelSize {
  standard50x30(name: '50 × 30 مم (قياسي)', widthMm: 50, heightMm: 30),
  compact40x25(name: '40 × 25 مم (مدمج)', widthMm: 40, heightMm: 25),
  small38x25(name: '38 × 25 مم (صغير)', widthMm: 38, heightMm: 25);

  final String name;
  final double widthMm;
  final double heightMm;

  const BarcodeLabelSize({
    required this.name,
    required this.widthMm,
    required this.heightMm,
  });

  PdfPageFormat get format => PdfPageFormat(
    widthMm * PdfPageFormat.mm,
    heightMm * PdfPageFormat.mm,
    marginAll: 2 * PdfPageFormat.mm,
  );
}

/// Service dedicated to creating professional, scannable barcode label PDFs.
class BarcodeLabelService {
  static pw.Font? _cachedBaseFont;
  static pw.Font? _cachedBoldFont;

  static Future<pw.ThemeData> _buildArabicTheme() async {
    try {
      if (_cachedBaseFont == null || _cachedBoldFont == null) {
        final regularBytes = await rootBundle.load(
          'assets/fonts/Cairo-Regular.ttf',
        );
        final boldBytes = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
        _cachedBaseFont = pw.Font.ttf(regularBytes);
        _cachedBoldFont = pw.Font.ttf(boldBytes);
      }
      return pw.ThemeData.withFont(
        base: _cachedBaseFont!,
        bold: _cachedBoldFont!,
        fontFallback: [_cachedBaseFont!],
      );
    } catch (_) {
      return pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
    }
  }

  /// Generates a PDF document containing [copies] of a scannable barcode label.
  ///
  /// Guarantees:
  /// - True scannable vector barcode using Code 128.
  /// - Arabic RTL support for product name and store name.
  /// - Customizable label dimensions.
  /// - Optional price and unit displays.
  /// - Absolutely zero tax data displayed.
  static Future<Uint8List> generateLabelsPdf({
    required ItemModel item,
    String? unitSymbol,
    String? storeName,
    BarcodeLabelSize size = BarcodeLabelSize.standard50x30,
    int copies = 1,
    bool showPrice = true,
    bool showUnit = true,
    bool showStoreName = false,
  }) async {
    final theme = await _buildArabicTheme();
    final doc = pw.Document(theme: theme);
    final count = copies < 1 ? 1 : copies;

    final format = size.format;
    final barcodeData = item.code.trim().isNotEmpty
        ? item.code.trim()
        : '000000000000';

    for (int i = 0; i < count; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: format,
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // Optional Store Name
                  if (showStoreName &&
                      storeName != null &&
                      storeName.trim().isNotEmpty)
                    pw.Text(
                      storeName.trim(),
                      style: pw.TextStyle(
                        fontSize: 6,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      maxLines: 1,
                    ),

                  // Product Name
                  pw.Text(
                    item.name,
                    style: pw.TextStyle(
                      fontSize: size == BarcodeLabelSize.standard50x30
                          ? 7.5
                          : 6.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    maxLines: 1,
                    textAlign: pw.TextAlign.center,
                  ),

                  pw.SizedBox(height: 1),

                  // True Vector Scannable Barcode
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: barcodeData,
                        drawText: true,
                        textStyle: const pw.TextStyle(fontSize: 6),
                      ),
                    ),
                  ),

                  pw.SizedBox(height: 1),

                  // Bottom info: Price and Unit (if selected)
                  if (showPrice)
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          'السعر: ${item.sellingPrice.format(includeSymbol: true)}',
                          style: pw.TextStyle(
                            fontSize: size == BarcodeLabelSize.standard50x30
                                ? 7.5
                                : 6.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (showUnit &&
                            unitSymbol != null &&
                            unitSymbol.isNotEmpty) ...[
                          pw.SizedBox(width: 3),
                          pw.Text(
                            '/ $unitSymbol',
                            style: const pw.TextStyle(fontSize: 6),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      );
    }

    return doc.save();
  }
}
