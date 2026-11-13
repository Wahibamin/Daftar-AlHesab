import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../utils/money.dart';
import 'financial_accounts.dart';
import 'treasury_ledger.dart';

/// Settlement metadata never posts a second party balance or treasury receipt.
class SettlementsRepository {
  final AppDatabase manager;
  SettlementsRepository([AppDatabase? manager])
    : manager = manager ?? AppDatabase.instance;

  static Future<void> registerCheque(
    DatabaseExecutor db, {
    int? voucherId,
    int? invoiceId,
    required Money amount,
    required int direction,
    required TreasuryAccount outgoingAccount,
    required DateTime createdAt,
  }) async {
    if (!amount.isPositive) return;
    await db.insert('cheques', {
      'voucher_id': voucherId,
      'invoice_id': invoiceId,
      'amount_int': amount.rawUnits,
      'direction': direction,
      'state': 'pending',
      'account': direction == -1 ? outgoingAccount.dbValue : null,
      'created_at': createdAt.millisecondsSinceEpoch,
    });
  }

  static Future<void> requireReversalFunds(
    DatabaseExecutor db, {
    required String source,
    int? id,
    required PaymentMethod method,
    required Money amount,
  }) async {
    if (!amount.isPositive) return;
    if (method != PaymentMethod.cheque) {
      return TreasuryLedger.requireFunds(db, method.account, amount);
    }
    final row = await db.query(
      'cheques',
      where: '${source}_id=?',
      whereArgs: [id],
    );
    if (row.isNotEmpty && row.single['state'] == 'cleared') {
      final account = TreasuryAccount.values.firstWhere(
        (a) => a.dbValue == row.single['account'],
      );
      await TreasuryLedger.requireFunds(db, account, amount);
    }
  }

  Future<List<Map<String, Object?>>> getCheques() async {
    final db = await manager.database;
    return db.rawQuery(
      '''WITH sources AS (${TreasuryLedger.activeSources})
      SELECT c.*,s.number,s.party_id FROM cheques c JOIN sources s ON ${TreasuryLedger.chequeJoin}
      ORDER BY CASE c.state WHEN 'legacy_review' THEN 0 WHEN 'pending' THEN 1 ELSE 2 END,c.created_at,c.id''',
    );
  }

