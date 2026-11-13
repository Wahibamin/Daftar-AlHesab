import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/features/parties/services/communication_service.dart';
import 'package:m3/features/parties/pages/party_editor_page.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';

void main() {
  tearDown(() {
    ContactPickerService.permissionDelegate = null;
    ContactPickerService.pickerDelegate = null;
    ContactPickerService.simulatePermissionDenied = false;
  });
  test(
    'PH05 unimplemented native contact picker never returns a demonstration contact',
    () async {
      expect(await ContactPickerService.pickContact(), isNull);
      expect(await ContactPickerService.checkAndRequestPermission(), isFalse);
      final result = await ContactPickerService.safePickContact();
      expect(result.isSuccess, isFalse);
      expect(result.isGranted, isFalse);
      expect(result.contact, isNull);
      expect(result.message, contains('غير متاح'));
    },
  );
  testWidgets(
    'PH05 contact button explains missing implementation without filling or saving fake data',
    (tester) async {
      final repo = FakePartiesRepository();
      await tester.pumpWidget(
        MaterialApp(home: PartyEditorPage(repository: repo)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('جهات الاتصال'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('اختيار جهات اتصال الهاتف غير متاح'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        isEmpty,
      );
      expect(await repo.getParties(), isEmpty);
    },
  );
}
