import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/deadlines.dart';
import 'controller.dart';

Future<T?> showFormDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required Iterable<TextEditingController> controllers,
}) {
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    animationStyle: AnimationStyle.noAnimation,
  );
  unawaited(
    route.completed.then((_) {
      for (final c in controllers) {
        c.dispose();
      }
    }),
  );
  return Navigator.of(context, rootNavigator: true).push(route);
}

Future<T?> showInstantDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  builder: builder,
  animationStyle: AnimationStyle.noAnimation,
);

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message, {
  String action = 'Xác nhận',
}) async =>
    await showInstantDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<void> equipmentForm(
  BuildContext context,
  AppController c, {
  Equipment? equipment,
}) async {
  final e = equipment ?? Equipment(name: '');
  final keys = <String, String>{
    'name': 'Tên thiết bị *',
    'type': 'Loại thiết bị',
    'brandModel': 'Hãng / Model',
    'country': 'Nước sản xuất',
    'yearMade': 'Năm sản xuất',
    'chassisNo': 'Số khung',
    'engineNo': 'Số động cơ',
    'controlPlate': 'Biển kiểm soát (CAH-xx-xxx)',
    'oldControlPlate': 'Biển kiểm soát cũ',
    'roadPlate': 'Biển đăng ký giao thông',
    'purpose': 'Mục đích sử dụng',
    'operatingAt': 'Hoạt động tại',
    'note': 'Ghi chú',
  };
  final json = e.toJson();
  final fields = {
    for (final key in keys.keys)
      key: TextEditingController(text: json[key]?.toString() ?? ''),
  };
  var group = e.group;
  var management = e.managementStatus;
  var self = e.selfPropelled;
  String? error;
  final form = GlobalKey<FormState>();
  final drafts = <ItemDraft>[], everyDraft = <ItemDraft>[];
  final existing = c.items
      .where((i) => equipment != null && i.equipmentId == equipment.id)
      .toList();
  final saved = await showFormDialog<(Equipment, List<DeadlineItem>)>(
    // Read when the dialog closes, so drafts added later are disposed too.
    controllers: fields.values.followedBy(
      everyDraft.expand((d) => d.controllers),
    ),
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(equipment == null ? 'Thêm thiết bị' : 'Sửa thiết bị'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth > 580
                      ? (constraints.maxWidth - 16) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final entry in keys.entries)
                        SizedBox(
                          width: entry.key == 'note'
                              ? constraints.maxWidth
                              : width,
                          child: TextFormField(
                            controller: fields[entry.key],
                            decoration: InputDecoration(labelText: entry.value),
                            maxLines: entry.key == 'note' ? 3 : 1,
                            keyboardType: entry.key == 'yearMade'
                                ? TextInputType.number
                                : TextInputType.text,
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (entry.key == 'name' && text.isEmpty) {
                                return 'Vui lòng nhập tên thiết bị.';
                              }
                              if (entry.key == 'yearMade' &&
                                  text.isNotEmpty &&
                                  (int.tryParse(text) == null ||
                                      int.parse(text) < 1900 ||
                                      int.parse(text) > 9999)) {
                                return 'Năm không hợp lệ.';
                              }
                              if (entry.key == 'controlPlate' &&
                                  text.isNotEmpty &&
                                  !RegExp(
                                    r'^CAH-\d{2}-\d{3}$',
                                  ).hasMatch(text)) {
                                return 'Định dạng CAH-xx-xxx; biển cũ nhập ở ô riêng.';
                              }
                              return null;
                            },
                          ),
                        ),
                      SizedBox(
                        width: width,
                        child: DropdownButtonFormField<String>(
                          initialValue: group,
                          decoration: const InputDecoration(labelText: 'Nhóm'),
                          isExpanded: true,
                          items: {...c.groups, group}
                              .map(
                                (g) => DropdownMenuItem(
                                  value: g,
                                  child: Text(
                                    g,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => group = v!,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: DropdownButtonFormField<ManagementStatus>(
                          initialValue: management,
                          decoration: const InputDecoration(
                            labelText: 'Trạng thái quản lý',
                          ),
                          isExpanded: true,
                          items: ManagementStatus.values
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => management = v!,
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Thiết bị tự hành'),
                        value: self,
                        onChanged: (v) => setState(() => self = v!),
                      ),
                      SizedBox(
                        width: constraints.maxWidth,
                        child: ItemDraftsEditor(
                          drafts: drafts,
                          existing: existing,
                          onAdd: (kind) => setState(() {
                            final d = ItemDraft(kind);
                            drafts.add(d);
                            everyDraft.add(d);
                          }),
                          onRemove: (d) => setState(() => drafts.remove(d)),
                          onChanged: () => setState(() {}),
                        ),
                      ),
                      if (error != null)
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  );
                },
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
              try {
                final result = e.copy({
                  for (final key in keys.keys)
                    key: key == 'yearMade'
                        ? int.tryParse(fields[key]!.text.trim())
                        : fields[key]!.text.trim(),
                  'group': group,
                  'managementStatus': management.name,
                  'selfPropelled': self,
                });
                Navigator.pop(context, (
                  result,
                  [for (final d in drafts) d.build(result.id)],
                ));
              } catch (ex) {
                setState(() => error = ex.toString());
              }
            },
            child: const Text('Lưu thiết bị'),
          ),
        ],
      ),
    ),
  );
  if (saved != null) await c.saveEquipmentWithItems(saved.$1, saved.$2);
}

