import 'dart:io';
import 'package:equipment_manager/services/spreadsheets.dart';

void main() {
  final target = File('assets/templates/EquipmentManager-mau-nhap.xlsx');
  target.parent.createSync(recursive: true);
  target.writeAsBytesSync(SpreadsheetService().template());
  stdout.writeln(target.path);
}
