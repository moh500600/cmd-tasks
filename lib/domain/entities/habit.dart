class Habit {
  final int? id;
  final int userId;
  final String name;
  final String description;
  final int iconCode;
  final int color;

  /// Bit mask of active weekdays: bit (weekday-1), Monday=bit0 ... Sunday=bit6.
  final int daysMask;

  /// 'HH:mm' or null.
  final String? reminderTime;
  final bool archived;
  final DateTime createdAt;

  const Habit({
    this.id,
    required this.userId,
    required this.name,
    this.description = '',
    this.iconCode = 0xe5ca, // Icons.check
    this.color = 0xFF16A34A,
    this.daysMask = 0x7F,
    this.reminderTime,
    this.archived = false,
    required this.createdAt,
  });

  bool isActiveOn(DateTime day) => (daysMask & (1 << (day.weekday - 1))) != 0;

  Habit copyWith({
    int? id,
    String? name,
    String? description,
    int? iconCode,
    int? color,
    int? daysMask,
    String? reminderTime,
    bool clearReminder = false,
    bool? archived,
  }) =>
      Habit(
        id: id ?? this.id,
        userId: userId,
        name: name ?? this.name,
        description: description ?? this.description,
        iconCode: iconCode ?? this.iconCode,
        color: color ?? this.color,
        daysMask: daysMask ?? this.daysMask,
        reminderTime: clearReminder ? null : (reminderTime ?? this.reminderTime),
        archived: archived ?? this.archived,
        createdAt: createdAt,
      );
}

/// Computed statistics for one habit.
class HabitStats {
  final int currentStreak;
  final int bestStreak;
  final double monthlyRate; // 0..1 for current month (scheduled days so far)
  final int totalDone;
  final Set<DateTime> doneDays; // date-only values

  const HabitStats({
    required this.currentStreak,
    required this.bestStreak,
    required this.monthlyRate,
    required this.totalDone,
    required this.doneDays,
  });
}