Future<void> itemForm(
  BuildContext context,
  AppController c, {
  DeadlineItem? item,
  String? equipmentId,
}) async {
  if (c.equipment.isEmpty) {
    throw StateError('Hãy thêm thiết bị trước khi tạo hạng mục.');
  }
  final i =
      item ??
      DeadlineItem(
        equipmentId: equipmentId ?? c.equipment.first.id,
        kind: ItemKind.maintenance,
        title: 'Bảo dưỡng',
      );
  var kind = i.kind;
  var mode = i.insuranceMode;
  var selectedEquipment = i.equipmentId;
  var provider = i.provider;
  var needsConfirmation = i.requiresConfirmation;
  var expired = i.expiredWithoutDate;
  final title = TextEditingController(text: i.title);
  final due = TextEditingController(
    text: i.dueDate == null ? '' : displayDate(i.dueDate, i.precision),
  );
  final cycle = TextEditingController(text: i.cycleMonths.toString());
  final cost = TextEditingController(text: i.cost?.toString() ?? '');
  final note = TextEditingController(text: i.note);
  final form = GlobalKey<FormState>();
  String? error;
  final saved = await showFormDialog<DeadlineItem>(
    controllers: [title, due, cycle, cost, note],
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(item == null ? 'Thêm hạng mục theo dõi' : 'Sửa hạng mục'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedEquipment,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Thiết bị'),
                    items: c.equipment
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(
                              '${e.name} • ${e.displayPlate}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: item == null
                        ? (v) => selectedEquipment = v!
                        : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ItemKind>(
                    initialValue: kind,
                    decoration: const InputDecoration(
                      labelText: 'Loại hạng mục',
                    ),
                    items: ItemKind.values
                        .map(
                          (v) =>
                              DropdownMenuItem(value: v, child: Text(v.label)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      kind = v!;
                      if (item == null) title.text = kind.label;
                      if (kind == ItemKind.lifespan) cycle.text = '0';
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Tên hạng mục *',
                    ),
                    validator: (v) =>
                        v!.trim().isEmpty ? 'Vui lòng nhập tên.' : null,
                  ),
                  const SizedBox(height: 16),
                  if (kind == ItemKind.insurance) ...[
                    DropdownButtonFormField<InsuranceMode>(
                      initialValue: mode,
                      decoration: const InputDecoration(
                        labelText: 'Chế độ bảo hiểm',
                      ),
                      items: InsuranceMode.values
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(v.label),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => mode = v!),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: due,
                    decoration: const InputDecoration(
                      labelText: 'Hạn: dd/MM/yyyy hoặc MM/yyyy',
                      helperText:
                          'Để trống: Cần cập nhật. Hạn tháng tính đến cuối tháng.',
                    ),
                    validator: (v) {
                      if (v!.trim().isEmpty) {
                        return kind == ItemKind.insurance &&
                                mode == InsuranceMode.dated
                            ? 'Nhập ngày hết hạn.'
                            : null;
                      }
                      try {
                        parseVietnameseDate(v);
                        return null;
                      } on FormatException catch (e) {
                        return e.message;
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: cycle,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Chu kỳ (tháng)',
                      helperText:
                          '0 = làm một lần. Niên hạn sử dụng luôn là 0.',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null ||
                              n < 0 ||
                              (kind == ItemKind.lifespan && n != 0)
                          ? 'Chu kỳ không hợp lệ.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: provider,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Đơn vị thực hiện',
                    ),
                    items: {'', ...c.providers, provider}
                        .map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.isEmpty ? 'Chưa chọn' : p),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => provider = v!,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: cost,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Chi phí (VND, tùy chọn)',
                    ),
                    validator: (v) =>
                        v!.isEmpty ||
                            (int.tryParse(v) != null && int.parse(v) >= 0)
                        ? null
                        : 'Nhập số nguyên không âm.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: note,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Ghi chú'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cần xác nhận lại dữ liệu'),
                    value: needsConfirmation,
                    onChanged: (v) => setState(() => needsConfirmation = v!),
                  ),
                  if (kind != ItemKind.insurance)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Đã hết hạn, chưa rõ ngày'),
                      value: expired,
                      onChanged: (v) => setState(() => expired = v!),
                    ),
                  if (i.isDone)
                    const Text(
                      'Đã xong. Các lần hoàn thành được ghi trong lịch sử.',
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
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
              try {
                final parsed = due.text.trim().isEmpty
                    ? null
                    : parseVietnameseDate(due.text);
                Navigator.pop(
                  context,
                  i.copy({
                    'equipmentId': selectedEquipment,
                    'kind': kind.name,
                    'title': title.text.trim(),
                    'dueDate': parsed?.date.toIso8601String(),
                    'precision':
                        parsed?.precision.name ?? DatePrecision.day.name,
                    'cycleMonths': int.parse(cycle.text),
                    'provider': provider,
                    'insuranceMode': mode.name,
                    'cost': int.tryParse(cost.text),
                    'note': note.text.trim(),
                    'isDone': i.isDone,
                    'requiresConfirmation': needsConfirmation,
                    'expiredWithoutDate':
                        kind != ItemKind.insurance && expired && parsed == null,
                  }),
                );
              } catch (ex) {
                setState(() => error = ex.toString());
              }
            },
            child: const Text('Lưu hạng mục'),
          ),
        ],
      ),
    ),
  );
  if (saved != null) await c.saveItem(saved);
}

