import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/task.dart';
import '../providers/providers.dart';
import '../screens/tasks/task_detail_screen.dart';
import 'common.dart';

class TaskTile extends ConsumerWidget {
  final Task task;
  final bool swipe;
  const TaskTile({super.key, required this.task, this.swipe = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final overdue = task.isOverdueAt(now);
    final pc = priorityColor(task.priority);
    final progress = task.effectiveProgress;

    Future<void> toggleDone() async {
      final next = task.isCompleted ? TaskStatus.todo : TaskStatus.completed;
      await guard(context, () async {
        final created = await ref.read(actionsProvider).setStatus(task, next);
        if (created != null && context.mounted) {
          showSnack(context, context.trf('next_occurrence_created', {'date': fmtDateTime(context, created.dueDate!)}));
        }
      });
    }

    final card = Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id!))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 14, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(
              value: task.isCompleted,
              shape: const CircleBorder(),
              activeColor: Colors.green,
              side: BorderSide(color: pc, width: 2),
              onChanged: task.archived ? null : (_) => toggleDone(),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 10),
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                    color: task.isCompleted ? cs.onSurfaceVariant : null,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Pill(priorityLabel(context, task.priority), pc, icon: Icons.flag_rounded),
                  if (task.dueDate != null)
                    Pill(fmtDateTime(context, task.dueDate!), overdue ? cs.error : cs.onSurfaceVariant,
                        icon: overdue ? Icons.warning_amber_rounded : Icons.schedule_rounded),
                  if (task.status == TaskStatus.inProgress || task.status == TaskStatus.postponed)
                    Pill(statusLabel(context, task.status), statusColor(task.status)),
                  if (task.projectName != null) Pill(task.projectName!, cs.primary, icon: Icons.folder_rounded),
                  for (final t in task.tags.take(3)) Pill('#${t.name}', Color(t.color)),
                  if (task.subtasks.isNotEmpty)
                    Pill('${task.subtasks.where((s) => s.done).length}/${task.subtasks.length}', cs.secondary,
                        icon: Icons.checklist_rounded),
                  if (task.attachments.isNotEmpty)
                    Pill('${task.attachments.length}', cs.secondary, icon: Icons.attach_file_rounded),
                  if (task.repeat != RepeatRule.none) Icon(Icons.repeat_rounded, size: 16, color: cs.secondary),
                ]),
                if (progress > 0 && !task.isCompleted) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: progress / 100, minHeight: 5, color: pc, backgroundColor: pc.withValues(alpha: 0.12)),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );

    if (!swipe || task.archived) return Padding(padding: const EdgeInsets.only(bottom: 10), child: card);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('task-${task.id}-${task.updatedAt.millisecondsSinceEpoch}'),
        background: _swipeBg(context, Icons.check_rounded, Colors.green, context.tr(task.isCompleted ? 'mark_undone' : 'mark_done'), true),
        secondaryBackground: _swipeBg(context, Icons.archive_rounded, Colors.orange, context.tr('archive'), false),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) {
            await toggleDone();
          } else {
            await guard(context, () => ref.read(actionsProvider).archiveTask(task, true), successKey: 'archived_msg');
          }
          return false;
        },
        child: card,
      ),
    );
  }

  Widget _swipeBg(BuildContext c, IconData icon, Color color, String label, bool start) => Container(
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(18)),
        alignment: start ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ]),
      );
}

class TaskListView extends StatelessWidget {
  final List<Task> tasks;
  final String emptyText;
  final EdgeInsets padding;
  const TaskListView({super.key, required this.tasks, required this.emptyText, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 96)});

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return EmptyState(icon: Icons.task_alt_rounded, text: emptyText);
    return ListView.builder(
      padding: padding,
      itemCount: tasks.length,
      itemBuilder: (_, i) => TweenAnimationBuilder<double>(
        key: ValueKey(tasks[i].id),
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 200 + (i * 30).clamp(0, 300)),
        builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child)),
        child: TaskTile(task: tasks[i]),
      ),
    );
  }
}