  /// Legacy review is explicit. Historical amounts/dates and party debt remain intact.
  Future<void> reviewLegacyCheque(
    int id, {
    required bool alreadyCleared,
    required TreasuryAccount account,
    required DateTime effectiveAt,
  }) async {
    if (alreadyCleared && effectiveAt.isAfter(DateTime.now())) {
      throw ArgumentError('لا يمكن إثبات تسوية بتاريخ مستقبلي');
    }
    final db = await manager.database;
    await db.transaction((txn) async {
      final row = await _activeCheque(txn, id);
      if (row['state'] != 'legacy_review') {
        throw StateError('تمت مراجعة هذا الشيك بالفعل');
      }
      await txn.update(
        'cheques',
        {
          'state': alreadyCleared ? 'cleared' : 'pending',
          'account': alreadyCleared || row['direction'] == -1
              ? account.dbValue
              : null,
          'effective_at': alreadyCleared
              ? effectiveAt.millisecondsSinceEpoch
              : null,
          'reviewed_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id=? AND state=?',
        whereArgs: [id, 'legacy_review'],
      );
    });
  }

  Future<bool> clearCheque(
    int id, {
    required TreasuryAccount account,
    required DateTime effectiveAt,
  }) async {
    if (effectiveAt.isAfter(DateTime.now())) {
      throw ArgumentError('لا يمكن تحصيل شيك بتاريخ مستقبلي');
    }
    final db = await manager.database;
    return db.transaction((txn) async {
      final row = await _activeCheque(txn, id);
      if (row['state'] == 'cleared') return false;
      if (row['state'] == 'legacy_review') {
        throw StateError('راجع حالة الشيك القديم أولاً');
      }
      if (row['direction'] == -1 && row['account'] != account.dbValue) {
        throw ArgumentError('تسوية الشيك الصادر تكون من حساب الحجز نفسه');
      }
      final changed = await txn.update(
        'cheques',
        {
          'state': 'cleared',
          'account': account.dbValue,
          'effective_at': effectiveAt.millisecondsSinceEpoch,
        },
        where: "id=? AND state='pending'",
        whereArgs: [id],
      );
      return changed == 1;
    });
  }

  Future<Map<String, Object?>> _activeCheque(
    DatabaseExecutor db,
    int id,
  ) async {
    final rows = await db.rawQuery(
      '''WITH sources AS (${TreasuryLedger.activeSources})
      SELECT c.* FROM cheques c JOIN sources s ON ${TreasuryLedger.chequeJoin} WHERE c.id=?''',
      [id],
    );
    if (rows.isEmpty) throw StateError('الشيك غير موجود أو مستنده ملغى');
    return rows.single;
  }

  static Future<Map<int, int>> allocationsForInvoices(
    DatabaseExecutor db,
    List<int> ids,
  ) async {
    if (ids.isEmpty) return {};
    final rows = await db.rawQuery(
      '''SELECT a.invoice_id,SUM(a.amount_int) AS amount FROM receipt_allocations a
      JOIN vouchers v ON v.id=a.voucher_id WHERE a.released_at IS NULL AND (v.status IS NULL OR v.status='approved')
      AND a.invoice_id IN (${List.filled(ids.length, '?').join(',')}) GROUP BY a.invoice_id''',
      ids,
    );
    return {for (final r in rows) r['invoice_id'] as int: r['amount'] as int};
  }

  Future<List<Map<String, Object?>>> getReceipts() async {
    final db = await manager.database;
    return db.rawQuery(
      '''SELECT v.*,COALESCE((SELECT SUM(a.amount_int) FROM receipt_allocations a
      WHERE a.voucher_id=v.id AND a.released_at IS NULL),0) AS allocated_int FROM vouchers v
      WHERE v.voucher_type='receipt' AND v.party_id IS NOT NULL AND (v.status IS NULL OR v.status='approved') ORDER BY v.voucher_date,v.id''',
    );
  }

  Future<List<Map<String, Object?>>> getOpenInvoices(int partyId) async {
    final db = await manager.database;
    final rows = await db.query(
      'invoices',
      where: "party_id=? AND invoice_type='sale' AND status='approved'",
      whereArgs: [partyId],
      orderBy: 'invoice_date,id',
    );
    final allocations = await allocationsForInvoices(
      db,
      rows.map((r) => r['id'] as int).toList(),
    );
    return rows
        .map(
          (r) => <String, Object?>{
            ...r,
            'effective_remaining_int':
                (r['remaining_amount_int'] as int) -
                (allocations[r['id']] ?? 0),
          },
        )
        .where((r) => (r['effective_remaining_int'] as int) > 0)
        .toList();
  }

  Future<List<Map<String, Object?>>> getAllocations() async {
    final db = await manager.database;
    return db.rawQuery(
      '''SELECT a.*,v.voucher_number,i.invoice_number,v.status AS voucher_status
      FROM receipt_allocations a JOIN vouchers v ON v.id=a.voucher_id JOIN invoices i ON i.id=a.invoice_id ORDER BY a.id DESC''',
    );
  }

  Future<int> allocateReceipt({
    required int voucherId,
    required int invoiceId,
    required Money amount,
    required String requestKey,
  }) async {
    if (!amount.isPositive || requestKey.trim().isEmpty) {
      throw ArgumentError('مبلغ أو معرف تخصيص غير صالح');
    }
    final db = await manager.database;
    return db.transaction((txn) async {
      final previous = await txn.query(
        'receipt_allocations',
        where: 'request_key=?',
        whereArgs: [requestKey],
      );
      final vr = await txn.query(
        'vouchers',
        where: 'id=?',
        whereArgs: [voucherId],
      );
      final ir = await txn.query(
        'invoices',
        where: 'id=?',
        whereArgs: [invoiceId],
      );
      if (vr.isEmpty || ir.isEmpty) {
        throw ArgumentError('السند أو الفاتورة غير موجود');
      }
      final v = vr.single;
      final i = ir.single;
      if (v['voucher_type'] != 'receipt' ||
          (v['status'] != null && v['status'] != 'approved') ||
          v['party_id'] == null ||
          i['invoice_type'] != 'sale' ||
          i['status'] != 'approved' ||
          i['party_id'] != v['party_id']) {
        throw ArgumentError(
          'التخصيص يتطلب سند قبض وفاتورة بيع معتمدين للعميل نفسه',
        );
      }
      final party = await txn.query(
        'parties',
        columns: ['type'],
        where: 'id=?',
        whereArgs: [v['party_id']],
      );
      if (party.isEmpty ||
          !['customer', 'both'].contains(party.single['type'])) {
        throw ArgumentError('الطرف ليس عميلاً');
      }
      if (previous.isNotEmpty) {
        final old = previous.single;
        if (old['voucher_id'] == voucherId &&
            old['invoice_id'] == invoiceId &&
            old['amount_int'] == amount.rawUnits &&
            old['released_at'] == null) {
          return old['id'] as int;
        }
        throw StateError('معرف إعادة المحاولة مستخدم لتخصيص آخر أو مفكوك');
      }
      final used =
          (await txn.rawQuery(
                'SELECT COALESCE(SUM(amount_int),0) AS amount FROM receipt_allocations WHERE voucher_id=? AND released_at IS NULL',
                [voucherId],
              )).single['amount']
              as int;
      final allocated =
          (await allocationsForInvoices(txn, [invoiceId]))[invoiceId] ?? 0;
      if (amount.rawUnits > (v['amount_int'] as int) - used) {
        throw ArgumentError('المبلغ أكبر من الجزء غير المخصص من السند');
      }
      if (amount.rawUnits > (i['remaining_amount_int'] as int) - allocated) {
        throw ArgumentError(
          'المبلغ أكبر من متبقي الفاتورة؛ أبق الزيادة غير مخصصة',
        );
      }
      return txn.insert('receipt_allocations', {
        'voucher_id': voucherId,
        'invoice_id': invoiceId,
        'amount_int': amount.rawUnits,
        'request_key': requestKey,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<void> releaseAllocation(int id) async {
    final db = await manager.database;
    await db.transaction((txn) async {
      await txn.update(
        'receipt_allocations',
        {'released_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id=? AND released_at IS NULL',
        whereArgs: [id],
      );
    });
  }
}
