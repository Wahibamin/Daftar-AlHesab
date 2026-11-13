import 'package:flutter_test/flutter_test.dart';
import 'package:m3/features/inventory/pages/items_page.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/main.dart';
import 'licensing/fakes.dart';

void main() {
  testWidgets('RafApp boots into ItemsPage with inventory navigation', (
    WidgetTester tester,
  ) async {
    final repo = FakeInventoryRepository();
    await repo.seedDefaultDataIfEmpty();

    await tester.pumpWidget(
      RafApp(
        licenseService: FakeLicenseService(),
        home: ItemsPage(
          repository: repo,
          initialItems: const [],
          initialCategories: const [],
          initialUnits: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('دليل المخزون والأصناف'), findsOneWidget);
    expect(find.text('إضافة صنف'), findsOneWidget);
    expect(find.text('الكل'), findsOneWidget);
  });
}
