import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../domain/models.dart';
import '../domain/deadlines.dart';
import '../domain/service_history.dart';
import 'controller.dart';
import 'forms.dart';

String _money(int cost) =>
    '${NumberFormat.decimalPattern('vi_VN').format(cost)} VND';

class ServiceHistoryPage extends StatefulWidget {
  const ServiceHistoryPage({
    super.key,
    required this.controller,
    required this.equipment,
  });
  final AppController controller;
  final Equipment equipment;
  @override
  State<ServiceHistoryPage> createState() => _ServiceHistoryPageState();
}

class _ServiceHistoryPageState extends State<ServiceHistoryPage> {
  final search = TextEditingController();
  ItemKind? kind;
  int? year;
  AppController get c => widget.controller;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final visits = serviceVisits(
        [widget.equipment],
        c.items,
        c.history,
        c.serviceRecords,
      );
      final query = search.text.trim().toLowerCase();
      final rows = visits
          .where(
            (v) =>
                (kind == null || kind == v.kind) &&
                (year == null || year == v.doneDate.year) &&
                '${v.title} ${v.provider} ${v.note}'.toLowerCase().contains(
                  query,
                ),
          )
          .toList();
      final years = {?year, for (final v in visits) v.doneDate.year}.toList()
        ..sort((a, b) => b.compareTo(a));
      final total = rows.fold<int>(0, (sum, v) => sum + (v.cost ?? 0));
      return Scaffold(
        appBar: AppBar(title: const Text('Lịch sử bảo trì / sửa chữa')),
        body: LayoutBuilder(
          builder: (context, bounds) => Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: bounds.maxHeight * .65),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.equipment.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (widget.equipment.displayPlate.isNotEmpty)
                          Text(widget.equipment.displayPlate),
                        const SizedBox(height: 12),
                        TextField(
                          controller: search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Tìm nội dung, đơn vị, ghi chú',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<ItemKind>(
                                initialValue: kind,
                                decoration: const InputDecoration(
                                  labelText: 'Loại công việc',
                                ),
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('Tất cả'),
                                  ),
                                  for (final k in [
                                    ItemKind.maintenance,
                                    ItemKind.repair,
                                  ])
                                    DropdownMenuItem(
                                      value: k,
                                      child: Text(k.label),
                                    ),
                                ],
                                onChanged: (v) => setState(() => kind = v),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                initialValue: year,
                                decoration: const InputDecoration(
                                  labelText: 'Năm',
                                ),
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('Tất cả'),
                                  ),
                                  for (final y in years)
                                    DropdownMenuItem(
                                      value: y,
                                      child: Text('$y'),
                                    ),
                                ],
                                onChanged: (v) => setState(() => year = v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${rows.length} lần • Chi phí đã ghi: ${_money(total)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (rows.any((r) => r.cost == null))
                          const Text(
                            'Một số lần chưa có chi phí.',
                            style: TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Chưa có lịch sử phù hợp. Bấm Ghi công việc để nhập lần bảo trì/sửa chữa đã thực hiện.',
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final visit = rows[index];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${displayDate(visit.doneDate)} • ${visit.kind.label}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (visit.record != null)
                                        PopupMenuButton<String>(
                                          tooltip: 'Thao tác lịch sử',
                                          onSelected: (action) => _run(() async {
                                            if (action == 'edit') {
                                              await serviceRecordForm(
                                                context,
                                                c,
                                                widget.equipment,
                                                record: visit.record,
                                              );
                                            } else if (await confirmAction(
                                              context,
                                              'Xóa lịch sử?',
                                              'Xóa công việc “${visit.title}” khỏi sổ bảo trì/sửa chữa?',
                                              action: 'Xóa lịch sử',
                                            )) {
                                              await c.deleteServiceRecord(
                                                visit.record!.id,
                                              );
                                            }
                                          }),
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Sửa'),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text('Xóa'),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  Text(
                                    visit.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    visit.provider.isEmpty
                                        ? 'Chưa ghi đơn vị thực hiện'
                                        : visit.provider,
                                  ),
                                  Text(
                                    visit.cost == null
                                        ? 'Chưa ghi chi phí'
                                        : _money(visit.cost!),
                                  ),
                                  if (visit.note.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(visit.note),
                                    ),
                                  if (visit.record == null)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Từ hoàn thành hạng mục',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: null,
          onPressed: () =>
              _run(() => serviceRecordForm(context, c, widget.equipment)),
          icon: const Icon(Icons.add),
          label: const Text('Ghi công việc'),
        ),
      );
    },
  );
}

