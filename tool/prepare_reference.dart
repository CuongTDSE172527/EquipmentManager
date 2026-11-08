import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:equipment_manager/services/spreadsheets.dart';
import 'package:equipment_manager/domain/importing.dart';

/// Local, read-only source inspection. Input and outputs are git-ignored.
void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    throw ArgumentError('Truyền đường dẫn source-rows.json cục bộ.');
  }
  final data = jsonDecode(File(args.first).readAsStringSync()) as List;
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
  final output = args.length == 2
      ? args[1]
      : 'private/nguon-chua-xac-nhan.xlsx';
  File(output).writeAsBytesSync(book.encode()!);
  File(
    output.replaceFirst(RegExp(r'\.xlsx$'), '.report.json'),
  ).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(plan.report()),
  );
  stdout.writeln(
    'Đọc ${plan.readRows} dòng; phân tích ${plan.records.length}; ${plan.issues.where((i) => i.error).length} lỗi. Chưa nhập vào database.',
  );
}
