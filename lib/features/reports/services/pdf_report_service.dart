import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/utils/formatters.dart';
import '../../parties/models/party_model.dart';
import '../../parties/models/statement_model.dart';
import '../../sales/models/invoice_model.dart';
import '../../settings/pages/store_settings_page.dart';
import '../repositories/reports_repository.dart';

/// PDF Generation and Printing Engine for RAF ERP with full Arabic RTL support and Zero-Tofu.
class PdfReportService {
  static pw.Font? _cachedBaseFont;
  static pw.Font? _cachedBoldFont;

  /// Loads Cairo Arabic font from local assets with zero network latency and Zero-Tofu (no squares □□□).
  static Future<pw.ThemeData> _buildArabicTheme() async {
    // 1. Primary: Load bundled offline fonts directly from assets
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
      // 2. Secondary fallback (e.g. running outside Flutter engine)
      try {
        final baseFont = await PdfGoogleFonts.cairoRegular();
        final boldFont = await PdfGoogleFonts.cairoBold();
        return pw.ThemeData.withFont(
          base: baseFont,
          bold: boldFont,
          fontFallback: [baseFont],
        );
      } catch (_) {
        // 3. Minimal fallback
        return pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 1. Commercial Invoice PDF (A4 & 80mm POS Thermal)
  // ---------------------------------------------------------------------------

  static Future<Uint8List> generateInvoicePdf({
    required InvoiceModel invoice,
    Map<int, String>? itemNames,
    StoreSettingsModel? storeSettings,
    bool isThermal = false,
  }) async {
    final pdf = pw.Document();
    final theme = await _buildArabicTheme();
    final store = storeSettings ?? StoreSettingsManager.instance.settings;
    final pageFormat = isThermal
        ? const PdfPageFormat(
            80 * PdfPageFormat.mm,
            double.infinity,
            marginAll: 4 * PdfPageFormat.mm,
          )
        : PdfPageFormat.a4.copyWith(
            marginLeft: 15 * PdfPageFormat.mm,
            marginRight: 15 * PdfPageFormat.mm,
            marginTop: 15 * PdfPageFormat.mm,
            marginBottom: 15 * PdfPageFormat.mm,
          );

    final items = invoice.items ?? [];
    final qrData =
        'Store: ${store.storeName}\n'
        'Inv: ${invoice.invoiceNumber}\n'
        'Date: ${DateFormatter.formatDate(invoice.invoiceDate)}\n'
        'Total: ${CurrencyFormatter.format(invoice.total)}';

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: theme,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Header (Store Name, Contact Info, Title)
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        store.storeName,
                        style: pw.TextStyle(
                          fontSize: isThermal ? 14 : 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'هاتف: ${store.phone} | ${store.address}',
                        style: pw.TextStyle(
                          fontSize: isThermal ? 8 : 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey200,
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(4),
                          ),
                        ),
                        child: pw.Text(
                          invoice.invoiceType.arabicLabel,
                          style: pw.TextStyle(
                            fontSize: isThermal ? 10 : 13,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 8),
                pw.Divider(thickness: 1, color: PdfColors.grey400),
                pw.SizedBox(height: 4),

                // Invoice Metadata Details
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'رقم الفاتورة: ${invoice.invoiceNumber}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      'التاريخ: ${DateFormatter.formatDate(invoice.invoiceDate)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'السداد: ${invoice.paymentType.arabicLabel}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      'الحالة: ${invoice.status.arabicLabel}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),

                pw.Text(
                  'وسيلة الدفع: ${invoice.paymentMethod.arabicLabel}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 8),

                // Items Table
                pw.TableHelper.fromTextArray(
                  border: pw.TableBorder.all(
                    color: PdfColors.grey300,
                    width: 0.5,
                  ),
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: isThermal ? 8 : 10,
                  ),
                  cellStyle: pw.TextStyle(fontSize: isThermal ? 8 : 9),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.grey100,
                  ),
                  headers: ['#', 'الصنف', 'الكمية', 'السعر', 'الإجمالي'],
                  data: List.generate(items.length, (i) {
                    final item = items[i];
                    final name =
                        itemNames?[item.itemId] ?? 'صنف #${item.itemId}';
                    return [
                      '${i + 1}',
                      name,
                      '${item.quantity}',
                      CurrencyFormatter.format(
                        item.unitPrice,
                        includeSymbol: false,
                      ),
                      CurrencyFormatter.format(
                        item.totalPrice,
                        includeSymbol: false,
                      ),
                    ];
                  }),
                ),

                pw.SizedBox(height: 8),

                // Totals Summary Box
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(4),
                    ),
                  ),
                  child: pw.Column(
                    children: [
                      _buildSummaryRow(
                        'المجموع:',
                        CurrencyFormatter.format(invoice.subtotal),
                      ),
                      if (!invoice.discount.isZero)
                        _buildSummaryRow(
                          'الخصم:',
                          '-${CurrencyFormatter.format(invoice.discount)}',
                        ),
                      pw.Divider(thickness: 0.5, color: PdfColors.grey300),
                      _buildSummaryRow(
                        'الصافي الإجمالي:',
                        CurrencyFormatter.format(invoice.total),
                        isBold: true,
                        fontSize: isThermal ? 11 : 13,
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 10),

                // QR Code for E-Invoicing
                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: qrData,
                    width: isThermal ? 55 : 75,
                    height: isThermal ? 55 : 75,
                  ),
                ),

                if (store.invoiceFooterNote.isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  pw.Center(
                    child: pw.Text(
                      store.invoiceFooterNote,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: isThermal ? 7 : 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // ---------------------------------------------------------------------------
  // 2. Account Statement PDF (كشف الحساب)
  // ---------------------------------------------------------------------------

  static Future<Uint8List> generateStatementPdf({
    required PartyModel party,
    required PartyStatementSummary statement,
    StoreSettingsModel? storeSettings,
  }) async {
    final pdf = pw.Document();
    final theme = await _buildArabicTheme();
    final store = storeSettings ?? StoreSettingsManager.instance.settings;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Top Branding Header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          store.storeName,
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'هاتف: ${store.phone}',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.teal700,
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(4),
                        ),
                      ),
                      child: pw.Text(
                        'كشف حساب رسمي',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 10),
                pw.Divider(thickness: 1, color: PdfColors.grey400),
                pw.SizedBox(height: 6),

                // Party Information Card
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(4),
                    ),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'الاسم: ${party.name}',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          pw.Text(
                            'النوع: ${party.type.arabicLabel} | هاتف: ${party.phone}',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'الرصيد الختامي: ${CurrencyFormatter.format(statement.currentBalance.abs)} ${party.isDebtor
                                ? "(مدين / لنا)"
                                : party.isCreditor
                                ? "(دائن / له)"
                                : "(خالص)"}',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 11,
                              color: party.isDebtor
                                  ? PdfColors.red700
                                  : party.isCreditor
                                  ? PdfColors.green700
                                  : PdfColors.black,
                            ),
                          ),
                          pw.Text(
                            'تاريخ الطباعة: ${DateFormatter.formatDate(DateTime.now())}',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 12),

