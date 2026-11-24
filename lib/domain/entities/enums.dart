/// Task priority levels (stored as int in the DB).
enum TaskPriority {
  low,
  medium,
  high,
  urgent;

  static TaskPriority fromIndex(int? i) =>
      TaskPriority.values[(i ?? 1).clamp(0, TaskPriority.values.length - 1)];
}

/// Task lifecycle status (stored as text in the DB).
enum TaskStatus {
  todo,
  inProgress,
  completed,
  postponed;

  static TaskStatus fromName(String? n) => TaskStatus.values.firstWhere(
        (e) => e.name == n,
        orElse: () => TaskStatus.todo,
      );
}

/// Repeat rule for recurring tasks / reminders.
enum RepeatRule {
  none,
  daily,
  weekly,
  monthly;

  static RepeatRule fromName(String? n) => RepeatRule.values.firstWhere(
        (e) => e.name == n,
        orElse: () => RepeatRule.none,
      );

  DateTime? next(DateTime? from) {
    if (from == null) return null;
    switch (this) {
      case RepeatRule.none:
        return null;
      case RepeatRule.daily:
        return from.add(const Duration(days: 1));
      case RepeatRule.weekly:
        return from.add(const Duration(days: 7));
      case RepeatRule.monthly:
        final m = from.month == 12 ? 1 : from.month + 1;
        final y = from.month == 12 ? from.year + 1 : from.year;
        final lastDay = DateTime(y, m + 1, 0).day;
        return DateTime(y, m, from.day > lastDay ? lastDay : from.day,
            from.hour, from.minute);
    }
  }
}

enum ProjectStatus {
  planning,
  active,
  onHold,
  completed;

  static ProjectStatus fromName(String? n) => ProjectStatus.values.firstWhere(
        (e) => e.name == n,
        orElse: () => ProjectStatus.active,
      );
}

enum AttachmentType {
  file,
  image,
  link;

  static AttachmentType fromName(String? n) => AttachmentType.values
      .firstWhere((e) => e.name == n, orElse: () => AttachmentType.file);
}

/// The 9 organisational sections required by the spec.
enum TaskSection {
  today,
  tomorrow,
  thisWeek,
  upcoming,
  overdue,
  completed,
  postponed,
  archived,
  all,
}

enum TaskSort {
  dueDate,
  priority,
  createdAt,
  title,
  progress,
}
