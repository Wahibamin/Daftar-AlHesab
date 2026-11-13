import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../../core/accounting/treasury_ledger.dart';
import '../../../core/accounting/settlements_repository.dart';
import '../../parties/models/party_model.dart';
import '../models/voucher_model.dart';

/// Abstract contract for Financial Vouchers & Treasury repository in RAF ERP.
abstract class VouchersRepository {
  Future<List<VoucherModel>> getVouchers({
    VoucherPurpose? purpose,
    VoucherType? type,
    int? partyId,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    int? limit,
    int? offset,
  });

  Future<VoucherModel?> getVoucherById(int id);
  Future<VoucherModel?> getVoucherByNumber(String number);
  Future<int> createVoucher(VoucherModel voucher);
  Future<void> deleteVoucher(int id);
  Future<String> generateNextVoucherNumber(VoucherType type);
  Future<Money> getTreasuryBalance();
  Future<TreasurySnapshot> getTreasuryBalances();
  Future<Money> getExpenseTotal();
  Future<void> seedDefaultVouchersIfEmpty();
}

/// SQLite-backed implementation with atomic multi-table transactions for balance adjustments.
class SqliteVouchersRepository implements VouchersRepository {
  final AppDatabase _dbManager;

  SqliteVouchersRepository([AppDatabase? dbManager])
    : _dbManager = dbManager ?? AppDatabase.instance;

  @override
  Future<List<VoucherModel>> getVouchers({
    VoucherPurpose? purpose,
    VoucherType? type,
    int? partyId,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    int? limit,
    int? offset,
  }) async {
    final db = await _dbManager.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];
    if (purpose != null) {
      whereClauses.add('purpose = ?');
      whereArgs.add(purpose.name);
    }

    if (type != null) {
      whereClauses.add('voucher_type = ?');
      whereArgs.add(type.dbValue);
    }

    if (partyId != null) {
      whereClauses.add('party_id = ?');
      whereArgs.add(partyId);
    }

    if (startDate != null) {
      whereClauses.add('voucher_date >= ?');
      whereArgs.add(startDate.millisecondsSinceEpoch);
    }

