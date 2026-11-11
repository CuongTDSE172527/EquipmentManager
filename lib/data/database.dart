import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import '../domain/accounts.dart';
import '../domain/models.dart';
import '../domain/sync_model.dart';

/// SQL is explicit so the desktop reminder and migrations use the same schema.
/// Payloads are versioned domain records; indexed columns enforce relationships.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);
  factory AppDatabase.open(File file) => AppDatabase(NativeDatabase(file));
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());
  @override
  int get schemaVersion => 4;
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
      await _createSecurityAndSync();
    },
    onUpgrade: (_, from, to) async {
      if (from < 2) await _createServiceRecords();
      if (from < 3) await _createAttachments();
      if (from < 4) {
        await _createSecurityAndSync();
        // Records that existed before 0.4.0 are new to any future server.
        await seedSyncState(this, DateTime.now().toUtc().toIso8601String());
      }
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

  Future<void> _createSecurityAndSync() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, payload TEXT NOT NULL)',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS audit_log (id TEXT PRIMARY KEY, at TEXT NOT NULL, user_id TEXT NOT NULL, action TEXT NOT NULL, payload TEXT NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS audit_at ON audit_log(at)',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS sync_state (entity TEXT NOT NULL, id TEXT NOT NULL, version INTEGER NOT NULL, updated_at TEXT NOT NULL, updated_by TEXT NOT NULL, device_id TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(entity, id))',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS sync_dirty ON sync_state(dirty)',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS local_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }
}

/// Current backup format. 1 and 2 are JSON only; 3 adds attachment metadata,
/// with the bytes stored beside the JSON in a ZIP archive. Accounts, the audit
/// log and sync state are per device and never part of a backup.
const backupVersion = 3;

/// Marks every stored record as changed by this device, e.g. after migration
/// or a restore, so a future first sync uploads it.
Future<void> seedSyncState(GeneratedDatabase db, String now) async {
  final device = await _deviceId(db);
  for (final (entity, table, id) in [
    ('equipment', 'equipment', 'id'),
    ('item', 'deadline_items', 'id'),
    ('history', 'history_logs', 'id'),
    ('service', 'service_records', 'id'),
    ('attachment', 'attachments', 'id'),
    ('catalog', 'catalogs', "kind || ':' || name"),
  ]) {
    await db.customStatement(
      "INSERT OR IGNORE INTO sync_state SELECT '$entity', $id, 1, ?, '', ?, 0, 1 FROM $table",
      [now, device],
    );
  }
}

Future<String> _deviceId(GeneratedDatabase db) async {
  final rows = await db
      .customSelect("SELECT value FROM local_meta WHERE key = 'device_id'")
      .get();
  if (rows.isNotEmpty) return rows.single.read<String>('value');
  final id = newId();
  await db.customStatement("INSERT INTO local_meta VALUES ('device_id', ?)", [
    id,
  ]);
  return id;
}

/// Who is performing changes; recorded in the audit log and sync metadata.
class Actor {
  const Actor(this.id, this.name);
  final String id, name;
}

const _tables = {
  'equipment': 'equipment',
  'item': 'deadline_items',
  'history': 'history_logs',
  'service': 'service_records',
  'attachment': 'attachments',
};

class EquipmentRepository {
  EquipmentRepository(this.db, {this.clock = DateTime.now});
  final AppDatabase db;
  final DateTime Function() clock;

  /// Set by the session on login/logout. Null for background reminders.
  Actor? actor;
  int _bulk = 0;
  bool _remote = false;
  String? _device;

  Future<String> deviceId() async => _device ??= await _deviceId(db);

  Future<List<Json>> _rows(String table) async =>
      (await db.customSelect('SELECT payload FROM $table').get())
          .map((r) => jsonDecode(r.read<String>('payload')) as Json)
          .toList();
  Future<bool> _exists(String table, String id) async =>
      (await db
              .customSelect(
                'SELECT 1 FROM $table WHERE id = ?',
                variables: [Variable(id)],
              )
              .get())
          .isNotEmpty;
  Future<List<String>> _ids(String sql, String id) async =>
      (await db.customSelect(sql, variables: [Variable(id)]).get())
          .map((r) => r.read<String>('id'))
          .toList();

  // ---- change tracking ---------------------------------------------------

