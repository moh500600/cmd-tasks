import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/date_x.dart' as dx;
import '../../../domain/entities/task.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/task_tile.dart';
import '../tasks/task_edit_screen.dart';

enum CalView { day, week, month, year }

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => CalendarScreenState();
}

class CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalView _view = CalView.month;
  DateTime _focused = DateTime.now();
  DateTime _selected = dx.dateOnly(DateTime.now());

  DateTime get selectedDay => _selected;

  Map<DateTime, List<Task>> _group(List<Task> tasks) {
    final m = <DateTime, List<Task>>{};
    for (final t in tasks) {
      if (t.archived || t.dueDate == null) continue;
      (m[dx.dateOnly(t.dueDate!)] ??= []).add(t);
    }
    for (final l in m.values) {
      l.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    }
    return m;
  }

  void addOn(DateTime day) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TaskEditScreen(initialDue: ref.read(actionsProvider).defaultDueFor(day))),
      );

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(allTasksProvider);
    return AsyncView<List<Task>>(
      value: all,
      builder: (tasks) {
        final byDay = _group(tasks);
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<CalView>(
              showSelectedIcon: false,
              segments: [for (final v in CalView.values) ButtonSegment(value: v, label: Text(context.tr('cal_${v.name}')))],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey(_view),
                child: switch (_view) {
                  CalView.day => _dayView(context, byDay),
                  CalView.week || CalView.month => _tableView(context, byDay),
                  CalView.year => _yearView(context, byDay),
                },
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _tableView(BuildContext context, Map<DateTime, List<Task>> byDay) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final dayTasks = byDay[_selected] ?? const <Task>[];
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TableCalendar<Task>(
            locale: context.lang,
            firstDay: DateTime(now.year - 5),
            lastDay: DateTime(now.year + 10),
            focusedDay: _focused,
            startingDayOfWeek: StartingDayOfWeek.saturday,
            calendarFormat: _view == CalView.week ? CalendarFormat.week : CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: '', CalendarFormat.week: ''},
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
            selectedDayPredicate: (d) => isSameDay(d, _selected),
            eventLoader: (d) => byDay[dx.dateOnly(d)] ?? const [],
            onDaySelected: (sel, foc) => setState(() {
              _selected = dx.dateOnly(sel);
              _focused = foc;
            }),
            onDayLongPressed: (d, _) => addOn(d),
            onPageChanged: (f) => _focused = f,
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.25), shape: BoxShape.circle),
              todayTextStyle: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
              selectedDecoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              outsideDaysVisible: false,
            ),
            calendarBuilders: CalendarBuilders<Task>(
              markerBuilder: (context, day, events) {
                if (events.isEmpty) return null;
                final late = events.any((t) => t.isOverdueAt(now));
                final allDone = events.every((t) => t.isCompleted);
                return Positioned(
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: late ? Colors.red : (allDone ? Colors.green : cs.tertiary),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${events.length}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(children: [
            Expanded(child: Text(fmtDate(context, _selected), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            TextButton.icon(onPressed: () => addOn(_selected), icon: const Icon(Icons.add_rounded), label: Text(context.tr('add_task'))),
          ]),
        ),
      ),
      if (dayTasks.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(context.tr('no_tasks_day'), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          sliver: SliverList.builder(itemCount: dayTasks.length, itemBuilder: (_, i) => TaskTile(task: dayTasks[i])),
        ),
    ]);
  }

  Widget _dayView(BuildContext context, Map<DateTime, List<Task>> byDay) {
    final cs = Theme.of(context).colorScheme;
    final tasks = byDay[_selected] ?? const <Task>[];
    final now = DateTime.now();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          IconButton(
            icon: Icon(context.isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded),
            onPressed: () => setState(() => _selected = _selected.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: InkWell(
              onTap: () async {
                final d = await pickDateTime(context, initial: _selected, withTime: false);
                if (d != null) setState(() => _selected = d);
              },
              child: Text(fmtDate(context, _selected), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          IconButton(
            icon: Icon(context.isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
            onPressed: () => setState(() => _selected = _selected.add(const Duration(days: 1))),
          ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 100),
          itemCount: 24,
          itemBuilder: (_, h) {
            final slot = tasks.where((t) => t.dueDate!.hour == h).toList();
            final isNow = dx.isSameDay(now, _selected) && now.hour == h;
            return InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => TaskEditScreen(initialDue: DateTime(_selected.year, _selected.month, _selected.day, h)))),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 62,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(DateFormat('h a', context.lang).format(DateTime(2000, 1, 1, h)),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: isNow ? cs.primary : cs.onSurfaceVariant, fontWeight: isNow ? FontWeight.w800 : null)),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(children: [for (final t in slot) TaskTile(task: t, swipe: false)]),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _yearView(BuildContext context, Map<DateTime, List<Task>> byDay) {
    final year = _focused.year;
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          icon: Icon(context.isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded),
          onPressed: () => setState(() => _focused = DateTime(year - 1, _focused.month)),
        ),
        Text('$year', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        IconButton(
          icon: Icon(context.isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
          onPressed: () => setState(() => _focused = DateTime(year + 1, _focused.month)),
        ),
      ]),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 700 ? 4 : (c.maxWidth > 420 ? 3 : 2);
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, childAspectRatio: 0.95, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: 12,
            itemBuilder: (_, i) {
              final month = DateTime(year, i + 1);
              final days = DateTime(year, i + 2, 0).day;
              final offset = (month.weekday - DateTime.saturday + 7) % 7;
              var count = 0;
              for (var d = 1; d <= days; d++) {
                count += byDay[DateTime(year, i + 1, d)]?.length ?? 0;
              }
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() {
                    _focused = month;
                    _selected = month;
                    _view = CalView.month;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(children: [
                      Row(children: [
                        Expanded(child: Text(DateFormat('MMMM', context.lang).format(month), style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (count > 0) Pill('$count', cs.primary),
                      ]),
                      const SizedBox(height: 4),
                      Expanded(
                        child: GridView.count(
                          crossAxisCount: 7,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            for (var k = 0; k < offset; k++) const SizedBox(),
                            for (var d = 1; d <= days; d++)
                              Builder(builder: (_) {
                                final n = byDay[DateTime(year, i + 1, d)]?.length ?? 0;
                                final today = dx.isSameDay(DateTime.now(), DateTime(year, i + 1, d));
                                return Container(
                                  margin: const EdgeInsets.all(1),
                                  decoration: BoxDecoration(
                                    color: n == 0 ? null : cs.primary.withValues(alpha: (0.25 + n * 0.15).clamp(0.25, 1.0)),
                                    border: today ? Border.all(color: cs.primary) : null,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text('$d', style: TextStyle(fontSize: 7, color: n > 2 ? Colors.white : null)),
                                );
                              }),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            },
          );
        }),
      ),
    ]);
  }
}
