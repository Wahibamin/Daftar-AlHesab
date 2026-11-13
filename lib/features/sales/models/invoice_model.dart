import 'package:flutter/foundation.dart';
import '../../../core/utils/money.dart';
import '../../../core/accounting/financial_accounts.dart';
export '../../../core/accounting/financial_accounts.dart';

/// Transaction type of the commercial invoice.
enum InvoiceType {
  sale('sale', 'فاتورة مبيعات'),
  purchase('purchase', 'فاتورة مشتريات'),
  saleReturn('sale_return', 'مرتجع مبيعات'),
  purchaseReturn('purchase_return', 'مرتجع مشتريات');

  final String dbValue;
  final String arabicLabel;

  const InvoiceType(this.dbValue, this.arabicLabel);

  static InvoiceType fromString(String value) {
    return InvoiceType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => InvoiceType.sale,
    );
  }
}

/// Official lifecycle status of an invoice.
enum InvoiceStatus {
  draft('draft', 'مسودة'),
  approved('approved', 'معتمدة'),
  cancelled('cancelled', 'ملغاة');

  final String dbValue;
  final String arabicLabel;

  const InvoiceStatus(this.dbValue, this.arabicLabel);

  static InvoiceStatus fromString(String value) {
    return InvoiceStatus.values.firstWhere(
      (status) => status.dbValue == value,
      orElse: () => InvoiceStatus.draft,
    );
  }
}

/// Commercial settlement payment structure.
enum PaymentType {
  cash('cash', 'كامل السداد'),
  credit('credit', 'آجل'),
  partial('partial', 'جزئي'),
  transfer('transfer', 'تحويل بنكي');

  final String dbValue;
  final String arabicLabel;

  const PaymentType(this.dbValue, this.arabicLabel);

  static PaymentType fromString(String value) {
    return PaymentType.values.firstWhere(
      (payment) => payment.dbValue == value,
      orElse: () => PaymentType.cash,
    );
  }
}

/// Individual item/line entry within an invoice.
@immutable
class InvoiceItemModel {
  final int? id;
  final int? invoiceId;
  final int itemId;
  final int quantity;
  final Money unitPrice;
  final Money unitCost;
  final Money discount;
  final int taxRatePercent;
  final Money taxAmount;
  final Money totalPrice;

  const InvoiceItemModel({
    this.id,
    this.invoiceId,
    required this.itemId,
    required this.quantity,
    required this.unitPrice,
    this.unitCost = Money.zero,
    this.discount = Money.zero,
    this.taxRatePercent = 0,
    this.taxAmount = Money.zero,
    required this.totalPrice,
  });

  int get quantityInt => quantity;
  int get unitPriceInt => unitPrice.rawUnits;
  int get unitCostInt => unitCost.rawUnits;
  int get discountInt => discount.rawUnits;
  int get taxAmountInt => taxAmount.rawUnits;
  int get totalPriceInt => totalPrice.rawUnits;

  /// Factory constructor that automatically calculates exact financial line totals
  /// using strict integer arithmetic with zero tax.
  factory InvoiceItemModel.create({
    int? id,
    int? invoiceId,
    required int itemId,
    required int quantity,
    required Money unitPrice,
    Money unitCost = Money.zero,
    Money discount = Money.zero,
    int taxRatePercent = 0,
  }) {
    final gross = unitPrice * quantity;
    final total = gross - discount;

    return InvoiceItemModel(
      id: id,
      invoiceId: invoiceId,
      itemId: itemId,
      quantity: quantity,
      unitPrice: unitPrice,
      unitCost: unitCost,
      discount: discount,
      taxRatePercent: 0,
      taxAmount: Money.zero,
      totalPrice: total,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (invoiceId != null) 'invoice_id': invoiceId,
      'item_id': itemId,
      'quantity_int': quantityInt,
      'unit_price_int': unitPriceInt,
      'unit_cost_int': unitCostInt,
      'discount_int': discountInt,
      'tax_rate_percent': taxRatePercent,
      'tax_amount_int': taxAmountInt,
      'total_price_int': totalPriceInt,
    };
  }

  factory InvoiceItemModel.fromMap(Map<String, dynamic> map) {
    return InvoiceItemModel(
      id: map['id'] as int?,
      invoiceId: map['invoice_id'] as int?,
      itemId: map['item_id'] as int,
      quantity: map['quantity_int'] as int,
      unitPrice: Money(map['unit_price_int'] as int),
      unitCost: Money((map['unit_cost_int'] as int?) ?? 0),
      discount: Money((map['discount_int'] as int?) ?? 0),
      taxRatePercent: (map['tax_rate_percent'] as int?) ?? 0,
      taxAmount: Money((map['tax_amount_int'] as int?) ?? 0),
      totalPrice: Money(map['total_price_int'] as int),
    );
  }

