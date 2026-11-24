import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/task.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/task_tile.dart';

/// Standalone list for a section or a dashboard drill-down.
class SectionTasksScreen extends ConsumerWidget {
  final TaskSection? section;
  final TaskStatus? status;
  final bool highPriority;
  final String? title;
  const SectionTasksScreen({super.key, this.section, this.status, this.highPriority = false, this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allTasksProvider);
    return Scaffold(
      appBar: AppBar(title: Text(title ?? (section != null ? sectionLabel(context, section!) : ''))),
      body: AsyncView<List<Task>>(
        value: section != null ? ref.watch(sectionTasksProvider(section!)) : all,
        builder: (list) {
          var l = list;
          if (section == null) l = l.where((t) => !t.archived).toList();
          if (status != null) l = l.where((t) => t.status == status).toList();
          if (highPriority) l = l.where((t) => !t.isCompleted && t.priority.index >= TaskPriority.high.index).toList();
          return TaskListView(tasks: l, emptyText: context.tr('no_tasks'));
        },
      ),
    );
  }
}
