import 'models.dart';
import 'deadlines.dart';

String normalized(String text) {
  var s = text.toLowerCase().trim();
  const variants = [
    'àáạảãâầấậẩẫăằắặẳẵ',
    'èéẹẻẽêềếệểễ',
    'ìíịỉĩ',
    'òóọỏõôồốộổỗơờớợởỡ',
    'ùúụủũưừứựửữ',
    'ỳýỵỷỹ',
    'đ',
  ];
  const ascii = ['a', 'e', 'i', 'o', 'u', 'y', 'd'];
  for (var i = 0; i < variants.length; i++) {
    for (final char in variants[i].split('')) {
      s = s.replaceAll(char, ascii[i]);
    }
  }
  return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Keep punctuation in plates: CAH-10101 is NOT silently converted to CAH-01-001.
String plateKey(String text) =>
    text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

class ImportIssue {
  const ImportIssue(this.source, this.row, this.message, {this.error = false});
  final String source, message;
  final int row;
  final bool error;
  Json toJson() => {
    'source': source,
    'row': row,
    'message': message,
    'error': error,
  };
}

class ImportRecord {
  ImportRecord({
    required this.source,
    required this.row,
    required this.equipment,
    required this.items,
    required this.metadataOnly,
    required this.suppliedFields,
    this.suggestedIds = const [],
    this.targetId,
    this.approved = false,
  });
  final String source;
  final int row;
  final Equipment equipment;
  final List<DeadlineItem> items;
  final bool metadataOnly;
  final Set<String> suppliedFields;
  List<String> suggestedIds;
  String? targetId;
  bool approved;
  String get reference => '$source:$row';
}

class ImportPlan {
  final records = <ImportRecord>[];
  final issues = <ImportIssue>[];
  final pendingItems = <PendingItem>[];
  int readRows = 0;

  void add(ImportPlan other) {
    records.addAll(other.records);
    issues.addAll(other.issues);
    pendingItems.addAll(other.pendingItems);
    readRows += other.readRows;
  }

  /// Attaches item-sheet rows to equipment rows of this import (by plate,
  /// else by name). Rows for equipment not in the import become item-only
  /// records, which are matched to existing equipment like any other row.
  void linkItems() {
    final extra = <String, ImportRecord>{};
    for (final p in pendingItems) {
      final plate = plateKey(p.plate);
      final name = normalized(p.name);
      Set<String> platesOf(ImportRecord r) => [
        r.equipment.controlPlate,
        r.equipment.oldControlPlate,
        r.equipment.roadPlate,
      ].where((x) => x.isNotEmpty).map(plateKey).toSet();
      var candidates = plate.isEmpty
          ? <ImportRecord>[]
          : records.where((r) => platesOf(r).contains(plate)).toList();
      if (candidates.isEmpty && name.isNotEmpty) {
        candidates = records
            .where(
              (r) =>
                  normalized(r.equipment.name) == name &&
                  (plate.isEmpty || platesOf(r).isEmpty),
            )
            .toList();
      }
      final preferred = candidates.where((r) => !r.metadataOnly).toList();
      final target = preferred.length == 1
          ? preferred.single
          : preferred.isEmpty && candidates.length == 1
          ? candidates.single
          : null;
      if (candidates.isNotEmpty && target == null) {
        issues.add(
          ImportIssue(
            p.source,
            p.row,
            'Khớp ${candidates.length} thiết bị trong file (${candidates.map((r) => r.reference).join(', ')}); hãy ghi biển số để phân biệt.',
            error: true,
          ),
        );
        continue;
      }
      final record =
          target ??
          extra.putIfAbsent(plate.isNotEmpty ? 'p:$plate' : 'n:$name', () {
            final created = ImportRecord(
              source: p.source,
              row: p.row,
              equipment: Equipment(
                name: p.name.isEmpty ? p.plate.trim() : p.name,
                group: 'Chưa phân nhóm',
              ).copy(plateFields(p.plate)),
              items: [],
              metadataOnly: false,
              // Matched to existing equipment, it changes only the items.
              suppliedFields: const {},
            );
            records.add(created);
            return created;
          });
      final item = p.item.copy({'equipmentId': record.equipment.id});
      if (record.items.any(
        (i) => i.kind == item.kind && i.title == item.title,
      )) {
        issues.add(
          ImportIssue(
            p.source,
            p.row,
            '${item.title}: thiết bị đã có hạng mục cùng loại và tên trong lần nhập này; dòng sau ghi đè dòng trước.',
          ),
        );
      }
      record.items.add(item);
    }
    pendingItems.clear();
  }

  bool get hasErrors => issues.any((i) => i.error);
  bool get ready =>
      !hasErrors && records.isNotEmpty && records.every((r) => r.approved);
  Json report() => {
    'readRows': readRows,
    'validRows': records.length,
    'issues': issues.map((e) => e.toJson()).toList(),
    'matches': records
        .map(
          (r) => {
            'source': r.source,
            'row': r.row,
            'name': r.equipment.name,
            'plate': r.equipment.displayPlate,
            'suggestions': r.suggestedIds,
            'selectedId': r.targetId,
            'approved': r.approved,
          },
        )
        .toList(),
  };

  void suggestMatches(List<Equipment> existing) {
    final seen = <Equipment>[...existing];
    for (final r in records) {
      final plates = [
        r.equipment.controlPlate,
        r.equipment.oldControlPlate,
        r.equipment.roadPlate,
      ].where((p) => p.isNotEmpty).map(plateKey).toSet();
      final exact = seen
          .where(
            (e) => [
              e.controlPlate,
              e.oldControlPlate,
              e.roadPlate,
            ].any((p) => p.isNotEmpty && plates.contains(plateKey(p))),
          )
          .toList();
      final names = seen
          .where((e) => normalized(e.name) == normalized(r.equipment.name))
          .toList();
      r.suggestedIds = {
        ...exact.map((e) => e.id),
        ...names.map((e) => e.id),
      }.toList();
      // Every link, including an exact plate, requires explicit approval.
      if (r.suggestedIds.isNotEmpty) {
        issues.add(
          ImportIssue(
            r.source,
            r.row,
            'Có ${r.suggestedIds.length} thiết bị có thể khớp; cần chọn và xác nhận.',
          ),
        );
      }
      seen.add(r.equipment);
    }
  }
}

String _value(Map<String, String> row, List<String> names) {
  for (final name in names) {
    final v = row[normalized(name)];
    if (v != null) return v.trim();
  }
  return '';
}

/// Parse a source sheet, preserving group headings and original row numbers.
void parseEquipmentRows(
  ImportPlan plan,
  String source,
  List<List<String>> rows, {
  required bool metadataOnly,
  required DateTime today,
}) {
  var header = -1;
  for (var n = 0; n < rows.length; n++) {
    if (rows[n].any(
      (c) => [
        'tenphuongtien',
        'tenphuongtienthietbi',
        'tenthietbi',
        'ten',
      ].contains(normalized(c)),
    )) {
      header = n;
      break;
    }
  }
  if (header < 0) {
    plan.issues.add(
      ImportIssue(
        source,
        1,
        'Không tìm thấy cột Tên phương tiện.',
        error: true,
      ),
    );
    return;
  }
  final keys = rows[header].map(normalized).toList();
  final requiredHeaders = metadataOnly
      ? [
          'stt',
          'nuocsanxuat',
          'namsanxuat',
          'sokhung',
          'sodongco',
          'bienkiemsoat',
          'mucdichsudung',
          'hoatdongtai',
        ]
      : [
          'stt',
          'bienso',
          'handangkiem',
          'hanbaohiem',
          'baoduongtieptheo',
          'ghichu',
        ];
  final missing = requiredHeaders.where((k) => !keys.contains(k)).toList();
  if (missing.isNotEmpty) {
    plan.issues.add(
      ImportIssue(
        source,
        header + 1,
        'Thiếu cột bắt buộc: ${missing.join(', ')}.',
        error: true,
      ),
    );
    return;
  }
  final numbering = <String, int>{};
  var group = metadataOnly ? 'Chưa phân nhóm' : 'I. Phục vụ bay';
  for (var n = header + 1; n < rows.length; n++) {
    if (rows[n].every((c) => c.trim().isEmpty)) continue;
    final first = rows[n].where((c) => c.trim().isNotEmpty).first.trim();
    if (RegExp(r'^[IVXLCDM]+$').hasMatch(first)) {
      final title = rows[n]
          .skip(1)
          .where((c) => c.trim().isNotEmpty)
          .firstOrNull;
      group = title == null ? first : '$first. ${title.trim()}';
      numbering.clear();
      continue;
    }
    if (RegExp(r'^[IVXLCDM]+[.\s]').hasMatch(first) &&
        int.tryParse(first) == null) {
      group = first;
      numbering.clear();
      continue;
    }
    final row = <String, String>{
      for (var c = 0; c < keys.length && c < rows[n].length; c++)
        keys[c]: rows[n][c],
    };
    final stt = _value(row, ['STT']);
    final name = _value(row, [
      'Tên phương tiện',
      'Tên phương tiện thiết bị',
      'Tên thiết bị',
      'Tên',
    ]);
    plan.readRows++;
    if (stt.isNotEmpty) {
      if (numbering.containsKey(stt)) {
        plan.issues.add(
          ImportIssue(
            source,
            n + 1,
            'Trùng STT $stt với dòng ${numbering[stt]}. Không dùng STT làm mã thiết bị.',
          ),
        );
      }
      numbering[stt] = n + 1;
    }
    if (name.isEmpty) {
      plan.issues.add(
        ImportIssue(source, n + 1, 'Thiếu tên phương tiện.', error: true),
      );
      continue;
    }
    final rawPlate = _value(
      row,
      metadataOnly ? ['Biển kiểm soát'] : ['Biển số'],
    );
    final plate =
        ['khongcapbs', 'khongcapbienso'].contains(normalized(rawPlate))
        ? ''
        : rawPlate;
    final note = [
      _value(row, ['Ghi chú']),
      if (rawPlate.isNotEmpty && plate.isEmpty) 'Biển số nguồn: $rawPlate',
    ].where((s) => s.isNotEmpty).join('; ');
    final explicitGroup = _value(row, ['Nhóm']);
    final yearText = _value(row, ['Năm sản xuất']);
    final year = int.tryParse(yearText);
    if (yearText.isNotEmpty && (year == null || year < 1900 || year > 9999)) {
      plan.issues.add(
        ImportIssue(
          source,
          n + 1,
          'Năm sản xuất không hợp lệ: $yearText.',
          error: true,
        ),
      );
      continue;
    }
    var management = ManagementStatus.active;
    if (metadataOnly) {
      for (final field in [
        'Nước sản xuất',
        'Năm sản xuất',
        'Số khung',
        'Số động cơ',
        'Mục đích sử dụng',
        'Hoạt động tại',
      ]) {
        if (_value(row, [field]).isEmpty) {
          plan.issues.add(
            ImportIssue(
              source,
              n + 1,
              '$field: ô nguồn trống; cần kiểm tra có áp dụng hay không.',
            ),
          );
        }
      }
    }
    final noteKey = normalized(note);
    if (noteKey.contains('bangiao')) management = ManagementStatus.handedOver;
    if (noteKey.contains('tangcuong')) management = ManagementStatus.deployed;
    if (noteKey.contains('ngungsudung')) management = ManagementStatus.retired;
    final canonical = RegExp(
      r'^CAH-\d{2}-\d{3}$',
    ).hasMatch(plate.toUpperCase());
    final internal = plate.toUpperCase().startsWith('CAH');
    final equipment = Equipment(
      name: name,
      group: explicitGroup.isEmpty ? group : explicitGroup,
      controlPlate: (metadataOnly || canonical) ? plate.toUpperCase() : '',
      oldControlPlate: !metadataOnly && internal && !canonical
          ? plate.toUpperCase()
          : '',
      roadPlate: !metadataOnly && !internal ? plate.toUpperCase() : '',
      country: _value(row, ['Nước sản xuất']),
      yearMade: year,
      chassisNo: _value(row, ['Số khung']),
      engineNo: _value(row, ['Số động cơ']),
      purpose: _value(row, ['Mục đích sử dụng']),
      operatingAt: _value(row, ['Hoạt động tại']).isEmpty
          ? 'Cảng HK Cà Mau'
          : _value(row, ['Hoạt động tại']),
      selfPropelled:
          !normalized(name).contains('khongtuhanh') &&
          !normalized(name).contains('mooc') &&
          normalized(name) != 'dolly',
      managementStatus: management,
      note: note,
    );
    final items = <DeadlineItem>[];
    if (!metadataOnly) {
      String provider = '';
      for (final p in [
        'SAGS',
        'Hyundai',
        'Cần Thơ FORD',
        'Toyota',
        'Isuzu',
        'Đức Tùng',
      ]) {
        if (noteKey.contains(normalized(p))) provider = p;
      }
      if (noteKey.contains('tuthuchien')) provider = 'CAH tự thực hiện';
      for (final entry in {
        'Hạn đăng kiểm': ItemKind.inspection,
        'Hạn bảo hiểm': ItemKind.insurance,
        'Bảo dưỡng tiếp theo': ItemKind.maintenance,
      }.entries) {
        final raw = _value(row, [entry.key]);
        try {
          final parsed = parseImportedDeadline(
            raw,
            equipment.id,
            entry.value,
            provider: entry.value == ItemKind.maintenance ? provider : '',
          );
          if (parsed != null) {
            items.add(parsed);
            if (parsed.dueDate == null &&
                !parsed.expiredWithoutDate &&
                parsed.insuranceMode != InsuranceMode.centralized &&
                parsed.insuranceMode != InsuranceMode.notApplicable) {
              plan.issues.add(
                ImportIssue(
                  source,
                  n + 1,
                  '${entry.key}: chưa có thông tin; không coi là còn hạn.',
                ),
              );
            }
            if (hasPastDeadline(parsed, today)) {
              plan.issues.add(
                ImportIssue(
                  source,
                  n + 1,
                  '${entry.key}: đã quá hạn tại ${displayDate(today)}.',
                ),
              );
            }
          }
        } on FormatException catch (e) {
          plan.issues.add(
            ImportIssue(
              source,
              n + 1,
              '${entry.key}: ${e.message}',
              error: true,
            ),
          );
        }
      }
      final lifespan = RegExp(
        r'(\d{1,2}/\d{4})\s*hết niên hạn',
        caseSensitive: false,
      ).firstMatch(note);
      if (lifespan != null) {
        try {
          final d = parseVietnameseDate(lifespan[1]!);
          items.add(
            DeadlineItem(
              equipmentId: equipment.id,
              kind: ItemKind.lifespan,
              title: 'Niên hạn sử dụng',
              dueDate: d.date,
              precision: d.precision,
              note: note,
            ),
          );
        } on FormatException catch (e) {
          plan.issues.add(
            ImportIssue(source, n + 1, 'Niên hạn: ${e.message}', error: true),
          );
        }
      }
    }
    if (plate.isEmpty) {
      plan.issues.add(
        ImportIssue(source, n + 1, 'Thiếu biển số/biển kiểm soát.'),
      );
    }
    final supplied = <String>{'name'};
    for (final entry in {
      'country': 'Nước sản xuất',
      'yearMade': 'Năm sản xuất',
      'chassisNo': 'Số khung',
      'engineNo': 'Số động cơ',
      'purpose': 'Mục đích sử dụng',
      'operatingAt': 'Hoạt động tại',
    }.entries) {
      if (_value(row, [entry.value]).isNotEmpty) supplied.add(entry.key);
    }
    if (plate.isNotEmpty) {
      supplied.add(
        metadataOnly || canonical
            ? 'controlPlate'
            : internal
            ? 'oldControlPlate'
            : 'roadPlate',
      );
    }
    if (explicitGroup.isNotEmpty || !metadataOnly) supplied.add('group');
    if (note.isNotEmpty) supplied.add('note');
    if (management != ManagementStatus.active) supplied.add('managementStatus');
    plan.records.add(
      ImportRecord(
        source: source,
        row: n + 1,
        equipment: equipment,
        items: items,
        metadataOnly: metadataOnly,
        suppliedFields: supplied,
      ),
    );
  }
}

DeadlineItem? parseImportedDeadline(
  String raw,
  String equipmentId,
  ItemKind kind, {
  String provider = '',
}) {
  final key = normalized(raw);
  if (['khongapdung', 'na', 'khong', '-'].contains(key) || raw.trim() == '-') {
    return kind == ItemKind.insurance
        ? DeadlineItem(
            equipmentId: equipmentId,
            kind: kind,
            title: kind.label,
            insuranceMode: InsuranceMode.notApplicable,
          )
        : null;
  }
  if (kind == ItemKind.insurance &&
      ['acvmua', 'acvmuataptrung'].contains(key)) {
    return DeadlineItem(
      equipmentId: equipmentId,
      kind: kind,
      title: kind.label,
      insuranceMode: InsuranceMode.centralized,
    );
  }
  if (['het', 'hetdk', 'dahet'].contains(key)) {
    return DeadlineItem(
      equipmentId: equipmentId,
      kind: kind,
      title: kind.label,
      expiredWithoutDate: true,
      insuranceMode: kind == ItemKind.insurance
          ? InsuranceMode.expired
          : InsuranceMode.unknown,
      provider: provider,
    );
  }
  if (key.isEmpty || ['chuacothongtin', 'chuaco'].contains(key)) {
    return DeadlineItem(
      equipmentId: equipmentId,
      kind: kind,
      title: kind.label,
      provider: provider,
    );
  }
  final date = parseVietnameseDate(raw);
  return DeadlineItem(
    equipmentId: equipmentId,
    kind: kind,
    title: kind.label,
    dueDate: date.date,
    precision: date.precision,
    provider: provider,
    insuranceMode: kind == ItemKind.insurance
        ? InsuranceMode.dated
        : InsuranceMode.unknown,
  );
}

/// Columns of the "Hạng mục theo dõi" sheet: one deadline item per row, so
/// one equipment can have any number of items with its own names.
const itemSheetName = 'Hạng mục theo dõi';
const itemColumns = [
  'Tên phương tiện',
  'Biển số',
  'Loại hạng mục',
  'Tên hạng mục',
  'Hạn',
  'Chu kỳ (tháng)',
  'Đơn vị thực hiện',
  'Ghi chú',
];

/// An item row waiting to be attached to an equipment row of the same import
/// (by plate, else by name) or to an item-only record.
class PendingItem {
  const PendingItem(this.source, this.row, this.name, this.plate, this.item);
  final String source, name, plate;
  final int row;
  final DeadlineItem item;
}

/// Index of the header row of an item sheet (also the app's own "Hạng mục"
/// report), or -1. Equipment sheets have "Hạn đăng kiểm", never plain "Hạn".
int itemHeaderRow(List<List<String>> rows) {
  for (var n = 0; n < rows.length && n < 12; n++) {
    final keys = rows[n].map(normalized).toSet();
    if (keys.contains('han') &&
        (keys.contains('tenhangmuc') || keys.contains('hangmuc'))) {
      return n;
    }
  }
  return -1;
}

ItemKind? itemKindFrom(String text) {
  final key = normalized(text);
  if (key.isEmpty) return null;
  for (final kind in ItemKind.values) {
    if (normalized(kind.label) == key || kind.name.toLowerCase() == key) {
      return kind;
    }
  }
  if (key.contains('baohiem')) return ItemKind.insurance;
  if (key.contains('dangkiem') || key.contains('kiemdinh')) {
    return ItemKind.inspection;
  }
  if (key.contains('baoduong')) return ItemKind.maintenance;
  if (key.contains('suachua')) return ItemKind.repair;
  if (key.contains('nienhan')) return ItemKind.lifespan;
  if (key == 'khac') return ItemKind.other;
  return null;
}

/// Same plate rules as the equipment sheets: CAH-xx-xxx is the control
/// plate, other CAH plates are old control plates, the rest road plates.
Json plateFields(String raw) {
  final plate = ['khongcapbs', 'khongcapbienso'].contains(normalized(raw))
      ? ''
      : raw.trim().toUpperCase();
  final canonical = RegExp(r'^CAH-\d{2}-\d{3}$').hasMatch(plate);
  final internal = plate.startsWith('CAH');
  return {
    'controlPlate': canonical ? plate : '',
    'oldControlPlate': internal && !canonical ? plate : '',
    'roadPlate': internal ? '' : plate,
  };
}

void parseItemRows(
  ImportPlan plan,
  String source,
  List<List<String>> rows, {
  required int header,
  required DateTime today,
}) {
  final keys = rows[header].map(normalized).toList();
  final hasEquipment = keys.any(
    (k) => [
      'tenphuongtien',
      'tenthietbi',
      'thietbi',
      'ten',
      'bienso',
      'bienkiemsoat',
    ].contains(k),
  );
  if (!hasEquipment) {
    plan.issues.add(
      ImportIssue(
        source,
        header + 1,
        'Thiếu cột Tên phương tiện hoặc Biển số.',
        error: true,
      ),
    );
    return;
  }
  for (var n = header + 1; n < rows.length; n++) {
    if (rows[n].every((c) => c.trim().isEmpty)) continue;
    final row = <String, String>{
      for (var c = 0; c < keys.length && c < rows[n].length; c++)
        keys[c]: rows[n][c],
    };
    final name = _value(row, [
      'Tên phương tiện',
      'Tên thiết bị',
      'Thiết bị',
      'Tên',
    ]);
    final plate = _value(row, ['Biển số', 'Biển kiểm soát']);
    final kindText = _value(row, ['Loại hạng mục', 'Loại']);
    var title = _value(row, ['Tên hạng mục', 'Hạng mục']);
    var raw = _value(row, ['Hạn']);
    final cycleText = _value(row, ['Chu kỳ (tháng)', 'Chu kỳ']);
    final provider = _value(row, ['Đơn vị thực hiện']);
    final note = _value(row, ['Ghi chú']);
    plan.readRows++;
    void issue(String message, {bool error = false}) =>
        plan.issues.add(ImportIssue(source, n + 1, message, error: error));
    if (name.isEmpty && plate.isEmpty) {
      issue('Thiếu tên phương tiện hoặc biển số.', error: true);
      continue;
    }
    if (title.isEmpty && kindText.isEmpty) {
      issue('Thiếu tên hạng mục.', error: true);
      continue;
    }
    var kind = itemKindFrom(kindText);
    if (kind == null && kindText.isNotEmpty) {
      issue('Loại “$kindText” không rõ; xếp vào loại Khác.');
    }
    kind ??= itemKindFrom(title) ?? ItemKind.other;
    if (title.isEmpty) title = kind.label;
    var cycle = 0;
    if (cycleText.isNotEmpty) {
      final value = int.tryParse(cycleText.replaceAll(RegExp(r'\s'), ''));
      if (value == null || value < 0 || value > 1200) {
        issue('Chu kỳ không hợp lệ: $cycleText.', error: true);
        continue;
      }
      cycle = value;
    }
    if (kind == ItemKind.lifespan && cycle != 0) {
      issue('$title: niên hạn không có chu kỳ; bỏ chu kỳ $cycle tháng.');
      cycle = 0;
    }
    var confirm = false;
    if (normalized(raw).endsWith('canxacnhan')) {
      confirm = true;
      raw = raw.replaceFirst(RegExp(r'\(\s*Cần xác nhận\s*\)\s*$'), '').trim();
    }
    if (normalized(raw) == 'daxong') {
      issue('$title: đã xong; không tạo hạng mục.');
      continue;
    }
    try {
      final parsed = parseImportedDeadline(raw, '', kind, provider: provider);
      if (parsed == null) {
        issue('$title: không áp dụng; không tạo hạng mục.');
        continue;
      }
      final item = parsed.copy({
        'title': title,
        'cycleMonths': cycle,
        'note': note,
        'provider': provider,
        'requiresConfirmation': confirm,
      });
      if (item.dueDate == null &&
          !item.expiredWithoutDate &&
          item.insuranceMode != InsuranceMode.centralized &&
          item.insuranceMode != InsuranceMode.notApplicable) {
        issue('$title: chưa có thông tin hạn; không coi là còn hạn.');
      }
      if (hasPastDeadline(item, today)) {
        issue('$title: đã quá hạn tại ${displayDate(today)}.');
      }
      plan.pendingItems.add(PendingItem(source, n + 1, name, plate, item));
    } on FormatException catch (e) {
      issue('$title: ${e.message}', error: true);
    }
  }
}
