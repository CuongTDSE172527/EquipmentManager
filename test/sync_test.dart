import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/sync_model.dart';
import 'package:equipment_manager/sync/sync_engine.dart';

/// Minimal server: keeps the newest state per record and a change feed.
class MemoryServer implements SyncTransport {
  final records = <String, SyncChange>{};
  final feed = <SyncChange>[];
  @override
  Future<List<SyncChange>> push(
    String deviceId,
    List<SyncChange> changes,
  ) async {
    for (final c in changes) {
      // Round-trip through JSON like a real HTTP server would.
      final copy = SyncChange.fromJson(
        jsonDecode(jsonEncode(c.toJson())) as Json,
      );
      final key = '${c.entity}/${c.id}';
      final current = records[key];
      if (current == null || copy.winsOver(current)) {
        records[key] = copy;
        feed.add(copy);
      }
    }
    return changes;
  }

  @override
  Future<SyncPull> pull(String deviceId, String? cursor) async {
    final from = int.parse(cursor ?? '0');
    return SyncPull(feed.sublist(from), '${feed.length}');
  }
}

void main() {
  test(
    'Mỗi thay đổi tăng phiên bản; xóa thiết bị tạo tombstone cho cả con',
    () async {
      final db = AppDatabase.memory();
      final repo = EquipmentRepository(db);
      try {
        final e = Equipment(name: 'Xe nâng');
        await repo.saveEquipment(e);
        await repo.saveEquipment(e.copy({'note': 'sửa'}));
        final item = DeadlineItem(
          equipmentId: e.id,
          kind: ItemKind.maintenance,
          title: 'Bảo dưỡng',
          cycleMonths: 6,
          provider: 'Đơn vị mới',
        );
        await repo.saveItem(item);
        await repo.recordCompletion(
          item.copy({'dueDate': DateTime(2027).toIso8601String()}),
          HistoryLog(itemId: item.id, doneDate: DateTime(2026, 11, 1)),
        );
        final data = Uint8List.fromList(utf8.encode('%PDF'));
        await repo.addAttachment(
          Attachment(
            equipmentId: e.id,
            fileName: 'a.pdf',
            size: data.length,
            sha256: sha256.convert(data).toString(),
          ),
          data,
        );
        var pending = await repo.pendingChanges();
        final equipment = pending.singleWhere((c) => c.entity == 'equipment');
        expect(equipment.version, 2);
        expect(equipment.payload!['note'], 'sửa');
        expect(pending.map((c) => c.entity).toSet(), {
          'catalog',
          'equipment',
          'item',
          'history',
          'attachment',
        });
        expect(
          base64Decode(
            pending
                    .singleWhere((c) => c.entity == 'attachment')
                    .payload!['data']
                as String,
          ),
          data,
        );
        await repo.markPushed(pending);
        expect(await repo.pendingSyncCount(), 0);
        await repo.deleteEquipment(e.id);
        pending = await repo.pendingChanges();
        expect(pending.every((c) => c.deleted && c.payload == null), isTrue);
        expect(pending.map((c) => c.entity).toSet(), {
          'equipment',
          'item',
          'history',
          'attachment',
        });
      } finally {
        await db.close();
      }
    },
  );

  test(
    'Nâng schema 3 lên 4: dữ liệu giữ nguyên và được xếp hàng đồng bộ',
    () async {
      final root = await Directory.systemTemp.createTemp('equipment-v4-');
      final path = p.join(root.path, 'equipment_manager.db');
      try {
        final legacy = AppDatabase.open(File(path));
        final e = Equipment(name: 'Thiết bị từ 0.3.0');
        await EquipmentRepository(legacy).saveEquipment(e);
        await legacy.close();
        final raw = sqlite3.open(path);
        for (final table in [
          'accounts',
          'audit_log',
          'sync_state',
          'local_meta',
        ]) {
          raw.execute('DROP TABLE $table');
        }
        raw.execute('PRAGMA user_version = 3');
        raw.close();

        final upgraded = AppDatabase.open(File(path));
        final repo = EquipmentRepository(upgraded);
        expect((await repo.equipment()).single.id, e.id);
        expect(await repo.accounts(), isEmpty);
        final pending = await repo.pendingChanges();
        expect(pending.where((c) => c.entity == 'equipment').single.id, e.id);
        expect(pending.where((c) => c.entity == 'catalog'), isNotEmpty);
        final device = await repo.deviceId();
        expect(pending.every((c) => c.deviceId == device), isTrue);
        await upgraded.close();
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'Hai máy đồng bộ qua máy chủ; bản sửa mới hơn thắng, xóa lan sang máy kia',
    () async {
      var clock = DateTime.utc(2026, 11, 11, 8);
      final dbA = AppDatabase.memory(), dbB = AppDatabase.memory();
      final a = EquipmentRepository(dbA, clock: () => clock);
      final b = EquipmentRepository(dbB, clock: () => clock);
      final server = MemoryServer();
      try {
        final e = Equipment(name: 'Xe thang');
        await a.saveEquipment(e);
        await a.saveItem(
          DeadlineItem(
            equipmentId: e.id,
            kind: ItemKind.inspection,
            title: 'ĐK',
          ),
        );
        final first = await SyncEngine(a, server).run();
        expect(first.pushed, greaterThanOrEqualTo(2));
        final received = await SyncEngine(b, server).run();
        expect(received.applied, greaterThanOrEqualTo(2));
        expect((await b.equipment()).single.name, 'Xe thang');
        expect((await b.items()).single.title, 'ĐK');
        // Applying remote changes does not queue them to be sent back.
        expect(await b.pendingSyncCount(), 0);

        clock = clock.add(const Duration(minutes: 1));
        await a.saveEquipment(e.copy({'name': 'Xe thang (máy A)'}));
        clock = clock.add(const Duration(minutes: 1));
        await b.saveEquipment(e.copy({'name': 'Xe thang (máy B, mới hơn)'}));
        await SyncEngine(a, server).run();
        final conflict = await SyncEngine(b, server).run();
        expect(conflict.skipped, 1);
        await SyncEngine(a, server).run();
        expect((await a.equipment()).single.name, 'Xe thang (máy B, mới hơn)');
        expect((await b.equipment()).single.name, 'Xe thang (máy B, mới hơn)');

        clock = clock.add(const Duration(minutes: 1));
        await b.deleteEquipment(e.id);
        await SyncEngine(b, server).run();
        await SyncEngine(a, server).run();
        expect(await a.equipment(), isEmpty);
        expect(await a.items(), isEmpty);
        expect((await a.auditEntries()).any((x) => x.action == 'sync'), isTrue);
      } finally {
        await dbA.close();
        await dbB.close();
      }
    },
  );

  test('Chưa cấu hình máy chủ thì không gửi gì', () async {
    final db = AppDatabase.memory();
    try {
      final repo = EquipmentRepository(db);
      await repo.saveEquipment(Equipment(name: 'Giữ trên máy'));
      await expectLater(
        SyncEngine(repo, const NotConfiguredTransport()).run(),
        throwsA(isA<SyncNotConfigured>()),
      );
      expect(await repo.pendingSyncCount(), greaterThan(0));
      expect(
        () => SyncChange.fromJson({
          'entity': 'accounts',
          'id': 'x',
          'version': 1,
          'updatedAt': '',
          'deviceId': 'd',
          'deleted': true,
        }),
        throwsFormatException,
      );
    } finally {
      await db.close();
    }
  });
}