    if (endDate != null) {
      whereClauses.add('voucher_date <= ?');
      whereArgs.add(endDate.millisecondsSinceEpoch);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim()}%';
      whereClauses.add(
        '(voucher_number LIKE ? OR statement LIKE ? OR reference_number LIKE ?)',
      );
      whereArgs.add(q);
      whereArgs.add(q);
      whereArgs.add(q);
    }

    final whereString = whereClauses.isNotEmpty
        ? whereClauses.join(' AND ')
        : null;

    final rows = await db.query(
      AppTables.vouchers,
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'voucher_date DESC, id DESC',
      limit: limit,
      offset: offset,
    );

    return rows.map(VoucherModel.fromMap).toList();
  }

  @override
  Future<VoucherModel?> getVoucherById(int id) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      AppTables.vouchers,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return VoucherModel.fromMap(rows.first);
  }

  @override
  Future<VoucherModel?> getVoucherByNumber(String number) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      AppTables.vouchers,
      where: 'voucher_number = ?',
      whereArgs: [number.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return VoucherModel.fromMap(rows.first);
  }

  @override
  Future<int> createVoucher(VoucherModel voucher) async {
    voucher.validateForPosting();
    final db = await _dbManager.database;
    return await db.transaction<int>((txn) async {
      if (voucher.isPayment) {
        await TreasuryLedger.requireFunds(
          txn,
          voucher.paymentMethod == PaymentMethod.cheque
              ? voucher.chequeAccount
              : voucher.paymentMethod.account,
          voucher.amount,
        );
      }
      // 1. Insert Voucher record
      final voucherId = await txn.insert(AppTables.vouchers, voucher.toMap());
      if (voucher.paymentMethod == PaymentMethod.cheque) {
        await SettlementsRepository.registerCheque(
          txn,
          voucherId: voucherId,
          amount: voucher.amount,
          direction: voucher.isReceipt ? 1 : -1,
          outgoingAccount: voucher.chequeAccount,
          createdAt: voucher.createdAt,
        );
      }

      // 2. Adjust Party Account Balance if assigned to a commercial entity
      if (voucher.partyId != null) {
        final partyRows = await txn.query(
          AppTables.parties,
          where: 'id = ?',
          whereArgs: [voucher.partyId],
          limit: 1,
        );

        if (partyRows.isNotEmpty) {
          final currentBal = partyRows.first['current_balance_int'] as int;
          // Invariant: Receipt increases (+ credit), Payment decreases (- debit)
          final int newBal;
          if (voucher.isReceipt) {
            newBal = currentBal + voucher.amountInt;
          } else {
            newBal = currentBal - voucher.amountInt;
          }

          final now = DateTime.now();
          await txn.update(
            AppTables.parties,
            {
              'current_balance_int': newBal,
              'updated_at': now.millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: [voucher.partyId],
          );
        }
      }

      return voucherId;
    });
  }

  @override
  Future<void> deleteVoucher(int id) async {
    final db = await _dbManager.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        AppTables.vouchers,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final voucher = VoucherModel.fromMap(rows.first);
      if (voucher.isCancelled) return; // Idempotent: already cancelled
      if (voucher.isReceipt) {
        await SettlementsRepository.requireReversalFunds(
          txn,
          source: 'voucher',
          id: id,
          method: voucher.paymentMethod,
          amount: voucher.amount,
        );
      }

      // Reverse Party Balance impact if voucher was approved
      if (voucher.partyId != null && voucher.isApproved) {
        final partyRows = await txn.query(
          AppTables.parties,
          where: 'id = ?',
          whereArgs: [voucher.partyId],
          limit: 1,
        );
        if (partyRows.isNotEmpty) {
          final currentBal = partyRows.first['current_balance_int'] as int;
          final int reversedBal;
          if (voucher.isReceipt) {
            reversedBal = currentBal - voucher.amountInt;
          } else {
            reversedBal = currentBal + voucher.amountInt;
          }

          final now = DateTime.now();
          await txn.update(
            AppTables.parties,
            {
              'current_balance_int': reversedBal,
              'updated_at': now.millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: [voucher.partyId],
          );
        }
      }

      // Soft cancel to preserve financial audit trail
      await txn.update(
        AppTables.vouchers,
        {'status': VoucherStatus.cancelled.dbValue},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  @override
  Future<String> generateNextVoucherNumber(VoucherType type) async {
    final db = await _dbManager.database;
    final prefix = type == VoucherType.receipt ? 'REC' : 'PAY';
    final year = DateTime.now().year;

    final rows = await db.rawQuery(
      'SELECT voucher_number FROM ${AppTables.vouchers} WHERE voucher_type = ? AND voucher_number LIKE ?',
      [type.dbValue, '$prefix-$year-%'],
    );
    int maxSeq = 0;
    final regex = RegExp('^$prefix-$year-(\\d+)\$');
    for (final row in rows) {
      final numStr = row['voucher_number'] as String?;
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
  Future<TreasurySnapshot> getTreasuryBalances() async =>
      TreasuryLedger.read(await _dbManager.database);

  @override
  Future<Money> getExpenseTotal() async {
    final db = await _dbManager.database;
    final rows = await db.rawQuery(
      "SELECT COALESCE(SUM(amount_int),0) AS total FROM ${AppTables.vouchers} WHERE purpose='expense' AND voucher_type='payment' AND (status IS NULL OR status='approved')",
    );
    return Money(rows.single['total'] as int);
  }

  /// Aggregate total; physical cash is exposed through balances.cash.
  @override
  Future<Money> getTreasuryBalance() async =>
      (await getTreasuryBalances()).total.available;

  @override
  Future<void> seedDefaultVouchersIfEmpty() async {
    // Demonstration transactions belong in explicit test fixtures, never SQLite startup.
  }
}

/// In-memory mock implementation of [VouchersRepository] for lightning-fast UI and unit tests.
class FakeVouchersRepository implements VouchersRepository {
  final List<VoucherModel> _vouchers = [];
  int _nextId = 1;

  // In-memory reference to parties to test live ledger adjustments
  final Map<int, PartyModel> inMemoryParties = {};

  @override
  Future<List<VoucherModel>> getVouchers({
    VoucherPurpose? purpose,
    VoucherType? type,
    int? partyId,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    int? limit,
    int? offset,
  }) async {
    var results = _vouchers.where((v) {
      if (purpose != null && v.purpose != purpose) return false;
      if (type != null && v.voucherType != type) return false;
      if (partyId != null && v.partyId != partyId) return false;
      if (startDate != null && v.voucherDate.isBefore(startDate)) return false;
      if (endDate != null && v.voucherDate.isAfter(endDate)) return false;
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        final matchNum = v.voucherNumber.toLowerCase().contains(q);
        final matchStmt = v.statement?.toLowerCase().contains(q) ?? false;
        final matchRef = v.referenceNumber?.toLowerCase().contains(q) ?? false;
        if (!matchNum && !matchStmt && !matchRef) return false;
      }
      return true;
    }).toList();

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
  Future<VoucherModel?> getVoucherById(int id) async {
    try {
      return _vouchers.firstWhere((v) => v.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<VoucherModel?> getVoucherByNumber(String number) async {
    try {
      return _vouchers.firstWhere((v) => v.voucherNumber == number.trim());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> createVoucher(VoucherModel voucher) async {
    voucher.validateForPosting();
    if (_vouchers.any(
      (v) =>
          v.voucherNumber == voucher.voucherNumber ||
          (voucher.id != null && v.id == voucher.id),
    )) {
      throw StateError('Voucher already exists');
    }
    final id = _nextId++;
    final vWithId = voucher.copyWith(id: id);
    _vouchers.add(vWithId);

    if (voucher.partyId != null) {
      final party = inMemoryParties[voucher.partyId];
      if (party != null) {
        final Money newBal;
        if (voucher.isReceipt) {
          newBal = party.currentBalance + voucher.amount;
        } else {
          newBal = party.currentBalance - voucher.amount;
        }
        inMemoryParties[voucher.partyId!] = party.copyWith(
          currentBalance: newBal,
        );
      }
    }

    return id;
  }

  @override
  Future<void> deleteVoucher(int id) async {
    final idx = _vouchers.indexWhere((v) => v.id == id);
    if (idx != -1) {
      final v = _vouchers[idx];
      if (v.isCancelled) return;
      if (v.partyId != null && v.isApproved) {
        final party = inMemoryParties[v.partyId];
        if (party != null) {
          final Money revBal;
          if (v.isReceipt) {
            revBal = party.currentBalance - v.amount;
          } else {
            revBal = party.currentBalance + v.amount;
          }
          inMemoryParties[v.partyId!] = party.copyWith(currentBalance: revBal);
        }
      }
      _vouchers[idx] = v.copyWith(status: VoucherStatus.cancelled);
    }
  }

  @override
  Future<String> generateNextVoucherNumber(VoucherType type) async {
    final prefix = type == VoucherType.receipt ? 'REC' : 'PAY';
    final year = DateTime.now().year;
    final regex = RegExp('^$prefix-$year-(\\d+)\$');
    int maxSeq = 0;
    for (final v in _vouchers.where((v) => v.voucherType == type)) {
      final match = regex.firstMatch(v.voucherNumber);
      if (match != null) {
        final seq = int.tryParse(match.group(1)!) ?? 0;
        if (seq > maxSeq) maxSeq = seq;
      }
    }
    final nextSeq = maxSeq + 1;
    return '$prefix-$year-${nextSeq.toString().padLeft(4, '0')}';
  }

  @override
  Future<TreasurySnapshot> getTreasuryBalances() async {
    final values = <TreasuryAccount, AccountCashFlow>{};
    var pending = Money.zero;
    for (final voucher in _vouchers.where((value) => value.isApproved)) {
      if (voucher.paymentMethod == PaymentMethod.cheque && voucher.isReceipt) {
        pending += voucher.amount;
        continue;
      }
      final account = voucher.paymentMethod == PaymentMethod.cheque ? voucher.chequeAccount : voucher.paymentMethod.account;
      final old = values[account] ?? AccountCashFlow.zero;
      if (voucher.paymentMethod == PaymentMethod.cheque) {
        values[account] = AccountCashFlow(receipts: old.receipts, payments: old.payments,
          balance: old.balance, reserved: old.reserved + voucher.amount);
        continue;
      }
      values[account] = AccountCashFlow(
        receipts:
            old.receipts + (voucher.isReceipt ? voucher.amount : Money.zero),
        payments:
            old.payments + (voucher.isPayment ? voucher.amount : Money.zero),
        balance:
            old.balance +
            (voucher.isReceipt ? voucher.amount : -voucher.amount),
        reserved: old.reserved,
      );
    }
    return TreasurySnapshot(
      cash: values[TreasuryAccount.cash] ?? AccountCashFlow.zero,
      bank: values[TreasuryAccount.bank] ?? AccountCashFlow.zero,
      transfers: values[TreasuryAccount.transfers] ?? AccountCashFlow.zero,
      pendingCheques: pending,
    );
  }

  @override
  Future<Money> getExpenseTotal() async => _vouchers
      .where((value) => value.isApproved && value.isExpense)
      .fold<Money>(Money.zero, (total, value) => total + value.amount);

  @override
  Future<Money> getTreasuryBalance() async =>
      (await getTreasuryBalances()).total.available;

  @override
  Future<void> seedDefaultVouchersIfEmpty() async {
    if (_vouchers.isEmpty) {
      final now = DateTime.now();
      final num = await generateNextVoucherNumber(VoucherType.receipt);
      final v = VoucherModel(
        id: _nextId++,
        voucherNumber: num,
        voucherType: VoucherType.receipt,
        partyId: 1,
        amount: const Money(100000), // 1,000.00 SAR
        paymentMethod: PaymentMethod.cash,
        statement: 'سند قبض تجريبي',
        voucherDate: now,
        createdAt: now,
      );
      _vouchers.add(v);
    }
  }
}
