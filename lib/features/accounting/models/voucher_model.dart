import 'package:flutter/foundation.dart';
import '../../../core/utils/money.dart';
import '../../../core/accounting/financial_accounts.dart';
export '../../../core/accounting/financial_accounts.dart';

enum VoucherPurpose { general, expense }

/// Financial voucher transaction type (Receipt or Payment).
enum VoucherType {
  receipt('receipt', 'سند قبض'),
  payment('payment', 'سند صرف');

  final String dbValue;
  final String arabicLabel;

  const VoucherType(this.dbValue, this.arabicLabel);

  static VoucherType fromString(String value) {
    return VoucherType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => VoucherType.receipt,
    );
  }
}

/// Lifecycle status of a financial voucher.
enum VoucherStatus {
  approved('approved', 'معتمد'),
  cancelled('cancelled', 'ملغى');

  final String dbValue;
  final String arabicLabel;

  const VoucherStatus(this.dbValue, this.arabicLabel);

  static VoucherStatus fromString(String value) {
    return VoucherStatus.values.firstWhere(
      (status) => status.dbValue == value,
      orElse: () => VoucherStatus.approved,
    );
  }
}

/// Official Financial Voucher Model (Receipt & Payment Vouchers).
///
/// Records treasury and party cash flows with strict integer amounts.
@immutable
class VoucherModel {
  final int? id;
  final String voucherNumber;
  final VoucherType voucherType;
  final VoucherStatus status;
  final int? partyId;
  final Money amount;
  final PaymentMethod paymentMethod;
  final TreasuryAccount chequeAccount;
  final VoucherPurpose purpose;
  final String? expenseCategory;
  final String? referenceNumber;
  final String? statement; // البيان
  final DateTime voucherDate;
  final DateTime createdAt;

  const VoucherModel({
    this.id,
    required this.voucherNumber,
    required this.voucherType,
    this.status = VoucherStatus.approved,
    this.partyId,
    required this.amount,
    required this.paymentMethod,
    this.chequeAccount = TreasuryAccount.bank,
    this.purpose = VoucherPurpose.general,
    this.expenseCategory,
    this.referenceNumber,
    this.statement,
    required this.voucherDate,
    required this.createdAt,
  });

  int get amountInt => amount.rawUnits;

  // ---------------------------------------------------------------------------
  // Financial State Indicators
  // ---------------------------------------------------------------------------

  /// Whether this voucher is currently active and approved.
  bool get isApproved => status == VoucherStatus.approved;

  /// Whether this voucher was voided or cancelled.
  bool get isCancelled => status == VoucherStatus.cancelled;

  /// Whether this voucher brings cash/funds INTO our treasury (Receipt / قبض).
  bool get isReceipt => voucherType == VoucherType.receipt;

  /// Whether this voucher pays cash/funds OUT of our treasury (Payment / صرف).
  bool get isPayment => voucherType == VoucherType.payment;
  bool get isExpense => purpose == VoucherPurpose.expense;

  /// New vouchers post immediately; cancellation is only a persisted transition.
  void validateForPosting() {
    if (!isApproved) throw StateError('لا يمكن ترحيل سند ملغى');
    if (!amount.isPositive) {
      throw ArgumentError('مبلغ السند يجب أن يكون أكبر من صفر');
    }
    if (isExpense &&
        (!isPayment ||
            partyId != null ||
            (statement?.trim().isEmpty ?? true))) {
      throw ArgumentError(
        'المصروف يتطلب سند صرف وبياناً واضحاً دون ربطه برصيد طرف',
      );
    }
    if (!isExpense && expenseCategory != null) {
      throw ArgumentError('تصنيف المصروف يخص المصروفات فقط');
    }
  }

  // ---------------------------------------------------------------------------
  // Serialization (SQLite Map)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'voucher_number': voucherNumber,
      'voucher_type': voucherType.dbValue,
      'status': status.dbValue,
      'party_id': partyId,
      'amount_int': amountInt,
      'payment_method': paymentMethod.dbValue,
      'cheque_account': chequeAccount.dbValue,
      'purpose': purpose.name,
      'expense_category': expenseCategory,
      'reference_number': referenceNumber,
      'statement': statement,
      'voucher_date': voucherDate.millisecondsSinceEpoch,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory VoucherModel.fromMap(Map<String, dynamic> map) {
    return VoucherModel(
      id: map['id'] as int?,
      voucherNumber: map['voucher_number'] as String,
      voucherType: VoucherType.fromString(map['voucher_type'] as String),
      status: VoucherStatus.fromString(
        (map['status'] as String?) ?? 'approved',
      ),
      partyId: map['party_id'] as int?,
      amount: Money(map['amount_int'] as int),
      paymentMethod: PaymentMethod.fromString(map['payment_method'] as String),
      chequeAccount: TreasuryAccount.values.firstWhere(
        (a) => a.dbValue == (map['cheque_account'] ?? 'bank'),
      ),
      purpose: VoucherPurpose.values.firstWhere(
        (value) => value.name == (map['purpose'] ?? 'general'),
      ),
      expenseCategory: map['expense_category'] as String?,
      referenceNumber: map['reference_number'] as String?,
      statement: map['statement'] as String?,
      voucherDate: DateTime.fromMillisecondsSinceEpoch(
        map['voucher_date'] as int,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  VoucherModel copyWith({
    int? id,
    String? voucherNumber,
    VoucherType? voucherType,
    VoucherStatus? status,
    int? partyId,
    Money? amount,
    PaymentMethod? paymentMethod,
    TreasuryAccount? chequeAccount,
    VoucherPurpose? purpose,
    String? expenseCategory,
    String? referenceNumber,
    String? statement,
    DateTime? voucherDate,
    DateTime? createdAt,
  }) {
    return VoucherModel(
      id: id ?? this.id,
      voucherNumber: voucherNumber ?? this.voucherNumber,
      voucherType: voucherType ?? this.voucherType,
      status: status ?? this.status,
      partyId: partyId ?? this.partyId,
      amount: amount ?? this.amount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      chequeAccount: chequeAccount ?? this.chequeAccount,
      purpose: purpose ?? this.purpose,
      expenseCategory: expenseCategory ?? this.expenseCategory,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      statement: statement ?? this.statement,
      voucherDate: voucherDate ?? this.voucherDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoucherModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          voucherNumber == other.voucherNumber &&
          voucherType == other.voucherType &&
          status == other.status &&
          amount == other.amount &&
          partyId == other.partyId;

  @override
  int get hashCode =>
      Object.hash(id, voucherNumber, voucherType, status, amount, partyId);
}
