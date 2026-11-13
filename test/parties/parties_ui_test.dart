import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/theme/raf_design_system.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/pages/account_statement_page.dart';
import 'package:m3/features/parties/pages/parties_page.dart';
import 'package:m3/features/parties/pages/party_editor_page.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/parties/services/communication_service.dart';
import 'package:m3/features/parties/widgets/balance_badge.dart';
import 'package:m3/features/parties/widgets/party_card.dart';

Widget _wrapWithRtlApp(Widget child) {
  return MaterialApp(
    theme: RafTheme.lightTheme,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

void main() {
  late FakePartiesRepository repo;

  setUp(() async {
    repo = FakePartiesRepository();
    await repo.seedDefaultDataIfEmpty();
  });

  group('Parties Widgets & UI Verification (Isolated In-Memory)', () {
    testWidgets(
      'BalanceBadge renders debtor, creditor, and settled states correctly',
      (tester) async {
        final now = DateTime.now();

        final debtor = PartyModel(
          id: 1,
          name: 'عميل مدين',
          phone: '0501111111',
          type: PartyType.customer,
          currentBalance: const Money(-50000), // -500.00 SAR (عليه)
          createdAt: now,
          updatedAt: now,
        );

        final creditor = PartyModel(
          id: 2,
          name: 'مورد دائن',
          phone: '0502222222',
          type: PartyType.supplier,
          currentBalance: const Money(120000), // +1,200.00 SAR (له)
          createdAt: now,
          updatedAt: now,
        );

        final settled = PartyModel(
          id: 3,
          name: 'عميل خالص',
          phone: '0503333333',
          type: PartyType.customer,
          currentBalance: Money.zero,
          createdAt: now,
          updatedAt: now,
        );

        await tester.pumpWidget(
          _wrapWithRtlApp(
            Scaffold(
              body: Column(
                children: [
                  BalanceBadge(party: debtor),
                  BalanceBadge(party: creditor),
                  BalanceBadge(party: settled),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('مدين (عليه): 500.00'), findsOneWidget);
        expect(find.text('دائن (له): 1,200.00'), findsOneWidget);
        expect(find.text('خالص (0.00)'), findsOneWidget);
      },
    );

    testWidgets(
      'PartyCard renders cleanly and does not overflow on narrow 360px screen',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final party = PartyModel(
          id: 1,
          name: 'شركة التجارة المتقدمة العالمية للتوريدات والخدمات اللوجستية',
          phone: '0501234567',
          type: PartyType.customer,
          currentBalance: const Money(-250000),
          creditLimit: const Money(1000000),
          address: 'الرياض - حي الملز - شارع الستين التجاري',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          _wrapWithRtlApp(
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(RafSpacing.md),
                child: PartyCard(party: party),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'شركة التجارة المتقدمة العالمية للتوريدات والخدمات اللوجستية',
          ),
          findsOneWidget,
        );
        expect(find.text('050 123 4567'), findsOneWidget);
        expect(find.text('كشف الحساب'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PartyEditorPage imports contact and formats credit limit properly',
      (tester) async {
        ContactPickerService.permissionDelegate = () async => true;
        ContactPickerService.pickerDelegate = () async =>
            ContactPickerService.mockContacts.first;
        addTearDown(() {
          ContactPickerService.permissionDelegate = null;
          ContactPickerService.pickerDelegate = null;
        });
        await tester.pumpWidget(
          _wrapWithRtlApp(
            PartyEditorPage(repository: repo, initialType: PartyType.customer),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('إضافة عميل جديد'), findsOneWidget);

        // Tap contact picker button
        final contactBtn = find.text('جهات الاتصال');
        expect(contactBtn, findsOneWidget);
        await tester.tap(contactBtn);
        await tester.pumpAndSettle();

        // First mock contact name is populated
        expect(find.text('مؤسسة النور للتوريدات'), findsOneWidget);
        expect(find.text('050 111 2233'), findsOneWidget);

        // Enter Credit Limit with thousands separator
        final creditField = find.byType(TextFormField).at(4);
        await tester.enterText(creditField, '50000.00');
        await tester.pumpAndSettle();

        expect(find.text('50,000.00'), findsOneWidget);
      },
    );

    testWidgets(
      'PartyEditorPage handles contact permission denial gracefully without crashing',
      (tester) async {
        ContactPickerService.simulatePermissionDenied = true;
        addTearDown(() {
          ContactPickerService.simulatePermissionDenied = false;
        });

        await tester.pumpWidget(
          _wrapWithRtlApp(
            PartyEditorPage(repository: repo, initialType: PartyType.customer),
          ),
        );
        await tester.pumpAndSettle();

        final contactBtn = find.text('جهات الاتصال');
        await tester.tap(contactBtn);
        await tester.pumpAndSettle();

        // Verify that polite warning SnackBar is displayed and app did not crash
        expect(
          find.text(
            'تم رفض إذن الوصول لجهات الاتصال. يمكنك كتابة الرقم يدوياً.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PartiesPage lists parties, switches tabs, and filters by debt',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final parties = await repo.getParties();

        await tester.pumpWidget(
          _wrapWithRtlApp(
            PartiesPage(repository: repo, initialParties: parties),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('دليل العملاء والموردين'), findsOneWidget);
        expect(find.text('العملاء'), findsOneWidget);
        expect(find.text('الموردون'), findsOneWidget);

        // Under Customers tab: shows customer
        expect(find.text('مؤسسة الأفق للتجارة'), findsOneWidget);
        expect(find.text('سوبرماركت البركة'), findsOneWidget);
        expect(find.text('شركة الوادي للصناعات الغذائية'), findsNothing);

        // Switch to Suppliers tab
        await tester.tap(find.text('الموردون'));
        await tester.pumpAndSettle();

        expect(find.text('شركة الوادي للصناعات الغذائية'), findsOneWidget);
        expect(find.text('مصنع الجزيرة للتعبئة والتغليف'), findsOneWidget);
        expect(find.text('مؤسسة الأفق للتجارة'), findsNothing);

        // Switch back to Customers
        await tester.tap(find.text('العملاء'));
        await tester.pumpAndSettle();

        // Tap 'عليهم مديونيات' filter chip
        final debtFilterChip = find.text('عليهم مديونيات (1)');
        expect(debtFilterChip, findsOneWidget);
        await tester.tap(debtFilterChip);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Only debtor customer is shown
        expect(find.text('مؤسسة الأفق للتجارة'), findsOneWidget);
        expect(find.text('سوبرماركت البركة'), findsNothing);
      },
    );

    testWidgets(
      'AccountStatementPage displays statement movements and balance cards',
      (tester) async {
        final party = (await repo.getPartyById(1))!;
        final summary = await repo.getAccountStatement(party.id!);

        await tester.pumpWidget(
          _wrapWithRtlApp(
            AccountStatementPage(
              party: party,
              repository: repo,
              initialSummary: summary,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('كشف حساب الطرف'), findsOneWidget);
        expect(find.text('مؤسسة الأفق للتجارة'), findsOneWidget);
        expect(find.text('الرصيد الحالي'), findsOneWidget);
        expect(find.text('إجمالي المدين'), findsOneWidget);
        expect(find.text('5,000.00'), findsOneWidget);
        expect(find.text('إجمالي الدائن'), findsOneWidget);
        // Both Current Balance and Total Credit cards display 2,500.00
        expect(find.text('2,500.00'), findsNWidgets(2));

        // Movement entries rendered
        expect(find.text('فاتورة مبيعات رقم INV-2026-001'), findsOneWidget);
        expect(find.text('دفعة نقدية مسددة'), findsOneWidget);
      },
    );

    test(
      'CommunicationService formats balance reminder message and builds valid URIs',
      () {
        final msg = CommunicationService.formatBalanceMessage(
          partyName: 'شركة النور',
          balance: const Money(-350000), // -3,500.00 SAR
        );

        expect(
          msg,
          'أهلاً بك شركة النور، نود تذكيرك بأن رصيدكم الحالي لدى [دفتر الحساب] هو: 3,500.00.',
        );

        final waUri = CommunicationService.buildWhatsAppUri('0501234567', msg);
        expect(waUri.host, 'wa.me');
        expect(waUri.path, '/966501234567');
        expect(waUri.queryParameters['text'], contains('3,500.00.'));

        final callUri = CommunicationService.buildCallUri('050-123-4567');
        expect(callUri.scheme, 'tel');
        expect(callUri.path, '0501234567');
      },
    );
  });
}
