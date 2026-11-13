import 'package:sqflite/sqflite.dart';
import '../utils/money.dart';
import 'financial_accounts.dart';

class InsufficientFundsException implements Exception {
  final String message;
  const InsufficientFundsException(this.message);
  @override
  String toString() => message;
}

/// Collected funds, outgoing reservations and uncollected cheques are distinct.
abstract final class TreasuryLedger {
  static const activeSources = '''
    SELECT id AS voucher_id,NULL AS invoice_id,amount_int AS amount,payment_method,
      voucher_date AS event_date,CASE voucher_type WHEN 'receipt' THEN 1 ELSE -1 END AS direction,
      voucher_number AS number,party_id FROM vouchers WHERE status IS NULL OR status='approved'
    UNION ALL
    SELECT NULL,id,paid_amount_int,payment_method,invoice_date,
      CASE WHEN invoice_type IN ('sale','purchase_return') THEN 1 ELSE -1 END,
      invoice_number,party_id FROM invoices WHERE status='approved' AND paid_amount_int>0
  ''';
  static const chequeJoin =
      '(c.voucher_id=s.voucher_id OR c.invoice_id=s.invoice_id)';

  static Future<TreasurySnapshot> read(
    DatabaseExecutor db, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final rows = await db.rawQuery(
      '''
      WITH sources AS ($activeSources), events AS (
        SELECT amount,event_date,direction,CASE payment_method WHEN 'cash' THEN 'cash'
          WHEN 'bank' THEN 'bank' WHEN 'transfer' THEN 'transfers' ELSE 'unknown' END AS account
          FROM sources WHERE payment_method!='cheque'
        UNION ALL
        SELECT c.amount_int,c.effective_at,c.direction,c.account FROM cheques c
          JOIN sources s ON $chequeJoin WHERE c.state='cleared'
      )
      SELECT account,
        SUM(CASE WHEN (? IS NULL OR event_date>=?) AND (? IS NULL OR event_date<=?) AND direction=1 THEN amount ELSE 0 END) AS receipts,
        SUM(CASE WHEN (? IS NULL OR event_date>=?) AND (? IS NULL OR event_date<=?) AND direction=-1 THEN amount ELSE 0 END) AS payments,
        SUM(direction*amount) AS balance FROM events GROUP BY account
    ''',
      [
        startDate?.millisecondsSinceEpoch,
        startDate?.millisecondsSinceEpoch,
        endDate?.millisecondsSinceEpoch,
        endDate?.millisecondsSinceEpoch,
        startDate?.millisecondsSinceEpoch,
        startDate?.millisecondsSinceEpoch,
        endDate?.millisecondsSinceEpoch,
        endDate?.millisecondsSinceEpoch,
      ],
    );
    final reservations = await db.rawQuery('''WITH sources AS ($activeSources)
      SELECT c.account,SUM(c.amount_int) AS amount FROM cheques c JOIN sources s ON $chequeJoin
      WHERE c.state='pending' AND c.direction=-1 GROUP BY c.account''');
    final values = <TreasuryAccount, AccountCashFlow>{};
    for (final account in TreasuryAccount.values) {
      final flow = rows
          .where((r) => r['account'] == account.dbValue)
          .firstOrNull;
      final held = reservations
          .where((r) => r['account'] == account.dbValue)
          .firstOrNull;
      values[account] = AccountCashFlow(
        receipts: Money((flow?['receipts'] as int?) ?? 0),
        payments: Money((flow?['payments'] as int?) ?? 0),
        balance: Money((flow?['balance'] as int?) ?? 0),
        reserved: Money((held?['amount'] as int?) ?? 0),
      );
    }
    if (rows.any(
      (r) => !TreasuryAccount.values.any((a) => a.dbValue == r['account']),
    )) {
      throw StateError('توجد عملية بوسيلة دفع غير معروفة؛ راجع بياناتها');
    }
    final pending = (await db.rawQuery(
      '''WITH sources AS ($activeSources)
      SELECT COALESCE(SUM(CASE WHEN s.direction=1 AND COALESCE(c.state,'legacy_review')!='cleared' THEN s.amount ELSE 0 END),0) AS incoming,
        SUM(CASE WHEN COALESCE(c.state,'legacy_review')='legacy_review' THEN 1 ELSE 0 END) AS reviews
      FROM sources s LEFT JOIN cheques c ON $chequeJoin WHERE s.payment_method='cheque' ''',
    )).single;
    return TreasurySnapshot(
      cash: values[TreasuryAccount.cash]!,
      bank: values[TreasuryAccount.bank]!,
      transfers: values[TreasuryAccount.transfers]!,
      pendingCheques: Money(pending['incoming'] as int),
      legacyReviewCount: (pending['reviews'] as int?) ?? 0,
    );
  }

  /// Must be called inside the same SQLite transaction as the financial post.
  static Future<void> requireFunds(
    DatabaseExecutor db,
    TreasuryAccount account,
    Money amount,
  ) async {
    if (!amount.isPositive) return;
    final unknown =
        (await db.rawQuery(
              '''WITH sources AS ($activeSources)
      SELECT COUNT(*) AS n FROM sources s LEFT JOIN cheques c ON $chequeJoin
      WHERE s.payment_method='cheque' AND s.direction=-1 AND COALESCE(c.state,'legacy_review')='legacy_review' ''',
            )).single['n']
            as int;
    if (unknown > 0) {
      throw const InsufficientFundsException(
        'راجع حساب الشيكات الصادرة القديمة أولاً؛ الصرف معلق لحماية الرصيد المتاح.',
      );
    }
    final available = (await read(db)).forAccount(account).available;
    if (available < amount) {
      throw InsufficientFundsException(
        'الرصيد المتاح في ${account.arabicLabel} غير كاف؛ لم تُسجل العملية.',
      );
    }
  }
}
