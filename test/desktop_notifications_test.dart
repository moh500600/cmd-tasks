// Windows does not repeat scheduled toasts, so repeating reminders are
// scheduled as their next occurrence. These checks pin that maths down.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_pro/data/services/notification_service.dart';

void main() {
  final now = DateTime(2026, 11, 2, 21, 0); // Monday 21:00

  test('one-shot in the future is unchanged', () {
    final w = DateTime(2026, 11, 3, 9, 0);
    expect(NotificationService.nextOccurrence(w, null, now), w);
  });

  test('daily: past time today moves to tomorrow', () {
    expect(NotificationService.nextOccurrence(DateTime(2026, 10, 1, 8, 30), DateTimeComponents.time, now),
        DateTime(2026, 11, 3, 8, 30));
  });

  test('weekly: keeps the weekday', () {
    // 2026-10-28 is a Wednesday.
    final r = NotificationService.nextOccurrence(DateTime(2026, 10, 28, 10, 0), DateTimeComponents.dayOfWeekAndTime, now);
    expect(r, DateTime(2026, 11, 4, 10, 0));
    expect(r.weekday, DateTime.wednesday);
  });

  test('monthly: same day next month, skipping short months', () {
    expect(NotificationService.nextOccurrence(DateTime(2026, 1, 1, 9, 0), DateTimeComponents.dayOfMonthAndTime, now),
        DateTime(2026, 12, 1, 9, 0));
    expect(NotificationService.nextOccurrence(DateTime(2026, 1, 31, 9, 0), DateTimeComponents.dayOfMonthAndTime, now),
        DateTime(2026, 12, 31, 9, 0));
  });

  test('yearly: next anniversary', () {
    expect(NotificationService.nextOccurrence(DateTime(2025, 3, 15, 9, 0), DateTimeComponents.dateAndTime, now),
        DateTime(2027, 3, 15, 9, 0));
  });
}
