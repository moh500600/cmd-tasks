import '../../core/utils/date_x.dart';
import '../entities/enums.dart';
import '../entities/task.dart';

/// Pure rules deciding which section a task belongs to.
class TaskSections {
  static bool matches(Task t, TaskSection s, DateTime now) {
    final today = dateOnly(now);
    final tomorrow = today.add(const Duration(days: 1));
    final due = t.dueDate;
    final open = !t.isCompleted && t.status != TaskStatus.postponed;
    switch (s) {
      case TaskSection.archived:
        return t.archived;
      case TaskSection.all:
        return !t.archived;
      default:
        if (t.archived) return false;
    }
    switch (s) {
      case TaskSection.today:
        return open &&
            due != null &&
            (isSameDay(due, today) ||
                (t.startDate != null &&
                    !dateOnly(t.startDate!).isAfter(today) &&
                    !dateOnly(due).isBefore(today)));
      case TaskSection.tomorrow:
        return open && due != null && isSameDay(due, tomorrow);
      case TaskSection.thisWeek:
        final end = today.add(const Duration(days: 7));
        return open &&
            due != null &&
            !dateOnly(due).isBefore(today) &&
            dateOnly(due).isBefore(end);
      case TaskSection.upcoming:
        return open && (due == null || !due.isBefore(now));
      case TaskSection.overdue:
        return t.isOverdueAt(now);
      case TaskSection.completed:
        return t.isCompleted;
      case TaskSection.postponed:
        return t.status == TaskStatus.postponed;
      case TaskSection.archived:
      case TaskSection.all:
        return true;
    }
  }

  static List<Task> filter(List<Task> tasks, TaskSection s, DateTime now) {
    final list = tasks.where((t) => matches(t, s, now)).toList();
    if (s == TaskSection.completed) {
      list.sort((a, b) => (b.completedAt ?? b.updatedAt)
          .compareTo(a.completedAt ?? a.updatedAt));
    } else {
      list.sort(compareDefault);
    }
    return list;
  }

  /// Due date ascending (no date last), then priority descending.
  static int compareDefault(Task a, Task b) {
    final ad = a.dueDate, bd = b.dueDate;
    if (ad == null && bd != null) return 1;
    if (ad != null && bd == null) return -1;
    if (ad != null && bd != null) {
      final c = ad.compareTo(bd);
      if (c != 0) return c;
    }
    return b.priority.index.compareTo(a.priority.index);
  }
}
