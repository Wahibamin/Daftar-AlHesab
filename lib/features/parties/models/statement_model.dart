import 'package:flutter/foundation.dart';
import '../../../core/utils/money.dart';
import 'party_model.dart';

/// Single financial entry in a commercial party's account statement ledger.
@immutable
class AccountStatementEntry {
  final int? id;
  final DateTime date;
  final String
  transactionType; // 'فاتورة مبيعات', 'فاتورة مشتريات', 'سند قبض', 'سند صرف', 'رصيد افتتاحي'
  final String? referenceNumber;
  final String statement;
  final Money debit; // مدين (المسحوبات / ما عليه)
  final Money credit; // دائن (المدفوعات / ما له)
  final Money runningBalance; // الرصيد التراكمي بعد العملية

  const AccountStatementEntry({
    this.id,
    required this.date,
    required this.transactionType,
    this.referenceNumber,
    required this.statement,
    required this.debit,
    required this.credit,
    required this.runningBalance,
  });

  bool get isDebit => debit.isPositive;
  bool get isCredit => credit.isPositive;
}

/// Comprehensive statement summary including historical totals and current standing.
@immutable
class PartyStatementSummary {
  final PartyModel party;
  final Money openingBalance;
  final Money totalDebit;
  final Money totalCredit;
  final Money currentBalance;
  final List<AccountStatementEntry> entries;

  const PartyStatementSummary({
    required this.party,
    required this.openingBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.currentBalance,
    required this.entries,
  });
}
