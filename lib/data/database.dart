import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import '../domain/models.dart';

/// SQL is explicit so the desktop reminder and migrations use the same schema.
/// Payloads are versioned domain records; indexed columns enforce relationships.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);
  factory AppDatabase.open(File file) => AppDatabase(NativeDatabase(file));
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());
  @override
  int get schemaVersion => 3;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE equipment (id TEXT PRIMARY KEY, name TEXT NOT NULL, management_status TEXT NOT NULL, payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE deadline_items (id TEXT PRIMARY KEY, equipment_id TEXT NOT NULL REFERENCES equipment(id) ON DELETE CASCADE, payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE INDEX items_equipment ON deadline_items(equipment_id)',
      );
      await customStatement(
        'CREATE TABLE history_logs (id TEXT PRIMARY KEY, item_id TEXT NOT NULL REFERENCES deadline_items(id) ON DELETE CASCADE, payload TEXT NOT NULL)',
      );
      await _createServiceRecords();
      await _createAttachments();
      await customStatement(
        'CREATE INDEX history_item ON history_logs(item_id)',
      );
      await customStatement(
        'CREATE TABLE settings (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE catalogs (kind TEXT NOT NULL, name TEXT NOT NULL, PRIMARY KEY(kind,name))',
      );
      for (final group in [
        'I. Phục vụ bay',
        'II. Khẩn nguy, văn phòng, khu bay',
      ]) {
        await customStatement('INSERT INTO catalogs VALUES (?, ?)', [
          'group',
          group,
        ]);
      }
      for (final provider in [
        'SAGS',
        'Hãng Hyundai',
        'Cần Thơ FORD',
        'Toyota',
        'Isuzu',
        'Đức Tùng',
        'CAH tự thực hiện',
      ]) {
        await customStatement('INSERT INTO catalogs VALUES (?, ?)', [
          'provider',
          provider,
        ]);
      }
    },
    onUpgrade: (_, from, to) async {
      if (from < 2) await _createServiceRecords();
      if (from < 3) await _createAttachments();
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );

  Future<void> _createServiceRecords() async {
    await customStatement(
      'CREATE TABLE service_records (id TEXT PRIMARY KEY, equipment_id TEXT NOT NULL REFERENCES equipment(id) ON DELETE CASCADE, payload TEXT NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX service_equipment ON service_records(equipment_id)',
    );
  }

  Future<void> _createAttachments() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS attachments (id TEXT PRIMARY KEY, equipment_id TEXT NOT NULL REFERENCES equipment(id) ON DELETE CASCADE, link_id TEXT, payload TEXT NOT NULL, data BLOB NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS attachments_equipment ON attachments(equipment_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS attachments_link ON attachments(link_id)',
    );
  }
}

/// Current backup format. 1 and 2 are JSON only; 3 adds attachment metadata,
/// with the bytes stored beside the JSON in a ZIP archive.
const backupVersion = 3;

class EquipmentRepository {
  EquipmentRepository(this.db);
  final AppDatabase db;

  Future<List<Json>> _rows(String table) async =>
      (await db.customSelect('SELECT payload FROM $table').get())
          .map((r) => jsonDecode(r.read<String>('payload')) as Json)
          .toList();
  Future<List<Equipment>> equipment() async =>
      (await _rows('equipment')).map(Equipment.fromJson).toList();
  Future<List<DeadlineItem>> items() async =>
      (await _rows('deadline_items')).map(DeadlineItem.fromJson).toList();
  Future<List<HistoryLog>> history() async =>
      (await _rows('history_logs')).map(HistoryLog.fromJson).toList();
  Future<List<ServiceRecord>> serviceRecords() async =>
      (await _rows('service_records')).map(ServiceRecord.fromJson).toList();

  Future<void> saveServiceRecord(ServiceRecord record) async {
    validateServiceRecord(record);
    await db.transaction(() async {
      await db.customStatement(
        'INSERT INTO service_records VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET equipment_id=excluded.equipment_id,payload=excluded.payload',
        [record.id, record.equipmentId, jsonEncode(record.toJson())],
      );
      if (record.provider.isNotEmpty) {
        await addCatalog('provider', record.provider);
      }
    });
  }

