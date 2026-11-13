import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../../core/accounting/treasury_ledger.dart';
import '../../../core/accounting/settlements_repository.dart';
import '../../inventory/models/item_model.dart';
import '../../inventory/models/movement_model.dart';
import '../../parties/models/party_model.dart';
import '../models/invoice_model.dart';

class InvoiceConflictException implements Exception {
  final String message;
  const InvoiceConflictException(this.message);
  @override
  String toString() => message;
}

const _numberConflict = InvoiceConflictException(
  'رقم الفاتورة مستخدم بالفعل. اختر رقماً آخر أو افتح المسودة الأصلية بمعرّفها.',
);
const _contentConflict = InvoiceConflictException(
  'لا يمكن اعتبار الطلب إعادة محاولة: محتواه يختلف عن الفاتورة المعتمدة المحفوظة.',
);

/// Abstract contract for Invoices & POS repository in RAF ERP.
abstract class InvoicesRepository {
  Future<List<InvoiceModel>> getInvoices({
    InvoiceType? type,
    List<InvoiceType>? types,
    InvoiceStatus? status,
    int? partyId,
    String? searchQuery,
    bool includeItems = false,
    int? limit,
    int? offset,
  });

  Future<InvoiceModel?> getInvoiceById(int id);
  Future<InvoiceModel?> getInvoiceByNumber(String number);
  Future<int> createInvoice(InvoiceModel invoice);
  Future<void> updateInvoice(InvoiceModel invoice);
  Future<int> saveAndFinalizeInvoice(InvoiceModel invoice);
  Future<void> finalizeInvoice(int invoiceId);
  Future<void> cancelInvoice(int invoiceId);
  Future<String> generateNextInvoiceNumber(InvoiceType type);
  Future<void> seedDefaultInvoicesIfEmpty();
}

/// Persistent SQLite implementation with atomic multi-table transactions.
class SqliteInvoicesRepository implements InvoicesRepository {
  final AppDatabase _dbManager;

  SqliteInvoicesRepository([AppDatabase? dbManager])
    : _dbManager = dbManager ?? AppDatabase.instance;

  Future<void> _ensureNumberAvailable(
    DatabaseExecutor txn,
    String number, {
    int? excludingId,
  }) async {
    final rows = await txn.query(
      AppTables.invoices,
      columns: ['id'],
      where: excludingId == null
          ? 'invoice_number = ?'
          : 'invoice_number = ? AND id != ?',
      whereArgs: excludingId == null ? [number] : [number, excludingId],
      limit: 1,
    );
    if (rows.isNotEmpty) throw _numberConflict;
  }

  Future<void> _validatePostingParty(
    DatabaseExecutor txn,
    InvoiceModel invoice,
  ) async {
    invoice.validateForPosting();
    if (invoice.partyId != null) {
      final party = await txn.query(
        AppTables.parties,
        columns: ['id', 'type'],
        where: 'id = ?',
        whereArgs: [invoice.partyId],
        limit: 1,
      );
      if (party.isEmpty) {
        throw ArgumentError('العميل أو المورد المحدد غير موجود');
      }
      final requiredType = switch (invoice.invoiceType) {
        InvoiceType.sale || InvoiceType.saleReturn => PartyType.customer,
        InvoiceType.purchase ||
        InvoiceType.purchaseReturn => PartyType.supplier,
      };
      // Compare persisted values directly: an unknown type must not fall back
      // to customer. Archive eligibility remains unchanged (no active filter).
      final storedType = party.single['type'];
      if (storedType != requiredType.dbValue &&
          storedType != PartyType.both.dbValue) {
        throw ArgumentError(
          'نوع الطرف غير متوافق مع ${invoice.invoiceType.arabicLabel}. '
          'اختر ${requiredType.arabicLabel} أو ${PartyType.both.arabicLabel}.',
        );
      }
    }
  }

