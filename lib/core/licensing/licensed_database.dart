import 'package:sqflite/sqflite.dart';
import 'license_service.dart';

/// Checks at SQLite transaction entry (after acquiring its queue), never halfway
/// through an accepted transaction. No accounting policies or SQL are changed.
class LicensedDatabase extends _LicensedExecutor implements Database {
  final Database _inner;
  final LicenseGuard guard;
  LicensedDatabase(this._inner, this.guard);

  @override
  Future<T> perform<T>(Future<T> Function(DatabaseExecutor) action) =>
      transaction((txn) => action(txn));

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction) action, {
    bool? exclusive,
  }) => _inner.transaction((txn) async {
    await guard.check();
    final permit = _TransactionPermit(txn, this);
    try {
      return await action(permit);
    } finally {
      permit.finished = true;
    }
  }, exclusive: exclusive);

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction) action) =>
      transaction(action);
  @override
  Database get database => this;
  @override
  String get path => _inner.path;
  @override
  bool get isOpen => _inner.isOpen;
  @override
  Future<void> close() => _inner.close();
}

class _TransactionPermit extends _LicensedExecutor implements Transaction {
  final Transaction _inner;
  final LicensedDatabase _root;
  bool finished = false;
  _TransactionPermit(this._inner, this._root);
  @override
  Database get database => _root;
  @override
  Future<T> perform<T>(Future<T> Function(DatabaseExecutor) action) {
    if (finished) throw StateError('Transaction permit has ended');
    return action(_inner);
  }
}

abstract class _LicensedExecutor implements DatabaseExecutor {
  Future<T> perform<T>(Future<T> Function(DatabaseExecutor) action);
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      perform((d) => d.execute(sql, arguments));
  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      perform((d) => d.rawInsert(sql, arguments));
  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      perform((d) => d.rawUpdate(sql, arguments));
  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      perform((d) => d.rawDelete(sql, arguments));
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) => perform((d) => d.rawQuery(sql, arguments));
  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => perform(
    (d) => d.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    ),
  );
  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => perform(
    (d) => d.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    ),
  );
  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      perform((d) => d.delete(table, where: where, whereArgs: whereArgs));
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => perform(
    (d) => d.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    ),
  );
  @override
  Batch batch() => _LicensedBatch(this);

  // Unsupported cursor/dev/new APIs fail closed; they never leak the raw DB.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unsupported licensed database API: ${invocation.memberName}',
  );
}

class _LicensedBatch implements Batch {
  final _LicensedExecutor executor;
  final List<void Function(Batch)> _operations = [];
  _LicensedBatch(this.executor);
  @override
  int get length => _operations.length;
  @override
  void execute(String sql, [List<Object?>? arguments]) =>
      _operations.add((b) => b.execute(sql, arguments));
  @override
  void rawInsert(String sql, [List<Object?>? arguments]) =>
      _operations.add((b) => b.rawInsert(sql, arguments));
  @override
  void rawUpdate(String sql, [List<Object?>? arguments]) =>
      _operations.add((b) => b.rawUpdate(sql, arguments));
  @override
  void rawDelete(String sql, [List<Object?>? arguments]) =>
      _operations.add((b) => b.rawDelete(sql, arguments));
  @override
  void rawQuery(String sql, [List<Object?>? arguments]) =>
      _operations.add((b) => b.rawQuery(sql, arguments));
  @override
  void insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _operations.add(
    (b) => b.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    ),
  );
  @override
  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _operations.add(
    (b) => b.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    ),
  );
  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _operations.add(
        (b) => b.delete(table, where: where, whereArgs: whereArgs),
      );
  @override
  void query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _operations.add(
    (b) => b.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    ),
  );
  @override
  Future<List<Object?>> commit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
  }) => executor.perform((d) {
    final b = d.batch();
    for (final operation in _operations) {
      operation(b);
    }
    return b.commit(noResult: noResult, continueOnError: continueOnError);
  });
  @override
  Future<List<Object?>> apply({
    bool? noResult,
    bool? continueOnError,
  }) => throw UnsupportedError(
    'Non-atomic batches are not allowed by the license boundary; use commit.',
  );
}
