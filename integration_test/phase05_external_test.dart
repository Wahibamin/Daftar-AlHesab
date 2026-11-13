// Physical-device tests for the remaining external functions. No business DB
// reads/writes and no messages, calls, prints, or real customer exports.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:printing/printing.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/core/widgets/barcode_scanner_dialog.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/services/barcode_label_service.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/models/statement_model.dart';
import 'package:m3/features/reports/repositories/reports_repository.dart';
import 'package:m3/features/reports/services/pdf_report_service.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/settings/pages/store_settings_page.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('DAFTAR_DEVICE_QA');
  const skipGranted = bool.fromEnvironment('PH05_SKIP_GRANTED_CAMERA');
  const skipDenied = bool.fromEnvironment('PH05_SKIP_DENIED_CAMERA');
  final results = <String, Object?>{};
  String? scannerResult;
  void record(String name, Object? value) {
    results[name] = value;
    binding.reportData = results;
    debugPrint('PH05_RESULT ${jsonEncode({'check': name, 'value': value})}');
  }

  testWidgets(
    'PH05 native PDF raster and real barcode image decoder',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      final dir = await Directory(
        '${Directory.systemTemp.path}/phase05_qa',
      ).create(recursive: true);
      record('artifact_directory', dir.path);
      final now = DateTime(2026, 11, 5);
      const store = StoreSettingsModel(
        storeName: 'دفتر الحساب — اختبار PH05',
        phone: '0500000000',
        address: 'عنوان تجريبي',
        invoiceFooterNote: 'مستند اختبار فقط',
      );
      final item = ItemModel(
        id: 1,
        code: 'PH05-1234567890',
        name: 'سلعة تجريبية عربية',
        unitId: 1,
        costPrice: const Money(600),
        sellingPrice: const Money(1000),
        stockQuantity: 10,
        createdAt: now,
        updatedAt: now,
      );
      final party = PartyModel(
        id: 1,
        name: 'عميل تجريبي PH05',
        phone: '0500000000',
        type: PartyType.customer,
        currentBalance: const Money(-3000),
        createdAt: now,
        updatedAt: now,
      );
      final invoice = InvoiceModel.buildWithItems(
        invoiceNumber: 'PH05-PDF-01',
        invoiceType: InvoiceType.sale,
        partyId: 1,
        status: InvoiceStatus.approved,
        paymentType: PaymentType.partial,
        paymentMethod: PaymentMethod.bank,
        paidAmount: const Money(1000),
        items: [
          InvoiceItemModel.create(
            itemId: 1,
            quantity: 4,
            unitPrice: const Money(1000),
          ),
        ],
        invoiceDate: now,
        createdAt: now,
        updatedAt: now,
      );
      final statement = PartyStatementSummary(
        party: party,
        openingBalance: Money.zero,
        totalDebit: const Money(4000),
        totalCredit: const Money(1000),
        currentBalance: const Money(-3000),
        entries: [
          AccountStatementEntry(
            date: now,
            transactionType: 'فاتورة مبيعات',
            referenceNumber: 'PH05-PDF-01',
            statement: 'سلعة تجريبية عربية',
            debit: const Money(4000),
            credit: Money.zero,
            runningBalance: const Money(-4000),
          ),
          AccountStatementEntry(
            date: now,
            transactionType: 'سداد جزئي',
            referenceNumber: 'PH05-PAY-01',
            statement: 'دفعة تجريبية',
            debit: Money.zero,
            credit: const Money(1000),
            runningBalance: const Money(-3000),
          ),
        ],
      );
      final profit = ProfitLossReportModel(
        startDate: now,
        endDate: now,
        totalRevenues: const Money(4000),
        costOfGoodsSold: const Money(2400),
        grossProfit: const Money(1600),
        operatingExpenses: const Money(500),
        netProfit: const Money(1100),
      );
      final pdfs = {
        'invoice': await PdfReportService.generateInvoicePdf(
          invoice: invoice,
          itemNames: {1: item.name},
          storeSettings: store,
        ),
        'statement': await PdfReportService.generateStatementPdf(
          party: party,
          statement: statement,
          storeSettings: store,
        ),
        'profit': await PdfReportService.generateProfitLossPdf(
          report: profit,
          storeSettings: store,
        ),
        'barcode': await BarcodeLabelService.generateLabelsPdf(
          item: item,
          unitSymbol: 'حبة',
        ),
      };
      for (final entry in pdfs.entries) {
        expect(String.fromCharCodes(entry.value.take(5)), '%PDF-');
        await File('${dir.path}/${entry.key}.pdf').writeAsBytes(entry.value);
        final raster = await Printing.raster(
          entry.value,
          pages: [0],
          dpi: entry.key == 'barcode' ? 300 : 130,
        ).first;
        // Android raster pixels have a transparent page background. Composite
        // onto paper white, as a PDF viewer does, before visual QA / ML Kit input.
        final image = await raster.toImage();
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)
          ..drawColor(Colors.white, ui.BlendMode.src);
        canvas.drawImage(image, ui.Offset.zero, ui.Paint());
        final picture = recorder.endRecording();
        final opaque = await picture.toImage(raster.width, raster.height);
        final data = await opaque.toByteData(format: ui.ImageByteFormat.png);
        final png = data!.buffer.asUint8List();
        image.dispose();
        opaque.dispose();
        picture.dispose();
        await File('${dir.path}/${entry.key}.png').writeAsBytes(png);
        record('pdf_${entry.key}', {
          'bytes': entry.value.length,
          'png_bytes': png.length,
          'width': raster.width,
          'height': raster.height,
        });
      }
      final decoder = MobileScannerController(autoStart: false);
      final capture = await decoder.analyzeImage('${dir.path}/barcode.png');
      expect(capture?.barcodes.any((b) => b.rawValue == item.code), isTrue);
      await decoder.dispose();
      record('native_image_barcode_decoder', {
        'expected': item.code,
        'decoded': true,
        'live_camera_scan': false,
      });
      record('artifact_directory', dir.path);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('PH05 PDF verification complete')),
        ),
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  Future<void> scanner(WidgetTester tester) async {
    scannerResult = null;
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('ph05_scan'),
              onPressed: () async {
                final result = await BarcodeScannerDialog.scan(context);
                scannerResult = result;
              },
              child: const Text('Scan PH05'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ph05_scan')));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'PH05 real denied camera permission gives Arabic manual fallback',
    (tester) async {
      BarcodeScannerDialog.mockBarcodeResult = null;
      await scanner(tester);
      debugPrint('PH05_CAMERA_DENY_READY');
      final deadline = DateTime.now().add(const Duration(seconds: 100));
      while (find
              .byKey(const Key('error_manual_input_button'))
              .evaluate()
              .isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.text('تعذر فتح الكاميرا'), findsOneWidget);
      expect(find.textContaining('تم رفض الإذن'), findsOneWidget);
      // Exercise the permission-dialog resume sequence that used to retry
      // denied initialization and emit an unhandled controllerInitializing.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('error_manual_input_button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('error_manual_input_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('manual_barcode_input_field')),
        'PH05-MANUAL',
      );
      await tester.tap(find.byKey(const Key('submit_manual_barcode_button')));
      await tester.pumpAndSettle();
      expect(scannerResult, 'PH05-MANUAL');
      record('camera_denied_manual_fallback', true);
    },
    skip: !enabled || skipDenied,
    timeout: const Timeout(Duration(minutes: 2)),
  );
  testWidgets(
    'PH05 granted camera permission initializes real stream',
    (tester) async {
      await scanner(tester);
      debugPrint('PH05_CAMERA_GRANT_READY');
      final deadline = DateTime.now().add(const Duration(seconds: 100));
      var initialized = false;
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 150));
        final widgets = find.byType(MobileScanner).evaluate();
        if (widgets.isNotEmpty) {
          final widget = widgets.single.widget as MobileScanner;
          final camera = widget.controller?.value;
          if (camera?.isInitialized == true &&
              camera?.isRunning == true &&
              camera?.error == null) {
            initialized = true;
            break;
          }
        }
      }
      expect(initialized, isTrue);
      await tester.tap(find.byKey(const Key('close_barcode_scanner_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      record('camera_real_stream_initialized', true);
      record(
        'live_physical_barcode_scan',
        'not verified on a physical barcode target',
      );
    },
    skip: !enabled || skipGranted,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
