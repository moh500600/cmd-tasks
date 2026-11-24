import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../domain/entities/project.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import 'project_detail_screen.dart';

String money(BuildContext c, double v) => NumberFormat.decimalPattern(c.lang).format(v);

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider(true));
    return AsyncView<List<Project>>(
      value: projects,
      builder: (all) {
        final list = all.where((p) => p.archived == _showArchived).toList();
        return LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 900 ? 3 : (c.maxWidth > 600 ? 2 : 1);
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text('${context.tr('active_projects')} (${all.where((p) => !p.archived).length})')),
                    ButtonSegment(value: true, label: Text('${context.tr('archived')} (${all.where((p) => p.archived).length})')),
                  ],
                  selected: {_showArchived},
                  onSelectionChanged: (s) => setState(() => _showArchived = s.first),
                ),
              ),
            ),
            if (list.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(icon: Icons.folder_open_rounded, text: context.tr(_showArchived ? 'no_archived_projects' : 'no_projects')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 178),
                  delegate: SliverChildBuilderDelegate((_, i) => ProjectCard(project: list[i]), childCount: list.length),
                ),
              ),
          ]);
        });
      },
    );
  }
}

class ProjectCard extends StatelessWidget {
  final Project project;
  const ProjectCard({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final p = project;
    final color = Color(p.color);
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectDetailScreen(projectId: p.id!))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ProjectAvatar(project: p, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Pill(projectStatusLabel(context, p.status), color),
                ]),
              ),
              if (p.overdueTasks > 0) Pill('${p.overdueTasks}', cs.error, icon: Icons.warning_amber_rounded),
            ]),
            const Spacer(),
            Row(children: [
              Text(context.trf('tasks_done_of', {'done': p.completedTasks, 'total': p.totalTasks}), style: TextStyle(color: cs.onSurfaceVariant)),
              const Spacer(),
              Text('${(p.progress * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: p.progress),
                duration: const Duration(milliseconds: 700),
                builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 8, color: color, backgroundColor: color.withValues(alpha: 0.15)),
              ),
            ),
            if (p.budget != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.account_balance_wallet_rounded, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('${money(context, p.spent)} / ${money(context, p.budget!)}', style: TextStyle(fontSize: 12, color: (p.budgetUsage ?? 0) > 1 ? cs.error : cs.onSurfaceVariant)),
                if (p.endDate != null) ...[
                  const Spacer(),
                  Icon(Icons.flag_rounded, size: 14, color: cs.onSurfaceVariant),
                  Text(' ${fmtShortDate(context, p.endDate!)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ]),
            ] else if (p.endDate != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.flag_rounded, size: 14, color: cs.onSurfaceVariant),
                Text(' ${fmtShortDate(context, p.endDate!)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

class ProjectAvatar extends StatelessWidget {
  final Project project;
  final double size;
  const ProjectAvatar({super.key, required this.project, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final color = Color(project.color);
    final img = project.imagePath != null ? File(project.imagePath!) : null;
    if (img != null && img.existsSync()) {
      return ClipRRect(borderRadius: BorderRadius.circular(size / 3.5), child: Image.file(img, width: size, height: size, fit: BoxFit.cover));
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(size / 3.5)),
      child: Icon(iconFromCode(project.iconCode), color: color, size: size * 0.55),
    );
  }
}
