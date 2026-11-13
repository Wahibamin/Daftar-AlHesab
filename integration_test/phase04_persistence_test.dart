// Explicit QA only. Creates synthetic PH04 persistence records in the real
// verified app, without clearing any existing records. Leaves them for the
// separate ADB force-stop/relaunch and read-only SQL verification.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:m3/features/inventory/models/item_model.dart';
import 'package:m3/features/inventory/repositories/inventory_repository.dart';
import 'package:m3/features/parties/models/party_model.dart';
import 'package:m3/features/parties/repositories/parties_repository.dart';
import 'package:m3/features/sales/models/invoice_model.dart';
import 'package:m3/features/sales/repositories/invoices_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'support/phase04_snapshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('DAFTAR_DEVICE_QA');
  testWidgets(
    'Phase04 persistent accounting fixture survives connection close and leaves records for process restart',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      final manager = AppDatabase.instance;
      // Explicit Debug-only business QA injection; never a distribution bypass.
      manager.configureForTesting();
      final db = await manager.database;
      expect(db.path.contains('/com.example.m3/'), isTrue);
      expect(await db.getVersion(), 5);
      final inventory = SqliteInventoryRepository();
      final parties = SqlitePartiesRepository();
      final invoices = SqliteInvoicesRepository();
      final vouchers = SqliteVouchersRepository();
      final now = DateTime.now();
      final before = await vouchers.getTreasuryBalances();
      expect(
        await inventory.getItemByCode('PH04-PERSIST-STOCK'),
        isNull,
        reason: 'Do not duplicate or overwrite an existing persistence fixture',
      );
      final unit = await inventory.insertUnit(
        UnitModel(name: 'PH04 Persist unit', symbol: 'P4', createdAt: now),
      );
      final item = await inventory.insertItem(
        ItemModel(
          code: 'PH04-PERSIST-STOCK',
          name: 'PH04 Persist stock',
          unitId: unit,
          stockQuantity: 10,
          costPrice: const Money(600),
          sellingPrice: const Money(1000),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final customer = await parties.insertParty(
        PartyModel(
          name: 'PH04 Persist customer',
          phone: '0500000099',
          type: PartyType.customer,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final request = InvoiceModel.buildWithItems(
        invoiceNumber: 'PH04-PERSIST-INVOICE',
        partyId: customer,
        invoiceType: InvoiceType.sale,
        paymentType: PaymentType.partial,
        paymentMethod: PaymentMethod.bank,
        paidAmount: const Money(1000),
        items: [
          InvoiceItemModel.create(
            itemId: item,
            quantity: 4,
            unitPrice: const Money(1000),
          ),
        ],
        invoiceDate: now,
        createdAt: now,
        updatedAt: now,
      );
      final invoice = await invoices.saveAndFinalizeInvoice(request);
      final receipt = await vouchers.createVoucher(
        VoucherModel(
          voucherNumber: 'PH04-PERSIST-RECEIPT',
          voucherType: VoucherType.receipt,
          amount: const Money(2500),
          paymentMethod: PaymentMethod.transfer,
          statement: 'PH04 Persist transfer 25',
          voucherDate: now,
          createdAt: now,
        ),
      );
      final expense = await vouchers.createVoucher(
        VoucherModel(
          voucherNumber: 'PH04-PERSIST-EXPENSE',
          voucherType: VoucherType.payment,
          purpose: VoucherPurpose.expense,
          expenseCategory: 'Electricity',
          amount: const Money(500),
          paymentMethod: PaymentMethod.cash,
          statement: 'PH04 Persist electricity 5',
          voucherDate: now,
          createdAt: now,
        ),
      );
      final after = await vouchers.getTreasuryBalances();
      expect((await inventory.getItemById(item))!.stockQuantity, 6);
      expect(
        (await parties.getPartyById(customer))!.currentBalance,
        const Money(-3000),
      );
      expect(after.cash.balance, before.cash.balance - const Money(500));
      expect(after.bank.balance, before.bank.balance + const Money(1000));
      expect(
        after.transfers.balance,
        before.transfers.balance + const Money(2500),
      );
      final snapshot = await phase04Snapshot(manager);
      // There are no UI callbacks in this fixture: every database Future above is awaited.
      await manager.close();
      final reopened = await manager.database;
      expect(await phase04Snapshot(manager), snapshot);
      expect((await invoices.getInvoiceById(invoice))!.isApproved, isTrue);
      expect((await vouchers.getVoucherById(receipt))!.isApproved, isTrue);
      expect((await vouchers.getVoucherById(expense))!.isExpense, isTrue);
      expect(
        (await reopened.rawQuery(
          'PRAGMA integrity_check',
        )).single.values.single,
        'ok',
      );
      expect(await reopened.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      final retryBefore = await phase04Snapshot(manager);
      await invoices.saveAndFinalizeInvoice(request.copyWith(id: invoice));
      expect(await phase04Snapshot(manager), retryBefore);
      debugPrint(
        'PHASE04_PERSISTENCE ${jsonEncode({'schema': 5, 'item_id': item, 'customer_id': customer, 'invoice_id': invoice, 'receipt_id': receipt, 'expense_id': expense, 'stock': 6, 'invoice_total_raw': 4000, 'invoice_paid_raw': 1000, 'invoice_remaining_raw': 3000, 'customer_balance_raw': -3000, 'cash_raw': after.cash.balance.rawUnits, 'bank_raw': after.bank.balance.rawUnits, 'transfers_raw': after.transfers.balance.rawUnits, 'connection_reopened': true, 'retry_unchanged': true, 'snapshot': snapshot})}',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('PH04 persistence fixture ready')),
        ),
      );
      await tester.pumpAndSettle();
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
