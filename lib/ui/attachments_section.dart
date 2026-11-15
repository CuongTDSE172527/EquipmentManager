import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../domain/deadlines.dart';
import '../domain/models.dart';
import '../services/attachment_files.dart';
import 'controller.dart';
import 'data_page.dart' show readPicked, saveBytes;
import 'forms.dart';

String formatBytes(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} KB'
    : '${(bytes / 1048576).toStringAsFixed(1).replaceAll('.', ',')} MB';

IconData attachmentIcon(Attachment a) => a.isImage
    ? Icons.image_outlined
    : a.extension == 'pdf'
    ? Icons.picture_as_pdf_outlined
    : ['xls', 'xlsx', 'csv', 'ods'].contains(a.extension)
    ? Icons.table_chart_outlined
    : ['zip', 'rar', '7z'].contains(a.extension)
    ? Icons.folder_zip_outlined
    : a.mimeType.startsWith('video/')
    ? Icons.movie_outlined
    : Icons.description_outlined;

/// Choices for linking a record file to one of the equipment's own records.
Map<String, String> attachmentLinks(AppController c, String equipmentId) => {
  for (final i in c.items.where((i) => i.equipmentId == equipmentId))
    i.id: '${i.kind.label}: ${i.title}',
  for (final r in c.serviceRecords.where((r) => r.equipmentId == equipmentId))
    r.id: 'Sổ bảo trì ${displayDate(r.doneDate)}: ${r.title}',
};

/// Most files picked from one folder in a single step.
const maxFolderFiles = 1000;

/// A folder of the equipment's records, built from the files' folder paths.
class RecordFolder {
  RecordFolder(this.path, this.name);
  final String path, name;
  final folders = <String, RecordFolder>{};
  final files = <Attachment>[];
  int get total =>
      files.length + folders.values.fold(0, (sum, f) => sum + f.total);
  int get bytes =>
      files.fold(0, (sum, f) => sum + f.size) +
      folders.values.fold(0, (sum, f) => sum + f.bytes);

  static RecordFolder of(Iterable<Attachment> files) {
    final root = RecordFolder('', '');
    for (final a in files) {
      var node = root;
      if (a.folder.isNotEmpty) {
        for (final part in a.folder.split('/')) {
          final path = node.path.isEmpty ? part : '${node.path}/$part';
          node = node.folders.putIfAbsent(part, () => RecordFolder(path, part));
        }
      }
      node.files.add(a);
    }
    return root;
  }
}

String _join(String parent, String child) =>
    normalizeFolder(parent.isEmpty ? child : '$parent/$child');

/// "Hồ sơ thiết bị": documents of one piece of equipment, in folders.
class AttachmentsSection extends StatelessWidget {
  const AttachmentsSection({
    super.key,
    required this.controller,
    required this.equipment,
    required this.run,
    this.opener = const AttachmentOpener(),
    this.canEdit = true,
  });
  final AppController controller;

  /// Read-only roles may open and save copies but not add, edit or delete.
  final bool canEdit;
  final Equipment equipment;
  final Future<void> Function(Future<void> Function()) run;
  final AttachmentOpener opener;
  AppController get c => controller;