  /// Bumps the record's version and queues it for the next sync push.
  Future<void> _track(String entity, String id, {bool deleted = false}) async {
    if (_remote) return;
    await db.customStatement(
      'INSERT INTO sync_state VALUES (?, ?, 1, ?, ?, ?, ?, 1) ON CONFLICT(entity, id) DO UPDATE SET version=version+1, updated_at=excluded.updated_at, updated_by=excluded.updated_by, device_id=excluded.device_id, deleted=excluded.deleted, dirty=1',
      [
        entity,
        id,
        clock().toUtc().toIso8601String(),
        actor?.id ?? '',
        await deviceId(),
        deleted ? 1 : 0,
      ],
    );
  }

  Future<void> _audit(
    String action,
    String entity,
    String entityId,
    String summary,
  ) async {
    if (_bulk > 0 || _remote) return;
    await logAudit(
      action,
      entity: entity,
      entityId: entityId,
      summary: summary,
    );
  }

  Future<void> logAudit(
    String action, {
    String entity = '',
    String entityId = '',
    String summary = '',
    Actor? as,
  }) async {
    final who = as ?? actor;
    final entry = AuditEntry(
      at: clock(),
      action: action,
      userId: who?.id ?? '',
      userName: who?.name ?? '',
      entity: entity,
      entityId: entityId,
      summary: summary,
    );
    await db.customStatement('INSERT INTO audit_log VALUES (?, ?, ?, ?, ?)', [
      entry.id,
      entry.at.toIso8601String(),
      entry.userId,
      entry.action,
      jsonEncode(entry.toJson()),
    ]);
  }

  /// Runs many writes as one transaction with a single audit line, e.g. an
  /// Excel import. Records are still tracked one by one for sync.
  Future<T> bulk<T>(
    String action,
    String entity,
    String summary,
    Future<T> Function() body,
  ) => db.transaction(() async {
    _bulk++;
    try {
      final result = await body();
      _bulk--;
      await _audit(action, entity, '', summary);
      return result;
    } catch (_) {
      _bulk--;
      rethrow;
    }
  });

  Future<List<AuditEntry>> auditEntries({int limit = 500}) async =>
      (await db
              .customSelect(
                'SELECT payload FROM audit_log ORDER BY at DESC, rowid DESC LIMIT ?',
                variables: [Variable(limit)],
              )
              .get())
          .map(
            (r) => AuditEntry.fromJson(
              jsonDecode(r.read<String>('payload')) as Json,
            ),
          )
          .toList();

  /// Keeps the log bounded on small devices.
  Future<void> pruneAudit({int keep = 50000}) => db.customStatement(
    'DELETE FROM audit_log WHERE id NOT IN (SELECT id FROM audit_log ORDER BY at DESC, rowid DESC LIMIT ?)',
    [keep],
  );

  // ---- accounts ----------------------------------------------------------

  Future<List<UserAccount>> accounts() async =>
      (await _rows('accounts')).map(UserAccount.fromJson).toList()
        ..sort((a, b) => a.username.compareTo(b.username));

  Future<UserAccount?> accountByUsername(String username) async {
    final rows = await db
        .customSelect(
          'SELECT payload FROM accounts WHERE username = ?',
          variables: [Variable(username)],
        )
        .get();
    return rows.isEmpty
        ? null
        : UserAccount.fromJson(
            jsonDecode(rows.single.read<String>('payload')) as Json,
          );
  }

  Future<void> saveAccount(UserAccount a) => db.customStatement(
    'INSERT INTO accounts VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET username=excluded.username,payload=excluded.payload',
    [a.id, a.username, jsonEncode(a.toJson())],
  );