  Future<void> deleteServiceRecord(String id) => db.transaction(() async {
    await _unlinkAttachments(id);
    await db.customStatement('DELETE FROM service_records WHERE id=?', [id]);
  });

  /// Metadata only; bytes are read on demand with [attachmentData].
  Future<List<Attachment>> attachments() async =>
      (await _rows('attachments')).map(Attachment.fromJson).toList();

  Future<Uint8List> attachmentData(String id) async {
    final rows = await db
        .customSelect(
          'SELECT data FROM attachments WHERE id = ?',
          variables: [Variable(id)],
        )
        .get();
    if (rows.isEmpty) throw StateError('Không tìm thấy tệp đính kèm.');
    return rows.single.read<Uint8List>('data');
  }

  Future<void> addAttachment(Attachment a, Uint8List data) async {
    validateAttachment(a);
    if (data.length != a.size || sha256.convert(data).toString() != a.sha256) {
      throw const FormatException('Nội dung tệp đính kèm không khớp.');
    }
    await db.customStatement('INSERT INTO attachments VALUES (?, ?, ?, ?, ?)', [
      a.id,
      a.equipmentId,
      a.linkId,
      jsonEncode(a.toJson()),
      data,
    ]);
  }

  /// Changes title, note or link; the stored bytes are never replaced.
  Future<void> updateAttachment(Attachment a) async {
    validateAttachment(a);
    final current = (await attachments()).where((x) => x.id == a.id);
    if (current.isEmpty ||
        current.single.sha256 != a.sha256 ||
        current.single.equipmentId != a.equipmentId) {
      throw const FormatException('Không sửa được tệp đính kèm này.');
    }
    await db.customStatement(
      'UPDATE attachments SET link_id=?, payload=? WHERE id=?',
      [a.linkId, jsonEncode(a.toJson()), a.id],
    );
  }

  Future<void> deleteAttachment(String id) =>
      db.customStatement('DELETE FROM attachments WHERE id=?', [id]);

  /// Documents outlive the item or record they were linked to; they move back
  /// to the equipment instead of being deleted with it.
  Future<void> _unlinkAttachments(String linkId) async {
    final rows = await db
        .customSelect(
          'SELECT payload FROM attachments WHERE link_id = ?',
          variables: [Variable(linkId)],
        )
        .get();
    for (final row in rows) {
      final a = Attachment.fromJson(
        jsonDecode(row.read<String>('payload')) as Json,
      ).copy({'linkId': null});
      await db.customStatement(
        'UPDATE attachments SET link_id=NULL, payload=? WHERE id=?',
        [jsonEncode(a.toJson()), a.id],
      );
    }
  }

  Future<AppSettings> settings() async {
    final rows = await _rows('settings');
    return rows.isEmpty
        ? const AppSettings()
        : AppSettings.fromJson(rows.first);
  }

  Future<List<String>> catalog(String kind) async =>
      (await db
              .customSelect(
                'SELECT name FROM catalogs WHERE kind = ? ORDER BY name',
                variables: [Variable(kind)],
              )
              .get())
          .map((r) => r.read<String>('name'))
          .toList();
  Future<void> addCatalog(String kind, String name) async {
    if (!['group', 'provider'].contains(kind) || name.trim().isEmpty) {
      throw ArgumentError('Danh mục không hợp lệ.');
    }
    await db.customStatement('INSERT OR IGNORE INTO catalogs VALUES (?, ?)', [
      kind,
      name.trim(),
    ]);
  }