  @override
  Widget build(BuildContext context) {
    final files = c.attachments
        .where((a) => a.equipmentId == equipment.id)
        .toList();
    final root = RecordFolder.of(files);
    final links = attachmentLinks(c, equipment.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          children: [
            Text(
              'Hồ sơ thiết bị (${files.length})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (canEdit)
              Wrap(
                children: [
                  TextButton.icon(
                    onPressed: () => run(() => _addFiles(context, '')),
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Thêm tệp'),
                  ),
                  TextButton.icon(
                    onPressed: () => run(() => _addFolder(context, '')),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Thêm thư mục'),
                  ),
                ],
              ),
          ],
        ),
        if (files.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Chưa có hồ sơ. Có thể thêm ảnh/PDF giấy đăng kiểm, hợp đồng, biên bản, bản vẽ… hoặc cả một thư mục (tối đa $maxAttachmentLabel mỗi tệp).',
            ),
          ),
        ..._children(context, root, links),
      ],
    );
  }

  List<Widget> _children(
    BuildContext context,
    RecordFolder folder,
    Map<String, String> links,
  ) {
    final folders = folder.folders.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final files = [...folder.files]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return [
      for (final f in folders) _folderTile(context, f, links),
      for (final a in files) _fileTile(context, a, links),
    ];
  }

  Widget _folderTile(
    BuildContext context,
    RecordFolder f,
    Map<String, String> links,
  ) => ExpansionTile(
    key: PageStorageKey('records-${equipment.id}-${f.path}'),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(left: 20),
    leading: const Icon(Icons.folder_outlined),
    title: Text(f.name),
    subtitle: Text('${f.total} tệp • ${formatBytes(f.bytes)}'),
    trailing: canEdit
        ? PopupMenuButton<String>(
            tooltip: 'Thao tác thư mục',
            onSelected: (v) =>
                unawaited(run(() => _folderAction(context, f, v))),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'files', child: Text('Thêm tệp vào đây')),
              PopupMenuItem(value: 'folder', child: Text('Thêm thư mục con')),
              PopupMenuItem(value: 'rename', child: Text('Đổi tên / chuyển')),
              PopupMenuItem(value: 'delete', child: Text('Xóa thư mục')),
            ],
          )
        : null,
    children: _children(context, f, links),
  );

  Widget _fileTile(
    BuildContext context,
    Attachment a,
    Map<String, String> links,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(attachmentIcon(a)),
    title: Text(a.title),
    subtitle: Text(
      [
        if (a.title != a.fileName) a.fileName,
        formatBytes(a.size),
        displayDate(a.createdAt),
        if (a.linkId != null && links[a.linkId] != null)
          'Liên quan: ${links[a.linkId]}',
        if (a.note.isNotEmpty) a.note,
      ].join(' • '),
    ),
    onTap: () => run(() => _open(a)),
    trailing: PopupMenuButton<String>(
      tooltip: 'Thao tác tệp',
      onSelected: (v) => unawaited(run(() => _action(context, a, v))),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'open', child: Text('Mở')),
        const PopupMenuItem(value: 'save', child: Text('Lưu bản sao')),
        if (canEdit) ...const [
          PopupMenuItem(value: 'edit', child: Text('Sửa thông tin / chuyển')),
          PopupMenuItem(value: 'delete', child: Text('Xóa tệp')),
        ],
      ],
    ),
  );

  Future<void> _open(Attachment a) async {
    try {
      await opener.open(a, await c.repository.attachmentData(a.id));
    } on PlatformException catch (e) {
      throw FileSystemException(e.message ?? 'Không mở được tệp hồ sơ.');
    }
  }

  Future<void> _action(
    BuildContext context,
    Attachment a,
    String action,
  ) async {
    switch (action) {
      case 'open':
        await _open(a);
      case 'save':
        await saveBytes(a.fileName, await c.repository.attachmentData(a.id));
      case 'edit':
        final saved = await attachmentForm(context, c, a);
        if (saved != null) await c.updateAttachment(saved);
      case 'delete':
        if (await confirmAction(
          context,
          'Xóa tệp hồ sơ?',
          '“${a.title}” sẽ bị xóa khỏi ứng dụng. Các bản sao lưu đã tạo vẫn giữ tệp này.',
          action: 'Xóa tệp',
        )) {
          await c.deleteAttachment(a.id);
        }
    }
  }

  Future<void> _folderAction(
    BuildContext context,
    RecordFolder f,
    String action,
  ) async {
    switch (action) {
      case 'files':
        await _addFiles(context, f.path);
      case 'folder':
        await _addFolder(context, f.path);
      case 'rename':
        final name = await askFolderName(
          context,
          title: 'Đổi tên / chuyển thư mục',
          initial: f.path,
          helper: 'Dùng / để đặt vào thư mục khác, ví dụ: Pháp lý/Đăng kiểm.',
        );
        if (name != null) {
          await c.renameAttachmentFolder(equipment.id, f.path, name);
        }
      case 'delete':
        if (context.mounted &&
            await confirmAction(
              context,
              'Xóa thư mục “${f.name}”?',
              '${f.total} tệp trong thư mục và các thư mục con sẽ bị xóa khỏi ứng dụng. Các bản sao lưu đã tạo vẫn giữ các tệp này.',
              action: 'Xóa thư mục',
            )) {
          await c.deleteAttachmentFolder(equipment.id, f.path);
        }
    }
  }

  Attachment _draft(String name, Uint8List bytes, String folder) => Attachment(
    equipmentId: equipment.id,
    fileName: name,
    size: bytes.length,
    sha256: sha256.convert(bytes).toString(),
    folder: folder,
  );

  /// Null when [name] can be kept as a record file.
  static String? fileProblem(String name, int? size) {
    if (blockedAttachmentTypes.contains(fileExtension(name))) {
      return 'tệp chương trình/script không được lưu vào hồ sơ';
    }
    if (size == 0) return 'tệp trống';
    if (size != null && size > maxAttachmentBytes) {
      return 'lớn hơn $maxAttachmentLabel';
    }
    return null;
  }

  Future<void> _addFiles(BuildContext context, String folder) async {
    final picked = await FilePicker.pickFiles(dialogTitle: 'Chọn tệp hồ sơ');
    if (picked.isEmpty) return;
    if (picked.length == 1) {
      final file = picked.single;
      final problem = fileProblem(file.name, await file.length());
      if (problem != null) throw FormatException('${file.name}: $problem.');
      final bytes = await readPicked(
        file,
        maxAttachmentBytes,
        'Tệp lớn hơn $maxAttachmentLabel. Hãy nén hoặc chia nhỏ.',
      );
      if (bytes.isEmpty) throw const FormatException('Tệp trống.');
      final draft = _draft(file.name, bytes, folder);
      validateAttachment(draft);
      if (!context.mounted) return;
      final saved = await attachmentForm(context, c, draft, isNew: true);
      if (saved != null) await c.addAttachment(saved, bytes);
      return;
    }
    final skipped = <String>[];
    var added = 0;
    Stream<(Attachment, Uint8List)> files() async* {
      for (final file in picked) {
        final problem = fileProblem(file.name, await file.length());
        if (problem != null) {
          skipped.add('${file.name}: $problem');
          continue;
        }
        final bytes = await file.readAsBytes();
        final problemAfterRead = fileProblem(file.name, bytes.length);
        if (problemAfterRead != null) {
          skipped.add('${file.name}: $problemAfterRead');
          continue;
        }
        added++;
        yield (_draft(file.name, bytes, folder), bytes);
      }
    }

    await c.addAttachments(files());
    if (context.mounted) await _summary(context, added, skipped);
  }

  /// Windows: pick a real folder and keep its structure. Android cannot read
  /// a picked folder without broad storage access, so it names a folder and
  /// adds the chosen files into it.
  Future<void> _addFolder(BuildContext context, String parent) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      final name = await askFolderName(context, title: 'Tên thư mục mới');
      if (name == null || !context.mounted) return;
      await _addFiles(context, _join(parent, name));
      return;
    }
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Chọn thư mục hồ sơ',
    );
    if (path == null) return;
    final dir = Directory(path);
    final base = _join(parent, p.basename(dir.path));
    final found = <(File, String)>[];
    final skipped = <String>[];
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: dir.path);
      final name = p.basename(entity.path);
      final sub = p.dirname(relative);
      final folder = _join(base, sub == '.' ? '' : sub);
      final size = await entity.length();
      final problem = folderProblem(folder) ?? fileProblem(name, size);
      if (problem != null) {
        skipped.add('$relative: $problem');
        continue;
      }
      found.add((entity, folder));
      total += size;
      if (found.length > maxFolderFiles) {
        throw const FormatException(
          'Thư mục có hơn $maxFolderFiles tệp. Hãy chọn từng thư mục con.',
        );
      }
    }
    if (found.isEmpty) {
      throw FormatException(
        skipped.isEmpty
            ? 'Thư mục không có tệp.'
            : 'Không có tệp nào thêm được: ${skipped.first}.',
      );
    }
    if (!context.mounted ||
        !await confirmAction(
          context,
          'Thêm thư mục “${p.basename(dir.path)}”?',
          '${found.length} tệp (${formatBytes(total)}) sẽ được lưu vào hồ sơ, giữ nguyên cấu trúc thư mục.${skipped.isEmpty ? '' : ' Bỏ qua ${skipped.length} tệp.'}',
          action: 'Thêm thư mục',
        )) {
      return;
    }
    Stream<(Attachment, Uint8List)> files() async* {
      for (final (file, folder) in found) {
        final bytes = await file.readAsBytes();
        yield (_draft(p.basename(file.path), bytes, folder), bytes);
      }
    }

    await c.addAttachments(files());
    if (context.mounted) await _summary(context, found.length, skipped);
  }

  Future<void> _summary(
    BuildContext context,
    int added,
    List<String> skipped,
  ) async {
    if (skipped.isEmpty) return;
    await showInstantDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Đã thêm $added tệp, bỏ qua ${skipped.length}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: Text(skipped.join('\n'))),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }
}

