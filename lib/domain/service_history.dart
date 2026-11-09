import 'models.dart';

class ServiceVisit {
  const ServiceVisit({
    required this.equipment,
    required this.kind,
    required this.title,
    required this.doneDate,
    required this.provider,
    required this.note,
    this.cost,
    this.record,
  });
  final Equipment equipment;
  final ItemKind kind;
  final String title, provider, note;
  final DateTime doneDate;
  final int? cost;

  /// Only manually entered visits are editable here. Completion logs are kept.
  final ServiceRecord? record;
}

List<ServiceVisit> serviceVisits(
  List<Equipment> equipment,
  List<DeadlineItem> items,
  List<HistoryLog> history,
  List<ServiceRecord> records,
) {
  final byEquipment = {for (final e in equipment) e.id: e};
  final byItem = {for (final i in items) i.id: i};
  final visits = <ServiceVisit>[];
  for (final record in records) {
    final e = byEquipment[record.equipmentId];
    if (e == null) continue;
    visits.add(
      ServiceVisit(
        equipment: e,
        kind: record.kind,
        title: record.title,
        doneDate: record.doneDate,
        cost: record.cost,
        provider: record.provider,
        note: record.note,
        record: record,
      ),
    );
  }
  for (final log in history) {
    final item = byItem[log.itemId];
    final e = byEquipment[item?.equipmentId];
    if (item == null ||
        e == null ||
        ![ItemKind.maintenance, ItemKind.repair].contains(item.kind)) {
      continue;
    }
    visits.add(
      ServiceVisit(
        equipment: e,
        kind: item.kind,
        title: item.title,
        doneDate: log.doneDate,
        cost: log.cost,
        provider: log.provider,
        note: log.note,
      ),
    );
  }
  visits.sort((a, b) {
    final date = b.doneDate.compareTo(a.doneDate);
    return date == 0 ? a.title.compareTo(b.title) : date;
  });
  return visits;
}