Future<void> completionForm(
  BuildContext context,
  AppController c,
  DeadlineItem item,
) async {
  final date = TextEditingController(text: displayDate(c.clock()));
  final cost = TextEditingController(text: item.cost?.toString() ?? '');
  final note = TextEditingController();
  final explicit = TextEditingController();
  var provider = item.provider;
  String? error;
  final form = GlobalKey<FormState>();
  final result = await showFormDialog<({DeadlineItem item, HistoryLog history})>(
    controllers: [date, cost, note, explicit],
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Gia hạn / Hoàn thành'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.cycleMonths == 0
                        ? 'Hạng mục sẽ chuyển sang Đã xong.'
                        : '${item.cycleMonths} tháng • tính từ ${[ItemKind.insurance, ItemKind.inspection].contains(item.kind) ? 'hạn cũ' : 'ngày thực hiện'}.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: date,
                    decoration: const InputDecoration(
                      labelText: 'Ngày thực hiện *',
                    ),
                    validator: (v) {
                      try {
                        final p = parseVietnameseDate(v!);
                        if (p.precision != DatePrecision.day) {
                          return 'Cần ngày cụ thể.';
                        }
                        return null;
                      } on FormatException catch (e) {
                        return e.message;
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  if (item.cycleMonths > 0 &&
                      item.dueDate == null &&
                      [
                        ItemKind.insurance,
                        ItemKind.inspection,
                      ].contains(item.kind)) ...[
                    TextFormField(
                      controller: explicit,
                      decoration: const InputDecoration(
                        labelText: 'Hạn tiếp theo đã xác nhận *',
                      ),
                      validator: (v) {
                        try {
                          parseVietnameseDate(v!);
                          return null;
                        } on FormatException catch (e) {
                          return e.message;
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: cost,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Chi phí (VND)',
                    ),
                    validator: (v) =>
                        v!.isEmpty ||
                            (int.tryParse(v) != null && int.parse(v) >= 0)
                        ? null
                        : 'Chi phí không hợp lệ.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: provider,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Đơn vị thực hiện',
                    ),
                    items: {'', ...c.providers, provider}
                        .map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.isEmpty ? 'Chưa chọn' : p),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => provider = v!,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: note,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú thực hiện',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
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
              try {
                final result = completeItem(
                  item,
                  doneDate: parseVietnameseDate(date.text).date,
                  cost: int.tryParse(cost.text),
                  provider: provider,
                  note: note.text.trim(),
                  explicitNextDate: explicit.text.isEmpty
                      ? null
                      : parseVietnameseDate(explicit.text).date,
                );
                Navigator.pop(context, result);
              } catch (ex) {
                setState(() => error = ex.toString());
              }
            },
            child: const Text('Xác nhận và ghi lịch sử'),
          ),
        ],
      ),
    ),
  );
  if (result != null) {
    await c.recordCompletion(result.item, result.history);
  }
}

/// A new deadline item typed into the equipment form.
class ItemDraft {
  ItemDraft(this.kind)
    : title = TextEditingController(text: kind.label),
      due = TextEditingController(),
      cycle = TextEditingController(text: '0');
  ItemKind kind;
  InsuranceMode mode = InsuranceMode.unknown;
  final TextEditingController title, due, cycle;
  Iterable<TextEditingController> get controllers => [title, due, cycle];

