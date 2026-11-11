import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:equipment_manager/domain/deadlines.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/planning.dart';
import 'package:equipment_manager/services/spreadsheets.dart';

/// Kiểm tra styles.xml như Excel: số lượng khai báo khớp số phần tử, mọi chỉ
/// số font/nền/viền/định dạng số đều trỏ tới mục có thật, màu là ARGB 8 ký tự.
/// Lỗi ở đây khiến Excel báo "We found a problem with some content" và tự sửa.
void expectValidStyles(Uint8List bytes, String label) {
  final archive = ZipDecoder().decodeBytes(bytes);
  XmlDocument part(String name) => XmlDocument.parse(
    utf8.decode(archive.findFile(name)!.content as List<int>),
  );
  final styles = part('xl/styles.xml');
  int counted(String name, String child) {
    final list = styles.findAllElements(name).single;
    final actual = list.childElements.where((e) => e.name.local == child);
    expect(
      int.parse(list.getAttribute('count')!),
      actual.length,
      reason: '$label: <$name count> khác số <$child>',
    );
    return actual.length;
  }

  final fonts = counted('fonts', 'font');
  final fills = counted('fills', 'fill');
  final borders = counted('borders', 'border');
  final xfs = counted('cellXfs', 'xf');
  final formats = <int>{};
  if (styles.findAllElements('numFmts').isNotEmpty) {
    counted('numFmts', 'numFmt');
    for (final f in styles.findAllElements('numFmt')) {
      expect(
        formats.add(int.parse(f.getAttribute('numFmtId')!)),
        isTrue,
        reason: '$label: trùng numFmtId',
      );
    }
  }
  for (final xf in styles.findAllElements('xf')) {
    int id(String a) => int.parse(xf.getAttribute(a) ?? '0');
    expect(id('fontId'), lessThan(fonts), reason: '$label: fontId');
    expect(id('fillId'), lessThan(fills), reason: '$label: fillId');
    expect(id('borderId'), lessThan(borders), reason: '$label: borderId');
    final format = id('numFmtId');
    expect(
      format < 164 || formats.contains(format),
      isTrue,
      reason: '$label: numFmtId $format chưa khai báo',
    );
  }
  for (final rgb in styles.descendantElements.map(
    (e) => e.getAttribute('rgb'),
  )) {
    if (rgb == null) continue;
    expect(
      RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(rgb),
      isTrue,
      reason: '$label: màu "$rgb" không phải ARGB 8 ký tự',
    );
  }
  for (final file in archive.files) {
    if (!file.name.startsWith('xl/worksheets/sheet')) continue;
    for (final c in part(file.name).findAllElements('c')) {
      final s = int.parse(c.getAttribute('s') ?? '0');
      expect(s, lessThan(xfs), reason: '$label: ô ${c.getAttribute('r')}');
    }
  }
}

void main() {
  test('Mọi file Excel xuất ra có styles.xml hợp lệ, Excel không phải sửa', () {
    final today = DateTime(2026, 11, 9);
    const settings = AppSettings();
    final e = Equipment(name: 'Xe thử', controlPlate: 'CAH-01-001');
    final items = [
      for (final (title, provider, due) in [
        ('Bảo dưỡng 1', 'SAGS', DateTime(2026, 12, 5)),
        ('Bảo dưỡng 2', 'Toyota', DateTime(2026, 10, 1)),
        ('Sửa chữa', '', DateTime(2026, 12, 20)),
      ])
        DeadlineItem(
          equipmentId: e.id,
          kind: ItemKind.maintenance,
          title: title,
          dueDate: due,
          provider: provider,
          cost: 1500000,
        ),
    ];
    final rows = trackedDeadlines([e], items, settings, today);
    final plan = plannedDeadlines(rows, PlanPeriod.nextMonth, today);
    expect(plan, isNotEmpty);
    final service = SpreadsheetService();
    final books = {
      'Mẫu nhập': service.template(),
      'Theo dõi': service.trackingReport([e], items, settings),
      'Phụ lục': service.appendixReport([e], settings),
      'Hạng mục': service.itemsReport(rows, [], settings),
      'Kế hoạch': service.planReport(
        plan,
        planRange(PlanPeriod.nextMonth, today),
        settings,
      ),
    };
    for (final MapEntry(:key, :value) in books.entries) {
      expectValidStyles(value, key);
    }
  });
}
