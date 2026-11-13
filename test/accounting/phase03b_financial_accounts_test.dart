import 'dart:io';
import 'package:m3/core/accounting/settlements_repository.dart';
import '../../test_support/funded_treasury.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/database/business_data_wiper.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/reports/repositories/reports_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final manager = AppDatabase.instance;
  final invoices = SqliteInvoicesRepository();
  final vouchers = SqliteVouchersRepository();
  final reports = SqliteReportsRepository();
  final inventory = SqliteInventoryRepository();
  final date = DateTime(2026, 11, 5, 12);
  late Directory directory;
  late int item, party;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'daftar_phase03b_accounts_',
    );
    manager.configureForTesting(
      factory: databaseFactoryFfi,
      path: '${directory.path}/isolated.db',
    );
    final unit = await inventory.insertUnit(
      UnitModel(name: 'قطعة', symbol: 'حبة', createdAt: date),
    );
    item = await inventory.insertItem(
      ItemModel(
        code: 'ACCOUNTS-B',
        name: 'صنف الحسابات',
        unitId: unit,
        costPrice: const Money(6000),
        sellingPrice: const Money(10000),
        stockQuantity: 20,
        createdAt: date,
        updatedAt: date,
      ),
    );
    party = await SqlitePartiesRepository().insertParty(
      PartyModel(
        name: 'طرف اختبار',
        phone: '0500000000',
        type: PartyType.both,
        createdAt: date,
        updatedAt: date,
      ),
    );
  });
  tearDown(() async {
    await manager.close();
    await directory.delete(recursive: true);
  });
  InvoiceModel invoice(InvoiceType type, PaymentMethod method) =>
      InvoiceModel.buildWithItems(
        invoiceNumber: 'ACCOUNT-INV',
        invoiceType: type,
        partyId: party,
        paymentType: PaymentType.partial,
        paymentMethod: method,
        paidAmount: const Money(3000),
        items: [
          InvoiceItemModel.create(
            itemId: item,
            quantity: 1,
            unitPrice: const Money(10000),
          ),
        ],
        invoiceDate: date,
        createdAt: date,
        updatedAt: date,
      );
  VoucherModel voucher({
    String number = 'ACCOUNT-V',
    PaymentMethod method = PaymentMethod.cash,
    VoucherType type = VoucherType.payment,
    VoucherPurpose purpose = VoucherPurpose.general,
    int? partyId,
    int amount = 2500,
    String? statement = 'بيان الاختبار',
  }) => VoucherModel(
    voucherNumber: number,
    voucherType: type,
    partyId: partyId,
    amount: Money(amount),
    paymentMethod: method,
    purpose: purpose,
    expenseCategory: purpose == VoucherPurpose.expense ? 'خدمات' : null,
    statement: statement,
    voucherDate: date,
    createdAt: date,
  );
  Future<ProfitLossReportModel> profit() => reports.getProfitLossReport(
    startDate: date.subtract(const Duration(days: 1)),
    endDate: date.add(const Duration(days: 1)),
  );

  for (final type in InvoiceType.values) {
    for (final method in PaymentMethod.values) {
      test(
        'Phase03B $type $method posts only to its account and reverses once',
        () async {
          final incoming =
              type == InvoiceType.sale || type == InvoiceType.purchaseReturn;
          final target = method == PaymentMethod.cheque
              ? TreasuryAccount.bank
              : method.account;
          final funding = incoming ? 0 : 10000;
          if (!incoming) {
            await fundTreasury(
              await manager.database,
              amount: funding,
              method: method == PaymentMethod.cheque ? 'bank' : method.dbValue,
            );
          }
          final request = invoice(type, method);
          final id = await invoices.saveAndFinalizeInvoice(request);
          final sign = incoming ? 1 : -1;
          final balance = await vouchers.getTreasuryBalances();
          for (final account in TreasuryAccount.values) {
            expect(
              balance.forAccount(account).balance.rawUnits,
              account == target
                  ? funding + (method == PaymentMethod.cheque ? 0 : 3000 * sign)
                  : 0,
            );
          }
          expect(
            balance.forAccount(target).reserved.rawUnits,
            method == PaymentMethod.cheque && !incoming ? 3000 : 0,
          );
          expect(
            balance.pendingCheques.rawUnits,
            method == PaymentMethod.cheque && incoming ? 3000 : 0,
          );
          final saved = (await invoices.getInvoiceById(id))!;
          expect(saved.paymentMethod, method);
          await invoices.saveAndFinalizeInvoice(request.copyWith(id: id));
          await expectLater(
            invoices.saveAndFinalizeInvoice(
              saved.copyWith(
                paymentMethod: method == PaymentMethod.cash
                    ? PaymentMethod.bank
                    : PaymentMethod.cash,
              ),
            ),
            throwsA(isA<InvoiceConflictException>()),
          );
          final flow = await reports.getTreasuryCashFlowReport(
            startDate: date,
            endDate: date,
          );
          expect(
            flow.accounts.forAccount(target).net.rawUnits,
            method == PaymentMethod.cheque ? 0 : 3000 * sign,
          );
          expect(
            flow.currentTreasuryBalance,
            (await vouchers.getTreasuryBalances()).total.available,
          );
          await invoices.cancelInvoice(id);
          await invoices.cancelInvoice(id);
          expect(
            (await vouchers.getTreasuryBalances()).total.available,
            Money(funding),
          );
        },
      );
    }
  }
  test(
    'Phase03B cheque stays uncollected until explicit bank collection',
    () async {
      await vouchers.createVoucher(
        voucher(type: VoucherType.receipt, method: PaymentMethod.cheque),
      );
      final before = await vouchers.getTreasuryBalances();
      expect(before.total.available, Money.zero);
      expect(before.pendingCheques, const Money(2500));
      final settlements = SettlementsRepository();
      final cheque = (await settlements.getCheques()).single;
      await settlements.clearCheque(
        cheque['id'] as int,
        account: TreasuryAccount.bank,
        effectiveAt: DateTime.now(),
      );
      expect(
        (await vouchers.getTreasuryBalances()).bank.available,
        const Money(2500),
      );
      expect(
        (await vouchers.getTreasuryBalances()).transfers.available,
        Money.zero,
      );
    },
  );
  test(
    'Phase03B independent voucher with matching invoice reference is counted once in its own account',
    () async {
      await invoices.saveAndFinalizeInvoice(
        invoice(InvoiceType.sale, PaymentMethod.bank),
      );
      final value = voucher(
        type: VoucherType.receipt,
        method: PaymentMethod.transfer,
      ).copyWith(referenceNumber: 'ACCOUNT-INV');
      final id = await vouchers.createVoucher(value);
      final result = await vouchers.getTreasuryBalances();
      expect(result.cash.balance, Money.zero);
      expect(result.bank.balance, const Money(3000));
      expect(result.transfers.balance, const Money(2500));
      await expectLater(vouchers.createVoucher(value), throwsA(anything));
      await vouchers.deleteVoucher(id);
      await vouchers.deleteVoucher(id);
      expect(
        (await vouchers.getTreasuryBalances()).transfers.balance,
        Money.zero,
      );
    },
  );
  test('Phase03B general disbursement is not an operating expense', () async {
    await fundTreasury(await manager.database, amount: 10000);
    await vouchers.createVoucher(voucher());
    expect((await profit()).operatingExpenses, Money.zero);
    expect(
      (await vouchers.getTreasuryBalances()).cash.available,
      const Money(7500),
    );
  });
  for (final method in PaymentMethod.values) {
    test(
      'Phase03B expense $method is one payment, one expense, no party balance, cancellation idempotent',
      () async {
        final account = method == PaymentMethod.cheque
            ? TreasuryAccount.bank
            : method.account;
        await fundTreasury(
          await manager.database,
          amount: 10000,
          method: method == PaymentMethod.cheque ? 'bank' : method.dbValue,
        );
        final id = await vouchers.createVoucher(
          voucher(method: method, purpose: VoucherPurpose.expense),
        );
        expect((await profit()).operatingExpenses, const Money(2500));
        expect((await profit()).netProfit, const Money(-2500));
        expect(
          (await vouchers.getTreasuryBalances()).forAccount(account).available,
          const Money(7500),
        );
        expect(
          (await SqlitePartiesRepository().getPartyById(party))!.currentBalance,
          Money.zero,
        );
        final expenses = await vouchers.getVouchers(
          purpose: VoucherPurpose.expense,
        );
        expect(expenses.length, 1);
        expect(expenses.single.expenseCategory, 'خدمات');
        await vouchers.deleteVoucher(id);
        await vouchers.deleteVoucher(id);
        expect((await profit()).operatingExpenses, Money.zero);
        expect(
          (await vouchers.getTreasuryBalances()).forAccount(account).available,
          const Money(10000),
        );
        expect(
          (await vouchers.getVouchers(
            purpose: VoucherPurpose.expense,
          )).single.isCancelled,
          isTrue,
        );
      },
    );
  }
  for (final invalid in ['receipt', 'party', 'empty', 'zero', 'negative']) {
    test(
      'Phase03B invalid expense $invalid is rejected before any financial effect',
      () async {
        final request = voucher(
          purpose: VoucherPurpose.expense,
          type: invalid == 'receipt'
              ? VoucherType.receipt
              : VoucherType.payment,
          partyId: invalid == 'party' ? party : null,
          statement: invalid == 'empty' ? ' ' : 'مصروف اختبار',
          amount: invalid == 'zero'
              ? 0
              : invalid == 'negative'
              ? -1
              : 2500,
        );
        await expectLater(vouchers.createVoucher(request), throwsArgumentError);
        expect(await vouchers.getVouchers(), isEmpty);
        expect(await vouchers.getTreasuryBalance(), Money.zero);
      },
    );
  }
  test(
    'Phase03B cumulative account balances and period flows remain separate across reopen',
    () async {
      await vouchers.createVoucher(
        voucher(
          number: 'OLD',
          method: PaymentMethod.bank,
          type: VoucherType.receipt,
        ).copyWith(voucherDate: date.subtract(const Duration(days: 2))),
      );
      await vouchers.createVoucher(
        voucher(
          number: 'NOW',
          method: PaymentMethod.bank,
          purpose: VoucherPurpose.expense,
        ),
      );
      await manager.close();
      final report = await reports.getTreasuryCashFlowReport(
        startDate: date,
        endDate: date,
      );
      expect(report.accounts.bank.receipts, Money.zero);
      expect(report.accounts.bank.payments, const Money(2500));
      expect(report.accounts.bank.balance, Money.zero);
      expect((await profit()).operatingExpenses, const Money(2500));
    },
  );
  test(
    'Phase03B business-data wipe clears expenses and all account balances',
    () async {
      await fundTreasury(await manager.database);
      await vouchers.createVoucher(voucher(purpose: VoucherPurpose.expense));
      await BusinessDataWiper().clearAllBusinessData();
      expect(
        await vouchers.getVouchers(purpose: VoucherPurpose.expense),
        isEmpty,
      );
      expect((await vouchers.getTreasuryBalances()).total.balance, Money.zero);
    },
  );
}