  Future<void> renameCatalog(
    String kind,
    String oldName,
    String newName,
  ) async {
    if (newName.trim().isEmpty) {
      throw ArgumentError('Tên danh mục không được trống.');
    }
    await db.transaction(() async {
      await addCatalog(kind, newName);
      if (kind == 'group') {
        for (final e in await equipment()) {
          if (e.group == oldName) {
            await saveEquipment(e.copy({'group': newName.trim()}));
          }
        }
      } else {
        for (final item in await items()) {
          if (item.provider == oldName) {
            await saveItem(item.copy({'provider': newName.trim()}));
          }
        }
        // Historical provider names deliberately retain the name at execution time.
      }
      await db.customStatement('DELETE FROM catalogs WHERE kind=? AND name=?', [
        kind,
        oldName,
      ]);
    });
  }

  Future<void> saveEquipment(Equipment e) async {
    if (e.name.trim().isEmpty) {
      throw ArgumentError('Tên thiết bị không được trống.');
    }
    if (e.yearMade != null && (e.yearMade! < 1900 || e.yearMade! > 9999)) {
      throw ArgumentError('Năm sản xuất không hợp lệ.');
    }
    await db.customStatement(
      'INSERT INTO equipment VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,management_status=excluded.management_status,payload=excluded.payload',
      [e.id, e.name, e.managementStatus.name, jsonEncode(e.toJson())],
    );
    await addCatalog('group', e.group);
  }

  Future<void> saveItem(DeadlineItem item) async {
    if (item.title.trim().isEmpty ||
        item.cycleMonths < 0 ||
        (item.cost ?? 0) < 0) {
      throw ArgumentError('Hạng mục không hợp lệ.');
    }
    if (item.kind == ItemKind.lifespan && item.cycleMonths != 0) {
      throw ArgumentError('Niên hạn không có chu kỳ.');
    }
    await db.customStatement(
      'INSERT INTO deadline_items VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET equipment_id=excluded.equipment_id,payload=excluded.payload',
      [item.id, item.equipmentId, jsonEncode(item.toJson())],
    );
    if (item.provider.isNotEmpty) await addCatalog('provider', item.provider);
  }

  Future<void> deleteEquipment(String id) =>
      db.customStatement('DELETE FROM equipment WHERE id=?', [id]);
  Future<void> deleteItem(String id) => db.transaction(() async {
    await _unlinkAttachments(id);
    await db.customStatement('DELETE FROM deadline_items WHERE id=?', [id]);
  });
  Future<void> saveSettings(AppSettings settings) async {
    validateSettings(settings);
    await db.customStatement(
      'INSERT INTO settings VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
      [jsonEncode(settings.toJson())],
    );
  }

  Future<void> recordCompletion(DeadlineItem item, HistoryLog log) async {
    if (item.id != log.itemId) {
      throw ArgumentError('Lịch sử không khớp hạng mục.');
    }
    await db.transaction(() async {
      await saveItem(item);
      await db.customStatement('INSERT INTO history_logs VALUES (?, ?, ?)', [
        log.id,
        log.itemId,
        jsonEncode(log.toJson()),
      ]);
    });
  }

  Future<Json> snapshot() async => {
    'format': 'EquipmentManager',
    'version': backupVersion,
    'equipment': (await equipment()).map((e) => e.toJson()).toList(),
    'items': (await items()).map((e) => e.toJson()).toList(),
    'history': (await history()).map((e) => e.toJson()).toList(),
    'serviceRecords': (await serviceRecords()).map((e) => e.toJson()).toList(),
    'settings': (await settings()).toJson(),
    'groups': await catalog('group'),
    'providers': await catalog('provider'),
    'attachments': (await attachments()).map((e) => e.toJson()).toList(),
  };

