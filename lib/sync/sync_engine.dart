import '../data/database.dart';
import '../domain/sync_model.dart';

/// What a sync server returns for a pull: changes made by other devices since
/// [cursor] was issued, and the cursor to send next time.
class SyncPull {
  const SyncPull(this.changes, this.cursor, {this.hasMore = false});
  final List<SyncChange> changes;
  final String cursor;
  final bool hasMore;
}

/// The only seam between the app and a server. A cloud service, an on-premise
/// server or a shared folder each implement these two calls; see
/// docs/SYNC.md for the HTTP contract this mirrors.
abstract class SyncTransport {
  /// Sends local changes. Returns the ones the server stored; anything not
  /// returned stays queued and is sent again next time.
  Future<List<SyncChange>> push(String deviceId, List<SyncChange> changes);

  /// Receives changes from other devices after [cursor] (null: from start).
  Future<SyncPull> pull(String deviceId, String? cursor);
}

class SyncNotConfigured implements Exception {
  const SyncNotConfigured();
  @override
  String toString() =>
      'Chưa cấu hình máy chủ đồng bộ. Dữ liệu chỉ nằm trên máy này.';
}

/// Default in 0.4.0: nothing leaves the device.
class NotConfiguredTransport implements SyncTransport {
  const NotConfiguredTransport();
  @override
  Future<List<SyncChange>> push(String deviceId, List<SyncChange> changes) =>
      throw const SyncNotConfigured();
  @override
  Future<SyncPull> pull(String deviceId, String? cursor) =>
      throw const SyncNotConfigured();
}

class SyncReport {
  int pushed = 0, pulled = 0, applied = 0, skipped = 0;
  final conflicts = <String>[];
}

/// Push-then-pull cycle. Safe to repeat: pushes are idempotent per record
/// version and the pull cursor is saved only after changes are applied.
class SyncEngine {
  SyncEngine(this.repository, this.transport, {this.batchSize = 200});
  final EquipmentRepository repository;
  final SyncTransport transport;
  final int batchSize;
  static const cursorKey = 'sync_cursor';

  Future<SyncReport> run() async {
    final report = SyncReport();
    final device = await repository.deviceId();
    while (true) {
      final pending = await repository.pendingChanges(limit: batchSize);
      if (pending.isEmpty) break;
      final accepted = await transport.push(device, pending);
      await repository.markPushed(accepted);
      report.pushed += accepted.length;
      // Stop instead of looping forever when the server rejects a batch.
      if (accepted.length < pending.length) break;
    }
    var cursor = await repository.metaValue(cursorKey);
    while (true) {
      final pull = await transport.pull(device, cursor);
      final remote = pull.changes.where((c) => c.deviceId != device).toList();
      final result = await repository.applyRemote(remote);
      report
        ..pulled += pull.changes.length
        ..applied += result.applied
        ..skipped += result.skipped
        ..conflicts.addAll(result.conflicts);
      cursor = pull.cursor;
      await repository.setMetaValue(cursorKey, cursor);
      if (!pull.hasMore) break;
    }
    return report;
  }
}
