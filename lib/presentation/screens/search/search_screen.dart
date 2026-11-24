import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/task.dart';
import '../../../domain/entities/task_filter.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/task_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _q.text = ref.read(searchFilterProvider).query;
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _set(TaskFilter f) => ref.read(searchFilterProvider.notifier).set(f);

  Future<void> _openFilters() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _FilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(searchFilterProvider);
    final results = ref.watch(searchResultsProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _q,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.tr('search_hint'),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            filled: false,
            suffixIcon: _q.text.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.close), onPressed: () {
                    _q.clear();
                    _set(f.copyWith(query: ''));
                    setState(() {});
                  }),
          ),
          onChanged: (v) {
            _set(f.copyWith(query: v));
            setState(() {});
          },
        ),
        actions: [
          IconButton(
            tooltip: context.tr('filters'),
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: f.activeCount > 0,
              label: Text('${f.activeCount}'),
              child: const Icon(Icons.tune_rounded),
            ),
          ),
        ],
      ),
      body: Column(children: [
        if (f.activeCount > 0 || f.includeArchived)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(children: [
              Expanded(child: Text(context.trf('filters_active', {'n': f.activeCount}), style: const TextStyle(fontWeight: FontWeight.w600))),
              TextButton(onPressed: () => _set(TaskFilter(query: f.query)), child: Text(context.tr('clear'))),
            ]),
          ),
        Expanded(
          child: AsyncView<List<Task>>(
            value: results,
            builder: (list) => f.isEmpty && !f.includeArchived
                ? (list.isEmpty
                    ? EmptyState(icon: Icons.search_rounded, text: context.tr('search_empty_prompt'))
                    : TaskListView(tasks: list, emptyText: ''))
                : TaskListView(tasks: list, emptyText: context.tr('no_results')),
          ),
        ),
      ]),
    );
  }
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(searchFilterProvider);
    void set(TaskFilter n) => ref.read(searchFilterProvider.notifier).set(n);
    final projects = ref.watch(projectsProvider(true)).value ?? const [];
    final tags = ref.watch(tagsProvider).value ?? const [];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, controller) => ListView(controller: controller, padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Text(context.tr('filters'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        SectionHeader(context.tr('priority')),
        Wrap(spacing: 8, children: [
          for (final p in TaskPriority.values)
            FilterChip(
              label: Text(priorityLabel(context, p)),
              selected: f.priorities.contains(p),
              onSelected: (v) => set(f.copyWith(priorities: v ? {...f.priorities, p} : ({...f.priorities}..remove(p)))),
            ),
        ]),
        SectionHeader(context.tr('status')),
        Wrap(spacing: 8, children: [
          for (final s in TaskStatus.values)
            FilterChip(
              label: Text(statusLabel(context, s)),
              selected: f.statuses.contains(s),
              onSelected: (v) => set(f.copyWith(statuses: v ? {...f.statuses, s} : ({...f.statuses}..remove(s)))),
            ),
        ]),
        SectionHeader(context.tr('project')),
        DropdownButtonFormField<int?>(
          initialValue: f.projectId,
          isExpanded: true,
          items: [
            DropdownMenuItem(value: null, child: Text(context.tr('any_project'))),
            for (final p in projects) DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) => set(v == null ? f.copyWith(clearProject: true) : f.copyWith(projectId: v)),
        ),
        if (tags.isNotEmpty) ...[
          SectionHeader(context.tr('tags')),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final g in tags)
              FilterChip(
                label: Text('#${g.name}'),
                selected: f.tagIds.contains(g.id),
                onSelected: (v) => set(f.copyWith(tagIds: v ? {...f.tagIds, g.id!} : ({...f.tagIds}..remove(g.id)))),
              ),
          ]),
        ],
        SectionHeader(context.tr('due_date')),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: Text(f.from == null ? context.tr('from') : fmtShortDate(context, f.from!)),
              onPressed: () async {
                final d = await pickDateTime(context, initial: f.from, withTime: false);
                if (d != null) set(f.copyWith(from: d));
              },
              onLongPress: () => set(f.copyWith(clearFrom: true)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(f.to == null ? context.tr('to') : fmtShortDate(context, f.to!)),
              onPressed: () async {
                final d = await pickDateTime(context, initial: f.to, withTime: false);
                if (d != null) set(f.copyWith(to: d));
              },
              onLongPress: () => set(f.copyWith(clearTo: true)),
            ),
          ),
          if (f.from != null || f.to != null)
            IconButton(onPressed: () => set(f.copyWith(clearFrom: true, clearTo: true)), icon: const Icon(Icons.close_rounded)),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('include_archived')),
          value: f.includeArchived,
          onChanged: (v) => set(f.copyWith(includeArchived: v)),
        ),
        SectionHeader(context.tr('sort')),
        Wrap(spacing: 8, children: [
          for (final s in TaskSort.values)
            ChoiceChip(label: Text(context.tr('sort_${s.name}')), selected: f.sort == s, onSelected: (_) => set(f.copyWith(sort: s))),
        ]),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(context.tr('ascending')), icon: const Icon(Icons.arrow_upward_rounded)),
            ButtonSegment(value: false, label: Text(context.tr('descending')), icon: const Icon(Icons.arrow_downward_rounded)),
          ],
          selected: {f.ascending},
          onSelectionChanged: (s) => set(f.copyWith(ascending: s.first)),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('show_results'))),
      ]),
    );
  }
}
