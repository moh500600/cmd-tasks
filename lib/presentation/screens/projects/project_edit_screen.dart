import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/platform/desktop_files.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/validators.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/project.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import 'projects_screen.dart';

class ProjectEditScreen extends ConsumerStatefulWidget {
  final Project? initial;
  const ProjectEditScreen({super.key, this.initial});

  @override
  ConsumerState<ProjectEditScreen> createState() => _ProjectEditScreenState();
}

class _ProjectEditScreenState extends ConsumerState<ProjectEditScreen> {
  final _form = GlobalKey<FormState>();
  late Project _p;
  late final TextEditingController _name, _desc, _budget, _spent;

  @override
  void initState() {
    super.initState();
    _p = widget.initial ??
        Project(userId: ref.read(sessionProvider)!.id, name: '', iconCode: kPickableIcons.first.codePoint, createdAt: DateTime.now());
    _name = TextEditingController(text: _p.name);
    _desc = TextEditingController(text: _p.description);
    _budget = TextEditingController(text: _p.budget?.toString() ?? '');
    _spent = TextEditingController(text: _p.spent == 0 ? '' : _p.spent.toString());
  }

  @override
  void dispose() {
    for (final c in [_name, _desc, _budget, _spent]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(String s) => s.trim().isEmpty ? null : double.tryParse(normalizeDigits(s.trim()));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final budget = _num(_budget.text);
    final p = _p.copyWith(
      name: _name.text,
      description: _desc.text,
      budget: budget,
      clearBudget: budget == null,
      spent: _num(_spent.text) ?? 0,
    );
    final ok = await guard(context, () => ref.read(actionsProvider).saveProject(p), successKey: 'saved_msg');
    if (ok && mounted) Navigator.pop(context);
  }

  Future<void> _pickImage() async {
    await guard(context, () async {
      final x = await pickImageFile(source: ImageSource.gallery, imageQuality: 85, maxWidth: 800);
      if (x == null) return;
      final path = await ref.read(fileStorageProvider).saveBytes(await x.readAsBytes(), x.name, folder: 'projects');
      setState(() => _p = _p.copyWith(imagePath: path));
    });
  }

  @override
  Widget build(BuildContext context) {
    String? numV(String? v) {
      final e = Validators.optionalNumber(v);
      return e == null ? null : context.tr(e);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(_p.id == null ? 'new_project' : 'edit_project')),
        actions: [TextButton(onPressed: _save, child: Text(context.tr('save')))],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Stack(children: [
                ProjectAvatar(project: _p, size: 88),
                PositionedDirectional(
                  end: 0,
                  bottom: 0,
                  child: CircleAvatar(radius: 14, child: const Icon(Icons.photo_camera_rounded, size: 16)),
                ),
              ]),
            ),
          ),
          if (_p.imagePath != null)
            Center(child: TextButton(onPressed: () => setState(() => _p = Project(
                  id: _p.id, userId: _p.userId, name: _p.name, description: _p.description, iconCode: _p.iconCode, color: _p.color,
                  startDate: _p.startDate, endDate: _p.endDate, budget: _p.budget, spent: _p.spent, status: _p.status,
                  archived: _p.archived, createdAt: _p.createdAt)), child: Text(context.tr('remove_image')))),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: context.tr('project_name'), prefixIcon: const Icon(Icons.folder_rounded)),
            validator: (v) {
              final e = Validators.title(v);
              return e == null ? null : context.tr(e);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _desc, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: context.tr('description'))),
          SectionHeader(context.tr('status')),
          Wrap(spacing: 8, children: [
            for (final s in ProjectStatus.values)
              ChoiceChip(label: Text(projectStatusLabel(context, s)), selected: _p.status == s, onSelected: (_) => setState(() => _p = _p.copyWith(status: s))),
          ]),
          SectionHeader(context.tr('dates')),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: Text(_p.startDate == null ? context.tr('start_date') : fmtShortDate(context, _p.startDate!)),
                onPressed: () async {
                  final d = await pickDateTime(context, initial: _p.startDate, withTime: false);
                  if (d != null) setState(() => _p = _p.copyWith(startDate: d));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.flag_rounded),
                label: Text(_p.endDate == null ? context.tr('end_date') : fmtShortDate(context, _p.endDate!)),
                onPressed: () async {
                  final d = await pickDateTime(context, initial: _p.endDate, withTime: false);
                  if (d != null) setState(() => _p = _p.copyWith(endDate: d));
                },
              ),
            ),
          ]),
          SectionHeader(context.tr('budget_optional')),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _budget,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: context.tr('budget'), prefixIcon: const Icon(Icons.account_balance_wallet_rounded)),
                validator: numV,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _spent,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: context.tr('spent'), prefixIcon: const Icon(Icons.payments_rounded)),
                validator: numV,
              ),
            ),
          ]),
          SectionHeader(context.tr('color')),
          ColorPickerRow(value: _p.color, onChanged: (c) => setState(() => _p = _p.copyWith(color: c))),
          SectionHeader(context.tr('icon')),
          IconPickerRow(value: _p.iconCode, color: _p.color, onChanged: (i) => setState(() => _p = _p.copyWith(iconCode: i))),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded), label: Text(context.tr('save'))),
        ]),
      ),
    );
  }
}
