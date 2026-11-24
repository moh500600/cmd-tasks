import '../../core/utils/date_x.dart';
import '../entities/habit.dart';

class HabitStatsCalculator {
  /// Streak counts consecutive *scheduled* days that were completed, going
  /// back from today (today is allowed to be still pending).
  static HabitStats compute(Habit habit, Set<DateTime> logs, DateTime now) {
    final done = logs.map(dateOnly).toSet();
    final today = dateOnly(now);
    final created = dateOnly(habit.createdAt);
    final earliest = done.isEmpty
        ? created
        : [created, ...done].reduce((a, b) => a.isBefore(b) ? a : b);

    // Current streak.
    var current = 0;
    var day = today;
    if (habit.isActiveOn(today) && !done.contains(today)) {
      day = day.subtract(const Duration(days: 1));
    }
    while (!day.isBefore(earliest)) {
      if (habit.isActiveOn(day)) {
        if (done.contains(day)) {
          current++;
        } else {
          break;
        }
      }
      day = day.subtract(const Duration(days: 1));
    }

    // Best streak.
    var best = 0, run = 0;
    for (var d = earliest; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
      if (!habit.isActiveOn(d)) continue;
      if (done.contains(d)) {
        run++;
        if (run > best) best = run;
      } else if (d != today) {
        run = 0;
      }
    }

    // Monthly rate: done scheduled days / scheduled days so far this month.
    final monthStart = DateTime(today.year, today.month, 1);
    final from = created.isAfter(monthStart) ? created : monthStart;
    var scheduled = 0, hit = 0;
    for (var d = from; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
      if (!habit.isActiveOn(d)) continue;
      scheduled++;
      if (done.contains(d)) hit++;
    }

    return HabitStats(
      currentStreak: current,
      bestStreak: best < current ? current : best,
      monthlyRate: scheduled == 0 ? 0 : hit / scheduled,
      totalDone: done.length,
      doneDays: done,
    );
  }
}
