import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/platform/platform_support.dart';

import '../../domain/entities/habit.dart';
import '../../domain/entities/task.dart';
import 'settings_repository.dart';

/// Local notifications: due reminders, deadline approaching, overdue alerts,
/// a daily digest and habit reminders. Everything is scheduled on-device.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _exact = false;

  static const _digestId = 2000000000;
  static int _taskId(int taskId, int kind) => taskId * 10 + kind; // kind 1..3
  static int _habitId(int habitId, int weekday) => 1000000000 + habitId * 10 + weekday;

  Future<void> init() async {
    if (_ready) return;
    if (!_desktopNotificationsAvailable) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(_guessLocation());
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_stat_notify'),
          // iOS: permission is asked from Settings → Notifications (requestPermissions).
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          // Desktop (Windows toasts / Linux libnotify).
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(
            appName: 'CMD Tasks',
            appUserModelId: 'MohammadNidal.TasksPro',
            guid: 'a3b9e1c7-4d2f-4e8a-b6c5-9f0d1e2a3b4c',
          ),
        ),
      );
      _ready = true;
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      _exact = await android?.canScheduleExactNotifications() ?? false;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// Picks an IANA zone matching the device's current offset/abbreviation
  /// (e.g. Asia/Aden for Yemen) so daily repeats fire at local wall time.
  static tz.Location _guessLocation() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final abbr = now.timeZoneName;
    tz.Location? byOffset;
    for (final loc in tz.timeZoneDatabase.locations.values) {
      final z = loc.currentTimeZone;
      if (z.offset == offset) {
        if (z.abbreviation == abbr) return loc;
        byOffset ??= loc;
      }
    }
    if (offset == const Duration(hours: 3)) return tz.getLocation('Asia/Aden');
    return byOffset ?? tz.UTC;
  }

  /// Desktop note: Windows shows scheduled toasts but does not repeat them, so
  /// a repeating reminder is scheduled as its next occurrence (the app
  /// re-plans reminders every time it starts). Linux has no scheduled
  /// notifications at all, so only immediate ones are shown there.
  static DateTime nextOccurrence(DateTime when, DateTimeComponents? repeat, DateTime now) {
    if (repeat == null || when.isAfter(now)) return when;
    var at = when;
    switch (repeat) {
      case DateTimeComponents.time:
        at = DateTime(now.year, now.month, now.day, when.hour, when.minute, when.second);
        if (!at.isAfter(now)) at = DateTime(now.year, now.month, now.day + 1, when.hour, when.minute, when.second);
      case DateTimeComponents.dayOfWeekAndTime:
        at = DateTime(now.year, now.month, now.day, when.hour, when.minute, when.second);
        while (at.weekday != when.weekday || !at.isAfter(now)) {
          at = DateTime(at.year, at.month, at.day + 1, when.hour, when.minute, when.second);
        }
      case DateTimeComponents.dayOfMonthAndTime:
        var m = now.month;
        var y = now.year;
        for (var i = 0; i < 24; i++) {
          final c = DateTime(y, m, when.day, when.hour, when.minute, when.second);
          if (c.month == ((m - 1) % 12) + 1 && c.isAfter(now)) return c;
          m++;
          if (m > 12) {
            m = 1;
            y++;
          }
        }
      case DateTimeComponents.dateAndTime:
        at = DateTime(now.year, when.month, when.day, when.hour, when.minute, when.second);
        if (!at.isAfter(now)) at = DateTime(now.year + 1, when.month, when.day, when.hour, when.minute, when.second);
    }
    return at;
  }

  /// Linux desktop notifications need a D-Bus session (any normal desktop has
  /// one). Without it (e.g. a headless/remote session) notifications are
  /// skipped instead of throwing.
  static bool get _desktopNotificationsAvailable {
    if (!PlatformSupport.isLinux) return true;
    final env = Platform.environment;
    if ((env['DBUS_SESSION_BUS_ADDRESS'] ?? '').isNotEmpty) return true;
    final runtime = env['XDG_RUNTIME_DIR'];
    return runtime != null && File('$runtime/bus').existsSync();
  }

  Future<bool> requestPermissions() async {
    await init();
    if (!_ready) return false;
    try {
      return await _requestPermissions();
    } catch (e) {
      debugPrint('permission request failed: $e');
      return false;
    }
  }

  Future<bool> _requestPermissions() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final granted = await android.requestNotificationsPermission() ?? false;
    try {
      _exact = await android.canScheduleExactNotifications() ?? false;
      if (!_exact) {
        await android.requestExactAlarmsPermission();
        _exact = await android.canScheduleExactNotifications() ?? false;
      }
    } catch (_) {
      _exact = false;
    }
    return granted;
  }

  NotificationDetails _details(AppSettings s, {String channel = 'tasks'}) {
    final sound = s.sound;
    final id = '${channel}_${sound ? 's' : 'm'}${s.vibrate ? 'v' : ''}';
    return NotificationDetails(
      android: AndroidNotificationDetails(
        id,
        channel == 'habits' ? 'Habits / العادات' : 'Tasks / المهام',
        channelDescription: 'CMD Tasks reminders',
        importance: Importance.high,
        priority: Priority.high,
        playSound: sound,
        enableVibration: s.vibrate,
        visibility: s.hideNotificationContent ? NotificationVisibility.private : NotificationVisibility.public,
      ),
    );
  }

  AndroidScheduleMode get _mode =>
      _exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;

  Future<void> _schedule(
    int id,
    DateTime when,
    String title,
    String body,
    AppSettings s, {
    String channel = 'tasks',
    DateTimeComponents? match,
  }) async {
    if (!_ready) return;
    if (!PlatformSupport.scheduledNotifications) return; // Linux: immediate notifications only
    final osRepeats = PlatformSupport.repeatingNotifications;
    if (!osRepeats) when = nextOccurrence(when, match, DateTime.now());
    try {
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: _details(s, channel: channel),
        androidScheduleMode: _mode,
        title: title,
        body: body,
        matchDateTimeComponents: osRepeats ? match : null,
      );
    } catch (e) {
      debugPrint('schedule failed: $e');
    }
  }

  Future<void> cancelTask(int taskId) async {
    if (!_ready) return;
    try {
      for (var k = 1; k <= 3; k++) {
        await _plugin.cancel(id: _taskId(taskId, k));
      }
    } catch (e) {
      debugPrint('cancel failed: $e');
    }
  }

  Future<void> scheduleTask(Task t, AppSettings s, bool ar) async {
    if (t.id == null) return;
    await cancelTask(t.id!);
    if (!s.notificationsEnabled || t.archived || t.isCompleted || t.dueDate == null) return;
    final now = DateTime.now();
    final due = t.dueDate!;
    final title = s.hideNotificationContent ? (ar ? 'مهمة' : 'Task') : t.title;
    if (t.reminderMinutes != null) {
      final at = due.subtract(Duration(minutes: t.reminderMinutes!));
      if (at.isAfter(now)) {
        await _schedule(
          _taskId(t.id!, 1),
          at,
          '⏰ $title',
          t.reminderMinutes == 0
              ? (ar ? 'حان موعد المهمة' : 'Task is due now')
              : (ar ? 'موعد المهمة بعد ${t.reminderMinutes} دقيقة' : 'Due in ${t.reminderMinutes} minutes'),
          s,
        );
      }
    }
    if (s.deadlineAlerts) {
      final at = due.subtract(Duration(hours: s.deadlineHoursBefore));
      if (at.isAfter(now)) {
        await _schedule(
          _taskId(t.id!, 2),
          at,
          '⌛ $title',
          ar
              ? 'الموعد النهائي يقترب (${s.deadlineHoursBefore} ساعة)'
              : 'Deadline approaching (${s.deadlineHoursBefore}h)',
          s,
        );
      }
    }
    if (s.overdueAlerts) {
      final at = due.add(const Duration(minutes: 1));
      if (at.isAfter(now)) {
        await _schedule(
          _taskId(t.id!, 3),
          at,
          '⚠️ $title',
          ar ? 'المهمة متأخرة عن موعدها' : 'This task is now overdue',
          s,
        );
      }
    }
  }

  Future<void> scheduleDigest(AppSettings s, bool ar, {required int todayCount, required int overdueCount}) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _digestId);
    } catch (_) {
      return;
    }
    if (!s.notificationsEnabled || !s.dailyDigest) return;
    final t = s.digestTimeOfDay;
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    await _schedule(
      _digestId,
      at,
      ar ? '☀️ مهامك اليوم' : '☀️ Your day',
      ar
          ? 'افتح التطبيق لرؤية مهام اليوم${overdueCount > 0 ? ' — عندك $overdueCount متأخرة' : ''}'
          : 'Open the app to see today\'s tasks${overdueCount > 0 ? ' — $overdueCount overdue' : ''}',
      s,
      match: DateTimeComponents.time,
    );
  }

  Future<void> cancelHabit(int habitId) async {
    if (!_ready) return;
    try {
      for (var d = 1; d <= 7; d++) {
        await _plugin.cancel(id: _habitId(habitId, d));
      }
    } catch (e) {
      debugPrint('cancel failed: $e');
    }
  }

  Future<void> scheduleHabit(Habit h, AppSettings s, bool ar) async {
    if (h.id == null) return;
    await cancelHabit(h.id!);
    if (!s.notificationsEnabled || h.archived || h.reminderTime == null) return;
    final p = h.reminderTime!.split(':').map(int.parse).toList();
    final now = DateTime.now();
    for (var wd = 1; wd <= 7; wd++) {
      if ((h.daysMask & (1 << (wd - 1))) == 0) continue;
      var at = DateTime(now.year, now.month, now.day, p[0], p[1]);
      while (at.weekday != wd || !at.isAfter(now)) {
        at = at.add(const Duration(days: 1));
      }
      await _schedule(
        _habitId(h.id!, wd),
        at,
        '🔁 ${h.name}',
        ar ? 'وقت عادتك اليومية' : 'Time for your habit',
        s,
        channel: 'habits',
        match: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  Future<void> rescheduleAll(
    List<Task> tasks,
    List<Habit> habits,
    AppSettings s,
    bool ar, {
    required int todayCount,
    required int overdueCount,
  }) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      return;
    }
    if (!s.notificationsEnabled) return;
    final horizon = DateTime.now().add(const Duration(days: 60));
    for (final t in tasks) {
      if (t.dueDate != null && t.dueDate!.isBefore(horizon)) await scheduleTask(t, s, ar);
    }
    for (final h in habits) {
      await scheduleHabit(h, s, ar);
    }
    await scheduleDigest(s, ar, todayCount: todayCount, overdueCount: overdueCount);
  }

  Future<void> cancelAll() async {
    try {
      if (_ready) await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<void> showTest(AppSettings s, bool ar) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: 1,
        title: ar ? '🔔 تجربة الإشعارات' : '🔔 Test notification',
        body: ar ? 'الإشعارات تعمل بشكل صحيح ✅' : 'Notifications are working ✅',
        notificationDetails: _details(s),
      );
    } catch (e) {
      debugPrint('show failed: $e');
    }
  }
}
