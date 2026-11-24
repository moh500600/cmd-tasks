import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/platform/desktop_files.dart';
import '../../../core/platform/platform_support.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/validators.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/task.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

class TaskEditScreen extends ConsumerStatefulWidget {
  final Task? initial;
  final DateTime? initialDue;
  final int? projectId;
  const TaskEditScreen({super.key, this.initial, this.initialDue, this.projectId});

  @override
  ConsumerState<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends ConsumerState<TaskEditScreen> {
  final _form = GlobalKey<FormState>();
  late Task _t;
  late final TextEditingController _title, _desc, _notes, _tag, _sub;
  bool _saving = false;

  static const reminderOptions = [0, 5, 10, 15, 30, 60, 120, 1440, 2880];

  @override
  void initState() {
    super.initState();
    final a = ref.read(actionsProvider);
    _t = widget.initial ?? a.blankTask(due: widget.initialDue, projectId: widget.projectId);
    _title = TextEditingController(text: _t.title);
    _desc = TextEditingController(text: _t.description);
    _notes = TextEditingController(text: _t.notes);
    _tag = TextEditingController();
    _sub = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in [_title, _desc, _notes, _tag, _sub]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isNew => _t.id == null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_t.startDate != null && _t.dueDate != null && _t.dueDate!.isBefore(_t.startDate!)) {
      showSnack(context, context.tr('err_due_before_start'), error: true);
      return;
    }
    setState(() => _saving = true);
    final task = _t.copyWith(title: _title.text, description: _desc.text, notes: _notes.text);
    final ok = await guard(context, () => ref.read(actionsProvider).saveTask(task), successKey: 'saved_msg');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  void _addTag(String raw) {
    final name = raw.trim().replaceAll('#', '');
    if (name.isEmpty) return;
    final tag = Tag(name: name);
    if (!_t.tags.contains(tag)) setState(() => _t = _t.copyWith(tags: [..._t.tags, tag]));
    _tag.clear();
  }

  void _addSub() {
    final s = _sub.text.trim();
    if (s.isEmpty) return;
    setState(() => _t = _t.copyWith(subtasks: [..._t.subtasks, Subtask(title: s)]));
    _sub.clear();
  }

  Future<void> _pickImage(ImageSource src) async {
    await guard(context, () async {
      final x = await pickImageFile(source: src, imageQuality: 85, maxWidth: 2000);
      if (x == null) return;
      final path = await ref.read(fileStorageProvider).saveBytes(await x.readAsBytes(), x.name);
      setState(() => _t = _t.copyWith(attachments: [
            ..._t.attachments,
            Attachment(type: AttachmentType.image, name: x.name, pathOrUrl: path, createdAt: DateTime.now()),
          ]));
    });
  }

  Future<void> _pickFiles() async {
    await guard(context, () async {
      final files = await FilePicker.pickFiles();
      for (final f in files) {
        final bytes = await f.xFile.readAsBytes();
        final path = await ref.read(fileStorageProvider).saveBytes(bytes, f.name);
        final isImg = RegExp(r'\.(png|jpe?g|gif|webp|heic)$', caseSensitive: false).hasMatch(f.name);
        setState(() => _t = _t.copyWith(attachments: [
              ..._t.attachments,
              Attachment(type: isImg ? AttachmentType.image : AttachmentType.file, name: f.name, pathOrUrl: path, createdAt: DateTime.now()),
            ]));
      }
    });
  }

  Future<void> _addLink() async {
    final url = TextEditingController();
    final name = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('add_link')),
        content: Form(
          key: key,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: url,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'https://'),
              validator: (v) {
                final e = Validators.url(v);
                return e == null ? null : ctx.tr(e);
              },
            ),
            const SizedBox(height: 10),
            TextFormField(controller: name, decoration: InputDecoration(labelText: ctx.tr('link_title_optional'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, true); }, child: Text(ctx.tr('add'))),
        ],
      ),
    );
    if (ok == true) {
      final u = url.text.trim();
      setState(() => _t = _t.copyWith(attachments: [
            ..._t.attachments,
            Attachment(type: AttachmentType.link, name: name.text.trim().isEmpty ? Uri.parse(u).host : name.text.trim(), pathOrUrl: u, createdAt: DateTime.now()),
          ]));
    }
  }

  String _reminderLabel(int m) {
    if (m == 0) return context.tr('at_due_time');
    if (m % 1440 == 0) return context.trf('days_before', {'n': m ~/ 1440});
    if (m % 60 == 0) return context.trf('hours_before', {'n': m ~/ 60});
    return context.trf('minutes_before', {'n': m});
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider(false)).value ?? const [];
    final allTags = ref.watch(tagsProvider).value ?? const [];
    final cs = Theme.of(context).colorScheme;
    final hasSubs = _t.subtasks.isNotEmpty;

    Widget dateTile(String label, IconData icon, DateTime? value, ValueChanged<DateTime?> onChanged) => Card(
          child: ListTile(
            leading: Icon(icon, color: cs.primary),
            title: Text(label),
            subtitle: Text(value == null ? context.tr('not_set') : fmtDateTime(context, value)),
            trailing: value == null
                ? const Icon(Icons.add_rounded)
                : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => onChanged(null)),
            onTap: () async {
              final d = await pickDateTime(context, initial: value);
              if (d != null) onChanged(d);
            },
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(_isNew ? 'new_task' : 'edit_task')),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton.tonal(
              onPressed: _saving ? null : _save,
              child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(context.tr('save')),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
          TextFormField(
            controller: _title,
            autofocus: _isNew,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            decoration: InputDecoration(labelText: context.tr('title'), prefixIcon: const Icon(Icons.title_rounded)),
            validator: (v) {
              final e = Validators.title(v);
              return e == null ? null : context.tr(e);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _desc,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(labelText: context.tr('description'), prefixIcon: const Icon(Icons.notes_rounded)),
          ),
          SectionHeader(context.tr('priority')),
          SegmentedButton<TaskPriority>(
            showSelectedIcon: false,
            segments: [
              for (final p in TaskPriority.values)
                ButtonSegment(value: p, label: Text(priorityLabel(context, p), style: TextStyle(color: priorityColor(p), fontWeight: FontWeight.w700))),
            ],
            selected: {_t.priority},
            onSelectionChanged: (s) => setState(() => _t = _t.copyWith(priority: s.first)),
          ),
          SectionHeader(context.tr('status')),
          Wrap(spacing: 8, children: [
            for (final s in TaskStatus.values)
              ChoiceChip(
                label: Text(statusLabel(context, s)),
                selected: _t.status == s,
                selectedColor: statusColor(s).withValues(alpha: 0.25),
                onSelected: (_) => setState(() => _t = _t.copyWith(status: s)),
              ),
          ]),
          SectionHeader(context.tr('dates')),
          dateTile(context.tr('start_date'), Icons.play_circle_outline_rounded, _t.startDate,
              (d) => setState(() => _t = d == null ? _t.copyWith(clearStart: true) : _t.copyWith(startDate: d))),
          const SizedBox(height: 8),
          dateTile(context.tr('due_date'), Icons.event_rounded, _t.dueDate, (d) => setState(() {
                _t = d == null ? _t.copyWith(clearDue: true) : _t.copyWith(dueDate: d);
                if (d != null && _t.reminderMinutes == null) {
                  _t = _t.copyWith(reminderMinutes: ref.read(settingsProvider).defaultReminderMinutes);
                }
              })),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: _t.reminderMinutes,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('reminder'), prefixIcon: const Icon(Icons.notifications_rounded)),
                items: [
                  DropdownMenuItem(value: null, child: Text(context.tr('no_reminder'))),
                  for (final m in {...reminderOptions, ?_t.reminderMinutes})
                    DropdownMenuItem(value: m, child: Text(_reminderLabel(m))),
                ],
                onChanged: _t.dueDate == null
                    ? null
                    : (v) => setState(() => _t = v == null ? _t.copyWith(clearReminder: true) : _t.copyWith(reminderMinutes: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<RepeatRule>(
                initialValue: _t.repeat,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('repeat'), prefixIcon: const Icon(Icons.repeat_rounded)),
                items: [for (final r in RepeatRule.values) DropdownMenuItem(value: r, child: Text(repeatLabel(context, r)))],
                onChanged: (v) => setState(() => _t = _t.copyWith(repeat: v)),
              ),
            ),
          ]),
          if (_t.repeat != RepeatRule.none && _t.dueDate == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.tr('repeat_needs_due'), style: TextStyle(color: cs.error, fontSize: 12)),
            ),
          SectionHeader(context.tr('project')),
          DropdownButtonFormField<int?>(
            initialValue: projects.any((p) => p.id == _t.projectId) ? _t.projectId : null,
            isExpanded: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.folder_rounded)),
            items: [
              DropdownMenuItem(value: null, child: Text(context.tr('no_project'))),
              for (final p in projects) DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => setState(() => _t = v == null ? _t.copyWith(clearProject: true) : _t.copyWith(projectId: v)),
          ),
          SectionHeader('${context.tr('progress')}: ${hasSubs ? _t.effectiveProgress : _t.progress}%',
              trailing: hasSubs ? Text(context.tr('progress_from_subtasks'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)) : null),
          Slider(
            value: (hasSubs ? _t.effectiveProgress : _t.progress).toDouble(),
            max: 100,
            divisions: 20,
            label: '${_t.progress}%',
            onChanged: hasSubs ? null : (v) => setState(() => _t = _t.copyWith(progress: v.round())),
          ),
          SectionHeader(context.tr('subtasks')),
          ..._t.subtasks.asMap().entries.map((e) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: Checkbox(
                    value: e.value.done,
                    onChanged: (v) => setState(() {
                      final list = [..._t.subtasks];
                      list[e.key] = e.value.copyWith(done: v ?? false);
                      _t = _t.copyWith(subtasks: list);
                    }),
                  ),
                  title: Text(e.value.title),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed: () => setState(() => _t = _t.copyWith(subtasks: [..._t.subtasks]..removeAt(e.key))),
                  ),
                ),
              )),
          TextField(
            controller: _sub,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addSub(),
            decoration: InputDecoration(
              hintText: context.tr('add_subtask'),
              prefixIcon: const Icon(Icons.checklist_rounded),
              suffixIcon: IconButton(icon: const Icon(Icons.add_circle_rounded), onPressed: _addSub),
            ),
          ),
          SectionHeader(context.tr('tags')),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final g in _t.tags)
              InputChip(
                label: Text('#${g.name}'),
                onDeleted: () => setState(() => _t = _t.copyWith(tags: [..._t.tags]..remove(g))),
              ),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: _tag,
            onSubmitted: _addTag,
            decoration: InputDecoration(
              hintText: context.tr('add_tag'),
              prefixIcon: const Icon(Icons.sell_rounded),
              suffixIcon: IconButton(icon: const Icon(Icons.add_circle_rounded), onPressed: () => _addTag(_tag.text)),
            ),
          ),
          if (allTags.where((g) => !_t.tags.contains(g)).isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final g in allTags.where((g) => !_t.tags.contains(g)).take(12))
                ActionChip(label: Text('#${g.name}'), onPressed: () => _addTag(g.name)),
            ]),
          ],
          SectionHeader(context.tr('notes')),
          TextFormField(
            controller: _notes,
            maxLines: 6,
            minLines: 3,
            decoration: InputDecoration(hintText: context.tr('notes_hint')),
          ),
          SectionHeader(context.tr('attachments')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo_library_rounded), label: Text(context.tr('gallery'))),
            // The camera is a phone feature; desktop picks image files instead.
            if (PlatformSupport.camera)
              OutlinedButton.icon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.photo_camera_rounded), label: Text(context.tr('camera'))),
            OutlinedButton.icon(onPressed: _pickFiles, icon: const Icon(Icons.attach_file_rounded), label: Text(context.tr('file'))),
            OutlinedButton.icon(onPressed: _addLink, icon: const Icon(Icons.link_rounded), label: Text(context.tr('link'))),
          ]),
          const SizedBox(height: 8),
          for (final a in _t.attachments)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: a.type == AttachmentType.image && File(a.pathOrUrl).existsSync()
                    ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(a.pathOrUrl), width: 44, height: 44, fit: BoxFit.cover))
                    : Icon(a.type == AttachmentType.link ? Icons.link_rounded : Icons.insert_drive_file_rounded),
                title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => setState(() => _t = _t.copyWith(attachments: [..._t.attachments]..remove(a))),
                ),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(context.tr('save')),
          ),
        ]),
      ),
    );
  }
}
