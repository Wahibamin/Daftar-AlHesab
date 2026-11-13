import '../utils/money.dart';

enum TreasuryAccount {
  cash('cash', 'الصندوق'),
  bank('bank', 'البنك'),
  transfers('transfers', 'الحوالات');

  final String dbValue;
  final String arabicLabel;
  const TreasuryAccount(this.dbValue, this.arabicLabel);
}

enum PaymentMethod {
  cash('cash', 'نقداً'),
  transfer('transfer', 'حوالة'),
  bank('bank', 'بطاقة / بنك'),
  cheque('cheque', 'شيك');

  final String dbValue;
  final String arabicLabel;
  const PaymentMethod(this.dbValue, this.arabicLabel);
  TreasuryAccount get account => switch (this) {
    PaymentMethod.cash => TreasuryAccount.cash,
    PaymentMethod.bank => TreasuryAccount.bank,
    PaymentMethod.transfer => TreasuryAccount.transfers,
    // Default issuing account only. Receipts require an explicit collection
    // account and never become available merely because this value exists.
    PaymentMethod.cheque => TreasuryAccount.bank,
  };
  static PaymentMethod fromString(String value) =>
      PaymentMethod.values.firstWhere(
        (method) => method.dbValue == value,
        orElse: () => throw FormatException('وسيلة دفع غير معروفة: $value'),
      );
}

class AccountCashFlow {
  final Money receipts;
  final Money payments;
  final Money balance;
  final Money reserved;
  const AccountCashFlow({
    this.receipts = Money.zero,
    this.payments = Money.zero,
    this.balance = Money.zero,
    this.reserved = Money.zero,
  });
  static const zero = AccountCashFlow();
  Money get net => receipts - payments;
  Money get available => balance - reserved;
}

class TreasurySnapshot {
  final AccountCashFlow cash;
  final AccountCashFlow bank;
  final AccountCashFlow transfers;
  final Money pendingCheques;
  final int legacyReviewCount;
  const TreasurySnapshot({
    this.cash = AccountCashFlow.zero,
    this.bank = AccountCashFlow.zero,
    this.transfers = AccountCashFlow.zero,
    this.pendingCheques = Money.zero,
    this.legacyReviewCount = 0,
  });
  AccountCashFlow forAccount(TreasuryAccount account) => switch (account) {
    TreasuryAccount.cash => cash,
    TreasuryAccount.bank => bank,
    TreasuryAccount.transfers => transfers,
  };
  AccountCashFlow get total => AccountCashFlow(
    receipts: cash.receipts + bank.receipts + transfers.receipts,
    payments: cash.payments + bank.payments + transfers.payments,
    balance: cash.balance + bank.balance + transfers.balance,
    reserved: cash.reserved + bank.reserved + transfers.reserved,
  );
}
