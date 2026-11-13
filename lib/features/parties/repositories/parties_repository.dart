import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../sales/models/invoice_model.dart';
import '../../accounting/models/voucher_model.dart';
import '../models/party_model.dart';
import '../models/statement_model.dart';

/// Abstract contract for parties (customers and suppliers) repository in RAF ERP.
abstract class PartiesRepository {
  Future<List<PartyModel>> getParties({
    bool includeArchived = false,
    PartyType? type,
    String? searchQuery,
    bool? debtorOnly,
    int? limit,
    int? offset,
  });

  Future<PartyModel?> getPartyById(int id);
  Future<PartyModel?> getPartyByPhone(String phone);
  Future<int> insertParty(PartyModel party);
  Future<int> updateParty(PartyModel party);
  Future<int> deleteParty(int id);
  Future<PartyStatementSummary> getAccountStatement(int partyId);
  Future<void> seedDefaultDataIfEmpty();
}

/// SQLite-backed persistent implementation of [PartiesRepository].
class SqlitePartiesRepository implements PartiesRepository {
  final AppDatabase _dbManager;

  SqlitePartiesRepository([AppDatabase? dbManager])
    : _dbManager = dbManager ?? AppDatabase.instance;

  @override
  Future<List<PartyModel>> getParties({
    bool includeArchived = false,
    PartyType? type,
    String? searchQuery,
    bool? debtorOnly,
    int? limit,
    int? offset,
  }) async {
    final db = await _dbManager.database;
    final whereClauses = <String>[if (!includeArchived) 'is_active = 1'];
    final whereArgs = <dynamic>[];

    if (type != null) {
      whereClauses.add('(type = ? OR type = ?)');
      whereArgs.add(type.dbValue);
      whereArgs.add(PartyType.both.dbValue);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim()}%';
      whereClauses.add('(name LIKE ? OR phone LIKE ?)');
      whereArgs.add(q);
      whereArgs.add(q);
    }

    if (debtorOnly == true) {
      whereClauses.add('current_balance_int < 0');
    }

    final whereString = whereClauses.join(' AND ');

    final rows = await db.query(
      AppTables.parties,
      where: whereString.isEmpty ? null : whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'name ASC',
      limit: limit,
      offset: offset,
    );