Future<void> serviceRecordForm(
  BuildContext context,
  AppController c,
  Equipment equipment, {
  ServiceRecord? record,
}) async {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(text: record?.title ?? '');
  final date = TextEditingController(
    text: displayDate(record?.doneDate ?? c.clock()),
  );
  final cost = TextEditingController(text: record?.cost?.toString() ?? '');
  final provider = TextEditingController(text: record?.provider ?? '');
  final note = TextEditingController(text: record?.note ?? '');
  var kind = record?.kind ?? ItemKind.maintenance;
  int? parseCost(String raw) =>
      int.tryParse(raw.replaceAll(RegExp(r'[.,\s]'), ''));
  final result = await showFormDialog<ServiceRecord>(
    context: context,
    controllers: [title, date, cost, provider, note],
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          record == null
              ? 'Ghi công việc đã thực hiện'
              : 'Sửa lịch sử bảo trì / sửa chữa',
        ),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(equipment.name),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ItemKind>(
                    initialValue: kind,
                    decoration: const InputDecoration(
                      labelText: 'Loại công việc',
                    ),
                    items: [
                      for (final k in [ItemKind.maintenance, ItemKind.repair])
                        DropdownMenuItem(value: k, child: Text(k.label)),
                    ],
                    onChanged: (v) => setState(() => kind = v!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Nội dung công việc *',
                    ),
                    validator: (v) =>
                        v!.trim().isEmpty ? 'Nhập nội dung công việc.' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: date,
                    decoration: const InputDecoration(
                      labelText: 'Ngày thực hiện *',
                      hintText: 'dd/MM/yyyy',
                    ),
                    validator: (v) {
                      try {
                        final parsed = parseVietnameseDate(v!);
                        if (parsed.precision != DatePrecision.day) {
                          return 'Nhập ngày cụ thể dd/MM/yyyy.';
                        }
                        if (parsed.date.isAfter(dateOnly(c.clock()))) {
                          return 'Ngày thực hiện không được ở tương lai.';
                        }
                        return null;
                      } on FormatException catch (e) {
                        return e.message;
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: cost,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Chi phí (VND)',
                      hintText: 'Ví dụ: 1.500.000',
                    ),
                    validator: (v) =>
                        v!.trim().isEmpty ||
                            (parseCost(v) != null && parseCost(v)! >= 0)
                        ? null
                        : 'Nhập chi phí nguyên không âm.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: provider,
                    decoration: InputDecoration(
                      labelText: 'Đơn vị thực hiện',
                      suffixIcon: PopupMenuButton<String>(
                        tooltip: 'Chọn đơn vị đã có',
                        onSelected: (v) => provider.text = v,
                        itemBuilder: (_) => [
                          for (final p in c.providers)
                            PopupMenuItem(value: p, child: Text(p)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: note,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Chi tiết, phụ tùng, kết quả',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Ghi sổ công việc đã làm. Hạn theo dõi được giữ nguyên.',
                    style: TextStyle(fontSize: 12),
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
                ServiceRecord(
                  id: record?.id,
                  equipmentId: equipment.id,
                  kind: kind,
                  title: title.text.trim(),
                  doneDate: parseVietnameseDate(date.text).date,
                  cost: parseCost(cost.text),
                  provider: provider.text.trim(),
                  note: note.text.trim(),
                ),
              );
            },
            child: const Text('Lưu lịch sử'),
          ),
        ],
      ),
    ),
  );
  if (result != null) await c.saveServiceRecord(result);
}
