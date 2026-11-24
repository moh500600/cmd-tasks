import '../../core/utils/date_x.dart';
import '../entities/enums.dart';
import '../entities/task.dart';

class DashboardStats {
  final int total;
  final int completed;
  final int inProgress;
  final int overdue;
  final int notStarted;
  final double dailyRate; // 0..1
  final double weeklyRate; // 0..1
  final int highPriority; // open high + urgent
  final List<Task> upcoming;
  final List<int> completedLast7Days; // index 0 = 6 days ago, 6 = today
  final List<int> createdLast7Days;

  const DashboardStats({
    required this.total,
    required this.completed,
    required this.inProgress,
    required this.overdue,
    required this.notStarted,
    required this.dailyRate,
    required this.weeklyRate,
    required this.highPriority,
    required this.upcoming,
    required this.completedLast7Days,
    required this.createdLast7Days,
  });
}

class PeriodReport {
  final DateTime from;
  final DateTime to; // exclusive
  final int created;
  final int completed;
  final int overdue;
  final Duration? avgCompletionTime;
  final double productivityRate; // completed / (due in period)
  final Map<int, int> completedByWeekday; // weekday(1..7) -> count
  final List<int> completedPerDay; // per day of the period
  final List<Task> completedTasks;

  const PeriodReport({
    required this.from,
    required this.to,
    required this.created,
    required this.completed,
    required this.overdue,
    required this.avgCompletionTime,
    required this.productivityRate,
    required this.completedByWeekday,
    required this.completedPerDay,
    required this.completedTasks,
  });

  int? get bestWeekday {
    if (completedByWeekday.values.every((v) => v == 0)) return null;
    return completedByWeekday.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}

/// Pure statistics functions — no IO, fully unit-testable.
class StatsCalculator {
  static DashboardStats dashboard(List<Task> all, DateTime now) {
    final tasks = all.where((t) => !t.archived).toList();
    final today = dateOnly(now);
    final tomorrow = today.add(const Duration(days: 1));
    final weekStart = startOfWeek(now);
    final weekEnd = weekStart.add(const Duration(days: 7));

    bool dueIn(Task t, DateTime a, DateTime b) =>
        t.dueDate != null && !t.dueDate!.isBefore(a) && t.dueDate!.isBefore(b);

    final dueToday = tasks.where((t) => dueIn(t, today, tomorrow)).toList();
    final dueWeek = tasks.where((t) => dueIn(t, weekStart, weekEnd)).toList();
    double rate(List<Task> l) =>
        l.isEmpty ? 0 : l.where((t) => t.isCompleted).length / l.length;

    final completedPerDay = List<int>.filled(7, 0);
    final createdPerDay = List<int>.filled(7, 0);
    for (final t in tasks) {
      if (t.completedAt != null) {
        final d = today.difference(dateOnly(t.completedAt!)).inDays;
        if (d >= 0 && d < 7) completedPerDay[6 - d]++;
      }
      final c = today.difference(dateOnly(t.createdAt)).inDays;
      if (c >= 0 && c < 7) createdPerDay[6 - c]++;
    }

    final upcoming = tasks
        .where((t) => !t.isCompleted && t.status != TaskStatus.postponed &&
            t.dueDate != null && !t.dueDate!.isBefore(now))
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

    return DashboardStats(
      total: tasks.length,
      completed: tasks.where((t) => t.isCompleted).length,
      inProgress: tasks.where((t) => t.status == TaskStatus.inProgress).length,
      overdue: tasks.where((t) => t.isOverdueAt(now)).length,
      notStarted: tasks.where((t) => t.status == TaskStatus.todo).length,
      dailyRate: rate(dueToday),
      weeklyRate: rate(dueWeek),
      highPriority: tasks
          .where((t) => !t.isCompleted && t.priority.index >= TaskPriority.high.index)
          .length,
      upcoming: upcoming.take(5).toList(),
      completedLast7Days: completedPerDay,
      createdLast7Days: createdPerDay,
    );
  }

  static PeriodReport period(List<Task> all, DateTime from, DateTime to, DateTime now) {
    bool inP(DateTime? d) => d != null && !d.isBefore(from) && d.isBefore(to);
    final completed = all.where((t) => t.isCompleted && inP(t.completedAt)).toList()
      ..sort((a, b) => a.completedAt!.compareTo(b.completedAt!));
    final created = all.where((t) => inP(t.createdAt)).length;
    final overdue = all
        .where((t) => !t.archived && t.isOverdueAt(now) && inP(t.dueDate))
        .length;
    final dueInPeriod = all.where((t) => inP(t.dueDate)).toList();
    final productivity = dueInPeriod.isEmpty
        ? (completed.isEmpty ? 0.0 : 1.0)
        : dueInPeriod.where((t) => t.isCompleted).length / dueInPeriod.length;

    Duration? avg;
    final durations = completed
        .map((t) => t.completedAt!.difference(t.startDate ?? t.createdAt))
        .where((d) => !d.isNegative)
        .toList();
    if (durations.isNotEmpty) {
      final totalMin = durations.fold<int>(0, (s, d) => s + d.inMinutes);
      avg = Duration(minutes: (totalMin / durations.length).round());
    }

    final byWeekday = {for (var i = 1; i <= 7; i++) i: 0};
    final days = dateOnly(to).difference(dateOnly(from)).inDays.clamp(1, 400);
    final perDay = List<int>.filled(days, 0);
    for (final t in completed) {
      byWeekday[t.completedAt!.weekday] = byWeekday[t.completedAt!.weekday]! + 1;
      final idx = dateOnly(t.completedAt!).difference(dateOnly(from)).inDays;
      if (idx >= 0 && idx < days) perDay[idx]++;
    }

    return PeriodReport(
      from: from,
      to: to,
      created: created,
      completed: completed.length,
      overdue: overdue,
      avgCompletionTime: avg,
      productivityRate: productivity,
      completedByWeekday: byWeekday,
      completedPerDay: perDay,
      completedTasks: completed,
    );
  }

  /// Relative change in percent between two values (null when base is 0).
  static double? change(num current, num previous) =>
      previous == 0 ? null : ((current - previous) / previous) * 100;
}
