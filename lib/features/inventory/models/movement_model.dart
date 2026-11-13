import 'package:flutter/foundation.dart';
import '../../../core/utils/money.dart';

/// Supported types of stock movement in the inventory ledger.
enum MovementType {
  initial('initial', 'رصيد افتتاحي'),
  purchase('purchase', 'فاتورة شراء'),
  sale('sale', 'فاتورة بيع'),
  purchaseReturn('purchase_return', 'مرتجع مشتريات'),
  saleReturn('sale_return', 'مرتجع مبيعات'),
  damaged('damaged', 'إتلاف / هالك'),
  adjustment('adjustment', 'تسوية جردية'),
  cancellation('cancellation', 'إلغاء مستند / حركة عكسية');

  final String dbValue;
  final String arabicLabel;

  const MovementType(this.dbValue, this.arabicLabel);

  static MovementType fromString(String value) {
    return MovementType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => MovementType.adjustment,
    );
  }
}

/// Inventory ledger movement model.
///
/// Records every change in stock with exact integer quantities and financial unit cost.
@immutable
class InventoryMovementModel {
  final int? id;
  final int itemId;
  final MovementType movementType;
  final int quantity;
  final Money unitCost;
  final int? referenceId;
  final String? referenceType;
  final DateTime movementDate;
  final String? notes;
  final DateTime createdAt;

  const InventoryMovementModel({
    this.id,
    required this.itemId,
    required this.movementType,
    required this.quantity,
    required this.unitCost,
    this.referenceId,
    this.referenceType,
    required this.movementDate,
    this.notes,
    required this.createdAt,
  });

  int get quantityInt => quantity;
  int get unitCostInt => unitCost.rawUnits;

  // ---------------------------------------------------------------------------
  // Financial & Ledger Intelligence
  // ---------------------------------------------------------------------------

  /// Total valuation for this specific stock movement.
  Money get totalCost => unitCost * quantity.abs();

  /// Whether this movement increases physical stock in warehouse.
  bool get increasesStock {
    switch (movementType) {
      case MovementType.initial:
      case MovementType.purchase:
      case MovementType.saleReturn:
        return true;
      case MovementType.sale:
      case MovementType.purchaseReturn:
      case MovementType.damaged:
        return false;
      case MovementType.adjustment:
      case MovementType.cancellation:
        return quantity >= 0;
    }
  }

  /// Signed integer delta applied to current stock.
  int get effectiveQuantityDelta =>
      increasesStock ? quantity.abs() : -quantity.abs();

  // ---------------------------------------------------------------------------
  // Serialization (SQLite Map)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'item_id': itemId,
      'movement_type': movementType.dbValue,
      'quantity_int': quantityInt,
      'unit_cost_int': unitCostInt,
      'reference_id': referenceId,
      'reference_type': referenceType,
      'movement_date': movementDate.millisecondsSinceEpoch,
      'notes': notes,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory InventoryMovementModel.fromMap(Map<String, dynamic> map) {
    return InventoryMovementModel(
      id: map['id'] as int?,
      itemId: map['item_id'] as int,
      movementType: MovementType.fromString(map['movement_type'] as String),
      quantity: map['quantity_int'] as int,
      unitCost: Money(map['unit_cost_int'] as int),
      referenceId: map['reference_id'] as int?,
      referenceType: map['reference_type'] as String?,
      movementDate: DateTime.fromMillisecondsSinceEpoch(
        map['movement_date'] as int,
      ),
      notes: map['notes'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  InventoryMovementModel copyWith({
    int? id,
    int? itemId,
    MovementType? movementType,
    int? quantity,
    Money? unitCost,
    int? referenceId,
    String? referenceType,
    DateTime? movementDate,
    String? notes,
    DateTime? createdAt,
  }) {
    return InventoryMovementModel(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      movementType: movementType ?? this.movementType,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
      referenceId: referenceId ?? this.referenceId,
      referenceType: referenceType ?? this.referenceType,
      movementDate: movementDate ?? this.movementDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryMovementModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          itemId == other.itemId &&
          movementType == other.movementType &&
          quantity == other.quantity &&
          unitCost == other.unitCost &&
          movementDate == other.movementDate;

  @override
  int get hashCode =>
      Object.hash(id, itemId, movementType, quantity, unitCost, movementDate);
}
