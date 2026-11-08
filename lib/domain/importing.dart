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
  int readRows = 0;
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