  // ---- data --------------------------------------------------------------

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
      final existed = await _exists('service_records', record.id);
      await db.customStatement(
        'INSERT INTO service_records VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET equipment_id=excluded.equipment_id,payload=excluded.payload',
        [record.id, record.equipmentId, jsonEncode(record.toJson())],
      );
      if (record.provider.isNotEmpty) {
        await addCatalog('provider', record.provider);
      }
      await _track('service', record.id);
      await _audit(
        existed ? 'update' : 'create',
        'service',
        record.id,
        '${record.title} (${record.doneDate.toIso8601String().substring(0, 10)})',
      );
    });
  }

  Future<void> deleteServiceRecord(String id) => db.transaction(() async {
    await _unlinkAttachments(id);
    await db.customStatement('DELETE FROM service_records WHERE id=?', [id]);
    await _track('service', id, deleted: true);
    await _audit('delete', 'service', id, '');
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
    await db.transaction(() async {
      await db.customStatement(
        'INSERT INTO attachments VALUES (?, ?, ?, ?, ?)',
        [a.id, a.equipmentId, a.linkId, jsonEncode(a.toJson()), data],
      );
      await _track('attachment', a.id);
      await _audit('create', 'attachment', a.id, a.title);
    });
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
    await db.transaction(() async {
      await db.customStatement(
        'UPDATE attachments SET link_id=?, payload=? WHERE id=?',
        [a.linkId, jsonEncode(a.toJson()), a.id],
      );
      await _track('attachment', a.id);
      await _audit('update', 'attachment', a.id, a.title);
    });
  }

  Future<void> deleteAttachment(String id) => db.transaction(() async {
    await db.customStatement('DELETE FROM attachments WHERE id=?', [id]);
    await _track('attachment', id, deleted: true);
    await _audit('delete', 'attachment', id, '');
  });

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
      await _track('attachment', a.id);
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
    final exists = await db
        .customSelect(
          'SELECT 1 FROM catalogs WHERE kind = ? AND name = ?',
          variables: [Variable(kind), Variable(name.trim())],
        )
        .get();
    if (exists.isNotEmpty) return;
    await db.customStatement('INSERT INTO catalogs VALUES (?, ?)', [
      kind,
      name.trim(),
    ]);
    await _track('catalog', '$kind:${name.trim()}');
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
      await _track('catalog', '$kind:$oldName', deleted: true);
      await _audit(
        'update',
        'catalog',
        '$kind:$oldName',
        '$oldName → ${newName.trim()}',
      );
    });
  }

  Future<void> saveEquipment(Equipment e) async {
    if (e.name.trim().isEmpty) {
      throw ArgumentError('Tên thiết bị không được trống.');
    }
    if (e.yearMade != null && (e.yearMade! < 1900 || e.yearMade! > 9999)) {
      throw ArgumentError('Năm sản xuất không hợp lệ.');
    }
    await db.transaction(() async {
      final existed = await _exists('equipment', e.id);
      await db.customStatement(
        'INSERT INTO equipment VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,management_status=excluded.management_status,payload=excluded.payload',
        [e.id, e.name, e.managementStatus.name, jsonEncode(e.toJson())],
      );
      await addCatalog('group', e.group);
      await _track('equipment', e.id);
      await _audit(existed ? 'update' : 'create', 'equipment', e.id, e.name);
    });
  }

  Future<void> saveItem(DeadlineItem item, {String action = ''}) async {
    if (item.title.trim().isEmpty ||
        item.cycleMonths < 0 ||
        (item.cost ?? 0) < 0) {
      throw ArgumentError('Hạng mục không hợp lệ.');
    }
    if (item.kind == ItemKind.lifespan && item.cycleMonths != 0) {
      throw ArgumentError('Niên hạn không có chu kỳ.');
    }
    await db.transaction(() async {
      final existed = await _exists('deadline_items', item.id);
      await db.customStatement(
        'INSERT INTO deadline_items VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET equipment_id=excluded.equipment_id,payload=excluded.payload',
        [item.id, item.equipmentId, jsonEncode(item.toJson())],
      );
      if (item.provider.isNotEmpty) {
        await addCatalog('provider', item.provider);
      }
      await _track('item', item.id);
      await _audit(
        action.isNotEmpty
            ? action
            : existed
            ? 'update'
            : 'create',
        'item',
        item.id,
        '${item.kind.label}: ${item.title}',
      );
    });
  }

  /// Children are removed by the database's cascade; tombstones are written
  /// for each of them so other devices delete the same records.
  Future<void> deleteEquipment(String id) => db.transaction(() async {
    final items = await _ids(
      'SELECT id FROM deadline_items WHERE equipment_id = ?',
      id,
    );
    for (final item in items) {
      for (final log in await _ids(
        'SELECT id FROM history_logs WHERE item_id = ?',
        item,
      )) {
        await _track('history', log, deleted: true);
      }
      await _track('item', item, deleted: true);
    }
    for (final service in await _ids(
      'SELECT id FROM service_records WHERE equipment_id = ?',
      id,
    )) {
      await _track('service', service, deleted: true);
    }
    for (final file in await _ids(
      'SELECT id FROM attachments WHERE equipment_id = ?',
      id,
    )) {
      await _track('attachment', file, deleted: true);
    }
    final name = (await equipment()).where((e) => e.id == id).firstOrNull;
    await db.customStatement('DELETE FROM equipment WHERE id=?', [id]);
    await _track('equipment', id, deleted: true);
    await _audit('delete', 'equipment', id, name?.name ?? '');
  });

  Future<void> deleteItem(String id) => db.transaction(() async {
    await _unlinkAttachments(id);
    for (final log in await _ids(
      'SELECT id FROM history_logs WHERE item_id = ?',
      id,
    )) {
      await _track('history', log, deleted: true);
    }
    final item = (await items()).where((i) => i.id == id).firstOrNull;
    await db.customStatement('DELETE FROM deadline_items WHERE id=?', [id]);
    await _track('item', id, deleted: true);
    await _audit('delete', 'item', id, item?.title ?? '');
  });

  /// Settings are per device and are not synchronised.
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
      await saveItem(item, action: 'complete');
      await db.customStatement('INSERT INTO history_logs VALUES (?, ?, ?)', [
        log.id,
        log.itemId,
        jsonEncode(log.toJson()),
      ]);
      await _track('history', log.id);
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
  /// Accounts and the audit log stay as they are on this device.
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
    await bulk(
      'restore',
      'data',
      '${equipmentRows.length} thiết bị, ${itemRows.length} hạng mục, ${attached.length} tệp',
      () async {
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
        // A restore starts a new history for sync: every record is re-sent.
        await db.customStatement('DELETE FROM sync_state');
        await seedSyncState(db, clock().toUtc().toIso8601String());
      },
    );
  }

  // ---- sync --------------------------------------------------------------

  Future<int> pendingSyncCount() async =>
      (await db
              .customSelect(
                'SELECT COUNT(*) AS n FROM sync_state WHERE dirty = 1',
              )
              .get())
          .single
          .read<int>('n');

  Future<String?> metaValue(String key) async {
    final rows = await db
        .customSelect(
          'SELECT value FROM local_meta WHERE key = ?',
          variables: [Variable(key)],
        )
        .get();
    return rows.isEmpty ? null : rows.single.read<String>('value');
  }

  Future<void> setMetaValue(String key, String value) => db.customStatement(
    'INSERT INTO local_meta VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );

  Future<({SyncChange state, bool dirty})?> _localState(
    String entity,
    String id,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM sync_state WHERE entity = ? AND id = ?',
          variables: [Variable(entity), Variable(id)],
        )
        .get();
    if (rows.isEmpty) return null;
    final r = rows.single;
    return (
      state: SyncChange(
        entity: entity,
        id: id,
        version: r.read<int>('version'),
        updatedAt: r.read<String>('updated_at'),
        updatedBy: r.read<String>('updated_by'),
        deviceId: r.read<String>('device_id'),
        deleted: r.read<int>('deleted') == 1,
      ),
      dirty: r.read<int>('dirty') == 1,
    );
  }

  Future<Json?> _payload(String entity, String id) async {
    if (entity == 'catalog') {
      final i = id.indexOf(':');
      final rows = await db
          .customSelect(
            'SELECT 1 FROM catalogs WHERE kind = ? AND name = ?',
            variables: [
              Variable(id.substring(0, i)),
              Variable(id.substring(i + 1)),
            ],
          )
          .get();
      return rows.isEmpty
          ? null
          : {'kind': id.substring(0, i), 'name': id.substring(i + 1)};
    }
    final rows = await db
        .customSelect(
          'SELECT payload FROM ${_tables[entity]} WHERE id = ?',
          variables: [Variable(id)],
        )
        .get();
    if (rows.isEmpty) return null;
    final json = jsonDecode(rows.single.read<String>('payload')) as Json;
    // Template only: a real server should receive attachment bytes through a
    // separate, resumable upload instead of inline base64.
    if (entity == 'attachment') {
      json['data'] = base64Encode(await attachmentData(id));
    }
    return json;
  }

  /// Local changes not yet acknowledged by a server, parents first.
  Future<List<SyncChange>> pendingChanges({int limit = 500}) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM sync_state WHERE dirty = 1 LIMIT ?',
          variables: [Variable(limit)],
        )
        .get();
    final changes = <SyncChange>[];
    for (final r in rows) {
      final entity = r.read<String>('entity'), id = r.read<String>('id');
      var deleted = r.read<int>('deleted') == 1;
      final payload = deleted ? null : await _payload(entity, id);
      deleted = deleted || payload == null;
      changes.add(
        SyncChange(
          entity: entity,
          id: id,
          version: r.read<int>('version'),
          updatedAt: r.read<String>('updated_at'),
          updatedBy: r.read<String>('updated_by'),
          deviceId: r.read<String>('device_id'),
          deleted: deleted,
          payload: payload,
        ),
      );
    }
    changes.sort(
      (a, b) => syncEntities.indexOf(a.entity) - syncEntities.indexOf(b.entity),
    );
    return changes;
  }

  /// Clears the dirty flag only if the record was not edited again meanwhile.
  Future<void> markPushed(List<SyncChange> changes) => db.transaction(() async {
    for (final c in changes) {
      await db.customStatement(
        'UPDATE sync_state SET dirty = 0 WHERE entity = ? AND id = ? AND version = ?',
        [c.entity, c.id, c.version],
      );
    }
  });

  /// Applies changes from other devices with last-writer-wins. Upserts go
  /// parents first and deletions children first so foreign keys hold.
  Future<SyncApplyResult> applyRemote(List<SyncChange> changes) async {
    final result = SyncApplyResult();
    final ordered = [
      ...changes.where((c) => !c.deleted).toList()..sort(
        (a, b) =>
            syncEntities.indexOf(a.entity) - syncEntities.indexOf(b.entity),
      ),
      ...changes.where((c) => c.deleted).toList()..sort(
        (a, b) =>
            syncEntities.indexOf(b.entity) - syncEntities.indexOf(a.entity),
      ),
    ];
    for (final change in ordered) {
      final local = await _localState(change.entity, change.id);
      if (local != null && !change.winsOver(local.state)) {
        result.skipped++;
        continue;
      }
      try {
        await db.transaction(() async {
          _remote = true;
          try {
            await _writeRemote(change);
          } finally {
            _remote = false;
          }
          await db.customStatement(
            'INSERT INTO sync_state VALUES (?, ?, ?, ?, ?, ?, ?, 0) ON CONFLICT(entity, id) DO UPDATE SET version=excluded.version, updated_at=excluded.updated_at, updated_by=excluded.updated_by, device_id=excluded.device_id, deleted=excluded.deleted, dirty=0',
            [
              change.entity,
              change.id,
              change.version,
              change.updatedAt,
              change.updatedBy,
              change.deviceId,
              change.deleted ? 1 : 0,
            ],
          );
        });
        // An unsent local edit lost to a newer one from another device.
        if (local != null && local.dirty) {
          result.conflicts.add(
            '${change.entity} ${change.id}: bản từ máy khác mới hơn, thay bản chưa gửi trên máy này.',
          );
        }
        result.applied++;
      } catch (e) {
        result.conflicts.add('${change.entity} ${change.id}: $e');
      }
    }
    if (result.applied > 0) {
      await logAudit(
        'sync',
        entity: 'data',
        summary: 'Nhận ${result.applied} thay đổi, bỏ qua ${result.skipped}',
      );
    }
    return result;
  }

  Future<void> _writeRemote(SyncChange c) async {
    if (c.entity == 'catalog') {
      final i = c.id.indexOf(':');
      final kind = c.id.substring(0, i), name = c.id.substring(i + 1);
      if (c.deleted) {
        await db.customStatement(
          'DELETE FROM catalogs WHERE kind=? AND name=?',
          [kind, name],
        );
      } else {
        await addCatalog(kind, name);
      }
      return;
    }
    if (c.deleted) {
      await db.customStatement('DELETE FROM ${_tables[c.entity]} WHERE id=?', [
        c.id,
      ]);
      return;
    }
    final p = c.payload!;
    switch (c.entity) {
      case 'equipment':
        await saveEquipment(Equipment.fromJson(p));
      case 'item':
        await saveItem(DeadlineItem.fromJson(p));
      case 'service':
        await saveServiceRecord(ServiceRecord.fromJson(p));
      case 'history':
        final log = HistoryLog.fromJson(p);
        await db.customStatement(
          'INSERT INTO history_logs VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET item_id=excluded.item_id,payload=excluded.payload',
          [log.id, log.itemId, jsonEncode(log.toJson())],
        );
      case 'attachment':
        final data = base64Decode(p.remove('data') as String);
        final a = Attachment.fromJson(p);
        await db.customStatement('DELETE FROM attachments WHERE id=?', [a.id]);
        await addAttachment(a, Uint8List.fromList(data));
    }
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
