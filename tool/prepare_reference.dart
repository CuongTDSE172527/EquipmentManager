import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:equipment_manager/services/spreadsheets.dart';
import 'package:equipment_manager/domain/importing.dart';

/// Local, read-only source inspection. Input and outputs are git-ignored.
void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError('Truyền đường dẫn source-rows.json cục bộ.');
  }
  final data = jsonDecode(File(args.single).readAsStringSync()) as List;
  final book = Excel.createExcel();
  final plan = ImportPlan();
  for (final source in data) {
    final name = source['source'] as String;
    final metadata = name == 'Phụ lục';
    final rows = (source['rows'] as List)
        .map((r) => (r as List).cast<String>())
        .toList();
    final allRows = [metadata ? appendixColumns : trackingColumns, ...rows];
    final sheet = book[name];
    for (final row in allRows) {
      sheet.appendRow(row.map((v) => TextCellValue(v)).toList());
    }
    parseEquipmentRows(
      plan,
      name,
      allRows,
      metadataOnly: metadata,
      today: DateTime.now(),
    );
  }
  book.delete('Sheet1');
  File('private/nguon-chua-xac-nhan.xlsx').writeAsBytesSync(book.encode()!);
  File('private/kiem-tra-nguon.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(plan.report()),
  );
  stdout.writeln(
    'Đọc ${plan.readRows} dòng; phân tích ${plan.records.length}; ${plan.issues.where((i) => i.error).length} lỗi. Chưa nhập vào database.',
  );
}