    return rows.map(PartyModel.fromMap).toList();
  }

  @override
  Future<PartyModel?> getPartyById(int id) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      AppTables.parties,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PartyModel.fromMap(rows.first);
  }

  @override
  Future<PartyModel?> getPartyByPhone(String phone) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      AppTables.parties,
      where: 'phone = ? AND is_active = 1',
      whereArgs: [phone.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PartyModel.fromMap(rows.first);
  }

  @override
  Future<int> insertParty(PartyModel party) async {
    final db = await _dbManager.database;
    return await db.insert(AppTables.parties, party.toMap());
  }

  @override
  Future<int> updateParty(PartyModel party) async {
    if (party.id == null) {
      throw ArgumentError('Cannot update party without id');
    }
    final db = await _dbManager.database;
    // Metadata editors may hold a stale snapshot while financial transactions
    // change the account. Opening/current balances belong to the ledger.
    final metadata = party.copyWith(updatedAt: DateTime.now()).toMap()
      ..remove('id')
      ..remove('created_at')
      ..remove('is_active')
      ..remove('current_balance_int')
      ..remove('opening_balance_int');
    return await db.update(
      AppTables.parties,
      metadata,
      where: 'id = ?',
      whereArgs: [party.id],
    );
  }

  @override
  Future<int> deleteParty(int id) async {
    final db = await _dbManager.database;
    return await db.update(
      AppTables.parties,
      {'is_active': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<PartyStatementSummary> getAccountStatement(int partyId) async {
    final party = await getPartyById(partyId);
    if (party == null) {
      throw ArgumentError('Party not found for id $partyId');
    }

    final db = await _dbManager.database;

    // Fetch ONLY approved invoices for this party (exclude drafts and cancelled)
    final invoiceRows = await db.query(
      AppTables.invoices,
      where: 'party_id = ? AND status = ?',
      whereArgs: [partyId, InvoiceStatus.approved.dbValue],
      orderBy: 'invoice_date ASC, id ASC',
    );

    // Fetch ONLY approved vouchers for this party (exclude cancelled)
    final voucherRows = await db.query(
      AppTables.vouchers,
      where: 'party_id = ? AND (status IS NULL OR status = ?)',
      whereArgs: [partyId, VoucherStatus.approved.dbValue],
      orderBy: 'voucher_date ASC, id ASC',
    );

    final entries = <AccountStatementEntry>[];

    for (final row in invoiceRows) {
      final invDate = DateTime.fromMillisecondsSinceEpoch(
        row['invoice_date'] as int,
      );
      final invType = InvoiceType.fromString(row['invoice_type'] as String);
      final invNumber = row['invoice_number'] as String;
      final total = Money(row['total_int'] as int);
      final paid = Money(row['paid_amount_int'] as int);
      final id = row['id'] as int?;

      switch (invType) {
        case InvoiceType.sale:
          // Total invoice amount is debit (customer owes us)
          entries.add(
            AccountStatementEntry(
              id: id,
              date: invDate,
              transactionType: 'فاتورة مبيعات',
              referenceNumber: invNumber,
              statement: 'فاتورة مبيعات رقم $invNumber (إجمالي الفاتورة)',
              debit: total,
              credit: Money.zero,
              runningBalance: Money.zero,
            ),
          );
          // If cash paid down at invoice issuance: credit (party paid us)
          if (paid > Money.zero) {
            entries.add(
              AccountStatementEntry(
                id: id,
                date: invDate,
                transactionType: 'سداد نقدي',
                referenceNumber: invNumber,
                statement: 'دفعة مسددة مع الفاتورة رقم $invNumber',
                debit: Money.zero,
                credit: paid,
                runningBalance: Money.zero,
              ),
            );
          }
          break;

        case InvoiceType.purchase:
          // Total invoice amount is credit (we owe supplier)
          entries.add(
            AccountStatementEntry(
              id: id,
              date: invDate,
              transactionType: 'فاتورة مشتريات',
              referenceNumber: invNumber,
              statement: 'فاتورة مشتريات رقم $invNumber (إجمالي الفاتورة)',
              debit: Money.zero,
              credit: total,
              runningBalance: Money.zero,
            ),
          );
          // If cash paid down at invoice issuance: debit (we paid supplier)
          if (paid > Money.zero) {
            entries.add(
              AccountStatementEntry(
                id: id,
                date: invDate,
                transactionType: 'سداد نقدي',
                referenceNumber: invNumber,
                statement: 'دفعة مسددة مع الفاتورة رقم $invNumber',
                debit: paid,
                credit: Money.zero,
                runningBalance: Money.zero,
              ),
            );
          }
          break;

        case InvoiceType.saleReturn:
          // Return: goods returned by customer, reduces debt -> credit
          entries.add(
            AccountStatementEntry(
              id: id,
              date: invDate,
              transactionType: 'مرتجع مبيعات',
              referenceNumber: invNumber,
              statement: 'مرتجع مبيعات رقم $invNumber (إجمالي المرتجع)',
              debit: Money.zero,
              credit: total,
              runningBalance: Money.zero,
            ),
          );
          // If cash refund was paid to customer: debit
          if (paid > Money.zero) {
            entries.add(
              AccountStatementEntry(
                id: id,
                date: invDate,
                transactionType: 'استرداد نقدي',
                referenceNumber: invNumber,
                statement: 'مبلغ مسترد نقداً مع المرتجع رقم $invNumber',
                debit: paid,
                credit: Money.zero,
                runningBalance: Money.zero,
              ),
            );
          }
          break;

        case InvoiceType.purchaseReturn:
          // Return: goods returned to supplier, reduces what we owe -> debit
          entries.add(
            AccountStatementEntry(
              id: id,
              date: invDate,
              transactionType: 'مرتجع مشتريات',
              referenceNumber: invNumber,
              statement: 'مرتجع مشتريات رقم $invNumber (إجمالي المرتجع)',
              debit: total,
              credit: Money.zero,
              runningBalance: Money.zero,
            ),
          );
          // If supplier refunded cash to us: credit
          if (paid > Money.zero) {
            entries.add(
              AccountStatementEntry(
                id: id,
                date: invDate,
                transactionType: 'استرداد نقدي',
                referenceNumber: invNumber,
                statement: 'مبلغ مسترد نقداً مع المرتجع رقم $invNumber',
                debit: Money.zero,
                credit: paid,
                runningBalance: Money.zero,
              ),
            );
          }
          break;
      }
    }

    for (final row in voucherRows) {
      final vDate = DateTime.fromMillisecondsSinceEpoch(
        row['voucher_date'] as int,
      );
      final vType = VoucherType.fromString(row['voucher_type'] as String);
      final vNumber = row['voucher_number'] as String;
      final amount = Money(row['amount_int'] as int);
      final statement = (row['statement'] as String?)?.trim();
      final isReceipt = vType == VoucherType.receipt;

      entries.add(
        AccountStatementEntry(
          id: row['id'] as int?,
          date: vDate,
          transactionType: isReceipt ? 'سند قبض' : 'سند صرف',
          referenceNumber: vNumber,
          statement: (statement != null && statement.isNotEmpty)
              ? statement
              : (isReceipt ? 'سند قبض رقم $vNumber' : 'سند صرف رقم $vNumber'),
          debit: isReceipt ? Money.zero : amount,
          credit: isReceipt ? amount : Money.zero,
          runningBalance: Money.zero,
        ),
      );
    }

    // Sort all combined entries chronologically
    entries.sort((a, b) => a.date.compareTo(b.date));

    // Calculate running balance and totals with exact opening balance preservation
    final resolvedEntries = <AccountStatementEntry>[];
    var running = party.openingBalance;
    var totalDebit = Money.zero;
    var totalCredit = Money.zero;

    if (party.openingBalance != Money.zero) {
      final isDebtor = party.openingBalance.isNegative;
      final openingDebit = isDebtor ? party.openingBalance.abs : Money.zero;
      final openingCredit = !isDebtor ? party.openingBalance : Money.zero;

      totalDebit = totalDebit + openingDebit;
      totalCredit = totalCredit + openingCredit;

      resolvedEntries.add(
        AccountStatementEntry(
          date: party.createdAt,
          transactionType: 'رصيد افتتاحي',
          referenceNumber: null,
          statement: 'رصيد افتتاحي للطرف',
          debit: openingDebit,
          credit: openingCredit,
          runningBalance: party.openingBalance,
        ),
      );
    }

    for (final e in entries) {
      totalDebit = totalDebit + e.debit;
      totalCredit = totalCredit + e.credit;
      // Balance invariant: credit increases (+), debit decreases (-)
      running = running + e.credit - e.debit;

      resolvedEntries.add(
        AccountStatementEntry(
          id: e.id,
          date: e.date,
          transactionType: e.transactionType,
          referenceNumber: e.referenceNumber,
          statement: e.statement,
          debit: e.debit,
          credit: e.credit,
          runningBalance: running,
        ),
      );
    }

    return PartyStatementSummary(
      party: party,
      openingBalance: party.openingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      currentBalance: party.currentBalance,
      entries: resolvedEntries,
    );
  }

  @override
  Future<void> seedDefaultDataIfEmpty() async {
    final db = await _dbManager.database;
    // Production startup must never manufacture parties or opening debt.
    // Keep the legacy completion marker; existing business records are untouched.
    await db.insert(AppTables.appSettings, {
      'key': 'parties_seed_completed',
      'value': 'true',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

/// In-memory mock implementation of [PartiesRepository] for fast, reliable testing.
class FakePartiesRepository implements PartiesRepository {
  final List<PartyModel> _parties = [];
  final Map<int, List<AccountStatementEntry>> _mockStatements = {};
  int _nextId = 1;
  bool _partiesSeedCompleted = false;

  void clearBusinessData() {
    _parties.clear();
    _mockStatements.clear();
    _partiesSeedCompleted = true;
  }

  @override
  Future<void> seedDefaultDataIfEmpty() async {
    if (_partiesSeedCompleted) return;
    if (_parties.isEmpty) {
      _partiesSeedCompleted = true;
      final now = DateTime.now();

      final c1 = PartyModel(
        id: _nextId++,
        name: 'مؤسسة الأفق للتجارة',
        phone: '0501234567',
        type: PartyType.customer,
        currentBalance: const Money(-250000), // Debtor -2,500.00 SAR
        creditLimit: const Money(1000000), // 10,000.00 SAR
        address: 'الرياض - حي الملز',
        createdAt: now,
        updatedAt: now,
      );

      final c2 = PartyModel(
        id: _nextId++,
        name: 'سوبرماركت البركة',
        phone: '0559876543',
        type: PartyType.customer,
        currentBalance: Money.zero,
        creditLimit: const Money(500000),
        address: 'جدة - حي الصفا',
        createdAt: now,
        updatedAt: now,
      );

      final s1 = PartyModel(
        id: _nextId++,
        name: 'شركة الوادي للصناعات الغذائية',
        phone: '0567788990',
        type: PartyType.supplier,
        currentBalance: const Money(1500000), // Creditor +15,000.00 SAR
        creditLimit: const Money(5000000),
        address: 'الدمام - المدينة الصناعية',
        createdAt: now,
        updatedAt: now,
      );

      final s2 = PartyModel(
        id: _nextId++,
        name: 'مصنع الجزيرة للتعبئة والتغليف',
        phone: '0543210987',
        type: PartyType.supplier,
        currentBalance: Money.zero,
        creditLimit: const Money(2000000),
        address: 'الرياض - السلي',
        createdAt: now,
        updatedAt: now,
      );

      _parties.addAll([c1, c2, s1, s2]);

      // Seed mock statement entries for c1
      _mockStatements[c1.id!] = [
        AccountStatementEntry(
          id: 1,
          date: now.subtract(const Duration(days: 10)),
          transactionType: 'فاتورة مبيعات',
          referenceNumber: 'INV-2026-001',
          statement: 'فاتورة مبيعات رقم INV-2026-001',
          debit: const Money(500000),
          credit: Money.zero,
          runningBalance: const Money(-500000),
        ),
        AccountStatementEntry(
          id: 2,
          date: now.subtract(const Duration(days: 3)),
          transactionType: 'سند قبض',
          referenceNumber: 'RCT-2026-001',
          statement: 'دفعة نقدية مسددة',
          debit: Money.zero,
          credit: const Money(250000),
          runningBalance: const Money(-250000),
        ),
      ];
    }
  }

  @override
  Future<List<PartyModel>> getParties({
    bool includeArchived = false,
    PartyType? type,
    String? searchQuery,
    bool? debtorOnly,
    int? limit,
    int? offset,
  }) async {
    var results = _parties.where((p) {
      if (!includeArchived && !p.isActive) return false;
      if (type != null && p.type != type && p.type != PartyType.both) {
        return false;
      }
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        final match = p.name.toLowerCase().contains(q) || p.phone.contains(q);
        if (!match) return false;
      }
      if (debtorOnly == true && !p.isDebtor) {
        return false;
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
  Future<PartyModel?> getPartyById(int id) async {
    try {
      return _parties.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<PartyModel?> getPartyByPhone(String phone) async {
    try {
      return _parties.firstWhere((p) => p.phone == phone.trim() && p.isActive);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> insertParty(PartyModel party) async {
    final id = _nextId++;
    final partyWithId = party.copyWith(id: id);
    _parties.add(partyWithId);
    return id;
  }

  @override
  Future<int> updateParty(PartyModel party) async {
    final idx = _parties.indexWhere((p) => p.id == party.id);
    if (idx != -1) {
      _parties[idx] = party.copyWith(
        currentBalance: _parties[idx].currentBalance,
        openingBalance: _parties[idx].openingBalance,
        isActive: _parties[idx].isActive,
        createdAt: _parties[idx].createdAt,
        updatedAt: DateTime.now(),
      );
      return 1;
    }
    return 0;
  }

  @override
  Future<int> deleteParty(int id) async {
    final idx = _parties.indexWhere((p) => p.id == id);
    if (idx != -1) {
      _parties[idx] = _parties[idx].copyWith(isActive: false);
      return 1;
    }
    return 0;
  }

  @override
  Future<PartyStatementSummary> getAccountStatement(int partyId) async {
    final party = await getPartyById(partyId);
    if (party == null) {
      throw ArgumentError('Party not found for id $partyId');
    }

    final entries = _mockStatements[partyId] ?? [];
    var totalDebit = Money.zero;
    var totalCredit = Money.zero;

    for (final e in entries) {
      totalDebit = totalDebit + e.debit;
      totalCredit = totalCredit + e.credit;
    }

    return PartyStatementSummary(
      party: party,
      openingBalance: party.openingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      currentBalance: party.currentBalance,
      entries: entries,
    );
  }
}
