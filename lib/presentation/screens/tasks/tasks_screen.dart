import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/task.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/task_tile.dart';

class TasksScreen extends ConsumerStatefulWidget {
  final TaskSection initialSection;
  const TasksScreen({super.key, this.initialSection = TaskSection.today});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  late TaskSection _section = widget.initialSection;
  TaskSort? _sort;

  List<Task> _sorted(List<Task> l) {
    if (_sort == null) return l;
    final list = [...l];
    switch (_sort!) {
      case TaskSort.dueDate:
        list.sort((a, b) => (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999)));
      case TaskSort.priority:
        list.sort((a, b) => b.priority.index.compareTo(a.priority.index));
      case TaskSort.createdAt:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case TaskSort.title:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case TaskSort.progress:
        list.sort((a, b) => b.effectiveProgress.compareTo(a.effectiveProgress));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(sectionCountsProvider).value ?? const {};
    final tasks = ref.watch(sectionTasksProvider(_section));
    return Column(children: [
      SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            for (final s in TaskSection.values)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  avatar: Icon(sectionIcon(s), size: 18, color: s == TaskSection.overdue && (counts[s] ?? 0) > 0 ? Colors.red : null),
                  label: Text('${sectionLabel(context, s)}  ${counts[s] ?? 0}'),
                  selected: _section == s,
                  onSelected: (_) => setState(() => _section = s),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Text(sectionLabel(context, _section), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          PopupMenuButton<TaskSort?>(
            tooltip: context.tr('sort'),
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (c) => [
              PopupMenuItem(value: null, child: Text(c.tr('sort_default'))),
              for (final s in TaskSort.values) PopupMenuItem(value: s, child: Text(c.tr('sort_${s.name}'))),
            ],
          ),
        ]),
      ),
      Expanded(
        child: AsyncView<List<Task>>(
          value: tasks,
          builder: (list) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(_section),
              child: TaskListView(tasks: _sorted(list), emptyText: context.tr('empty_${_section.name}')),
            ),
          ),
        ),
      ),
    ]);
  }
}