  DeadlineItem build(String equipmentId) {
    final parsed = due.text.trim().isEmpty
        ? null
        : parseVietnameseDate(due.text);
    return DeadlineItem(
      equipmentId: equipmentId,
      kind: kind,
      title: title.text.trim(),
      dueDate: parsed?.date,
      precision: parsed?.precision ?? DatePrecision.day,
      cycleMonths: kind == ItemKind.lifespan
          ? 0
          : int.tryParse(cycle.text.trim()) ?? 0,
      insuranceMode: kind != ItemKind.insurance
          ? InsuranceMode.unknown
          : parsed != null && mode == InsuranceMode.unknown
          ? InsuranceMode.dated
          : mode,
    );
  }
}

/// Rows for new items inside the equipment form; validated with the form.
class ItemDraftsEditor extends StatelessWidget {
  const ItemDraftsEditor({
    super.key,
    required this.drafts,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
    this.existing = const [],
  });
  final List<ItemDraft> drafts;
  final List<DeadlineItem> existing;
  final ValueChanged<ItemKind> onAdd;
  final ValueChanged<ItemDraft> onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 580;
        double w(double share) => wide
            ? (constraints.maxWidth - 92) * share
            : constraints.maxWidth - 64;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 32),
            Text('Hạng mục theo dõi', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              existing.isEmpty
                  ? 'Thêm các hạng mục cần theo dõi hạn; mỗi hạng mục có tên riêng. Có thể thêm sau trong chi tiết thiết bị.'
                  : 'Đang có ${existing.length}: ${existing.map((i) => i.title).join('; ')}. Hạng mục cũ sửa trong Theo dõi hạn hoặc chi tiết thiết bị; dưới đây chỉ thêm hạng mục mới.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final d in drafts)
              Card(
                key: ObjectKey(d),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: w(.28),
                              child: DropdownButtonFormField<ItemKind>(
                                initialValue: d.kind,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Loại',
                                ),
                                items: [
                                  for (final k in ItemKind.values)
                                    DropdownMenuItem(
                                      value: k,
                                      child: Text(
                                        k.label,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) {
                                  if (d.title.text.trim().isEmpty ||
                                      d.title.text == d.kind.label) {
                                    d.title.text = v!.label;
                                  }
                                  d.kind = v!;
                                  if (v == ItemKind.lifespan) {
                                    d.cycle.text = '0';
                                  }
                                  onChanged();
                                },
                              ),
                            ),
                            SizedBox(
                              width: w(.42),
                              child: TextFormField(
                                controller: d.title,
                                decoration: const InputDecoration(
                                  labelText: 'Tên hạng mục *',
                                ),
                                validator: (v) => v!.trim().isEmpty
                                    ? 'Nhập tên hạng mục.'
                                    : null,
                              ),
                            ),
                            SizedBox(
                              width: w(.3),
                              child: TextFormField(
                                controller: d.due,
                                decoration: const InputDecoration(
                                  labelText: 'Hạn',
                                  hintText: 'dd/MM/yyyy hoặc MM/yyyy',
                                ),
                                validator: (v) {
                                  if (v!.trim().isEmpty) {
                                    return d.kind == ItemKind.insurance &&
                                            d.mode == InsuranceMode.dated
                                        ? 'Nhập ngày hết hạn.'
                                        : null;
                                  }
                                  try {
                                    parseVietnameseDate(v);
                                    return null;
                                  } on FormatException catch (e) {
                                    return e.message;
                                  }
                                },
                              ),
                            ),
                            if (d.kind != ItemKind.lifespan)
                              SizedBox(
                                width: wide ? 150 : w(1),
                                child: TextFormField(
                                  controller: d.cycle,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Chu kỳ (tháng)',
                                  ),
                                  validator: (v) {
                                    final n = int.tryParse(v!.trim());
                                    return n == null || n < 0
                                        ? 'Chu kỳ không hợp lệ.'
                                        : null;
                                  },
                                ),
                              ),
                            if (d.kind == ItemKind.insurance)
                              SizedBox(
                                width: wide ? 240 : w(1),
                                child: DropdownButtonFormField<InsuranceMode>(
                                  initialValue: d.mode,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Chế độ bảo hiểm',
                                  ),
                                  items: [
                                    for (final m in InsuranceMode.values)
                                      DropdownMenuItem(
                                        value: m,
                                        child: Text(
                                          m.label,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) {
                                    d.mode = v!;
                                    onChanged();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Bỏ hạng mục này',
                        onPressed: () => onRemove(d),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in [
                  ItemKind.inspection,
                  ItemKind.insurance,
                  ItemKind.maintenance,
                  ItemKind.lifespan,
                  ItemKind.other,
                ])
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(
                      k == ItemKind.other ? 'Hạng mục khác' : k.label,
                    ),
                    onPressed: () => onAdd(k),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
