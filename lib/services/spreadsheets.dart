import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';
import '../domain/models.dart';
import '../domain/deadlines.dart';
import '../domain/importing.dart';
import '../domain/planning.dart';
import '../domain/service_history.dart';

const trackingColumns = [
  'STT',
  'Tên phương tiện',
  'Biển số',
  'Hạn đăng kiểm',
  'Hạn bảo hiểm',
  'Bảo dưỡng tiếp theo',
  'Ghi chú',
];
const appendixColumns = [
  'STT',
  'Tên phương tiện',
  'Nước sản xuất',
  'Năm sản xuất',
  'Số khung',
  'Số động cơ',
  'Biển kiểm soát',
  'Mục đích sử dụng',
  'Hoạt động tại',
];

String _cellText(Data? cell) {
  final v = cell?.value;
  if (v is DateCellValue || v is DateTimeCellValue) {
    // Excel stores a complete date even when the user only enters a month.
    // Ignore literals, locale directives and escaped characters in its format.
    final format = (cell?.cellStyle?.numberFormat.formatCode ?? '')
        .replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]|\\.'), '')
        .toLowerCase();
    final precision =
        format.contains('m') && format.contains('y') && !format.contains('d')
        ? DatePrecision.month
        : DatePrecision.day;
    final date = v is DateCellValue
        ? v.asDateTimeLocal()
        : (v as DateTimeCellValue).asDateTimeLocal();
    return displayDate(date, precision);
  }
  return v?.toString() ?? '';
}

ImportPlan readWorkbook(
  Uint8List bytes,
  String filename, {
  required DateTime today,
}) {
  if (bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('File nhập tối đa 20 MB.');
  }
  final plan = ImportPlan();
  if (filename.toLowerCase().endsWith('.csv')) {
    final text = utf8.decode(bytes).replaceFirst('\uFEFF', '');
    final first = text.split(RegExp(r'\r?\n')).first;
    final delimiter = first.split(';').length > first.split(',').length
        ? ';'
        : ',';
    // Giữ dòng trống để số dòng trong thông báo lỗi khớp với file gốc.
    final rows = CsvDecoder(
      fieldDelimiter: delimiter,
      skipEmptyLines: false,
    ).convert(text).map((r) => r.map((c) => c.toString()).toList()).toList();
    final metadata = rows
        .take(10)
        .expand((r) => r)
        .any((c) => normalized(c) == 'sokhung');
    parseEquipmentRows(
      plan,
      filename,
      rows,
      metadataOnly: metadata,
      today: today,
    );
  } else if (filename.toLowerCase().endsWith('.xlsx')) {
    // Limit decompressed input as well as compressed size (zip bomb protection).
    final zip = ZipDecoder().decodeBytes(bytes, verify: true);
    if (zip.files.fold<int>(0, (sum, f) => sum + f.size) > 80 * 1024 * 1024) {
      throw const FormatException('Nội dung Excel quá lớn.');
    }
    final book = Excel.decodeBytes(bytes);
    for (final entry in book.tables.entries) {
      final rows = entry.value.rows
          .map((r) => r.map(_cellText).toList())
          .toList();
      if (rows.every((r) => r.every((c) => c.trim().isEmpty))) continue;
      if (normalized(entry.key) == 'huongdan') continue;
      final metadata = rows
          .take(12)
          .expand((r) => r)
          .any((c) => normalized(c) == 'sokhung');
      parseEquipmentRows(
        plan,
        '$filename / ${entry.key}',
        rows,
        metadataOnly: metadata,
        today: today,
      );
    }
  } else {
    throw const FormatException(
      'Chỉ nhận Excel .xlsx hoặc CSV UTF-8. Hãy chuyển .doc/.docx sang mẫu Excel trước.',
    );
  }
  return plan;
}

class SpreadsheetService {
  Excel _book() => Excel.createExcel();
  void _row(Sheet sheet, List<Object?> values) => sheet.appendRow(
    values
        .map<CellValue?>(
          (v) => v == null
              ? null
              : v is int
              ? IntCellValue(v)
              : TextCellValue(v.toString()),
        )
        .toList(),
  );

