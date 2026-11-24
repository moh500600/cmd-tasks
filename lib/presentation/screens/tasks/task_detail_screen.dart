import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/task.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import 'task_edit_screen.dart';

Future<void> openAttachment(BuildContext context, Attachment a) async {
  if (a.type == AttachmentType.link) {
    final ok = await launchUrl(Uri.parse(a.pathOrUrl), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showSnack(context, context.tr('err_open'), error: true);
    return;
  }
  if (!File(a.pathOrUrl).existsSync()) {
    if (context.mounted) showSnack(context, context.tr('err_file_missing'), error: true);
    return;
  }
  if (a.type == AttachmentType.image) {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(child: Image.file(File(a.pathOrUrl))),
      ),
    );
    return;
  }
  final r = await OpenFilex.open(a.pathOrUrl);
  if (r.type != ResultType.done && context.mounted) showSnack(context, context.tr('err_open'), error: true);
}

class TaskDetailScreen extends ConsumerWidget {
  final int taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(taskProvider(taskId));
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('task_details')),
        actions: [
          if (async.value != null) ...[
            IconButton(
              tooltip: context.tr('edit'),
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => TaskEditScreen(initial: async.value!))),
            ),
            _menu(context, ref, async.value!),
          ],
        ],
      ),
      body: AsyncView<Task?>(
        value: async,
        builder: (t) => t == null
            ? EmptyState(icon: Icons.search_off_rounded, text: context.tr('err_not_found'))
            : _body(context, ref, t),
      ),
    );
  }

  Widget _menu(BuildContext context, WidgetRef ref, Task t) {
    final actions = ref.read(actionsProvider);
    return PopupMenuButton<String>(
      onSelected: (v) async {
        switch (v) {
          case 'dup':
            await guard(context, () async {
              final d = await actions.duplicateTask(t);
              if (context.mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: d.id!)));
              }
            }, successKey: 'duplicated_msg');
          case 'archive':
            await guard(context, () => actions.archiveTask(t, !t.archived),
                successKey: t.archived ? 'unarchived_msg' : 'archived_msg');
          case 'postpone':
            await guard(context, () => actions.setStatus(t, TaskStatus.postponed), successKey: 'postponed_msg');
          case 'delete':
            if (await confirm(context, context.tr('delete_task'), context.tr('delete_task_confirm'), okKey: 'delete', destructive: true)) {
              if (!context.mounted) return;
              final ok = await guard(context, () => actions.deleteTask(t), successKey: 'deleted_msg');
              if (ok && context.mounted) Navigator.pop(context);
            }
        }
      },
      itemBuilder: (c) => [
        PopupMenuItem(value: 'dup', child: ListTile(leading: const Icon(Icons.copy_rounded), title: Text(c.tr('duplicate')))),
        PopupMenuItem(value: 'archive', child: ListTile(leading: const Icon(Icons.archive_rounded), title: Text(c.tr(t.archived ? 'unarchive' : 'archive')))),
        if (t.status != TaskStatus.postponed && !t.isCompleted)
          PopupMenuItem(value: 'postpone', child: ListTile(leading: const Icon(Icons.pause_circle_rounded), title: Text(c.tr('postpone')))),
        PopupMenuItem(value: 'delete', child: ListTile(leading: const Icon(Icons.delete_rounded, color: Colors.red), title: Text(c.tr('delete')))),
      ],
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, Task t) {
    final cs = Theme.of(context).colorScheme;
    final actions = ref.read(actionsProvider);
    final now = DateTime.now();
    Widget row(IconData icon, String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, size: 20, color: color ?? cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Text('$label: ', style: TextStyle(color: cs.onSurfaceVariant)),
            Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color))),
          ]),
        );

    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(t.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              if (t.archived) Pill(context.tr('archived'), Colors.orange, icon: Icons.archive_rounded),
            ]),
            if (t.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(t.description, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: t.effectiveProgress / 100, minHeight: 10),
                ),
              ),
              const SizedBox(width: 10),
              Text('${t.effectiveProgress}%', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 14),
            Text(context.tr('status'), style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in TaskStatus.values)
                ChoiceChip(
                  label: Text(statusLabel(context, s)),
                  selected: t.status == s,
                  selectedColor: statusColor(s).withValues(alpha: 0.25),
                  onSelected: t.archived
                      ? null
                      : (_) => guard(context, () async {
                            final next = await actions.setStatus(t, s);
                            if (next != null && context.mounted) {
                              showSnack(context, context.trf('next_occurrence_created', {'date': fmtDateTime(context, next.dueDate!)}));
                            }
                          }),
                ),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            row(Icons.flag_rounded, context.tr('priority'), priorityLabel(context, t.priority), color: priorityColor(t.priority)),
            if (t.projectName != null) row(Icons.folder_rounded, context.tr('project'), t.projectName!),
            if (t.startDate != null) row(Icons.play_circle_outline_rounded, context.tr('start_date'), fmtDateTime(context, t.startDate!)),
            if (t.dueDate != null)
              row(Icons.event_rounded, context.tr('due_date'), fmtDateTime(context, t.dueDate!),
                  color: t.isOverdueAt(now) ? cs.error : null),
            if (t.reminderMinutes != null)
              row(Icons.notifications_active_rounded, context.tr('reminder'), _reminderText(context, t.reminderMinutes!)),
            if (t.repeat != RepeatRule.none) row(Icons.repeat_rounded, context.tr('repeat'), repeatLabel(context, t.repeat)),
            if (t.completedAt != null) row(Icons.check_circle_rounded, context.tr('completed_at'), fmtDateTime(context, t.completedAt!), color: Colors.green),
            row(Icons.add_circle_outline_rounded, context.tr('created_at'), fmtDateTime(context, t.createdAt)),
          ]),
        ),
      ),
      if (t.tags.isNotEmpty) ...[
        SectionHeader(context.tr('tags')),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final g in t.tags) Pill('#${g.name}', Color(g.color))]),
      ],
      if (t.subtasks.isNotEmpty) ...[
        SectionHeader('${context.tr('subtasks')} (${t.subtasks.where((s) => s.done).length}/${t.subtasks.length})'),
        Card(
          child: Column(children: [
            for (final s in t.subtasks)
              CheckboxListTile(
                value: s.done,
                title: Text(s.title, style: TextStyle(decoration: s.done ? TextDecoration.lineThrough : null)),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: t.archived ? null : (v) => guard(context, () => actions.toggleSubtask(s, v ?? false)),
              ),
          ]),
        ),
      ],
      if (t.notes.isNotEmpty) ...[
        SectionHeader(context.tr('notes')),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(t.notes))),
      ],
      if (t.attachments.isNotEmpty) ...[
        SectionHeader(context.tr('attachments')),
        _AttachmentsGrid(attachments: t.attachments),
      ],
      const SizedBox(height: 40),
    ]);
  }

  static String _reminderText(BuildContext c, int m) {
    if (m == 0) return c.tr('at_due_time');
    if (m % 1440 == 0) return c.trf('days_before', {'n': m ~/ 1440});
    if (m % 60 == 0) return c.trf('hours_before', {'n': m ~/ 60});
    return c.trf('minutes_before', {'n': m});
  }
}

class _AttachmentsGrid extends StatelessWidget {
  final List<Attachment> attachments;
  const _AttachmentsGrid({required this.attachments});

  @override
  Widget build(BuildContext context) {
    final images = attachments.where((a) => a.type == AttachmentType.image).toList();
    final others = attachments.where((a) => a.type != AttachmentType.image).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (images.isNotEmpty)
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => openAttachment(context, images[i]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: File(images[i].pathOrUrl).existsSync()
                    ? Image.file(File(images[i].pathOrUrl), width: 110, height: 110, fit: BoxFit.cover)
                    : Container(width: 110, color: Colors.black12, child: const Icon(Icons.broken_image)),
              ),
            ),
          ),
        ),
      const SizedBox(height: 8),
      for (final a in others)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(a.type == AttachmentType.link ? Icons.link_rounded : Icons.insert_drive_file_rounded),
            title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: a.type == AttachmentType.link ? Text(a.pathOrUrl, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: () => openAttachment(context, a),
          ),
        ),
    ]);
  }
}
