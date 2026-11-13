// Read-only follow-up: no reset, fixture insertion, or posting. This entrypoint
// can run again after Android force-stop/start to verify the same stored rows.
import 'dart:convert';
import '../test/licensing/fakes.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:m3/main.dart' as app;
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:m3/features/settings/pages/store_settings_page.dart';
import 'package:sqflite/sqflite.dart';
import 'support/phase04_snapshot.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('DAFTAR_DEVICE_QA');
  testWidgets(
    'Phase04 read-only stored records after process restart',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      AppDatabase.instance.configureForTesting();
      final db = await AppDatabase.instance.database;
      expect(db.path.contains('/com.example.m3/'), isTrue);
      final item = (await SqliteInventoryRepository().getItemByCode(
        'PH04-PERSIST-STOCK',
      ))!;
      final customer = (await SqlitePartiesRepository().getParties(
        searchQuery: 'PH04 Persist customer',
      )).single;
      final invoice = (await SqliteInvoicesRepository().getInvoiceByNumber(
        'PH04-PERSIST-INVOICE',
      ))!;
      final vouchers = SqliteVouchersRepository();
      final receipt = (await vouchers.getVoucherByNumber(
        'PH04-PERSIST-RECEIPT',
      ))!;
      final expense = (await vouchers.getVoucherByNumber(
        'PH04-PERSIST-EXPENSE',
      ))!;
      expect(item.stockQuantity, 6);
      expect(customer.currentBalance, const Money(-3000));
      expect(invoice.isApproved, isTrue);
      expect(invoice.total, const Money(4000));
      expect(invoice.paidAmount, const Money(1000));
      expect(invoice.remainingAmount, const Money(3000));
      expect(invoice.partyId, customer.id);
      expect(invoice.items!.single.itemId, item.id);
      expect(invoice.items!.single.quantity, 4);
      expect(receipt.isApproved, isTrue);
      expect(receipt.amount, const Money(2500));
      expect(expense.isApproved, isTrue);
      expect(expense.isExpense, isTrue);
      expect(expense.amount, const Money(500));
      final snapshot = await phase04Snapshot(AppDatabase.instance);
      expect(snapshot, {
        'items': 1,
        'parties': 1,
        'invoices': 1,
        'invoice_items': 1,
        'vouchers': 2,
        'inventory_movements': 2,
        'stocks': 6,
        'party_total': -3000,
        'cash': -500,
        'bank': 1000,
        'transfers': 2500,
      });
      expect(await db.getVersion(), 5);
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      final data = <String, Object?>{
        'pid': pid,
        'schema': 5,
        'integrity': 'ok',
        'foreign_key_violations': 0,
        'invoice_id': invoice.id,
        'receipt_id': receipt.id,
        'expense_id': expense.id,
        'invoice_total_raw': invoice.total.rawUnits,
        'invoice_paid_raw': invoice.paidAmount.rawUnits,
        'invoice_remaining_raw': invoice.remainingAmount.rawUnits,
        'snapshot': snapshot,
        'read_only': true,
      };
      debugPrint('PHASE04_RESTART_VERIFY ${jsonEncode(data)}');
      binding.reportData = data;
      await StoreSettingsManager.instance.loadSettings();
      await tester.pumpWidget(app.RafApp(licenseService: FakeLicenseService()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
