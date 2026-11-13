import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:m3/core/widgets/barcode_scanner_dialog.dart';

class _DeniedCamera extends MobileScannerPlatform {
  int starts = 0;
  @override
  Widget buildCameraView() => const SizedBox();
  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Stream<BarcodeCapture?> get barcodesStream => const Stream.empty();
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    throw const MobileScannerException(
      errorCode: MobileScannerErrorCode.permissionDenied,
    );
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  late MobileScannerPlatform original;
  late _DeniedCamera camera;
  setUp(() {
    original = MobileScannerPlatform.instance;
    camera = _DeniedCamera();
    MobileScannerPlatform.instance = camera;
    MobileScannerController.resetPlatformSessionOwner();
  });
  tearDown(() {
    MobileScannerPlatform.instance = original;
    MobileScannerController.resetPlatformSessionOwner();
  });

  testWidgets(
    'Resume after camera denial keeps manual fallback without retry',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BarcodeScannerDialog()));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('error_manual_input_button')),
        findsOneWidget,
      );
      final observer =
          tester.state(find.byType(BarcodeScannerDialog))
              as WidgetsBindingObserver;
      observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.starts, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Resume during scanner initialization does not start it twice', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BarcodeScannerDialog()));
    await tester.pumpAndSettle();
    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    scanner.controller!.value = scanner.controller!.value.copyWith(
      isInitialized: true,
      isStarting: true,
    );
    final observer =
        tester.state(find.byType(BarcodeScannerDialog))
            as WidgetsBindingObserver;
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(camera.starts, 1);
    scanner.controller!.value = scanner.controller!.value.copyWith(
      isStarting: false,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
