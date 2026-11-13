import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/accounting/pages/vouchers_list_page.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';

void main() {
  final date = DateTime(2026, 11, 5);
  final cases = [
    (VoucherType.receipt, VoucherPurpose.general, 'قبض عام (بدون طرف)'),
    (VoucherType.payment, VoucherPurpose.general, 'صرف عام (بدون طرف)'),
    (VoucherType.payment, VoucherPurpose.expense, 'مصروف تشغيلي (بدون طرف)'),
  ];
  for (final row in cases) {
    for (final cancelled in [false, true]) {
      testWidgets(
        'PH05 ${row.$1} ${row.$2} cancelled=$cancelled has accurate label without reposting',
        (tester) async {
          final repo = FakeVouchersRepository();
          final id = await repo.createVoucher(
            VoucherModel(
              voucherNumber: 'PH05-LABEL',
              voucherType: row.$1,
              purpose: row.$2,
              statement: 'PH05 Label test',
              amount: const Money(2500),
              paymentMethod: PaymentMethod.bank,
              voucherDate: date,
              createdAt: date,
            ),
          );
          if (cancelled) await repo.deleteVoucher(id);
          final before = (await repo.getVoucherById(id))!.toMap();
          final balance = (await repo.getTreasuryBalances()).bank.balance;
          await tester.pumpWidget(
            MaterialApp(
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: VouchersListPage(
                  vouchersRepo: repo,
                  partiesRepo: FakePartiesRepository(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(row.$3), findsOneWidget);
          expect(find.text('مصروف عام (بدون طرف)'), findsNothing);
          expect((await repo.getVoucherById(id))!.toMap(), before);
          expect((await repo.getTreasuryBalances()).bank.balance, balance);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final type in VoucherType.values) {
    testWidgets('PH05 $type linked party keeps its actual name', (
      tester,
    ) async {
      final parties = FakePartiesRepository();
      final party = await parties.insertParty(
        PartyModel(
          name: 'طرف PH05',
          phone: '0500000000',
          type: PartyType.both,
          createdAt: date,
          updatedAt: date,
        ),
      );
      final repo = FakeVouchersRepository();
      await repo.createVoucher(
        VoucherModel(
          voucherNumber: 'PH05-PARTY',
          voucherType: type,
          partyId: party,
          amount: const Money(100),
          paymentMethod: PaymentMethod.cash,
          voucherDate: date,
          createdAt: date,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: VouchersListPage(vouchersRepo: repo, partiesRepo: parties),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('طرف PH05'), findsOneWidget);
      expect(find.textContaining('(بدون طرف)'), findsNothing);
    });
  }
}
