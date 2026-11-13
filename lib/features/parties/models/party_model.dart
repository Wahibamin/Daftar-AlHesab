import 'package:flutter/foundation.dart';
import '../../../core/utils/money.dart';

/// Relationship party classification (Customer, Supplier, or Dual).
enum PartyType {
  customer('customer', 'عميل'),
  supplier('supplier', 'مورد'),
  both('both', 'عميل ومورد');

  final String dbValue;
  final String arabicLabel;

  const PartyType(this.dbValue, this.arabicLabel);

  static PartyType fromString(String value) {
    return PartyType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => PartyType.customer,
    );
  }
}

/// Commercial Party Model (Customer / Supplier / Both).
///
/// **Balance Invariant:**
/// - `currentBalance > 0`: Party is Creditor (له مستحقات علينا / دائن).
/// - `currentBalance < 0`: Party is Debtor (عليه مستحقات لنا / مدين).
/// - `currentBalance == 0`: Account is fully settled (متزن).
@immutable
class PartyModel {
  final int? id;
  final String name;
  final String phone;
  final PartyType type;
  final Money currentBalance;
  final Money openingBalance;
  final Money creditLimit;
  final String? address;
  final String? taxNumber;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PartyModel({
    this.id,
    required this.name,
    required this.phone,
    required this.type,
    this.currentBalance = Money.zero,
    this.openingBalance = Money.zero,
    this.creditLimit = Money.zero,
    this.address,
    this.taxNumber,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  int get currentBalanceInt => currentBalance.rawUnits;
  int get openingBalanceInt => openingBalance.rawUnits;
  int get creditLimitInt => creditLimit.rawUnits;

  // ---------------------------------------------------------------------------
  // Financial & Accounting Intelligence
  // ---------------------------------------------------------------------------

  /// Whether party has funds in our custody (Creditor / له).
  bool get isCreditor => currentBalance.isPositive;

  /// Whether party owes us money (Debtor / عليه).
  bool get isDebtor => currentBalance.isNegative;

  /// Whether the account is balanced to zero.
  bool get isSettled => currentBalance.isZero;

  /// Absolute monetary balance owed or due.
  Money get absoluteBalance => currentBalance.abs;

  /// Whether debtor balance has breached the assigned credit limit.
  bool get exceedsCreditLimit {
    if (creditLimit.isZero || !isDebtor) return false;
    return absoluteBalance > creditLimit;
  }

  /// Remaining available credit facility before reaching limit.
  Money get remainingCreditAvailable {
    if (creditLimit.isZero) return Money.zero;
    if (!isDebtor) return creditLimit;
    if (absoluteBalance >= creditLimit) return Money.zero;
    return creditLimit - absoluteBalance;
  }

  /// Official Arabic accounting balance description.
  String get balanceStatusArabic {
    if (isCreditor) return 'دائن (له)';
    if (isDebtor) return 'مدين (عليه)';
    return 'متزن';
  }

  // ---------------------------------------------------------------------------
  // Serialization (SQLite Map)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'phone': phone,
      'type': type.dbValue,
      'current_balance_int': currentBalanceInt,
      'opening_balance_int': openingBalanceInt,
      'credit_limit_int': creditLimitInt,
      'address': address,
      'tax_number': taxNumber,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory PartyModel.fromMap(Map<String, dynamic> map) {
    return PartyModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      phone: map['phone'] as String,
      type: PartyType.fromString(map['type'] as String),
      currentBalance: Money(map['current_balance_int'] as int),
      openingBalance: Money((map['opening_balance_int'] as int?) ?? 0),
      creditLimit: Money((map['credit_limit_int'] as int?) ?? 0),
      address: map['address'] as String?,
      taxNumber: map['tax_number'] as String?,
      isActive: (map['is_active'] as int?) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  PartyModel copyWith({
    int? id,
    String? name,
    String? phone,
    PartyType? type,
    Money? currentBalance,
    Money? openingBalance,
    Money? creditLimit,
    String? address,
    String? taxNumber,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PartyModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      type: type ?? this.type,
      currentBalance: currentBalance ?? this.currentBalance,
      openingBalance: openingBalance ?? this.openingBalance,
      creditLimit: creditLimit ?? this.creditLimit,
      address: address ?? this.address,
      taxNumber: taxNumber ?? this.taxNumber,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartyModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          phone == other.phone &&
          type == other.type &&
          currentBalance == other.currentBalance &&
          openingBalance == other.openingBalance;

  @override
  int get hashCode =>
      Object.hash(id, name, phone, type, currentBalance, openingBalance);
}
