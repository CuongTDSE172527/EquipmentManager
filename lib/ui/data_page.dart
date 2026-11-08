import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/deadlines.dart';
import '../domain/importing.dart';
import '../services/spreadsheets.dart';
import 'controller.dart';
import 'forms.dart';

Future<bool> saveBytes(String filename, Uint8List bytes) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Lưu tệp',
    fileName: filename,
    bytes: bytes,
  );
  if (path == null) return false;
  if (!Platform.isAndroid && !Platform.isIOS) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
  return true;
}

class DataPage extends StatefulWidget {
  const DataPage({super.key, required this.controller, required this.onError});
  final AppController controller;
  final ValueChanged<String> onError;
  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  bool busy = false, includeArchived = false;
  String? provider;
  DeadlineStatus? status;
  AppController get c => widget.controller;
  final sheets = SpreadsheetService();
  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      widget.onError('Không thực hiện được: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<Equipment> get equipment => c.equipment
      .where(
        (e) => includeArchived || e.managementStatus == ManagementStatus.active,
      )
      .toList();
  List<TrackedDeadline> get rows => c.tracked
      .where(
        (r) =>
            (includeArchived ||
                r.equipment.managementStatus == ManagementStatus.active) &&
            (provider == null || r.item.provider == provider) &&
            (status == null || r.status == status),
      )
      .toList();
  String get stamp => DateTime.now().toIso8601String().substring(0, 10);
  Widget _action(
    String title,
    String detail,
    IconData icon,
    VoidCallback action,
  ) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(detail),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: busy ? null : action,
    ),
  );
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      if (busy) const LinearProgressIndicator(),
      Text(
        'Nhập và bảo vệ dữ liệu',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      _action(
        'Tải mẫu nhập Excel',
        'Hai bảng Theo dõi và Phụ lục, kèm hướng dẫn điền. Không chứa dữ liệu thật.',
        Icons.download_outlined,
        () => _run(() async {
          await saveBytes('EquipmentManager-mau-nhap.xlsx', sheets.template());
        }),
      ),
      _action(
        'Nhập Excel / CSV',
        'Chọn một hoặc nhiều file. Kiểm tra lỗi, đối chiếu và xác nhận từng dòng trước khi ghi.',
        Icons.upload_file_outlined,
        () => _run(_import),
      ),
      _action(
        'Sao lưu toàn bộ dữ liệu',
        'Lưu thiết bị, hạng mục, lịch sử, danh mục và cài đặt vào một file JSON.',
        Icons.backup_outlined,
        () => _run(() async {
          final backup = await c.repository.snapshot();
          final now = DateTime.now();
          (backup['settings'] as Json)['lastBackup'] = now.toIso8601String();
          if (await saveBytes(
            'EquipmentManager-$stamp.backup.json',
            Uint8List.fromList(
              utf8.encode(const JsonEncoder.withIndent('  ').convert(backup)),
            ),
          )) {
            await c.repository.saveSettings(
              c.settings.copy({'lastBackup': now.toIso8601String()}),
            );
            await c.load();
            widget.onError('Đã lưu bản sao lưu.');
          }
        }),
      ),
      _action(
        'Khôi phục từ bản sao lưu',
        'Kiểm tra toàn bộ file trước khi thay dữ liệu hiện tại. Hãy sao lưu trước khi khôi phục.',
        Icons.restore_outlined,
        () => _run(_restore),
      ),
      const SizedBox(height: 24),
      Text('Xuất báo cáo Excel', style: Theme.of(context).textTheme.titleLarge),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Bao gồm thiết bị đã bàn giao / ngừng sử dụng'),
        value: includeArchived,
        onChanged: busy ? null : (v) => setState(() => includeArchived = v),
      ),
      _action(
        'Bảng theo dõi kiểm định, bảo hiểm, bảo dưỡng',
        '7 cột theo mẫu, phân nhóm số La Mã, khổ A4 ngang để in.',
        Icons.table_chart_outlined,
        () => _run(() async {
          await saveBytes(
            'EquipmentManager-theo-doi-$stamp.xlsx',
            sheets.trackingReport(equipment, c.items, c.settings),
          );
        }),
      ),
      _action(
        'Phụ lục cấp biển kiểm soát',
        'Đúng 9 cột của phụ lục quyết định, lấy tên cơ quan từ Cài đặt.',
        Icons.article_outlined,
        () => _run(() async {
          await saveBytes(
            'EquipmentManager-phu-luc-$stamp.xlsx',
            sheets.appendixReport(equipment, c.settings),
          );
        }),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              initialValue: provider,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Lọc đơn vị cho báo cáo hạng mục',
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Tất cả đơn vị'),
                ),
                for (final p in c.providers)
                  DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: (v) => setState(() => provider = v),
            ),
          ),
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<DeadlineStatus>(
              initialValue: status,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Lọc trạng thái cho báo cáo hạng mục',
              ),
              items: [
                const DropdownMenuItem<DeadlineStatus>(
                  value: null,
                  child: Text('Tất cả trạng thái'),
                ),
                for (final s in DeadlineStatus.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => status = v),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _action(
        'Danh sách hạng mục và lịch sử thực hiện',
        'Xuất theo bộ lọc ở trên, gom hạng mục theo đơn vị thực hiện.',
        Icons.history_outlined,
        () => _run(() async {
          await saveBytes(
            'EquipmentManager-hang-muc-lich-su-$stamp.xlsx',
            sheets.itemsReport(rows, c.history, c.settings),
          );
        }),
      ),
      const SizedBox(height: 20),
      const Text(
        'Dữ liệu trên các máy độc lập. Để chuyển sang máy khác, sao lưu rồi khôi phục trên máy đích. File sao lưu chứa dữ liệu của đơn vị; lưu ở nơi phù hợp.',
      ),
    ],
  );
  Future<void> _restore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null) return;
    final bytes = result.files.single.bytes!;
    if (bytes.length > 50 * 1024 * 1024) {
      throw const FormatException('File sao lưu quá lớn.');
    }
    final backup = jsonDecode(utf8.decode(bytes)) as Json;
    if (!mounted) return;
    if (!await confirmAction(
      context,
      'Khôi phục và thay dữ liệu hiện tại?',
      'File chứa ${(backup['equipment'] as List?)?.length ?? 0} thiết bị và ${(backup['items'] as List?)?.length ?? 0} hạng mục. Dữ liệu hiện tại sẽ được thay bằng bản sao lưu.',
      action: 'Khôi phục',
    )) {
      return;
    }
    await c.repository.restore(backup);
    await c.load();
    widget.onError(
      'Đã khôi phục dữ liệu. Vào Cài đặt để kiểm tra và đăng ký lại lịch nhắc trên máy này.',
    );
  }

  Future<void> _import() async {
    final selected = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    if (selected == null) return;
    final plan = ImportPlan();
    for (final file in selected.files) {
      final part = readWorkbook(file.bytes!, file.name, today: c.clock());
      plan.records.addAll(part.records);
      plan.issues.addAll(part.issues);
      plan.readRows += part.readRows;
    }
    plan.suggestMatches(c.equipment);
    if (!mounted) return;
    final decision = await showDialog<bool>(
      context: context,
      builder: (context) => _ImportPreview(plan: plan, existing: c.equipment),
    );
    if (decision == null) return;
    await c.importPlan(plan, confirmPast: decision);
    widget.onError('Đã nhập ${plan.records.length} dòng đã được xác nhận.');
  }
}