                // Movements Table
                pw.TableHelper.fromTextArray(
                  border: pw.TableBorder.all(
                    color: PdfColors.grey300,
                    width: 0.5,
                  ),
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                  ),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                  ),
                  headers: [
                    'التاريخ',
                    'العملية',
                    'المرجع',
                    'البيان',
                    'مدين (-)',
                    'دائن (+)',
                    'الرصيد',
                  ],
                  data: statement.entries.map((e) {
                    return [
                      DateFormatter.formatDate(e.date),
                      e.transactionType,
                      e.referenceNumber,
                      e.statement,
                      e.debit.isZero
                          ? '-'
                          : CurrencyFormatter.format(
                              e.debit,
                              includeSymbol: false,
                            ),
                      e.credit.isZero
                          ? '-'
                          : CurrencyFormatter.format(
                              e.credit,
                              includeSymbol: false,
                            ),
                      CurrencyFormatter.format(
                        e.runningBalance,
                        includeSymbol: false,
                      ),
                    ];
                  }).toList(),
                ),

                pw.SizedBox(height: 12),

                // Totals Bar
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    pw.Text(
                      'إجمالي المدين: ${CurrencyFormatter.format(statement.totalDebit)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'إجمالي الدائن: ${CurrencyFormatter.format(statement.totalCredit)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // ---------------------------------------------------------------------------
  // 3. Profit & Loss Report PDF (الأرباح والخسائر)
  // ---------------------------------------------------------------------------

  static Future<Uint8List> generateProfitLossPdf({
    required ProfitLossReportModel report,
    StoreSettingsModel? storeSettings,
  }) async {
    final pdf = pw.Document();
    final theme = await _buildArabicTheme();
    final store = storeSettings ?? StoreSettingsManager.instance.settings;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        store.storeName,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'قائمة الأرباح والخسائر (P&L)',
                        style: pw.TextStyle(
                          fontSize: 15,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.teal800,
                        ),
                      ),
                      pw.Text(
                        'للفترة من ${DateFormatter.formatDate(report.startDate)} إلى ${DateFormatter.formatDate(report.endDate)}',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Divider(thickness: 1, color: PdfColors.grey400),
                pw.SizedBox(height: 12),

                // P&L Statement Grid
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(6),
                    ),
                  ),
                  child: pw.Column(
                    children: [
                      _buildPnlRow(
                        '1. إجمالي الإيرادات والمبيعات الصافية',
                        CurrencyFormatter.format(report.totalRevenues),
                        isHeading: true,
                      ),
                      pw.SizedBox(height: 6),
                      _buildPnlRow(
                        '2. تكلفة البضاعة المباعة (COGS)',
                        '- ${CurrencyFormatter.format(report.costOfGoodsSold)}',
                      ),
                      pw.Divider(color: PdfColors.grey300),
                      _buildPnlRow(
                        '3. مجمل الربح التشغيلي (Gross Profit)',
                        CurrencyFormatter.format(report.grossProfit),
                        isBold: true,
                        badge: '${report.grossProfitMarginPercent}%',
                      ),
                      pw.SizedBox(height: 8),
                      _buildPnlRow(
                        '4. المصروفات العمومية والإدارية',
                        '- ${CurrencyFormatter.format(report.operatingExpenses)}',
                      ),
                      pw.Divider(thickness: 1.5, color: PdfColors.teal700),
                      _buildPnlRow(
                        '5. صافي الربح النهائي (Net Profit)',
                        CurrencyFormatter.format(report.netProfit),
                        isBold: true,
                        fontSize: 14,
                        badge: '${report.netProfitMarginPercent}%',
                        color: report.netProfit.isNegative
                            ? PdfColors.red700
                            : PdfColors.teal800,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // ---------------------------------------------------------------------------
  // Printing & Sharing Action
  // ---------------------------------------------------------------------------

  static Future<void> printOrSharePdf({
    required Uint8List pdfBytes,
    String documentName = 'RAF_Document.pdf',
  }) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: documentName,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static pw.Widget _buildSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    double fontSize = 10,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPnlRow(
    String label,
    String value, {
    bool isHeading = false,
    bool isBold = false,
    double fontSize = 11,
    String? badge,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: fontSize,
                  fontWeight: (isHeading || isBold)
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
              if (badge != null) ...[
                pw.SizedBox(width: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(3),
                    ),
                  ),
                  child: pw.Text(
                    'الهامش: $badge',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }
}
