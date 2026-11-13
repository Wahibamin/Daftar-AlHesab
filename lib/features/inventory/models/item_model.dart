import 'package:flutter/foundation.dart';
import '../../../core/utils/money.dart';

/// Unit of measurement model (e.g., Piece, Box, Kilogram).
@immutable
class UnitModel {
  final int? id;
  final String name;
  final String symbol;
  final int? baseUnitId;
  final int conversionFactor; // Integer multiplier relative to base unit
  final DateTime createdAt;

  const UnitModel({
    this.id,
    required this.name,
    required this.symbol,
    this.baseUnitId,
    this.conversionFactor = 1,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'symbol': symbol,
      'base_unit_id': baseUnitId,
      'conversion_factor_int': conversionFactor,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory UnitModel.fromMap(Map<String, dynamic> map) {
    return UnitModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      symbol: map['symbol'] as String,
      baseUnitId: map['base_unit_id'] as int?,
      conversionFactor: (map['conversion_factor_int'] as int?) ?? 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  UnitModel copyWith({
    int? id,
    String? name,
    String? symbol,
    int? baseUnitId,
    int? conversionFactor,
    DateTime? createdAt,
  }) {
    return UnitModel(
      id: id ?? this.id,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      baseUnitId: baseUnitId ?? this.baseUnitId,
      conversionFactor: conversionFactor ?? this.conversionFactor,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Whether this unit is marked as archived.
  bool get isArchived => name.contains('[مؤرشف]') || symbol.contains('[مؤرشف]');

  /// Clean display name with archive tag removed.
  String get cleanName => name.replaceAll('[مؤرشف]', '').trim();

  /// Clean display symbol with archive tag removed.
  String get cleanSymbol => symbol.replaceAll('[مؤرشف]', '').trim();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnitModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          symbol == other.symbol &&
          conversionFactor == other.conversionFactor;

  @override
  int get hashCode => Object.hash(id, name, symbol, conversionFactor);
}

/// Inventory Category model.
@immutable
class CategoryModel {
  final int? id;
  final String name;
  final String? description;
  final DateTime createdAt;

  const CategoryModel({
    this.id,
    required this.name,
    this.description,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: map['description'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  CategoryModel copyWith({
    int? id,
    String? name,
    String? description,
    DateTime? createdAt,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Whether this category is marked as archived.
  bool get isArchived =>
      (description != null && description!.contains('[مؤرشف]')) ||
      name.contains('[مؤرشف]');

  /// Clean display description with archive tag removed.
  String get cleanDescription =>
      (description ?? '').replaceAll('[مؤرشف]', '').trim();

  /// Clean display name with archive tag removed.
  String get cleanName => name.replaceAll('[مؤرشف]', '').trim();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Product & Inventory Item Model with strict integer financial values.
@immutable
class ItemModel {
  static const Object _unchangedExpiryDate = Object();
  final int? id;
  final String code;
  final String name;
  final int unitId;
  final int? categoryId;
  final Money costPrice;
  final Money sellingPrice;
  final int stockQuantity;
  final int minAlertLimit;
  final DateTime? expiryDate;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ItemModel({
    this.id,
    required this.code,
    required this.name,
    required this.unitId,
    this.categoryId,
    required this.costPrice,
    required this.sellingPrice,
    this.stockQuantity = 0,
    this.minAlertLimit = 0,
    this.expiryDate,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Raw integer getters for database synchronization
  int get costPriceInt => costPrice.rawUnits;
  int get sellingPriceInt => sellingPrice.rawUnits;
  int get stockQuantityInt => stockQuantity;
  int get minAlertLimitInt => minAlertLimit;

  // ---------------------------------------------------------------------------
  // Financial & Inventory Intelligence Getters
  // ---------------------------------------------------------------------------

  /// Total inventory valuation at cost price (`costPrice * stockQuantity`).
  Money get totalCostValuation => costPrice * stockQuantity;

  /// Total inventory valuation at selling price (`sellingPrice * stockQuantity`).
  Money get totalSellingValuation => sellingPrice * stockQuantity;

  /// Expected gross profit per unit (`sellingPrice - costPrice`).
  Money get grossMarginPerUnit => sellingPrice - costPrice;

  /// Whether current stock has hit or fallen below the minimum reorder alert limit.
  bool get isLowStock => stockQuantity <= minAlertLimit;

  /// Whether current stock is completely depleted.
  bool get isOutOfStock => stockQuantity <= 0;

  /// Whether product has expired.
  bool get isExpired => isExpiredAt();

  /// Products remain valid through their expiry calendar day.
  bool isExpiredAt([DateTime? referenceDate]) =>
      (remainingExpiryDays(referenceDate) ?? 0) < 0;

  /// Calculates remaining calendar days until expiration.
  /// Returns null if the item has no expiry date.
  int? remainingExpiryDays([DateTime? referenceDate]) {
    return calendarExpiryDays(expiryDate, referenceDate);
  }

  /// UTC date-only values avoid DST changing a calendar day to 23/25 hours.
  static int? calendarExpiryDays(DateTime? expiry, [DateTime? referenceDate]) {
    if (expiry == null) return null;
    final now = referenceDate ?? DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final exp = DateTime.utc(expiry.year, expiry.month, expiry.day);
    return exp.difference(today).inDays;
  }

  // ---------------------------------------------------------------------------
  // Serialization (SQLite Map)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'name': name,
      'unit_id': unitId,
      'category_id': categoryId,
      'cost_price_int': costPriceInt,
      'selling_price_int': sellingPriceInt,
      'stock_quantity_int': stockQuantityInt,
      'min_alert_limit_int': minAlertLimitInt,
      'expiry_date': expiryDate?.millisecondsSinceEpoch,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory ItemModel.fromMap(Map<String, dynamic> map) {
    return ItemModel(
      id: map['id'] as int?,
      code: map['code'] as String,
      name: map['name'] as String,
      unitId: map['unit_id'] as int,
      categoryId: map['category_id'] as int?,
      costPrice: Money(map['cost_price_int'] as int),
      sellingPrice: Money(map['selling_price_int'] as int),
      stockQuantity: (map['stock_quantity_int'] as int?) ?? 0,
      minAlertLimit: (map['min_alert_limit_int'] as int?) ?? 0,
      expiryDate: map['expiry_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['expiry_date'] as int)
          : null,
      isActive: (map['is_active'] as int?) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  ItemModel copyWith({
    int? id,
    String? code,
    String? name,
    int? unitId,
    int? categoryId,
    Money? costPrice,
    Money? sellingPrice,
    int? stockQuantity,
    int? minAlertLimit,
    Object? expiryDate = _unchangedExpiryDate,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ItemModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      unitId: unitId ?? this.unitId,
      categoryId: categoryId ?? this.categoryId,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      minAlertLimit: minAlertLimit ?? this.minAlertLimit,
      expiryDate: identical(expiryDate, _unchangedExpiryDate)
          ? this.expiryDate
          : expiryDate as DateTime?,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItemModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          code == other.code &&
          name == other.name &&
          costPrice == other.costPrice &&
          sellingPrice == other.sellingPrice &&
          stockQuantity == other.stockQuantity;

  @override
  int get hashCode =>
      Object.hash(id, code, name, costPrice, sellingPrice, stockQuantity);
}
