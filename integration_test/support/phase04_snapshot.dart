import 'package:m3/core/accounting/treasury_ledger.dart';
import 'package:m3/core/database/app_database.dart';

/// QA metadata only. Resolve the live connection on every call, rather than
/// retaining a Database captured before close/reopen. All reads are awaited in
/// one transaction, so callers can await this method before closing the manager.
Future<Map<String, Object?>> phase04Snapshot(AppDatabase manager) async {
  final live = await manager.database;
  return live.transaction((txn) async {
    final counts = <String, Object?>{};
    for (final table in [
      AppTables.items,
      AppTables.parties,
      AppTables.invoices,
      AppTables.invoiceItems,
      AppTables.vouchers,
      AppTables.inventoryMovements,
    ]) {
      counts[table] = (await txn.rawQuery(
        'SELECT COUNT(*) AS n FROM $table',
      )).single['n'];
    }
    final accounts = await TreasuryLedger.read(txn);
    return {
      ...counts,
      'stocks': (await txn.rawQuery(
        'SELECT SUM(stock_quantity_int) AS n FROM items',
      )).single['n'],
      'party_total': (await txn.rawQuery(
        'SELECT SUM(current_balance_int) AS n FROM parties',
      )).single['n'],
      'cash': accounts.cash.balance.rawUnits,
      'bank': accounts.bank.balance.rawUnits,
      'transfers': accounts.transfers.balance.rawUnits,
    };
  });
}