  void _style(Sheet sheet, int header, int columns) {
    for (var r = 0; r < sheet.maxRows; r++) {
      for (var c = 0; c < columns; c++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
        );
        cell.cellStyle = CellStyle(
          fontFamily: 'Times New Roman',
          fontSize: r == 0 ? 14 : 12,
          bold: r <= header,
          verticalAlign: VerticalAlign.Center,
          horizontalAlign: c == 0
              ? HorizontalAlign.Center
              : HorizontalAlign.Left,
          textWrapping: TextWrapping.WrapText,
          backgroundColorHex: ExcelColor.fromHexString(
            r == header ? 'FFE2E8F0' : 'FFFFFFFF',
          ),
          leftBorder: Border(
            borderStyle: BorderStyle.Thin,
            borderColorHex: ExcelColor.fromHexString('FFD9D9D9'),
          ),
          rightBorder: Border(
            borderStyle: BorderStyle.Thin,
            borderColorHex: ExcelColor.fromHexString('FFD9D9D9'),
          ),
          topBorder: Border(
            borderStyle: BorderStyle.Thin,
            borderColorHex: ExcelColor.fromHexString('FFD9D9D9'),
          ),
          bottomBorder: Border(
            borderStyle: BorderStyle.Thin,
            borderColorHex: ExcelColor.fromHexString('FFD9D9D9'),
          ),
        );
      }
      final values = sheet.rows[r];
      final mergedTitle =
          r < header || values.skip(1).every((c) => c?.value == null);
      var lines = 1;
      for (var c = 0; c < columns; c++) {
        final text = c < values.length
            ? values[c]?.value?.toString() ?? ''
            : '';
        final width = mergedTitle
            ? columns * 22
            : (c == 0
                  ? 7
                  : c == 1
                  ? 32
                  : 22);
        final needed = text
            .split('\n')
            .fold<int>(
              0,
              (sum, line) =>
                  sum + (line.length / width * 1.15).ceil().clamp(1, 1000),
            );
        if (needed > lines) lines = needed;
      }
      sheet.setRowHeight(r, lines * 16.0 + 10);
    }
    for (var c = 0; c < columns; c++) {
      sheet.setColumnWidth(
        c,
        c == 0
            ? 7
            : c == 1
            ? 32
            : 22,
      );
    }
  }

  void _title(Sheet sheet, AppSettings settings, String title, int columns) {
    _row(sheet, [settings.agency]);
    _row(sheet, [settings.team]);
    _row(sheet, [title]);
    for (var r = 0; r < 3; r++) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
        CellIndex.indexByColumnRow(columnIndex: columns - 1, rowIndex: r),
      );
    }
  }

  Uint8List _finish(Excel book, {int repeatRows = 1}) {
    if (book.tables.length > 1) book.delete('Sheet1');
    final bytes = book.encode()!;
    final input = ZipDecoder().decodeBytes(bytes);
    final output = Archive();
    for (final file in input.files) {
      if (file.name.startsWith('xl/worksheets/sheet') &&
          file.name.endsWith('.xml')) {
        final doc = XmlDocument.parse(utf8.decode(file.content as List<int>));
        final root = doc.rootElement;
        for (final name in [
          'sheetPr',
          'pageMargins',
          'pageSetup',
          'headerFooter',
        ]) {
          root.children.removeWhere(
            (n) => n is XmlElement && n.name.local == name,
          );
        }
        root.children.insert(
          0,
          XmlElement(XmlName('sheetPr'), [], [
            XmlElement(XmlName('pageSetUpPr'), [
              XmlAttribute(XmlName('fitToPage'), '1'),
            ]),
          ]),
        );
        root.children.add(
          XmlElement(XmlName('pageMargins'), [
            for (final e in {
              'left': '0.3',
              'right': '0.3',
              'top': '0.5',
              'bottom': '0.5',
              'header': '0.2',
              'footer': '0.2',
            }.entries)
              XmlAttribute(XmlName(e.key), e.value),
          ]),
        );
        root.children.add(
          XmlElement(XmlName('pageSetup'), [
            XmlAttribute(XmlName('paperSize'), '9'),
            XmlAttribute(XmlName('orientation'), 'landscape'),
            XmlAttribute(XmlName('fitToWidth'), '1'),
            XmlAttribute(XmlName('fitToHeight'), '0'),
          ]),
        );
        root.children.add(
          XmlElement(XmlName('headerFooter'), [], [
            XmlElement(XmlName('oddFooter'), [], [XmlText('&CTrang &P / &N')]),
          ]),
        );
        final content = utf8.encode(doc.toXmlString());
        output.addFile(ArchiveFile(file.name, content.length, content));
      } else if (file.name == 'xl/workbook.xml') {
        final doc = XmlDocument.parse(utf8.decode(file.content as List<int>));
        final root = doc.rootElement;
        var definitions = root.findElements('definedNames').firstOrNull;
        if (definitions == null) {
          definitions = XmlElement(XmlName('definedNames'));
          final calc = root.children.indexWhere(
            (n) => n is XmlElement && n.name.local == 'calcPr',
          );
          if (calc < 0) {
            root.children.add(definitions);
          } else {
            root.children.insert(calc, definitions);
          }
        }
        final sheets = root
            .findElements('sheets')
            .single
            .findElements('sheet')
            .toList();
        for (var index = 0; index < sheets.length; index++) {
          final name = sheets[index]
              .getAttribute('name')!
              .replaceAll("'", "''");
          definitions.children.add(
            XmlElement(
              XmlName('definedName'),
              [
                XmlAttribute(XmlName('name'), '_xlnm.Print_Titles'),
                XmlAttribute(XmlName('localSheetId'), '$index'),
              ],
              [XmlText("'$name'!\$1:\$$repeatRows")],
            ),
          );
        }
        final content = utf8.encode(doc.toXmlString());
        output.addFile(ArchiveFile(file.name, content.length, content));
      } else {
        output.addFile(file);
      }
    }
    return Uint8List.fromList(ZipEncoder().encode(output)!);
  }

  Uint8List template() {
    final book = _book();
    final tracking = book['Theo dõi'];
    _row(tracking, [...trackingColumns, 'Nhóm']);
    _style(tracking, 0, 8);
    final appendix = book['Phụ lục'];
    _row(appendix, appendixColumns);
    _style(appendix, 0, 9);
    final guide = book['Hướng dẫn'];
    for (final text in [
      'Điền bảng Theo dõi, bảng Phụ lục hoặc cả hai. Giữ nguyên tên cột.',
      'Ngày: dd/MM/yyyy hoặc MM/yyyy. Nhập ngày dưới dạng văn bản để giữ chính xác tháng.',
      'Bảo hiểm: ngày hết hạn; ACV mua; Hết; Không áp dụng; hoặc để trống nếu chưa có thông tin.',
      'Hạn đăng kiểm: ngày; Hết ĐK; Không áp dụng; hoặc để trống nếu chưa có thông tin.',
      'Không áp dụng / dấu -: không tạo hạng mục. Ô trống: tạo hạng mục Cần cập nhật.',
      'Tên, biển số, số khung, số động cơ phải là văn bản để không mất số 0 đầu.',
      'Nhóm: điền cột Nhóm hoặc dòng tiêu đề I. Phục vụ bay / II. Khẩn nguy, văn phòng, khu bay.',
      'Mọi ghép thiết bị đều phải chọn và xác nhận trong bản xem trước. STT không phải mã duy nhất.',
      'Không tự chuyển CAH-10101 thành CAH-01-001. Giữ nguyên biển nguồn để đối chiếu.',
    ]) {
      _row(guide, [text]);
    }
    guide.setColumnWidth(0, 110);
    return _finish(book);
  }

  String _due(DeadlineItem? item) {
    if (item == null) return 'Không áp dụng';
    if (item.isDone) return 'Đã xong';
    if (item.requiresConfirmation) {
      final label = item.dueDate != null
          ? displayDate(item.dueDate, item.precision)
          : item.expiredWithoutDate
          ? 'Đã hết'
          : item.insuranceMode.label;
      return '$label (Cần xác nhận)';
    }
    if (item.kind == ItemKind.insurance &&
        item.insuranceMode != InsuranceMode.dated) {
      return item.insuranceMode.label;
    }
    if (item.expiredWithoutDate) return 'Hết ĐK';
    return displayDate(item.dueDate, item.precision);
  }

  DeadlineItem? _first(
    List<DeadlineItem> items,
    String equipmentId,
    ItemKind kind,
  ) {
    final matches = items
        .where(
          (i) => i.equipmentId == equipmentId && i.kind == kind && !i.isDone,
        )
        .toList();
    matches.sort(
      (a, b) => (effectiveDue(a) ?? DateTime(9999)).compareTo(
        effectiveDue(b) ?? DateTime(9999),
      ),
    );
    return matches.firstOrNull;
  }

  Uint8List trackingReport(
    List<Equipment> equipment,
    List<DeadlineItem> items,
    AppSettings settings,
  ) {
    final book = _book();
    final sheet = book['Theo dõi'];
    _title(
      sheet,
      settings,
      'BẢNG THEO DÕI KIỂM ĐỊNH, CÔNG TÁC BẢO DƯỠNG TRANG THIẾT BỊ',
      7,
    );
    _row(sheet, trackingColumns);
    final groups = equipment.map((e) => e.group).toSet().toList()
      ..sort((a, b) {
        int order(String name) {
          final match = RegExp(r'^([IVXLCDM]+)[.\s]').firstMatch(name);
          if (match == null) return 1000000;
          final roman = match[1]!;
          const values = {
            'I': 1,
            'V': 5,
            'X': 10,
            'L': 50,
            'C': 100,
            'D': 500,
            'M': 1000,
          };
          var result = 0;
          for (var n = 0; n < roman.length; n++) {
            final value = values[roman[n]]!;
            result += n + 1 < roman.length && value < values[roman[n + 1]]!
                ? -value
                : value;
          }
          return result;
        }

        final n = order(a).compareTo(order(b));
        return n == 0 ? a.compareTo(b) : n;
      });
    var index = 0;
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      final title = group.replaceFirst(RegExp(r'^[IVXLCDM]+[.\s]+'), '');
      _row(sheet, ['${_roman(g + 1)}. $title']);
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: sheet.maxRows - 1),
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: sheet.maxRows - 1),
      );
      final rows = equipment.where((e) => e.group == group).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      for (final e in rows) {
        final lifespan = _first(items, e.id, ItemKind.lifespan);
        _row(sheet, [
          ++index,
          e.name,
          e.displayPlate,
          _due(_first(items, e.id, ItemKind.inspection)),
          _due(_first(items, e.id, ItemKind.insurance)),
          _due(_first(items, e.id, ItemKind.maintenance)),
          [
            e.note,
            if (e.managementStatus != ManagementStatus.active)
              e.managementStatus.label,
            if (lifespan != null) 'Niên hạn: ${_due(lifespan)}',
          ].where((s) => s.isNotEmpty).join('; '),
        ]);
      }
    }
    _style(sheet, 3, 7);
    sheet.setColumnWidth(6, 44);
    return _finish(book, repeatRows: 4);
  }

  Uint8List appendixReport(List<Equipment> equipment, AppSettings settings) {
    final book = _book();
    final sheet = book['Phụ lục'];
    _title(
      sheet,
      settings,
      'PHƯƠNG TIỆN, THIẾT BỊ CHUYÊN NGÀNH ĐƯỢC CẤP BIỂN KIỂM SOÁT',
      9,
    );
    _row(sheet, appendixColumns);
    var index = 0;
    for (final e in equipment.where((e) => e.controlPlate.isNotEmpty)) {
      _row(sheet, [
        ++index,
        e.name,
        e.country,
        e.yearMade,
        e.chassisNo,
        e.engineNo,
        e.controlPlate,
        e.purpose,
        e.operatingAt,
      ]);
    }
    _style(sheet, 3, 9);
    return _finish(book, repeatRows: 4);
  }

  Uint8List itemsReport(
    List<TrackedDeadline> rows,
    List<HistoryLog> history,
    AppSettings settings, {
    List<ServiceRecord> serviceRecords = const [],
    List<Equipment> equipment = const [],
    List<DeadlineItem>? serviceItems,
    String? serviceProvider,
  }) {
    final book = _book();
    final sheet = book['Hạng mục'];
    _title(sheet, settings, 'DANH SÁCH HẠNG MỤC THEO DÕI', 9);
    _row(sheet, [
      'Thiết bị',
      'Biển số',
      'Loại',
      'Hạng mục',
      'Hạn',
      'Trạng thái',
      'Đơn vị thực hiện',
      'Chu kỳ (tháng)',
      'Ghi chú',
    ]);
    final byProvider = [...rows]
      ..sort((a, b) {
        final p = a.item.provider.compareTo(b.item.provider);
        return p != 0 ? p : a.status.index.compareTo(b.status.index);
      });
    for (final r in byProvider) {
      _row(sheet, [
        r.equipment.name,
        r.equipment.displayPlate,
        r.item.kind.label,
        r.item.title,
        _due(r.item),
        r.status.label,
        r.item.provider,
        r.item.cycleMonths,
        r.item.note,
      ]);
    }
    _style(sheet, 3, 9);
    final logSheet = book['Lịch sử'];
    _title(logSheet, settings, 'LỊCH SỬ THỰC HIỆN', 9);
    _row(logSheet, [
      'Thiết bị',
      'Biển số',
      'Hạng mục',
      'Ngày thực hiện',
      'Chi phí (VND)',
      'Đơn vị thực hiện',
      'Hạn cũ',
      'Hạn tiếp theo',
      'Ghi chú',
    ]);
    final byItem = {for (final r in rows) r.item.id: r};
    for (final log in [
      ...history,
    ]..sort((a, b) => b.doneDate.compareTo(a.doneDate))) {
      final r = byItem[log.itemId];
      if (r == null) continue;
      _row(logSheet, [
        r.equipment.name,
        r.equipment.displayPlate,
        r.item.title,
        displayDate(log.doneDate),
        log.cost,
        log.provider,
        displayDate(log.previousDueDate, r.item.precision),
        displayDate(log.nextDueDate, r.item.precision),
        log.note,
      ]);
    }
    _style(logSheet, 3, 9);
    for (var row = 4; row < logSheet.maxRows; row++) {
      final cell = logSheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
      );
      if (cell.value is IntCellValue) {
        cell.cellStyle = cell.cellStyle!.copyWith(
          numberFormat: NumFormat.custom(formatCode: '#,##0 "VND"'),
        );
      }
    }
    final visits =
        serviceVisits(
              equipment.isEmpty
                  ? {
                      for (final r in rows) r.equipment.id: r.equipment,
                    }.values.toList()
                  : equipment,
              serviceItems ?? rows.map((r) => r.item).toList(),
              history,
              serviceRecords,
            )
            .where(
              (v) => serviceProvider == null || v.provider == serviceProvider,
            )
            .toList();
    final serviceSheet = book['Bảo trì sửa chữa'];
    _title(serviceSheet, settings, 'LỊCH SỬ BẢO TRÌ, SỬA CHỮA', 9);
    _row(serviceSheet, [
      'Thiết bị',
      'Biển số',
      'Loại công việc',
      'Nội dung',
      'Ngày thực hiện',
      'Chi phí (VND)',
      'Đơn vị thực hiện',
      'Chi tiết / Kết quả',
      'Nguồn ghi nhận',
    ]);
    for (final visit in visits) {
      _row(serviceSheet, [
        visit.equipment.name,
        visit.equipment.displayPlate,
        visit.kind.label,
        visit.title,
        displayDate(visit.doneDate),
        visit.cost,
        visit.provider,
        visit.note,
        visit.record == null ? 'Hoàn thành hạng mục' : 'Ghi công việc',
      ]);
    }
    _style(serviceSheet, 3, 9);
    for (var row = 4; row < serviceSheet.maxRows; row++) {
      final cell = serviceSheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
      );
      if (cell.value is IntCellValue) {
        cell.cellStyle = cell.cellStyle!.copyWith(
          numberFormat: NumFormat.custom(formatCode: '#,##0 "VND"'),
        );
      }
    }
    return _finish(book, repeatRows: 4);
  }

  /// Work plan for a calendar period, grouped by provider for meetings and
  /// cost planning. Past cost is shown only as a reference.
  Uint8List planReport(
    List<PlannedDeadline> rows,
    PlanRange range,
    AppSettings settings,
  ) {
    final book = _book();
    final sheet = book['Kế hoạch'];
    _title(
      sheet,
      settings,
      'KẾ HOẠCH CÔNG VIỆC ĐẾN HẠN ${range.title} (${displayDate(range.start)} – ${displayDate(range.end)})',
      9,
    );
    _row(sheet, [
      'STT',
      'Thiết bị',
      'Biển số',
      'Loại',
      'Hạng mục',
      'Hạn',
      'Tình trạng',
      'Chi phí lần trước (VND)',
      'Ghi chú',
    ]);
    final providers = <String>[];
    for (final r in rows) {
      if (!providers.contains(r.row.item.provider)) {
        providers.add(r.row.item.provider);
      }
    }
    var index = 0;
    for (final provider in providers) {
      final group = rows.where((r) => r.row.item.provider == provider).toList();
      _row(sheet, [
        '${provider.isEmpty ? 'Chưa chọn đơn vị thực hiện' : provider} (${group.length} hạng mục)',
      ]);
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: sheet.maxRows - 1),
        CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: sheet.maxRows - 1),
      );
      for (final r in group) {
        _row(sheet, [
          ++index,
          r.row.equipment.name,
          r.row.equipment.displayPlate,
          r.row.item.kind.label,
          r.row.item.title,
          _due(r.row.item),
          [
            r.overdue ? 'Quá hạn, chưa xử lý' : 'Đến hạn trong kỳ',
            if (r.row.item.requiresConfirmation) 'Cần xác nhận',
          ].join(' • '),
          r.row.item.cost,
          r.row.item.note,
        ]);
      }
    }
    if (rows.isEmpty) {
      _row(sheet, ['Không có hạng mục đến hạn trong kỳ.']);
    }
    _style(sheet, 3, 9);
    _money(sheet, 7);
    final summary = book['Tổng hợp'];
    _title(summary, settings, 'TỔNG HỢP THEO ĐƠN VỊ ${range.title}', 5);
    _row(summary, [
      'STT',
      'Đơn vị thực hiện',
      'Quá hạn',
      'Đến hạn trong kỳ',
      'Chi phí lần trước (VND)',
    ]);
    for (var n = 0; n < providers.length; n++) {
      final group = rows.where((r) => r.row.item.provider == providers[n]);
      final costs = group.map((r) => r.row.item.cost).whereType<int>();
      _row(summary, [
        n + 1,
        providers[n].isEmpty ? 'Chưa chọn đơn vị' : providers[n],
        group.where((r) => r.overdue).length,
        group.where((r) => !r.overdue).length,
        costs.isEmpty ? null : costs.reduce((a, b) => a + b),
      ]);
    }
    _style(summary, 3, 5);
    _money(summary, 4);
    return _finish(book, repeatRows: 4);
  }

  void _money(Sheet sheet, int column) {
    for (var row = 4; row < sheet.maxRows; row++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
      );
      if (cell.value is IntCellValue) {
        cell.cellStyle = cell.cellStyle!.copyWith(
          numberFormat: NumFormat.custom(formatCode: '#,##0 "VND"'),
        );
      }
    }
  }
}

String _roman(int number) {
  var result = '';
  var n = number;
  for (final pair in [
    (1000, 'M'),
    (900, 'CM'),
    (500, 'D'),
    (400, 'CD'),
    (100, 'C'),
    (90, 'XC'),
    (50, 'L'),
    (40, 'XL'),
    (10, 'X'),
    (9, 'IX'),
    (5, 'V'),
    (4, 'IV'),
    (1, 'I'),
  ]) {
    while (n >= pair.$1) {
      result += pair.$2;
      n -= pair.$1;
    }
  }
  return result;
}