  InvoiceItemModel copyWith({
    int? id,
    int? invoiceId,
    int? itemId,
    int? quantity,
    Money? unitPrice,
    Money? unitCost,
    Money? discount,
    int? taxRatePercent,
    Money? taxAmount,
    Money? totalPrice,
  }) {
    return InvoiceItemModel(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      itemId: itemId ?? this.itemId,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      unitCost: unitCost ?? this.unitCost,
      discount: discount ?? this.discount,
      taxRatePercent: taxRatePercent ?? this.taxRatePercent,
      taxAmount: taxAmount ?? this.taxAmount,
      totalPrice: totalPrice ?? this.totalPrice,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceItemModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          invoiceId == other.invoiceId &&
          itemId == other.itemId &&
          quantity == other.quantity &&
          unitPrice == other.unitPrice &&
          unitCost == other.unitCost &&
          totalPrice == other.totalPrice;

  @override
  int get hashCode => Object.hash(
    id,
    invoiceId,
    itemId,
    quantity,
    unitPrice,
    unitCost,
    totalPrice,
  );
}

/// Commercial Invoice Header Model (Sales / Purchases / Returns).
@immutable
class InvoiceModel {
  final int? id;
  final String invoiceNumber;
  final int? partyId;
  final InvoiceType invoiceType;
  final InvoiceStatus status;
  final PaymentType paymentType;
  final PaymentMethod paymentMethod;
  final TreasuryAccount chequeAccount;
  final Money subtotal;
  final Money discount;
  final Money tax;
  final Money total;
  final Money paidAmount;
  final Money remainingAtIssue;
  final Money allocatedAmount;
  Money get remainingAmount => remainingAtIssue - allocatedAmount;
  Money get settledAmount => paidAmount + allocatedAmount;
  final DateTime invoiceDate;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<InvoiceItemModel>? items;

  const InvoiceModel({
    this.id,
    required this.invoiceNumber,
    this.partyId,
    required this.invoiceType,
    this.status = InvoiceStatus.draft,
    this.paymentType = PaymentType.cash,
    PaymentMethod? paymentMethod,
    this.chequeAccount = TreasuryAccount.bank,
    required this.subtotal,
    this.discount = Money.zero,
    this.tax = Money.zero,
    required this.total,
    this.paidAmount = Money.zero,
    required Money remainingAmount,
    this.allocatedAmount = Money.zero,
    required this.invoiceDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.items,
  }) : remainingAtIssue = remainingAmount,
       paymentMethod =
           paymentMethod ??
           (paymentType == PaymentType.transfer
               ? PaymentMethod.transfer
               : PaymentMethod.cash);

  int get subtotalInt => subtotal.rawUnits;
  int get discountInt => discount.rawUnits;
  int get taxInt => tax.rawUnits;
  int get totalInt => total.rawUnits;
  int get paidAmountInt => paidAmount.rawUnits;
  int get remainingAmountInt => remainingAmount.rawUnits;

  // ---------------------------------------------------------------------------
  // Financial State Indicators
  // ---------------------------------------------------------------------------

  /// Whether the invoice is fully paid and has zero outstanding receivable/payable.
  bool get isFullyPaid => remainingAmount.isZero;

  /// Whether partial payment has been captured.
  bool get isPartiallyPaid => !settledAmount.isZero && !remainingAmount.isZero;

  /// Whether zero payment has been collected/made yet.
  bool get isUnpaid => settledAmount.isZero;

  /// Whether invoice is still an editable draft.
  bool get isDraft => status == InvoiceStatus.draft;

  /// Whether invoice is finalized and locked.
  bool get isApproved => status == InvoiceStatus.approved;

  /// Whether invoice was voided/cancelled.
  bool get isCancelled => status == InvoiceStatus.cancelled;

  /// Retries require the same persisted ID and the same business content.
  /// Generated row IDs, lifecycle status and the server update timestamp do
  /// not identify a new request. A zero input cost means "freeze catalog cost"
  /// at first posting, so retries use the already-frozen historical cost.
  bool hasSamePostedContent(InvoiceModel stored) {
    Map<String, dynamic> header(InvoiceModel invoice) => invoice.toMap()
      ..remove('id')
      ..remove('status')
      ..remove('updated_at');
    if (!mapEquals(header(this), header(stored))) return false;
    final requestedLines = items ?? const <InvoiceItemModel>[];
    final storedLines = stored.items ?? const <InvoiceItemModel>[];
    if (requestedLines.length != storedLines.length) return false;
    for (var index = 0; index < requestedLines.length; index++) {
      final requested = requestedLines[index];
      final saved = storedLines[index];
      final expected =
          requested
              .copyWith(
                unitCost: requested.unitCost.isZero
                    ? saved.unitCost
                    : requested.unitCost,
              )
              .toMap()
            ..remove('id')
            ..remove('invoice_id');
      final actual = saved.toMap()
        ..remove('id')
        ..remove('invoice_id');
      if (!mapEquals(expected, actual)) return false;
    }
    return true;
  }

  /// Validate at the repository boundary, including callers using the raw
  /// constructor or copyWith. Builders alone cannot protect persisted ledgers.
  /// New POS lines default to zero tax. Explicit historical tax amounts must
  /// still reconcile and survive persistence.
  void validateAmounts() {
    var gross = Money.zero;
    var lineDiscounts = Money.zero;
    var lineTaxes = Money.zero;
    for (final line in items ?? <InvoiceItemModel>[]) {
      final lineGross = line.unitPrice * line.quantity;
      if (line.quantity <= 0 ||
          line.unitPrice.isNegative ||
          line.unitCost.isNegative ||
          line.discount.isNegative ||
          line.discount > lineGross ||
          line.taxAmount.isNegative ||
          line.taxRatePercent < 0 ||
          line.totalPrice != lineGross - line.discount + line.taxAmount) {
        throw ArgumentError('كمية أو سعر أو خصم أو إجمالي الصنف غير صحيح');
      }
      gross += lineGross;
      lineDiscounts += line.discount;
      lineTaxes += line.taxAmount;
    }
    if (subtotal != gross ||
        discount.isNegative ||
        discount < lineDiscounts ||
        discount > subtotal ||
        tax.isNegative ||
        tax != lineTaxes ||
        total.isNegative ||
        total != subtotal - discount + tax) {
      throw ArgumentError(
        'الخصم يجب أن يكون بين صفر وقيمة الفاتورة، والإجمالي يجب أن يطابق الأصناف',
      );
    }
    if (paidAmount.isNegative ||
        paidAmount > total ||
        remainingAtIssue != total - paidAmount) {
      throw ArgumentError(
        'المدفوع يجب أن يكون بين صفر والإجمالي، والمتبقي يساوي الإجمالي ناقص المدفوع',
      );
    }
  }

  /// Drafts may be incomplete. Posting must assign every outstanding amount
  /// to a party and agree with the cash/credit/partial choices already exposed
  /// by the editor. Transfers retain their existing amount flexibility.
  void validateForPosting() {
    validateAmounts();
    if (remainingAmount.isPositive && partyId == null) {
      throw ArgumentError('يجب تحديد العميل أو المورد لترحيل المبلغ المتبقي');
    }
    switch (paymentType) {
      case PaymentType.cash:
        if (paidAmount != total) {
          throw ArgumentError('الفاتورة النقدية يجب أن تكون مسددة بالكامل');
        }
      case PaymentType.credit:
        if (!paidAmount.isZero) {
          throw ArgumentError(
            'الفاتورة الآجلة يجب ألا تحتوي على دفعة؛ اختر السداد الجزئي',
          );
        }
      case PaymentType.partial:
        if (!paidAmount.isPositive || !remainingAmount.isPositive) {
          throw ArgumentError(
            'السداد الجزئي يتطلب دفعة أكبر من صفر وأقل من الإجمالي',
          );
        }
      case PaymentType.transfer:
        // No new policy about bank settlement or treasury classification.
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Automatic Construction & Totals Calculation
  // ---------------------------------------------------------------------------

  /// Automatically aggregates line items and builds a mathematically verified invoice.
  factory InvoiceModel.buildWithItems({
    int? id,
    required String invoiceNumber,
    int? partyId,
    required InvoiceType invoiceType,
    InvoiceStatus status = InvoiceStatus.draft,
    PaymentType paymentType = PaymentType.cash,
    PaymentMethod? paymentMethod,
    TreasuryAccount chequeAccount = TreasuryAccount.bank,
    required List<InvoiceItemModel> items,
    Money additionalDiscount = Money.zero,
    Money paidAmount = Money.zero,
    required DateTime invoiceDate,
    String? notes,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    Money subtotal = Money.zero;
    Money itemDiscounts = Money.zero;
    Money itemTaxes = Money.zero;

    for (final item in items) {
      subtotal += (item.unitPrice * item.quantity);
      itemDiscounts += item.discount;
      itemTaxes += item.taxAmount;
    }

    final totalDiscount = itemDiscounts + additionalDiscount;
    final total = subtotal - totalDiscount + itemTaxes;
    // Preserve invalid overpayment in previews so validation can report it;
    // never disguise it as a fully settled invoice.
    final remaining = total - paidAmount;

    return InvoiceModel(
      id: id,
      invoiceNumber: invoiceNumber,
      partyId: partyId,
      invoiceType: invoiceType,
      status: status,
      paymentType: paymentType,
      paymentMethod: paymentMethod,
      chequeAccount: chequeAccount,
      subtotal: subtotal,
      discount: totalDiscount,
      tax: itemTaxes,
      total: total,
      paidAmount: paidAmount,
      remainingAmount: remaining,
      invoiceDate: invoiceDate,
      notes: notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      items: items,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization (SQLite Map)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'invoice_number': invoiceNumber,
      'party_id': partyId,
      'invoice_type': invoiceType.dbValue,
      'status': status.dbValue,
      'payment_type': paymentType.dbValue,
      'payment_method': paymentMethod.dbValue,
      'cheque_account': chequeAccount.dbValue,
      'subtotal_int': subtotalInt,
      'discount_int': discountInt,
      'tax_int': taxInt,
      'total_int': totalInt,
      'paid_amount_int': paidAmountInt,
      'remaining_amount_int': remainingAtIssue.rawUnits,
      'invoice_date': invoiceDate.millisecondsSinceEpoch,
      'notes': notes,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory InvoiceModel.fromMap(
    Map<String, dynamic> map, {
    List<InvoiceItemModel>? items,
  }) {
    return InvoiceModel(
      id: map['id'] as int?,
      invoiceNumber: map['invoice_number'] as String,
      partyId: map['party_id'] as int?,
      invoiceType: InvoiceType.fromString(map['invoice_type'] as String),
      status: InvoiceStatus.fromString(map['status'] as String),
      paymentType: PaymentType.fromString(map['payment_type'] as String),
      paymentMethod: map['payment_method'] == null
          ? null
          : PaymentMethod.fromString(map['payment_method'] as String),
      subtotal: Money(map['subtotal_int'] as int),
      discount: Money((map['discount_int'] as int?) ?? 0),
      tax: Money((map['tax_int'] as int?) ?? 0),
      total: Money(map['total_int'] as int),
      paidAmount: Money((map['paid_amount_int'] as int?) ?? 0),
      remainingAmount: Money((map['remaining_amount_int'] as int?) ?? 0),
      allocatedAmount: Money((map['allocated_amount_int'] as int?) ?? 0),
      chequeAccount: TreasuryAccount.values.firstWhere(
        (a) => a.dbValue == (map['cheque_account'] ?? 'bank'),
      ),
      invoiceDate: DateTime.fromMillisecondsSinceEpoch(
        map['invoice_date'] as int,
      ),
      notes: map['notes'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      items: items,
    );
  }

  InvoiceModel copyWith({
    int? id,
    String? invoiceNumber,
    int? partyId,
    InvoiceType? invoiceType,
    InvoiceStatus? status,
    PaymentType? paymentType,
    PaymentMethod? paymentMethod,
    TreasuryAccount? chequeAccount,
    Money? subtotal,
    Money? discount,
    Money? tax,
    Money? total,
    Money? paidAmount,
    Money? remainingAmount,
    Money? allocatedAmount,
    DateTime? invoiceDate,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<InvoiceItemModel>? items,
  }) {
    return InvoiceModel(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      partyId: partyId ?? this.partyId,
      invoiceType: invoiceType ?? this.invoiceType,
      status: status ?? this.status,
      paymentType: paymentType ?? this.paymentType,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      chequeAccount: chequeAccount ?? this.chequeAccount,
      subtotal: subtotal ?? this.subtotal,
      discount: discount ?? this.discount,
      tax: tax ?? this.tax,
      total: total ?? this.total,
      paidAmount: paidAmount ?? this.paidAmount,
      remainingAmount: remainingAmount ?? remainingAtIssue,
      allocatedAmount: allocatedAmount ?? this.allocatedAmount,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          invoiceNumber == other.invoiceNumber &&
          partyId == other.partyId &&
          total == other.total &&
          status == other.status;

  @override
  int get hashCode => Object.hash(id, invoiceNumber, partyId, total, status);
}
