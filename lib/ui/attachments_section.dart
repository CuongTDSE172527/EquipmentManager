import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    : ['xls', 'xlsx'].contains(a.extension)
    ? Icons.table_chart_outlined
    : Icons.description_outlined;

/// Choices for linking an attachment to one of the equipment's own records.
Map<String, String> attachmentLinks(AppController c, String equipmentId) => {
  for (final i in c.items.where((i) => i.equipmentId == equipmentId))
    i.id: '${i.kind.label}: ${i.title}',
  for (final r in c.serviceRecords.where((r) => r.equipmentId == equipmentId))
    r.id: 'Sổ bảo trì ${displayDate(r.doneDate)}: ${r.title}',
};

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
    final files =
        c.attachments.where((a) => a.equipmentId == equipment.id).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final links = attachmentLinks(c, equipment.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Tệp đính kèm (${files.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (canEdit)
              TextButton.icon(
                onPressed: () => run(() => _add(context)),
                icon: const Icon(Icons.attach_file),
                label: const Text('Thêm tệp'),
              ),
          ],
        ),
        if (files.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Chưa có tệp. Có thể đính kèm ảnh/PDF giấy đăng kiểm, hợp đồng, biên bản (tối đa 25 MB mỗi tệp).',
            ),
          ),
        for (final a in files)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(attachmentIcon(a)),
            title: Text(a.title),
            subtitle: Text(
              [
                a.fileName,
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
                  PopupMenuItem(value: 'edit', child: Text('Sửa thông tin')),
                  PopupMenuItem(value: 'delete', child: Text('Xóa tệp')),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _open(Attachment a) async {
    try {
      await opener.open(a, await c.repository.attachmentData(a.id));
    } on PlatformException catch (e) {
      throw FileSystemException(e.message ?? 'Không mở được tệp đính kèm.');
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
          'Xóa tệp đính kèm?',
          '“${a.title}” sẽ bị xóa khỏi ứng dụng. Các bản sao lưu đã tạo vẫn giữ tệp này.',
          action: 'Xóa tệp',
        )) {
          await c.deleteAttachment(a.id);
        }
    }
  }

  Future<void> _add(BuildContext context) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: attachmentTypes.keys.toList(),
    );
    if (file == null) return;
    final bytes = await readPicked(
      file,
      maxAttachmentBytes,
      'Tệp lớn hơn 25 MB. Hãy nén hoặc chia nhỏ.',
    );
    if (bytes.isEmpty) throw const FormatException('Tệp trống.');
    final draft = Attachment(
      equipmentId: equipment.id,
      fileName: file.name,
      size: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
    validateAttachment(draft);
    if (!context.mounted) return;
    final saved = await attachmentForm(context, c, draft, isNew: true);
    if (saved != null) await c.addAttachment(saved, bytes);
  }
}

Future<Attachment?> attachmentForm(
  BuildContext context,
  AppController c,
  Attachment a, {
  bool isNew = false,
}) {
  final title = TextEditingController(text: a.title);
  final note = TextEditingController(text: a.note);
  final links = attachmentLinks(c, a.equipmentId);
  var link = links.containsKey(a.linkId) ? a.linkId : null;
  return showFormDialog<Attachment>(
    controllers: [title, note],
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(isNew ? 'Thêm tệp đính kèm' : 'Sửa thông tin tệp'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a.fileName} • ${formatBytes(a.size)}'),
                const SizedBox(height: 16),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Tên hiển thị'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: link,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Liên quan đến'),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              a.copy({
                'title': title.text.trim().isEmpty
                    ? a.fileName
                    : title.text.trim(),
                'note': note.text.trim(),
                'linkId': link,
              }),
            ),
            child: Text(isNew ? 'Đính kèm' : 'Lưu'),
          ),
        ],
      ),
    ),
  );
}
