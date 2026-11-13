import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/database/app_database.dart';
import 'package:m3/core/utils/money.dart';
import 'package:m3/features/accounting/models/voucher_model.dart';
import 'package:m3/features/accounting/repositories/vouchers_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../integration_test/support/phase04_snapshot.dart';

void main() {
  sqfliteFfiInit();
  final manager = AppDatabase.instance;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'daftar_phase04_lifecycle_',
    );
    manager.configureForTesting(
      factory: databaseFactoryFfi,
      path: '${directory.path}/isolated.db',
    );
    final now = DateTime(2026, 11, 5);
    await SqliteVouchersRepository().createVoucher(
      VoucherModel(
        voucherNumber: 'PH04-LIFECYCLE',
        voucherType: VoucherType.receipt,
        amount: const Money(12345),
        paymentMethod: PaymentMethod.bank,
        voucherDate: now,
        createdAt: now,
      ),
    );
  });
  tearDown(() async {
    await manager.close();
    await directory.delete(recursive: true);
  });
  test(
    'Phase04 closed captured handle reproduces bug; shared snapshot reopens and preserves data',
    () async {
      final captured = await manager.database;
      final before = await phase04Snapshot(manager);
      expect(before['bank'], 12345);
      await manager.close();
      expect(captured.isOpen, isFalse);
      await expectLater(
        () => captured.rawQuery('SELECT COUNT(*) FROM vouchers'),
        throwsA(isA<DatabaseException>()),
      );
      final after = await phase04Snapshot(manager);
      expect(after, before);
      final live = await manager.database;
      expect(live.isOpen, isTrue);
      expect(await live.getVersion(), 6);
      expect(
        (await live.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
    },
  );
  test(
    'Phase04 awaited snapshot batches finish before close; later callbacks resolve a new connection',
    () async {
      final expected = await phase04Snapshot(manager);
      final batch = await Future.wait(
        List.generate(4, (_) => phase04Snapshot(manager)),
      );
      expect(batch, everyElement(equals(expected)));
      for (var cycle = 0; cycle < 3; cycle++) {
        await manager.close();
        final later = await Future<Map<String, Object?>>(
          () => phase04Snapshot(manager),
        );
        expect(later, expected);
      }
      expect(
        await (await manager.database).rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
    },
  );
}