  Future<void> _validateStockRemoval(
    DatabaseExecutor txn,
    List<InvoiceItemModel> lines,
  ) async {
    final quantities = <int, int>{};
    for (final line in lines) {
      quantities.update(
        line.itemId,
        (value) => value + line.quantity,
        ifAbsent: () => line.quantity,
      );
    }
    for (final entry in quantities.entries) {
      final rows = await txn.query(
        AppTables.items,
        columns: ['name', 'stock_quantity_int'],
        where: 'id = ?',
        whereArgs: [entry.key],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('الصنف غير موجود');
      final available = rows.single['stock_quantity_int'] as int;
      if (available < entry.value) {
        throw StateError(
          'المخزون غير كاف للصنف ${rows.single['name']}: المتوفر $available والمطلوب ${entry.value}',
        );
      }
    }
  }

  @override
  Future<List<InvoiceModel>> getInvoices({
    InvoiceType? type,
    List<InvoiceType>? types,
    InvoiceStatus? status,
    int? partyId,
    String? searchQuery,
    bool includeItems = false,
    int? limit,
    int? offset,
  }) async {
    final db = await _dbManager.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (types != null && types.isNotEmpty) {
      final placeholders = List.filled(types.length, '?').join(',');
      whereClauses.add('invoice_type IN ($placeholders)');
      whereArgs.addAll(types.map((t) => t.dbValue));
    } else if (type != null) {
      whereClauses.add('invoice_type = ?');
      whereArgs.add(type.dbValue);
    }

    if (status != null) {
      whereClauses.add('status = ?');
      whereArgs.add(status.dbValue);
    }

    if (partyId != null) {
      whereClauses.add('party_id = ?');
      whereArgs.add(partyId);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim()}%';
      whereClauses.add('invoice_number LIKE ?');
      whereArgs.add(q);
    }

    final whereString = whereClauses.isNotEmpty
        ? whereClauses.join(' AND ')
        : null;

    final rows = await db.query(
      AppTables.invoices,
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'invoice_date DESC, id DESC',
      limit: limit,
      offset: offset,
    );

    if (rows.isEmpty) return [];
    final allocations = await SettlementsRepository.allocationsForInvoices(
      db,
      rows.map((r) => r['id'] as int).toList(),
    );
    Map<String, dynamic> enriched(Map<String, Object?> r) => {
      ...r,
      'allocated_amount_int': allocations[r['id']] ?? 0,
    };

    if (!includeItems) {
      return rows
          .map((r) => InvoiceModel.fromMap(enriched(r), items: const []))
          .toList();
    }

    // Batch load items in ONE query to eliminate N+1 problem
    final invoiceIds = rows.map((r) => r['id'] as int).toList();
    final placeholders = List.filled(invoiceIds.length, '?').join(',');
    final itemsRows = await db.rawQuery(
      'SELECT * FROM ${AppTables.invoiceItems} WHERE invoice_id IN ($placeholders)',
      invoiceIds,
    );

    final itemsByInvoice = <int, List<InvoiceItemModel>>{};
    for (final itemRow in itemsRows) {
      final invId = itemRow['invoice_id'] as int;
      itemsByInvoice
          .putIfAbsent(invId, () => [])
          .add(InvoiceItemModel.fromMap(itemRow));
    }

    return rows.map((r) {
      final invId = r['id'] as int;
      return InvoiceModel.fromMap(
        enriched(r),
        items: itemsByInvoice[invId] ?? const [],
      );
    }).toList();
  }