class _ImportPreview extends StatefulWidget {
  const _ImportPreview({required this.plan, required this.existing});
  final ImportPlan plan;
  final List<Equipment> existing;
  @override
  State<_ImportPreview> createState() => _ImportPreviewState();
}

class _ImportPreviewState extends State<_ImportPreview> {
  bool confirmPast = true;
  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    return AlertDialog(
      title: const Text('Đối chiếu trước khi nhập'),
      content: SizedBox(
        width: 900,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Đọc ${p.readRows} dòng • ${p.records.length} dòng phân tích được • ${p.issues.where((i) => i.error).length} lỗi cần sửa',
              ),
              const SizedBox(height: 12),
              const Text(
                'Chọn “Tạo thiết bị mới” hoặc thiết bị cần ghép cho từng dòng. Đề xuất chỉ để đối chiếu; ứng dụng không tự chuyển biển cũ sang biển mới.',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Đánh dấu mốc đã quá hạn là “Cần xác nhận”'),
                subtitle: Text(
                  confirmPast
                      ? 'Giữ nguyên ngày gốc; trạng thái Cần cập nhật cho đến khi kiểm tra.'
                      : 'Nhập nguyên trạng; mốc đã qua được tính quá hạn.',
                ),
                value: confirmPast,
                onChanged: (v) => setState(() => confirmPast = v),
              ),
              for (final issue in p.issues)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${issue.error ? 'LỖI' : 'Lưu ý'} • ${issue.source}, dòng ${issue.row}: ${issue.message}',
                    style: TextStyle(
                      color: issue.error
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ),
              const Divider(),
              TextButton(
                onPressed: () => setState(() {
                  for (final r in p.records.where(
                    (r) => r.suggestedIds.isEmpty,
                  )) {
                    r.targetId = null;
                    r.approved = true;
                  }
                }),
                child: const Text(
                  'Xác nhận tạo mới các dòng không có đề xuất ghép',
                ),
              ),
              for (var n = 0; n < p.records.length; n++)
                _record(context, p.records[n], n),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await saveBytes(
              'EquipmentManager-doi-chieu.json',
              Uint8List.fromList(
                utf8.encode(
                  const JsonEncoder.withIndent('  ').convert(p.report()),
                ),
              ),
            );
          },
          child: const Text('Lưu báo cáo đối chiếu'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: p.ready ? () => Navigator.pop(context, confirmPast) : null,
          child: Text(
            'Nhập ${p.records.where((r) => r.approved).length}/${p.records.length} dòng',
          ),
        ),
      ],
    );
  }

  Widget _record(BuildContext context, ImportRecord r, int n) {
    final choices = <String, Equipment>{
      for (final e in [
        ...widget.existing,
        ...widget.plan.records.take(n).map((r) => r.equipment),
      ])
        e.id: e,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${r.equipment.name} • ${r.equipment.displayPlate}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text('${r.source} — dòng ${r.row}'),
            if (r.suggestedIds.isNotEmpty)
              Text(
                'Đề xuất: ${r.suggestedIds.map((id) => choices[id]).whereType<Equipment>().map((e) => '${e.name} (${e.displayPlate})').join('; ')}',
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('${r.reference}-${r.approved}-${r.targetId}'),
              initialValue: r.approved ? r.targetId ?? '__new' : '__choose',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Xác nhận cách nhập dòng này',
              ),
              items: [
                const DropdownMenuItem(
                  value: '__choose',
                  child: Text('Chưa xác nhận'),
                ),
                const DropdownMenuItem(
                  value: '__new',
                  child: Text('Tạo thiết bị mới'),
                ),
                for (final e in choices.values)
                  DropdownMenuItem(
                    value: e.id,
                    child: Text(
                      'Ghép: ${e.name} • ${e.displayPlate}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                r.approved = v != '__choose';
                r.targetId = v == '__new' || v == '__choose' ? null : v;
              }),
            ),
          ],
        ),
      ),
    );
  }
}
