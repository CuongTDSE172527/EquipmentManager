import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/database.dart';

Future<AppDatabase> openAppDatabase() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return AppDatabase.open(File(p.join(directory.path, 'equipment_manager.db')));
}