  @override
  Future<InvoiceModel?> getInvoiceById(int id) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      AppTables.invoices,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final itemsRows = await db.query(
      AppTables.invoiceItems,
      where: 'invoice_id = ?',
      whereArgs: [id],
    );
    final items = itemsRows.map(InvoiceItemModel.fromMap).toList();
    final allocations = await SettlementsRepository.allocationsForInvoices(db, [
      id,
    ]);
    return InvoiceModel.fromMap({
      ...rows.first,
      'allocated_amount_int': allocations[id] ?? 0,
    }, items: items);
  }

  @override
  Future<InvoiceModel?> getInvoiceByNumber(String number) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      AppTables.invoices,
      where: 'invoice_number = ?',
      whereArgs: [number.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final id = rows.first['id'] as int;
    final itemsRows = await db.query(
      AppTables.invoiceItems,
      where: 'invoice_id = ?',
      whereArgs: [id],
    );
    final items = itemsRows.map(InvoiceItemModel.fromMap).toList();
    final allocations = await SettlementsRepository.allocationsForInvoices(db, [
      id,
    ]);
    return InvoiceModel.fromMap({
      ...rows.first,
      'allocated_amount_int': allocations[id] ?? 0,
    }, items: items);
  }

  @override
  Future<int> createInvoice(InvoiceModel invoice) async {
    if (invoice.isCancelled) {
      throw StateError('Cannot create a cancelled invoice');
    }
    invoice.validateAmounts();
    if (invoice.status == InvoiceStatus.approved) {
      return await saveAndFinalizeInvoice(invoice);
    }

    final db = await _dbManager.database;
    return await db.transaction<int>((txn) async {
      await _ensureNumberAvailable(txn, invoice.invoiceNumber);
      final invoiceId = await txn.insert(AppTables.invoices, invoice.toMap());

      if (invoice.items != null) {
        for (final item in invoice.items!) {
          await txn.insert(
            AppTables.invoiceItems,
            item.copyWith(invoiceId: invoiceId).toMap(),
          );
        }
      }

      return invoiceId;
    });
  }

  @override
  Future<void> updateInvoice(InvoiceModel invoice) async {
    if (invoice.id == null) {
      throw ArgumentError('Cannot update an invoice without an ID');
    }

    final db = await _dbManager.database;
    await db.transaction((txn) async {
      // 1. Check current status
      final current = await txn.query(
        AppTables.invoices,
        where: 'id = ?',
        whereArgs: [invoice.id],
        limit: 1,
      );
      if (current.isEmpty) throw StateError('Invoice not found');
      if (current.first['status'] != InvoiceStatus.draft.dbValue ||
          invoice.status != InvoiceStatus.draft) {
        throw StateError('Only drafts can be modified through draft editing');
      }

      // 2. Update Header
      invoice.validateAmounts();
      await _ensureNumberAvailable(
        txn,
        invoice.invoiceNumber,
        excludingId: invoice.id,
      );
      await txn.update(
        AppTables.invoices,
        invoice.toMap(),
        where: 'id = ?',
        whereArgs: [invoice.id],
      );

      // 3. Replace items
      await txn.delete(
        AppTables.invoiceItems,
        where: 'invoice_id = ?',
        whereArgs: [invoice.id],
      );

      if (invoice.items != null) {
        for (final item in invoice.items!) {
          await txn.insert(
            AppTables.invoiceItems,
            item.copyWith(invoiceId: invoice.id).toMap(),
          );
        }
      }
    });
  }

  @override
  Future<int> saveAndFinalizeInvoice(InvoiceModel invoice) async {
    if (invoice.isCancelled) {
      throw StateError('Cannot finalize a cancelled invoice');
    }
    final db = await _dbManager.database;
    return await db.transaction<int>((txn) async {
      // Only an explicit persisted ID can identify a retry or an existing draft.
      final targetId = invoice.id;
      if (targetId != null) {
        final existingRows = await txn.query(
          AppTables.invoices,
          where: 'id = ?',
          whereArgs: [targetId],
          limit: 1,
        );
        if (existingRows.isEmpty) throw StateError('Invoice not found');
        if (existingRows.isNotEmpty) {
          final existingStatus = existingRows.first['status'] as String;
          if (existingStatus == InvoiceStatus.approved.dbValue) {
            final savedLines = await txn.query(
              AppTables.invoiceItems,
              where: 'invoice_id = ?',
              whereArgs: [targetId],
              orderBy: 'id ASC',
            );
            final saved = InvoiceModel.fromMap(
              existingRows.first,
              items: savedLines.map(InvoiceItemModel.fromMap).toList(),
            );
            if (!invoice.hasSamePostedContent(saved)) throw _contentConflict;
            return targetId;
          }
          if (existingStatus == InvoiceStatus.cancelled.dbValue) {
            throw StateError('Cannot finalize a cancelled invoice');
          }
        }
      }
      await _ensureNumberAvailable(
        txn,
        invoice.invoiceNumber,
        excludingId: targetId,
      );

      final items = invoice.items ?? [];
      invoice.validateAmounts();
      if (items.isEmpty) {
        throw StateError('Cannot finalize an invoice with no items');
      }
      await _validatePostingParty(txn, invoice);
      if (invoice.invoiceType == InvoiceType.sale ||
          invoice.invoiceType == InvoiceType.purchaseReturn) {
        await _validateStockRemoval(txn, items);
      }

      // Validate quantities before mutating
      for (final line in items) {
        if (line.quantity <= 0) {
          throw ArgumentError('Line quantity must be positive');
        }
      }

      final now = DateTime.now();

      // Keep the prepared header out of available funds until its ledger is
      // posted. The final approval is in this same atomic transaction.
      final invoiceToStore = invoice.copyWith(
        id: targetId,
        status: InvoiceStatus.draft,
        updatedAt: now,
      );

      final int invoiceId;
      if (targetId == null) {
        invoiceId = await txn.insert(
          AppTables.invoices,
          invoiceToStore.toMap(),
        );
      } else {
        invoiceId = targetId;
        await txn.update(
          AppTables.invoices,
          invoiceToStore.toMap(),
          where: 'id = ?',
          whereArgs: [invoiceId],
        );
        await txn.delete(
          AppTables.invoiceItems,
          where: 'invoice_id = ?',
          whereArgs: [invoiceId],
        );
      }

      // 3. Insert invoice items with frozen historical unit cost
      final frozenItems = <InvoiceItemModel>[];
      for (final line in items) {
        Money finalUnitCost = line.unitCost;
        if (finalUnitCost.isZero) {
          if (invoice.invoiceType == InvoiceType.purchase ||
              invoice.invoiceType == InvoiceType.purchaseReturn) {
            finalUnitCost = line.unitPrice;
          } else {
            final itemRows = await txn.query(
              AppTables.items,
              columns: ['cost_price_int'],
              where: 'id = ?',
              whereArgs: [line.itemId],
              limit: 1,
            );
            if (itemRows.isNotEmpty) {
              finalUnitCost = Money(itemRows.first['cost_price_int'] as int);
            }
          }
        }
        final itemWithCost = line.copyWith(
          invoiceId: invoiceId,
          unitCost: finalUnitCost,
        );
        frozenItems.add(itemWithCost);
        await txn.insert(AppTables.invoiceItems, itemWithCost.toMap());
      }

      // 4. Post inventory movements & party balance
      await _postInvoiceLedger(
        txn,
        invoiceToStore.copyWith(id: invoiceId, items: frozenItems),
        now,
      );

      await txn.update(AppTables.invoices, {'status': InvoiceStatus.approved.dbValue},
        where: 'id = ?', whereArgs: [invoiceId]);

      return invoiceId;
    });
  }

  @override
  Future<void> finalizeInvoice(int invoiceId) async {
    final db = await _dbManager.database;
    await db.transaction((txn) async {
      final invoiceRows = await txn.query(
        AppTables.invoices,
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      if (invoiceRows.isEmpty) throw StateError('Invoice not found');

      final currentStatus = invoiceRows.first['status'] as String;
      if (currentStatus == InvoiceStatus.approved.dbValue) {
        return; // Already approved
      }
      if (currentStatus == InvoiceStatus.cancelled.dbValue) {
        throw StateError('Cannot finalize a cancelled invoice');
      }

      final itemsRows = await txn.query(
        AppTables.invoiceItems,
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
      final items = itemsRows.map(InvoiceItemModel.fromMap).toList();
      if (items.isEmpty) {
        throw StateError('Cannot finalize an invoice with no items');
      }

      for (final line in items) {
        if (line.quantity <= 0) {
          throw ArgumentError('Line quantity must be positive');
        }
      }

      final invoice = InvoiceModel.fromMap(invoiceRows.first, items: items);
      await _validatePostingParty(txn, invoice);
      if (invoice.invoiceType == InvoiceType.sale ||
          invoice.invoiceType == InvoiceType.purchaseReturn) {
        await _validateStockRemoval(txn, items);
      }
      final now = DateTime.now();

      // Ensure historical unit_cost_int is frozen on items
      final frozenItems = <InvoiceItemModel>[];
      for (final line in items) {
        Money finalUnitCost = line.unitCost;
        if (finalUnitCost.isZero) {
          if (invoice.invoiceType == InvoiceType.purchase ||
              invoice.invoiceType == InvoiceType.purchaseReturn) {
            finalUnitCost = line.unitPrice;
          } else {
            final itemRows = await txn.query(
              AppTables.items,
              columns: ['cost_price_int'],
              where: 'id = ?',
              whereArgs: [line.itemId],
              limit: 1,
            );
            if (itemRows.isNotEmpty) {
              finalUnitCost = Money(itemRows.first['cost_price_int'] as int);
            }
          }
          await txn.update(
            AppTables.invoiceItems,
            {'unit_cost_int': finalUnitCost.rawUnits},
            where: 'id = ?',
            whereArgs: [line.id],
          );
        }
        frozenItems.add(line.copyWith(unitCost: finalUnitCost));
      }

      // Post inventory movements & party balance
      await _postInvoiceLedger(txn, invoice.copyWith(items: frozenItems), now);

      // Mark Invoice as Officially Approved
      await txn.update(
        AppTables.invoices,
        {
          'status': InvoiceStatus.approved.dbValue,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
    });
  }

  /// Internal helper to post inventory stock movements and commercial party ledger
  /// adjustments inside the current SQLite transaction.
  Future<void> _postInvoiceLedger(
    DatabaseExecutor txn,
    InvoiceModel invoice,
    DateTime now,
  ) async {
    final invoiceId = invoice.id!;
    final items = invoice.items ?? [];
    final incoming =
        invoice.invoiceType == InvoiceType.sale ||
        invoice.invoiceType == InvoiceType.purchaseReturn;
    if (!incoming) {
      await TreasuryLedger.requireFunds(
        txn,
        invoice.paymentMethod == PaymentMethod.cheque
            ? invoice.chequeAccount
            : invoice.paymentMethod.account,
        invoice.paidAmount,
      );
    }
    if (invoice.paymentMethod == PaymentMethod.cheque) {
      await SettlementsRepository.registerCheque(
        txn,
        invoiceId: invoiceId,
        amount: invoice.paidAmount,
        direction: incoming ? 1 : -1,
        outgoingAccount: invoice.chequeAccount,
        createdAt: now,
      );
    }

    // 1. Apply Inventory Stock Movements
    for (final line in items) {
      final itemRows = await txn.query(
        AppTables.items,
        where: 'id = ?',
        whereArgs: [line.itemId],
        limit: 1,
      );
      if (itemRows.isEmpty) throw StateError('Item ${line.itemId} not found');
      final currentStock = itemRows.first['stock_quantity_int'] as int;
      final costPrice = Money(itemRows.first['cost_price_int'] as int);

      final int newStock;
      final MovementType movementType;

      switch (invoice.invoiceType) {
        case InvoiceType.sale:
          newStock = currentStock - line.quantity;
          movementType = MovementType.sale;
          break;
        case InvoiceType.purchase:
          newStock = currentStock + line.quantity;
          movementType = MovementType.purchase;
          break;
        case InvoiceType.saleReturn:
          newStock = currentStock + line.quantity;
          movementType = MovementType.saleReturn;
          break;
        case InvoiceType.purchaseReturn:
          newStock = currentStock - line.quantity;
          movementType = MovementType.purchaseReturn;
          break;
      }

      // Update item stock
      final changed = await txn.rawUpdate(
        'UPDATE ${AppTables.items} SET stock_quantity_int = stock_quantity_int + ?, '
        'updated_at = ? WHERE id = ? AND (? >= 0 OR stock_quantity_int >= ?)',
        [
          newStock - currentStock,
          now.millisecondsSinceEpoch,
          line.itemId,
          newStock - currentStock,
          currentStock - newStock,
        ],
      );
      if (changed != 1) throw StateError('المخزون غير كاف لإتمام العملية');

      // Record inventory ledger movement
      final movement = InventoryMovementModel(
        itemId: line.itemId,
        movementType: movementType,
        quantity: line.quantity,
        unitCost: line.unitCost > Money.zero
            ? line.unitCost
            : (invoice.invoiceType == InvoiceType.purchase
                  ? line.unitPrice
                  : costPrice),
        referenceId: invoiceId,
        referenceType: 'invoice',
        movementDate: invoice.invoiceDate,
        notes:
            '${invoice.invoiceType.arabicLabel} رقم ${invoice.invoiceNumber}',
        createdAt: now,
      );
      await txn.insert(AppTables.inventoryMovements, movement.toMap());
    }

    // 2. Apply Commercial Party Balance Ledger Adjustment
    if (invoice.partyId != null && invoice.remainingAmountInt != 0) {
      final partyRows = await txn.query(
        AppTables.parties,
        where: 'id = ?',
        whereArgs: [invoice.partyId],
        limit: 1,
      );
      if (partyRows.isEmpty) {
        throw StateError('Party ${invoice.partyId} not found');
      }
      final currentPartyBal = partyRows.first['current_balance_int'] as int;
      final int newPartyBal;

      switch (invoice.invoiceType) {
        case InvoiceType.sale:
          // Customer owes remaining amount: balance decreases (-)
          newPartyBal = currentPartyBal - invoice.remainingAmountInt;
          break;
        case InvoiceType.purchase:
          // We owe supplier remaining amount: balance increases (+)
          newPartyBal = currentPartyBal + invoice.remainingAmountInt;
          break;
        case InvoiceType.saleReturn:
          // Returning sale: customer owed less: balance increases (+)
          newPartyBal = currentPartyBal + invoice.remainingAmountInt;
          break;
        case InvoiceType.purchaseReturn:
          // Returning purchase: we owe less: balance decreases (-)
          newPartyBal = currentPartyBal - invoice.remainingAmountInt;
          break;
      }

      await txn.update(
        AppTables.parties,
        {
          'current_balance_int': newPartyBal,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [invoice.partyId],
      );
    }
  }

  @override
  Future<void> cancelInvoice(int invoiceId) async {
    final db = await _dbManager.database;
    await db.transaction((txn) async {
      final invoiceRows = await txn.query(
        AppTables.invoices,
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      if (invoiceRows.isEmpty) throw StateError('Invoice not found');

      final currentStatus = invoiceRows.first['status'] as String;
      if (currentStatus == InvoiceStatus.cancelled.dbValue) {
        return; // Idempotent: already cancelled
      }

      final itemsRows = await txn.query(
        AppTables.invoiceItems,
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
      final items = itemsRows.map(InvoiceItemModel.fromMap).toList();
      final invoice = InvoiceModel.fromMap(invoiceRows.first, items: items);

      final now = DateTime.now();

      // If it was approved, reverse its impact
      if (currentStatus == InvoiceStatus.approved.dbValue) {
        final allocations = await SettlementsRepository.allocationsForInvoices(
          txn,
          [invoiceId],
        );
        if ((allocations[invoiceId] ?? 0) > 0) {
          throw StateError('فك تخصيص سندات القبض من الفاتورة قبل إلغائها');
        }
        if (invoice.invoiceType == InvoiceType.sale ||
            invoice.invoiceType == InvoiceType.purchaseReturn) {
          await SettlementsRepository.requireReversalFunds(
            txn,
            source: 'invoice',
            id: invoiceId,
            method: invoice.paymentMethod,
            amount: invoice.paidAmount,
          );
        }
        if (invoice.invoiceType == InvoiceType.purchase ||
            invoice.invoiceType == InvoiceType.saleReturn) {
          await _validateStockRemoval(txn, items);
        }
        // Guard against duplicate reversal if already recorded
        final existingCancels = await txn.query(
          AppTables.inventoryMovements,
          where: 'reference_id = ? AND reference_type = ?',
          whereArgs: [invoiceId, 'invoice_cancellation'],
        );
        if (existingCancels.isEmpty) {
          // Reverse inventory movements
          for (final line in items) {
            final itemRows = await txn.query(
              AppTables.items,
              where: 'id = ?',
              whereArgs: [line.itemId],
              limit: 1,
            );
            if (itemRows.isEmpty) {
              throw StateError('Item ${line.itemId} not found');
            }

            final currentStock = itemRows.first['stock_quantity_int'] as int;
            final int reversedStock;
            final int reverseDeltaQty;

            switch (invoice.invoiceType) {
              case InvoiceType.sale:
              case InvoiceType.purchaseReturn:
                reversedStock = currentStock + line.quantity;
                reverseDeltaQty = line.quantity;
                break;
              case InvoiceType.purchase:
              case InvoiceType.saleReturn:
                reversedStock = currentStock - line.quantity;
                reverseDeltaQty = -line.quantity;
                break;
            }

            await txn.rawUpdate(
              'UPDATE ${AppTables.items} SET stock_quantity_int = stock_quantity_int + ?, '
              'updated_at = ? WHERE id = ?',
              [
                reversedStock - currentStock,
                now.millisecondsSinceEpoch,
                line.itemId,
              ],
            );

            // Record auditable reverse movement in inventory ledger
            final reverseMovement = InventoryMovementModel(
              itemId: line.itemId,
              movementType: MovementType.cancellation,
              quantity: reverseDeltaQty,
              unitCost: line.unitCost,
              referenceId: invoiceId,
              referenceType: 'invoice_cancellation',
              movementDate: now,
              notes:
                  'إلغاء ${invoice.invoiceType.arabicLabel} رقم ${invoice.invoiceNumber}',
              createdAt: now,
            );
            await txn.insert(
              AppTables.inventoryMovements,
              reverseMovement.toMap(),
            );
          }

          // Reverse party balance
          if (invoice.partyId != null && invoice.remainingAmountInt != 0) {
            final partyRows = await txn.query(
              AppTables.parties,
              where: 'id = ?',
              whereArgs: [invoice.partyId],
              limit: 1,
            );
            if (partyRows.isEmpty) {
              throw StateError('Party ${invoice.partyId} not found');
            }

            final currentBal = partyRows.first['current_balance_int'] as int;
            final int reversedBal;

            switch (invoice.invoiceType) {
              case InvoiceType.sale:
                reversedBal = currentBal + invoice.remainingAmountInt;
                break;
              case InvoiceType.purchase:
                reversedBal = currentBal - invoice.remainingAmountInt;
                break;
              case InvoiceType.saleReturn:
                reversedBal = currentBal - invoice.remainingAmountInt;
                break;
              case InvoiceType.purchaseReturn:
                reversedBal = currentBal + invoice.remainingAmountInt;
                break;
            }

            await txn.update(
              AppTables.parties,
              {
                'current_balance_int': reversedBal,
                'updated_at': now.millisecondsSinceEpoch,
              },
              where: 'id = ?',
              whereArgs: [invoice.partyId],
            );
          }
        }
      }

      await txn.update(
        AppTables.invoices,
        {
          'status': InvoiceStatus.cancelled.dbValue,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
    });
  }

  @override
  Future<String> generateNextInvoiceNumber(InvoiceType type) async {
    final db = await _dbManager.database;
    final prefix = type == InvoiceType.sale
        ? 'INV'
        : type == InvoiceType.purchase
        ? 'PUR'
        : type == InvoiceType.saleReturn
        ? 'SRT'
        : 'PRT';
    final year = DateTime.now().year;

    final rows = await db.rawQuery(
      'SELECT invoice_number FROM ${AppTables.invoices} WHERE invoice_type = ? AND invoice_number LIKE ?',
      [type.dbValue, '$prefix-$year-%'],
    );

    int maxSeq = 0;
    final regex = RegExp('^$prefix-$year-(\\d+)\$');
    for (final row in rows) {
      final numStr = row['invoice_number'] as String?;
      if (numStr != null) {
        final match = regex.firstMatch(numStr);
        if (match != null) {
          final seq = int.tryParse(match.group(1)!) ?? 0;
          if (seq > maxSeq) maxSeq = seq;
        }
      }
    }
    final nextSeq = maxSeq + 1;
    return '$prefix-$year-${nextSeq.toString().padLeft(4, '0')}';
  }

  @override
  Future<void> seedDefaultInvoicesIfEmpty() async {
    // Demonstration transactions belong in explicit test fixtures, never SQLite startup.
  }
}

/// In-memory mock implementation of [InvoicesRepository] for blazing-fast UI tests.
class FakeInvoicesRepository implements InvoicesRepository {
  void _validateStockRemoval(List<InvoiceItemModel> lines) {
    final requested = <int, int>{};
    for (final line in lines) {
      requested.update(
        line.itemId,
        (value) => value + line.quantity,
        ifAbsent: () => line.quantity,
      );
    }
    for (final entry in requested.entries) {
      final item = inMemoryItems[entry.key];
      if (item != null && item.stockQuantity < entry.value) {
        throw StateError(
          'المخزون غير كاف للصنف ${item.name}: المتوفر ${item.stockQuantity}، المطلوب ${entry.value}',
        );
      }
    }
  }

  final List<InvoiceModel> _invoices = [];
  final Map<int, List<InvoiceItemModel>> _itemsMap = {};
  int _nextInvoiceId = 1;

  // In-memory references to items and parties to test ledger & stock posting live
  final Map<int, ItemModel> inMemoryItems = {};
  final Map<int, PartyModel> inMemoryParties = {};

  @override
  Future<List<InvoiceModel>> getInvoices({
    InvoiceType? type,
    List<InvoiceType>? types,
    InvoiceStatus? status,
    int? partyId,
    String? searchQuery,
    bool includeItems = false,
    int? limit,
    int? offset,
  }) async {
    var results = _invoices
        .where((inv) {
          if (types != null &&
              types.isNotEmpty &&
              !types.contains(inv.invoiceType)) {
            return false;
          }
          if (type != null && inv.invoiceType != type) return false;
          if (status != null && inv.status != status) return false;
          if (partyId != null && inv.partyId != partyId) return false;
          if (searchQuery != null && searchQuery.trim().isNotEmpty) {
            if (!inv.invoiceNumber.toLowerCase().contains(
              searchQuery.trim().toLowerCase(),
            )) {
              return false;
            }
          }
          return true;
        })
        .map((inv) {
          if (includeItems && inv.id != null) {
            return inv.copyWith(items: _itemsMap[inv.id!] ?? []);
          }
          return inv;
        })
        .toList();

    if (offset != null) {
      if (offset >= results.length) return [];
      results = results.sublist(offset);
    }
    if (limit != null && results.length > limit) {
      results = results.sublist(0, limit);
    }
    return results;
  }

  @override
  Future<InvoiceModel?> getInvoiceById(int id) async {
    try {
      final inv = _invoices.firstWhere((i) => i.id == id);
      final items = _itemsMap[id] ?? [];
      return inv.copyWith(items: items);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<InvoiceModel?> getInvoiceByNumber(String number) async {
    try {
      final inv = _invoices.firstWhere((i) => i.invoiceNumber == number.trim());
      final items = _itemsMap[inv.id] ?? [];
      return inv.copyWith(items: items);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> createInvoice(InvoiceModel invoice) async {
    if (invoice.isCancelled) {
      throw StateError('Cannot create a cancelled invoice');
    }
    invoice.validateAmounts();
    if (invoice.status == InvoiceStatus.approved) {
      return await saveAndFinalizeInvoice(invoice);
    }

    if (_invoices.any(
      (value) => value.invoiceNumber == invoice.invoiceNumber,
    )) {
      throw _numberConflict;
    }

    final id = _nextInvoiceId++;
    final invWithId = invoice.copyWith(id: id);
    _invoices.add(invWithId);

    if (invoice.items != null) {
      _itemsMap[id] = List.of(invoice.items!);
    }

    return id;
  }

  @override
  Future<void> updateInvoice(InvoiceModel invoice) async {
    final idx = _invoices.indexWhere((i) => i.id == invoice.id);
    if (idx == -1) throw StateError('Invoice not found');
    if (!_invoices[idx].isDraft || !invoice.isDraft) {
      throw StateError('Only drafts can be modified through draft editing');
    }
    invoice.validateAmounts();
    if (_invoices.any(
      (value) =>
          value.id != invoice.id &&
          value.invoiceNumber == invoice.invoiceNumber,
    )) {
      throw _numberConflict;
    }
    if (idx != -1) {
      _invoices[idx] = invoice;
      if (invoice.items != null) {
        _itemsMap[invoice.id!] = List.of(invoice.items!);
      }
    }
  }

  @override
  Future<int> saveAndFinalizeInvoice(InvoiceModel invoice) async {
    if (invoice.isCancelled) {
      throw StateError('Cannot finalize a cancelled invoice');
    }
    invoice.validateAmounts();
    // 1. Check idempotency
    final targetId = invoice.id;
    if (invoice.id != null) {
      final existing = _invoices.where((i) => i.id == invoice.id).firstOrNull;
      if (existing == null) throw StateError('Invoice not found');
      if (existing.status == InvoiceStatus.approved) {
        final saved = existing.copyWith(items: _itemsMap[existing.id] ?? []);
        if (!invoice.hasSamePostedContent(saved)) throw _contentConflict;
        return invoice.id!;
      }
      if (existing.status == InvoiceStatus.cancelled) {
        throw StateError('Cannot finalize a cancelled invoice');
      }
    }
    if (_invoices.any(
      (value) =>
          value.id != targetId && value.invoiceNumber == invoice.invoiceNumber,
    )) {
      throw _numberConflict;
    }

    final id = targetId ?? _nextInvoiceId++;
    final items = invoice.items ?? [];
    invoice.validateForPosting();
    if (items.isEmpty) {
      throw StateError('Cannot finalize an invoice with no items');
    }

    for (final line in items) {
      if (line.quantity <= 0) {
        throw ArgumentError('Line quantity must be positive');
      }
    }

    if (invoice.invoiceType == InvoiceType.sale ||
        invoice.invoiceType == InvoiceType.purchaseReturn) {
      _validateStockRemoval(items);
    }
    final invWithId = invoice.copyWith(
      id: id,
      status: InvoiceStatus.approved,
      items: items,
    );
    final existingIdx = _invoices.indexWhere((i) => i.id == id);
    if (existingIdx != -1) {
      _invoices[existingIdx] = invWithId;
    } else {
      _invoices.add(invWithId);
    }
    _itemsMap[id] = List.of(items);

    // Apply stock changes
    for (final line in items) {
      final item = inMemoryItems[line.itemId];
      if (item != null) {
        final int newStock;
        switch (invoice.invoiceType) {
          case InvoiceType.sale:
            newStock = item.stockQuantity - line.quantity;
            break;
          case InvoiceType.purchase:
            newStock = item.stockQuantity + line.quantity;
            break;
          case InvoiceType.saleReturn:
            newStock = item.stockQuantity + line.quantity;
            break;
          case InvoiceType.purchaseReturn:
            newStock = item.stockQuantity - line.quantity;
            break;
        }
        inMemoryItems[line.itemId] = item.copyWith(stockQuantity: newStock);
      }
    }

    // Apply party balance changes
    if (invoice.partyId != null && invoice.remainingAmountInt != 0) {
      final party = inMemoryParties[invoice.partyId];
      if (party != null) {
        final Money newBal;
        switch (invoice.invoiceType) {
          case InvoiceType.sale:
            newBal = party.currentBalance - invoice.remainingAmount;
            break;
          case InvoiceType.purchase:
            newBal = party.currentBalance + invoice.remainingAmount;
            break;
          case InvoiceType.saleReturn:
            newBal = party.currentBalance + invoice.remainingAmount;
            break;
          case InvoiceType.purchaseReturn:
            newBal = party.currentBalance - invoice.remainingAmount;
            break;
        }
        inMemoryParties[invoice.partyId!] = party.copyWith(
          currentBalance: newBal,
        );
      }
    }

    return id;
  }

  @override
  Future<void> finalizeInvoice(int invoiceId) async {
    final idx = _invoices.indexWhere((i) => i.id == invoiceId);
    if (idx == -1) throw StateError('Invoice not found');
    final invoice = _invoices[idx];
    if (invoice.status == InvoiceStatus.approved) return;
    if (invoice.status == InvoiceStatus.cancelled) {
      throw StateError('Cannot finalize a cancelled invoice');
    }

    final items = _itemsMap[invoiceId] ?? [];
    invoice.copyWith(items: items).validateForPosting();
    if (items.isEmpty) {
      throw StateError('Cannot finalize an invoice with no items');
    }

    // 1. Post stock changes to in-memory items
    if (invoice.invoiceType == InvoiceType.sale ||
        invoice.invoiceType == InvoiceType.purchaseReturn) {
      _validateStockRemoval(items);
    }
    for (final line in items) {
      final item = inMemoryItems[line.itemId];
      if (item != null) {
        final int newStock;
        switch (invoice.invoiceType) {
          case InvoiceType.sale:
            newStock = item.stockQuantity - line.quantity;
            break;
          case InvoiceType.purchase:
            newStock = item.stockQuantity + line.quantity;
            break;
          case InvoiceType.saleReturn:
            newStock = item.stockQuantity + line.quantity;
            break;
          case InvoiceType.purchaseReturn:
            newStock = item.stockQuantity - line.quantity;
            break;
        }
        inMemoryItems[line.itemId] = item.copyWith(stockQuantity: newStock);
      }
    }

    // 2. Post party balance changes
    if (invoice.partyId != null && invoice.remainingAmountInt != 0) {
      final party = inMemoryParties[invoice.partyId];
      if (party != null) {
        final Money newBal;
        switch (invoice.invoiceType) {
          case InvoiceType.sale:
            newBal = party.currentBalance - invoice.remainingAmount;
            break;
          case InvoiceType.purchase:
            newBal = party.currentBalance + invoice.remainingAmount;
            break;
          case InvoiceType.saleReturn:
            newBal = party.currentBalance + invoice.remainingAmount;
            break;
          case InvoiceType.purchaseReturn:
            newBal = party.currentBalance - invoice.remainingAmount;
            break;
        }
        inMemoryParties[invoice.partyId!] = party.copyWith(
          currentBalance: newBal,
        );
      }
    }

    _invoices[idx] = invoice.copyWith(status: InvoiceStatus.approved);
  }

  @override
  Future<void> cancelInvoice(int invoiceId) async {
    final idx = _invoices.indexWhere((i) => i.id == invoiceId);
    if (idx == -1) throw StateError('Invoice not found');
    final invoice = _invoices[idx];
    if (invoice.status == InvoiceStatus.cancelled) return; // Idempotent

    final items = _itemsMap[invoiceId] ?? [];

    if (invoice.status == InvoiceStatus.approved) {
      // Reverse stock
      if (invoice.invoiceType == InvoiceType.purchase ||
          invoice.invoiceType == InvoiceType.saleReturn) {
        _validateStockRemoval(items);
      }
      for (final line in items) {
        final item = inMemoryItems[line.itemId];
        if (item != null) {
          final int reversedStock;
          switch (invoice.invoiceType) {
            case InvoiceType.sale:
            case InvoiceType.purchaseReturn:
              reversedStock = item.stockQuantity + line.quantity;
              break;
            case InvoiceType.purchase:
            case InvoiceType.saleReturn:
              reversedStock = item.stockQuantity - line.quantity;
              break;
          }
          inMemoryItems[line.itemId] = item.copyWith(
            stockQuantity: reversedStock,
          );
        }
      }

      // Reverse party balance
      if (invoice.partyId != null && invoice.remainingAmountInt != 0) {
        final party = inMemoryParties[invoice.partyId];
        if (party != null) {
          final Money reversedBal;
          switch (invoice.invoiceType) {
            case InvoiceType.sale:
              reversedBal = party.currentBalance + invoice.remainingAmount;
              break;
            case InvoiceType.purchase:
              reversedBal = party.currentBalance - invoice.remainingAmount;
              break;
            case InvoiceType.saleReturn:
              reversedBal = party.currentBalance - invoice.remainingAmount;
              break;
            case InvoiceType.purchaseReturn:
              reversedBal = party.currentBalance + invoice.remainingAmount;
              break;
          }
          inMemoryParties[invoice.partyId!] = party.copyWith(
            currentBalance: reversedBal,
          );
        }
      }
    }

    _invoices[idx] = invoice.copyWith(status: InvoiceStatus.cancelled);
  }

  @override
  Future<String> generateNextInvoiceNumber(InvoiceType type) async {
    final prefix = type == InvoiceType.sale
        ? 'INV'
        : type == InvoiceType.purchase
        ? 'PUR'
        : type == InvoiceType.saleReturn
        ? 'SRT'
        : 'PRT';
    final year = DateTime.now().year;
    final regex = RegExp('^$prefix-$year-(\\d+)\$');
    int maxSeq = 0;
    for (final inv in _invoices.where((i) => i.invoiceType == type)) {
      final match = regex.firstMatch(inv.invoiceNumber);
      if (match != null) {
        final seq = int.tryParse(match.group(1)!) ?? 0;
        if (seq > maxSeq) maxSeq = seq;
      }
    }
    final nextSeq = maxSeq + 1;
    return '$prefix-$year-${nextSeq.toString().padLeft(4, '0')}';
  }

  @override
  Future<void> seedDefaultInvoicesIfEmpty() async {
    if (_invoices.isEmpty) {
      final now = DateTime.now();
      final num = await generateNextInvoiceNumber(InvoiceType.sale);
      final inv = InvoiceModel.buildWithItems(
        invoiceNumber: num,
        partyId: 1,
        invoiceType: InvoiceType.sale,
        status: InvoiceStatus.approved,
        paymentType: PaymentType.cash,
        items: [
          InvoiceItemModel.create(
            itemId: 1,
            quantity: 3,
            unitPrice: const Money(1500),
          ),
        ],
        paidAmount: const Money(4500), // 3 * 15.00 = 45.00 (no tax)
        invoiceDate: now,
        notes: 'فاتورة مبيعات نموذجية',
        createdAt: now,
        updatedAt: now,
      );
      await createInvoice(inv);
    }
  }
}
