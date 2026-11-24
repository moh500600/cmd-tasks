import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/project.dart';
import '../../../domain/entities/task.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/task_tile.dart';
import '../tasks/task_edit_screen.dart';
import 'project_edit_screen.dart';
import 'projects_screen.dart';

class ProjectDetailScreen extends ConsumerWidget {
  final int projectId;
  const ProjectDetailScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider(projectId));
    final tasks = ref.watch(projectTasksProvider(projectId));
    final p = project.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.name ?? ''),
        actions: [
          if (p != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectEditScreen(initial: p))),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                final a = ref.read(actionsProvider);
                if (v == 'archive') {
                  await guard(context, () => a.archiveProject(p, !p.archived), successKey: p.archived ? 'unarchived_msg' : 'archived_msg');
                } else if (v == 'delete') {
                  final choice = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(ctx.tr('delete_project')),
                      content: Text(ctx.tr('delete_project_confirm')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
                        TextButton(onPressed: () => Navigator.pop(ctx, 'keep'), child: Text(ctx.tr('delete_keep_tasks'))),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
                          onPressed: () => Navigator.pop(ctx, 'all'),
                          child: Text(ctx.tr('delete_with_tasks')),
                        ),
                      ],
                    ),
                  );
                  if (choice == null || !context.mounted) return;
                  final ok = await guard(context, () => a.deleteProject(p, deleteTasks: choice == 'all'), successKey: 'deleted_msg');
                  if (ok && context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (c) => [
                PopupMenuItem(value: 'archive', child: Text(c.tr(p.archived ? 'unarchive' : 'archive'))),
                PopupMenuItem(value: 'delete', child: Text(c.tr('delete'), style: const TextStyle(color: Colors.red))),
              ],
            ),
          ],
        ],
      ),
      floatingActionButton: p == null || p.archived
          ? null
          : FloatingActionButton.extended(
              heroTag: 'project-add',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskEditScreen(projectId: projectId))),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.tr('add_task')),
            ),
      body: AsyncView<Project?>(
        value: project,
        builder: (p) => p == null
            ? EmptyState(icon: Icons.search_off_rounded, text: context.tr('err_not_found'))
            : AsyncView<List<Task>>(value: tasks, builder: (list) => _body(context, p, list)),
      ),
    );
  }

  Widget _body(BuildContext context, Project p, List<Task> tasks) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(p.color);
    final now = DateTime.now();
    final active = tasks.where((t) => !t.archived).toList();
    final byStatus = {for (final s in TaskStatus.values) s: active.where((t) => t.status == s).length};
    final overdue = active.where((t) => t.isOverdueAt(now)).length;
    final daysLeft = p.endDate?.difference(DateTime(now.year, now.month, now.day)).inDays;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ProjectAvatar(project: p, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, children: [
                    Pill(projectStatusLabel(context, p.status), color),
                    if (p.archived) Pill(context.tr('archived'), Colors.orange),
                  ]),
                ]),
              ),
            ]),
            if (p.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(p.description, style: TextStyle(color: cs.onSurfaceVariant)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Text(context.tr('project_progress'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${(p.progress * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 18)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: p.progress, minHeight: 10, color: color, backgroundColor: color.withValues(alpha: 0.15)),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 16, runSpacing: 8, children: [
              if (p.startDate != null) _info(Icons.play_circle_outline_rounded, fmtShortDate(context, p.startDate!)),
              if (p.endDate != null) _info(Icons.flag_rounded, fmtShortDate(context, p.endDate!)),
              if (daysLeft != null)
                _info(Icons.hourglass_bottom_rounded,
                    daysLeft >= 0 ? context.trf('days_left', {'n': daysLeft}) : context.trf('days_late', {'n': -daysLeft}),
                    color: daysLeft < 0 ? cs.error : null),
            ]),
          ]),
        ),
      ),
      SectionHeader(context.tr('project_stats')),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            SizedBox(
              width: 120,
              height: 120,
              child: active.isEmpty
                  ? Center(child: Text(context.tr('no_tasks')))
                  : PieChart(PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 30,
                      sections: [
                        for (final e in byStatus.entries)
                          if (e.value > 0)
                            PieChartSectionData(
                              value: e.value.toDouble(),
                              color: statusColor(e.key),
                              radius: 24,
                              title: '${e.value}',
                              titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                      ],
                    )),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final e in byStatus.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: statusColor(e.key), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(statusLabel(context, e.key))),
                      Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded, size: 14, color: cs.error),
                    const SizedBox(width: 4),
                    Expanded(child: Text(context.tr('stat_overdue'))),
                    Text('$overdue', style: TextStyle(fontWeight: FontWeight.w700, color: cs.error)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
      if (p.budget != null) ...[
        SectionHeader(context.tr('budget')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Text('${context.tr('spent')}: ${money(context, p.spent)}'),
                const Spacer(),
                Text('${context.tr('budget')}: ${money(context, p.budget!)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (p.budgetUsage ?? 0).clamp(0, 1).toDouble(),
                  minHeight: 10,
                  color: (p.budgetUsage ?? 0) > 1 ? cs.error : Colors.teal,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  (p.budgetUsage ?? 0) > 1
                      ? context.trf('over_budget', {'v': money(context, p.spent - p.budget!)})
                      : context.trf('remaining_budget', {'v': money(context, p.budget! - p.spent)}),
                  style: TextStyle(color: (p.budgetUsage ?? 0) > 1 ? cs.error : cs.onSurfaceVariant),
                ),
              ),
            ]),
          ),
        ),
      ],
      SectionHeader('${context.tr('tasks')} (${active.length})'),
      if (active.isEmpty)
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Text(context.tr('project_no_tasks'), textAlign: TextAlign.center)))
      else
        for (final t in active) TaskTile(task: t),
    ]);
  }

  Widget _info(IconData i, String t, {Color? color}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 16, color: color), const SizedBox(width: 4), Text(t, style: TextStyle(color: color))]);
}
