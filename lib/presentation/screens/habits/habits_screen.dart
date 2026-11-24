import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/date_x.dart' as dx;
import '../../../core/utils/validators.dart';
import '../../../domain/entities/habit.dart';
import '../../../domain/services/habit_stats_calculator.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider);
    final logs = ref.watch(habitLogsProvider).value ?? const {};
    final today = dx.dateOnly(DateTime.now());
    return AsyncView<List<Habit>>(
      value: habits,
      builder: (list) {
        if (list.isEmpty) return EmptyState(icon: Icons.self_improvement_rounded, text: context.tr('no_habits'));
        final scheduledToday = list.where((h) => h.isActiveOn(today)).toList();
        final doneToday = scheduledToday.where((h) => logs[h.id]?.contains(today) ?? false).length;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: scheduledToday.isEmpty ? 0 : doneToday / scheduledToday.length,
                        strokeWidth: 6,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.green.withValues(alpha: 0.15),
                        color: Colors.green,
                      ),
                    ),
                    Text('$doneToday/${scheduledToday.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(context.tr('habits_today_progress'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          for (final h in list) _HabitTile(habit: h, logs: logs[h.id] ?? const {}),
        ]);
      },
    );
  }
}

class _HabitTile extends ConsumerWidget {
  final Habit habit;
  final Set<DateTime> logs;
  const _HabitTile({required this.habit, required this.logs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = dx.dateOnly(now);
    final stats = HabitStatsCalculator.compute(habit, logs, now);
    final color = Color(habit.color);
    final done = logs.contains(today);
    final active = habit.isActiveOn(today);
    // last 7 days strip
    final days = [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: habit.id!))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                  child: Icon(iconFromCode(habit.iconCode), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(habit.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, children: [
                      Pill('🔥 ${stats.currentStreak}', Colors.deepOrange),
                      Pill('${(stats.monthlyRate * 100).round()}% ${context.tr('this_month')}', color),
                    ]),
                  ]),
                ),
                AnimatedScale(
                  scale: done ? 1.1 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: done ? Colors.green : color.withValues(alpha: active ? 0.2 : 0.07)),
                    onPressed: () => guard(context, () => ref.read(actionsProvider).toggleHabit(habit, today)),
                    icon: Icon(done ? Icons.check_rounded : Icons.circle_outlined, color: done ? Colors.white : color),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                for (final d in days)
                  Expanded(
                    child: Column(children: [
                      Text(DateFormat('EEEEE', context.lang).format(d), style: const TextStyle(fontSize: 10)),
                      const SizedBox(height: 3),
                      Container(
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: logs.contains(d)
                              ? Colors.green
                              : (habit.isActiveOn(d) ? color.withValues(alpha: 0.15) : Colors.transparent),
                          borderRadius: BorderRadius.circular(4),
                          border: habit.isActiveOn(d) ? null : Border.all(color: Theme.of(context).dividerColor),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class HabitDetailScreen extends ConsumerStatefulWidget {
  final int habitId;
  const HabitDetailScreen({super.key, required this.habitId});

  @override
  ConsumerState<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends ConsumerState<HabitDetailScreen> {
  DateTime _focused = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final habits = ref.watch(habitsProvider).value ?? const [];
    final habit = habits.where((h) => h.id == widget.habitId).firstOrNull;
    final logs = ref.watch(habitLogsProvider).value?[widget.habitId] ?? const <DateTime>{};
    if (habit == null) return Scaffold(appBar: AppBar(), body: const SizedBox());
    final stats = HabitStatsCalculator.compute(habit, logs, DateTime.now());
    final color = Color(habit.color);
    final cs = Theme.of(context).colorScheme;
    Widget stat(String label, String v, IconData icon) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Icon(icon, color: color),
                const SizedBox(height: 4),
                Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(habit.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HabitEditScreen(initial: habit))),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              if (await confirm(context, context.tr('delete_habit'), context.tr('delete_habit_confirm'), okKey: 'delete', destructive: true)) {
                if (!context.mounted) return;
                final ok = await guard(context, () => ref.read(actionsProvider).deleteHabit(habit), successKey: 'deleted_msg');
                if (ok && context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (habit.description.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(habit.description)),
        Row(children: [
          stat(context.tr('current_streak'), '${stats.currentStreak}', Icons.local_fire_department_rounded),
          const SizedBox(width: 8),
          stat(context.tr('best_streak'), '${stats.bestStreak}', Icons.emoji_events_rounded),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          stat(context.tr('monthly_rate'), '${(stats.monthlyRate * 100).round()}%', Icons.percent_rounded),
          const SizedBox(width: 8),
          stat(context.tr('total_done'), '${stats.totalDone}', Icons.check_circle_rounded),
        ]),
        SectionHeader(context.tr('habit_calendar')),
        Card(
          child: TableCalendar(
            locale: context.lang,
            firstDay: DateTime(2020),
            lastDay: DateTime.now(),
            focusedDay: _focused.isAfter(DateTime.now()) ? DateTime.now() : _focused,
            startingDayOfWeek: StartingDayOfWeek.saturday,
            availableCalendarFormats: const {CalendarFormat.month: ''},
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
            onPageChanged: (f) => _focused = f,
            onDaySelected: (d, f) {
              _focused = f;
              guard(context, () => ref.read(actionsProvider).toggleHabit(habit, d));
            },
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, _) => _cell(day, logs, habit, color, cs),
              todayBuilder: (context, day, _) => _cell(day, logs, habit, color, cs, today: true),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(context.tr('habit_calendar_hint'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _cell(DateTime day, Set<DateTime> logs, Habit h, Color color, ColorScheme cs, {bool today = false}) {
    final done = logs.contains(dx.dateOnly(day));
    final active = h.isActiveOn(day);
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: done ? Colors.green : (active ? color.withValues(alpha: 0.08) : null),
        shape: BoxShape.circle,
        border: today ? Border.all(color: cs.primary, width: 2) : null,
      ),
      alignment: Alignment.center,
      child: Text('${day.day}', style: TextStyle(color: done ? Colors.white : (active ? null : cs.onSurfaceVariant.withValues(alpha: 0.5)))),
    );
  }
}

class HabitEditScreen extends ConsumerStatefulWidget {
  final Habit? initial;
  const HabitEditScreen({super.key, this.initial});

  @override
  ConsumerState<HabitEditScreen> createState() => _HabitEditScreenState();
}

class _HabitEditScreenState extends ConsumerState<HabitEditScreen> {
  final _form = GlobalKey<FormState>();
  late Habit _h;
  late final TextEditingController _name, _desc;

  @override
  void initState() {
    super.initState();
    _h = widget.initial ??
        Habit(userId: ref.read(sessionProvider)!.id, name: '', iconCode: Icons.check_circle_rounded.codePoint, createdAt: DateTime.now());
    _name = TextEditingController(text: _h.name);
    _desc = TextEditingController(text: _h.description);
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_h.daysMask == 0) {
      showSnack(context, context.tr('v_days'), error: true);
      return;
    }
    final ok = await guard(context, () => ref.read(actionsProvider).saveHabit(_h.copyWith(name: _name.text, description: _desc.text)),
        successKey: 'saved_msg');
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Display order Saturday → Friday; bit index = weekday - 1.
    const order = [6, 7, 1, 2, 3, 4, 5];
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(_h.id == null ? 'new_habit' : 'edit_habit')),
        actions: [TextButton(onPressed: _save, child: Text(context.tr('save')))],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _name,
            autofocus: _h.id == null,
            decoration: InputDecoration(labelText: context.tr('habit_name'), prefixIcon: const Icon(Icons.self_improvement_rounded)),
            validator: (v) {
              final e = Validators.title(v);
              return e == null ? null : context.tr(e);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _desc, decoration: InputDecoration(labelText: context.tr('description'))),
          SectionHeader(context.tr('repeat_days')),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final wd in order)
              FilterChip(
                label: Text(DateFormat('EEE', context.lang).format(DateTime(2024, 1, wd))),
                selected: (_h.daysMask & (1 << (wd - 1))) != 0,
                onSelected: (v) => setState(() => _h = _h.copyWith(daysMask: v ? _h.daysMask | (1 << (wd - 1)) : _h.daysMask & ~(1 << (wd - 1)))),
              ),
          ]),
          Row(children: [
            TextButton(onPressed: () => setState(() => _h = _h.copyWith(daysMask: 0x7F)), child: Text(context.tr('every_day'))),
          ]),
          SectionHeader(context.tr('reminder')),
          Card(
            child: ListTile(
              leading: const Icon(Icons.alarm_rounded),
              title: Text(_h.reminderTime ?? context.tr('no_reminder')),
              trailing: _h.reminderTime == null
                  ? const Icon(Icons.add_rounded)
                  : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _h = _h.copyWith(clearReminder: true))),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
                if (t != null) {
                  setState(() => _h = _h.copyWith(
                      reminderTime: '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'));
                }
              },
            ),
          ),
          SectionHeader(context.tr('color')),
          ColorPickerRow(value: _h.color, onChanged: (c) => setState(() => _h = _h.copyWith(color: c))),
          SectionHeader(context.tr('icon')),
          IconPickerRow(value: _h.iconCode, color: _h.color, onChanged: (i) => setState(() => _h = _h.copyWith(iconCode: i))),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded), label: Text(context.tr('save'))),
        ]),
      ),
    );
  }
}