  /// Parse and validate the complete backup before deleting any current records.
  /// [files] holds attachment bytes by attachment id (backup format 3).
  /// Formats 1 and 2 carry no attachments, so restoring them removes all.
  Future<void> restore(
    Json backup, {
    Map<String, Uint8List> files = const {},
  }) async {
    if (backup['format'] != 'EquipmentManager' ||
        ![1, 2, 3].contains(backup['version'])) {
      throw const FormatException(
        'File sao lưu không đúng định dạng hoặc phiên bản.',
      );
    }
    final equipmentRows = (backup['equipment'] as List)
        .map((e) => Equipment.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final itemRows = (backup['items'] as List)
        .map((e) => DeadlineItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final logs = (backup['history'] as List)
        .map((e) => HistoryLog.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final services =
        (backup['version'] == 1
                ? <dynamic>[]
                : backup['serviceRecords'] as List)
            .map(
              (e) =>
                  ServiceRecord.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
    for (final record in services) {
      validateServiceRecord(record);
    }
    final attached = backup['version'] == 3
        ? (backup['attachments'] as List? ?? const [])
              .map(
                (e) => Attachment.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList()
        : <Attachment>[];
    for (final a in attached) {
      validateAttachment(a);
      final data = files[a.id];
      if (data == null ||
          data.length != a.size ||
          sha256.convert(data).toString() != a.sha256) {
        throw FormatException(
          'Sao lưu thiếu hoặc hỏng tệp đính kèm “${a.title}”.',
        );
      }
    }
    final config = AppSettings.fromJson(
      Map<String, dynamic>.from(backup['settings'] as Map),
    );
    validateSettings(config);
    final ids = equipmentRows.map((e) => e.id).toSet();
    final itemIds = itemRows.map((e) => e.id).toSet();
    if (ids.length != equipmentRows.length ||
        itemIds.length != itemRows.length ||
        logs.map((e) => e.id).toSet().length != logs.length ||
        services.map((e) => e.id).toSet().length != services.length ||
        attached.map((e) => e.id).toSet().length != attached.length ||
        attached.any((e) => !ids.contains(e.equipmentId)) ||
        services.any((e) => !ids.contains(e.equipmentId)) ||
        itemRows.any((e) => !ids.contains(e.equipmentId)) ||
        logs.any((e) => !itemIds.contains(e.itemId))) {
      throw const FormatException(
        'Sao lưu có mã trùng hoặc dữ liệu mất liên kết.',
      );
    }
    for (final e in equipmentRows) {
      if (e.name.trim().isEmpty) {
        throw const FormatException('Tên thiết bị trống.');
      }
    }
    for (final i in itemRows) {
      if (i.title.trim().isEmpty ||
          i.cycleMonths < 0 ||
          (i.cost ?? 0) < 0 ||
          (i.kind == ItemKind.lifespan && i.cycleMonths != 0)) {
        throw const FormatException('Hạng mục trong sao lưu không hợp lệ.');
      }
    }
    final linkable = {...itemIds, ...services.map((e) => e.id)};
    await db.transaction(() async {
      await db.customStatement('DELETE FROM attachments');
      await db.customStatement('DELETE FROM service_records');
      await db.customStatement('DELETE FROM history_logs');
      await db.customStatement('DELETE FROM deadline_items');
      await db.customStatement('DELETE FROM equipment');
      await db.customStatement('DELETE FROM catalogs');
      for (final e in equipmentRows) {
        await saveEquipment(e);
      }
      for (final i in itemRows) {
        await saveItem(i);
      }
      for (final l in logs) {
        await db.customStatement('INSERT INTO history_logs VALUES (?,?,?)', [
          l.id,
          l.itemId,
          jsonEncode(l.toJson()),
        ]);
      }
      for (final record in services) {
        await saveServiceRecord(record);
      }
      for (final a in attached) {
        await addAttachment(
          linkable.contains(a.linkId) ? a : a.copy({'linkId': null}),
          files[a.id]!,
        );
      }
      for (final name in backup['groups'] as List) {
        await addCatalog('group', name as String);
      }
      for (final name in backup['providers'] as List) {
        await addCatalog('provider', name as String);
      }
      await saveSettings(config);
    });
  }
}

void validateSettings(AppSettings s) {
  if (s.warnDays < 0 ||
      s.lifespanWarnDays < 0 ||
      s.notifyHour < 0 ||
      s.notifyHour > 23 ||
      s.notifyMinute < 0 ||
      s.notifyMinute > 59 ||
      s.autoBackupDays < 1 ||
      s.autoBackupDays > 365 ||
      !['system', 'light', 'dark'].contains(s.theme)) {
    throw const FormatException('Cài đặt không hợp lệ.');
  }
}