/// Asks for a folder path; returns it normalized, or null when cancelled.
Future<String?> askFolderName(
  BuildContext context, {
  required String title,
  String initial = '',
  String? helper,
}) {
  final text = TextEditingController(text: initial);
  final form = GlobalKey<FormState>();
  return showFormDialog<String>(
    controllers: [text],
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: form,
          child: TextFormField(
            controller: text,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Tên thư mục',
              helperText: helper,
              helperMaxLines: 2,
            ),
            validator: (v) {
              final folder = normalizeFolder(v ?? '');
              return folder.isEmpty
                  ? 'Nhập tên thư mục.'
                  : folderProblem(folder);
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            Navigator.pop(context, normalizeFolder(text.text));
          },
          child: const Text('Lưu'),
        ),
      ],
    ),
  );
}

Future<Attachment?> attachmentForm(
  BuildContext context,
  AppController c,
  Attachment a, {
  bool isNew = false,
}) {
  final title = TextEditingController(text: a.title);
  final note = TextEditingController(text: a.note);
  final folder = TextEditingController(text: a.folder);
  final links = attachmentLinks(c, a.equipmentId);
  final form = GlobalKey<FormState>();
  var link = links.containsKey(a.linkId) ? a.linkId : null;
  return showFormDialog<Attachment>(
    controllers: [title, note, folder],
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(isNew ? 'Thêm tệp hồ sơ' : 'Sửa thông tin tệp'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${a.fileName} • ${formatBytes(a.size)}'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Tên hiển thị',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: folder,
                    decoration: const InputDecoration(
                      labelText: 'Thư mục',
                      helperText:
                          'Để trống: ngoài cùng. Dùng / cho thư mục con, ví dụ: Pháp lý/Đăng kiểm.',
                      helperMaxLines: 2,
                    ),
                    validator: (v) => folderProblem(normalizeFolder(v ?? '')),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    initialValue: link,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Liên quan đến',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Thiết bị (chung)'),
                      ),
                      for (final l in links.entries)
                        DropdownMenuItem<String?>(
                          value: l.key,
                          child: Text(l.value, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => link = v),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Ghi chú'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(
                context,
                a.copy({
                  'title': title.text.trim().isEmpty
                      ? a.fileName
                      : title.text.trim(),
                  'note': note.text.trim(),
                  'linkId': link,
                  'folder': normalizeFolder(folder.text),
                }),
              );
            },
            child: Text(isNew ? 'Lưu vào hồ sơ' : 'Lưu'),
          ),
        ],
      ),
    ),
  );
}
