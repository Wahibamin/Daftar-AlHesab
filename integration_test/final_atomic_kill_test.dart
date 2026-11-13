// Deliberately interrupted QA process; never part of lib/main.dart or Release.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Authorized QA forced-stop mid-transaction',
    (tester) async {
      final manager = AppDatabase.instance;
      manager.configureForTesting();
      final db = await manager.database;
      expect(db.path.contains('/com.example.m3.licenseqa/'), true);
      expect(
        (await db.rawQuery('SELECT COUNT(*) n FROM items')).single['n'],
        503,
      );
      await expectLater(
        db.rawInsert(
          'INSERT INTO invoice_items(invoice_id,item_id,quantity_int,unit_price_int,total_price_int) VALUES(999999,999999,1,100,100)',
        ),
        throwsA(isA<DatabaseException>()),
      );
      // A private probe table is independent of accounting records and schema.
      await db.execute(
        'CREATE TABLE IF NOT EXISTS qa_atomic_probe(id INTEGER PRIMARY KEY)',
      );
      expect(await db.query('qa_atomic_probe'), isEmpty);
      await db.transaction((txn) async {
        await txn.insert('qa_atomic_probe', {'id': 1});
        // The host waits for this marker, then force-stops this QA process only.
        // The subsequent read-only snapshot must find zero committed probe rows.
        // ignore: avoid_print
        print('FINAL_QA_ORPHAN_REJECTED_AND_KILL_TRANSACTION_READY');
        await Future<void>.delayed(const Duration(minutes: 5));
        throw StateError(
          'Host did not interrupt the QA fixture; rollback required',
        );
      });
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
