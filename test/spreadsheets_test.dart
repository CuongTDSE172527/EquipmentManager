import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/services/spreadsheets.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/deadlines.dart';

void main() {
  final service = SpreadsheetService();
  final e = Equipment(
    name: 'Thiết bị giả lập',
    controlPlate: 'CAH-01-999',
    roadPlate: '69A-00000',
    country: 'Việt Nam',
    yearMade: 2026,
  );
  final i = DeadlineItem(
    equipmentId: e.id,
    kind: ItemKind.maintenance,
    title: 'Bảo dưỡng',
    dueDate: DateTime(2026, 5, 31),
    precision: DatePrecision.month,
    provider: 'Đơn vị thử',
  );
  test('Mẫu nhập có đúng các cột và không nhúng dữ liệu thiết bị', () {
    final bytes = service.template();
    final book = Excel.decodeBytes(bytes);
    expect(book.tables.keys, containsAll(['Theo dõi', 'Phụ lục', 'Hướng dẫn']));
    expect(
      book['Theo dõi'].rows.first.take(7).map((c) => c?.value.toString()),
      trackingColumns,
    );
    expect(
      book['Phụ lục'].rows.first.map((c) => c?.value.toString()),
      appendixColumns,
    );
    expect(
      readWorkbook(bytes, 'template.xlsx', today: DateTime(2026)).records,
      isEmpty,
    );
  });
  test(
    'Báo cáo theo dõi ưu tiên biển giao thông, giữ MM/yyyy và cấu hình in',
    () {
      final bytes = service.trackingReport(
        [e],
        [i],
        const AppSettings(agency: 'CƠ QUAN THỬ'),
      );
      final sheet = Excel.decodeBytes(bytes)['Theo dõi'];
      expect(sheet.rows[0][0]!.value.toString(), 'CƠ QUAN THỬ');
      final row = sheet.rows.last;
      expect(row[2]!.value.toString(), '69A-00000');
      expect(row[5]!.value.toString(), '05/2026');
      final zip = ZipDecoder().decodeBytes(bytes);
      final xml = utf8.decode(
        zip.files
                .firstWhere(
                  (f) =>
                      f.name.startsWith('xl/worksheets/') &&
                      f.name.endsWith('.xml'),
                )
                .content
            as List<int>,
      );
      expect(xml, contains('orientation="landscape"'));
      expect(xml, contains('fitToWidth="1"'));
      expect(xml, contains('fitToHeight="0"'));
    },
  );
  test('Phụ lục đúng 9 cột; báo cáo hạng mục có sheet lịch sử', () {
    final sheet = Excel.decodeBytes(
      service.appendixReport([e], const AppSettings()),
    )['Phụ lục'];
    expect(sheet.rows[3].length, 9);
    expect(sheet.rows.last[6]!.value.toString(), 'CAH-01-999');
    final book = Excel.decodeBytes(
      service.itemsReport(
        trackedDeadlines([e], [i], const AppSettings(), DateTime(2026)),
        [],
        const AppSettings(),
      ),
    );
    expect(book.tables.keys, containsAll(['Hạng mục', 'Lịch sử']));
  });
}
