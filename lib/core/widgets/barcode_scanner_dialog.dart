import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/raf_design_system.dart';

/// Reusable full-screen modal sheet for camera barcode scanning.
///
/// Features:
/// - Fast offline scanning with ML Kit / zxing.
/// - Common commercial formats: EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39, QR.
/// - RTL Arabic UI with clear targeting reticle and controls.
/// - Torch & camera switch support.
/// - Friendly permission error states with manual barcode input fallback.
/// - Duplicate scan prevention.
/// - Test simulation support via [mockBarcodeResult].
class BarcodeScannerDialog extends StatefulWidget {
  /// When set, bypasses camera in automated tests and simulates scanning this barcode immediately.
  static String? mockBarcodeResult;

  final String title;
  final String prompt;

  const BarcodeScannerDialog({
    super.key,
    this.title = 'مسح باركود المنتج',
    this.prompt = 'وجّه الكاميرا نحو باركود السلعة ليتم التقاطه تلقائياً',
  });

  /// Helper static method to open the scanner dialog and return the scanned code.
  static Future<String?> scan(
    BuildContext context, {
    String title = 'مسح باركود المنتج',
    String prompt = 'وجّه الكاميرا نحو باركود السلعة ليتم التقاطه تلقائياً',
  }) {
    if (mockBarcodeResult != null) {
      return Future.value(mockBarcodeResult);
    }

    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => BarcodeScannerDialog(title: title, prompt: prompt),
      ),
    );
  }

  @override
  State<BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<BarcodeScannerDialog>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  bool _hasScanned = false;
  bool _isTorchOn = false;
  CameraFacing _facing = CameraFacing.back;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: _facing,
      torchEnabled: false,
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.itf14,
        BarcodeFormat.codabar,
        BarcodeFormat.qrCode,
        BarcodeFormat.dataMatrix,
      ],
    );

    // If mock result is set during widget tests, simulate immediate detection
    if (BarcodeScannerDialog.mockBarcodeResult != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasScanned) {
          _onBarcodeDetected(BarcodeScannerDialog.mockBarcodeResult!);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A denied request is also "initialized" in mobile_scanner. Permission
    // dialogs can resume this route while start() is still pending.
    final camera = _controller.value;
    if (_hasScanned || !camera.hasCameraPermission || camera.isStarting) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller.stop();
    } else if (state == AppLifecycleState.resumed) {
      _controller.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(String rawCode) {
    if (_hasScanned) return;
    final trimmed = rawCode.trim();
    if (trimmed.isEmpty) return;

    _hasScanned = true;
    _controller.stop();

    if (mounted) {
      Navigator.of(context).pop(trimmed);
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      setState(() {
        _isTorchOn = !_isTorchOn;
      });
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchCamera();
      setState(() {
        _facing = _facing == CameraFacing.back
            ? CameraFacing.front
            : CameraFacing.back;
      });
    } catch (_) {}
  }

  Future<void> _showManualInputDialog() async {
    final textCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final manualCode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'إدخال الباركود يدوياً',
          style: RafTypography.titleMedium,
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('manual_barcode_input_field'),
            controller: textCtrl,
            autofocus: true,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'قيمة الباركود',
              hintText: 'أدخل الباركود أو الكود التعريفي',
              prefixIcon: Icon(Icons.qr_code, size: 20),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'أدخل رمز الباركود' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            key: const Key('submit_manual_barcode_button'),
            style: ElevatedButton.styleFrom(backgroundColor: RafColors.primary),
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(ctx).pop(textCtrl.text.trim());
              }
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (manualCode != null && manualCode.isNotEmpty && mounted) {
      _onBarcodeDetected(manualCode);
    }
  }

  String _formatScannerError(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'تم رفض الإذن باستخدام الكاميرا.\nيرجى منح صلاحية الكاميرا من إعدادات التطبيق أو استخدام الإدخال اليدوي.';
      case MobileScannerErrorCode.unsupported:
        return 'الكاميرا غير مدعومة على هذا الجهاز.\nيمكنك كتابة الباركود يدوياً.';
      default:
        return 'تعذر تشغيل الكاميرا حالياً (${error.errorCode.name}).\nيمكنك استخدام خيار الإدخال اليدوي.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black.withValues(alpha: 0.85),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            key: const Key('close_barcode_scanner_button'),
            icon: const Icon(Icons.close),
            tooltip: 'إغلاق',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            widget.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: RafTypography.fontFamily,
              color: Colors.white,
            ),
          ),
          actions: [
            IconButton(
              key: const Key('scanner_manual_input_button'),
              icon: const Icon(Icons.keyboard_outlined),
              tooltip: 'إدخال يدوي',
              onPressed: _showManualInputDialog,
            ),
            IconButton(
              key: const Key('scanner_torch_button'),
              icon: Icon(
                _isTorchOn ? Icons.flash_on : Icons.flash_off,
                color: _isTorchOn ? Colors.amber : Colors.white,
              ),
              tooltip: _isTorchOn ? 'إيقاف الفلاش' : 'تشغيل الفلاش',
              onPressed: _toggleTorch,
            ),
            IconButton(
              key: const Key('scanner_switch_camera_button'),
              icon: const Icon(Icons.cameraswitch_outlined),
              tooltip: 'تبديل الكاميرا',
              onPressed: _switchCamera,
            ),
          ],
        ),
        body: Stack(
          children: [
            // Camera Stream
            MobileScanner(
              controller: _controller,
              onDetect: (BarcodeCapture capture) {
                if (_hasScanned) return;
                for (final barcode in capture.barcodes) {
                  final code = barcode.rawValue;
                  if (code != null && code.trim().isNotEmpty) {
                    _onBarcodeDetected(code);
                    break;
                  }
                }
              },
              errorBuilder: (context, error) {
                _errorMessage = _formatScannerError(error);
                return Center(
                  child: Container(
                    margin: const EdgeInsets.all(RafSpacing.lg),
                    padding: const EdgeInsets.all(RafSpacing.lg),
                    decoration: BoxDecoration(
                      color: RafColors.surface,
                      borderRadius: RafRadius.roundedMd,
                      border: Border.all(color: RafColors.border),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.no_photography_outlined,
                          size: 48,
                          color: RafColors.danger,
                        ),
                        const SizedBox(height: RafSpacing.md),
                        Text(
                          'تعذر فتح الكاميرا',
                          style: RafTypography.titleMedium.copyWith(
                            color: RafColors.danger,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: RafSpacing.sm),
                        Text(
                          _errorMessage!,
                          style: RafTypography.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: RafSpacing.lg),
                        ElevatedButton.icon(
                          key: const Key('error_manual_input_button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: RafColors.primary,
                          ),
                          onPressed: _showManualInputDialog,
                          icon: const Icon(Icons.keyboard, size: 18),
                          label: const Text('إدخال الباركود يدوياً'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // Reticle overlay
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ScannerOverlayPainter()),
              ),
            ),

            // Top Guidance Note
            Positioned(
              top: 24,
              left: 20,
              right: 20,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.qr_code_scanner,
                        color: RafColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.prompt,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFamily: RafTypography.fontFamily,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Action Bar: Manual Input
            Positioned(
              bottom: 30,
              left: 24,
              right: 24,
              child: Center(
                child: OutlinedButton.icon(
                  key: const Key('bottom_manual_input_button'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _showManualInputDialog,
                  icon: const Icon(Icons.keyboard, size: 18),
                  label: const Text(
                    'كتابة الباركود يدوياً',
                    style: TextStyle(
                      fontFamily: RafTypography.fontFamily,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter to draw high-contrast viewfinder frame with rounded corners.
class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double boxWidth = size.width * 0.78;
    final double boxHeight = boxWidth * 0.65;
    final left = (size.width - boxWidth) / 2;
    final top = (size.height - boxHeight) / 2 - 20;

    final rect = Rect.fromLTWH(left, top, boxWidth, boxHeight);

    // Dim outer region
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, backgroundPaint);

    // Border line
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(16)),
      borderPaint,
    );

    // Corner accents (green/primary)
    final cornerPaint = Paint()
      ..color =
          const Color(0xFF0D9488) // RAF Teal Primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    const cornerLen = 24.0;
    const rad = 16.0;

    // Top-Left
    canvas.drawLine(
      Offset(left + rad, top),
      Offset(left + rad + cornerLen, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top + rad),
      Offset(left, top + rad + cornerLen),
      cornerPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(left, top, rad * 2, rad * 2),
      3.14159,
      1.57079,
      false,
      cornerPaint,
    );

    // Top-Right
    canvas.drawLine(
      Offset(left + boxWidth - rad - cornerLen, top),
      Offset(left + boxWidth - rad, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + boxWidth, top + rad),
      Offset(left + boxWidth, top + rad + cornerLen),
      cornerPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(left + boxWidth - rad * 2, top, rad * 2, rad * 2),
      4.71238,
      1.57079,
      false,
      cornerPaint,
    );

    // Bottom-Left
    canvas.drawLine(
      Offset(left + rad, top + boxHeight),
      Offset(left + rad + cornerLen, top + boxHeight),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top + boxHeight - rad - cornerLen),
      Offset(left, top + boxHeight - rad),
      cornerPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(left, top + boxHeight - rad * 2, rad * 2, rad * 2),
      1.57079,
      1.57079,
      false,
      cornerPaint,
    );

    // Bottom-Right
    canvas.drawLine(
      Offset(left + boxWidth - rad - cornerLen, top + boxHeight),
      Offset(left + boxWidth - rad, top + boxHeight),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + boxWidth, top + boxHeight - rad - cornerLen),
      Offset(left + boxWidth, top + boxHeight - rad),
      cornerPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        left + boxWidth - rad * 2,
        top + boxHeight - rad * 2,
        rad * 2,
        rad * 2,
      ),
      0,
      1.57079,
      false,
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
