import 'models.dart';

/// Record kinds that take part in synchronisation, parents before children.
/// Accounts, audit log and device settings stay on each device.
const syncEntities = [
  'catalog',
  'equipment',
  'item',
  'history',
  'service',
  'attachment',
];

/// One versioned record state exchanged with a sync server. A deleted record
/// travels as a tombstone without payload so other devices remove it too.
class SyncChange {
  const SyncChange({
    required this.entity,
    required this.id,
    required this.version,
    required this.updatedAt,
    required this.updatedBy,
    required this.deviceId,
    this.deleted = false,
    this.payload,
  });
  final String entity, id, updatedBy, deviceId;
  final int version;

  /// UTC, ISO-8601, so timestamps from different devices compare as text.
  final String updatedAt;
  final bool deleted;
  final Json? payload;

  /// Last writer wins: newer timestamp first, device id breaks exact ties so
  /// every device reaches the same result without talking to the others.
  bool winsOver(SyncChange other) {
    final time = updatedAt.compareTo(other.updatedAt);
    if (time != 0) return time > 0;
    return deviceId.compareTo(other.deviceId) > 0;
  }

  Json toJson() => {
    'entity': entity,
    'id': id,
    'version': version,
    'updatedAt': updatedAt,
    'updatedBy': updatedBy,
    'deviceId': deviceId,
    'deleted': deleted,
    if (payload != null) 'payload': payload,
  };
  factory SyncChange.fromJson(Json j) {
    final change = SyncChange(
      entity: j['entity'] as String,
      id: j['id'] as String,
      version: j['version'] as int,
      updatedAt: j['updatedAt'] as String,
      updatedBy: j['updatedBy'] as String? ?? '',
      deviceId: j['deviceId'] as String,
      deleted: j['deleted'] as bool? ?? false,
      payload: j['payload'] == null
          ? null
          : Map<String, dynamic>.from(j['payload'] as Map),
    );
    if (!syncEntities.contains(change.entity) ||
        change.id.isEmpty ||
        change.version < 1 ||
        (!change.deleted && change.payload == null)) {
      throw const FormatException('Thay đổi đồng bộ không hợp lệ.');
    }
    return change;
  }
}

class SyncApplyResult {
  int applied = 0, skipped = 0;

  /// Local edits that lost to a newer remote edit, and records that could not
  /// be written (for example a child whose parent never arrived).
  final conflicts = <String>[];
}
