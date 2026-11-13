import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/accounting/treasury_ledger.dart';
import 'package:m3/core/utils/money.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test(
    'Phase03B v4 upgrade preserves money and classifies legacy payment methods',
    () async {
      final directory = await Directory.systemTemp.createTemp('daftar_v5_');
      final path = '${directory.path}/isolated.db';
      final manager = AppDatabase.instance;
      try {
        final old = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 4,
            onCreate: (db, _) async {
              await db.execute(
                'CREATE TABLE invoices (id INTEGER PRIMARY KEY, invoice_number TEXT, party_id INTEGER, created_at INTEGER DEFAULT 0, status TEXT, invoice_type TEXT, payment_type TEXT, paid_amount_int INTEGER, invoice_date INTEGER)',
              );
              await db.execute(
                'CREATE TABLE vouchers (id INTEGER PRIMARY KEY, voucher_number TEXT, party_id INTEGER, created_at INTEGER DEFAULT 0, status TEXT, voucher_type TEXT, payment_method TEXT, amount_int INTEGER, voucher_date INTEGER)',
              );
              await db.insert('invoices', {
                'status': 'approved',
                'invoice_type': 'sale',
                'payment_type': 'transfer',
                'paid_amount_int': 700,
                'invoice_date': 1,
              });
              await db.insert('invoices', {
                'status': 'approved',
                'invoice_type': 'sale',
                'payment_type': 'cash',
                'paid_amount_int': 300,
                'invoice_date': 1,
              });
              await db.insert('vouchers', {
                'status': 'approved',
                'voucher_type': 'payment',
                'payment_method': 'bank',
                'amount_int': 200,
                'voucher_date': 1,
              });
              await db.insert('vouchers', {
                'status': 'approved',
                'voucher_type': 'receipt',
                'payment_method': 'cheque',
                'amount_int': 100,
                'voucher_date': 1,
              });
            },
          ),
        );
        await old.close();
        manager.configureForTesting(factory: databaseFactoryFfi, path: path);
        final db = await manager.database;
        expect(await db.getVersion(), 6);
        expect(
          (await db.query('vouchers')).every(
            (row) =>
                row['purpose'] == 'general' && row['expense_category'] == null,
          ),
          isTrue,
        );
        final balances = await TreasuryLedger.read(db);
        expect(balances.cash.balance, const Money(300));
        expect(balances.bank.balance, const Money(-200));
        expect(balances.transfers.balance, const Money(700));
        expect(balances.pendingCheques, const Money(100));
        expect(balances.legacyReviewCount, 1);
        expect(
          (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
          1,
        );
        await manager.close();
        final reopened = await manager.database;
        expect(await reopened.getVersion(), 6);
        expect(
          (await TreasuryLedger.read(reopened)).total.balance,
          const Money(800),
        );
        expect((await reopened.query('invoices')).length, 2);
        expect((await reopened.query('vouchers')).length, 2);
      } finally {
        await manager.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
