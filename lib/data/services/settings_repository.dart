import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final String languageCode; // 'ar' | 'en'
  final ThemeMode themeMode;
  final bool notificationsEnabled;
  final int defaultReminderMinutes;
  final bool deadlineAlerts;
  final int deadlineHoursBefore;
  final bool overdueAlerts;
  final bool dailyDigest;
  final String digestTime; // HH:mm
  final bool sound;
  final bool vibrate;
  final bool keepSignedIn;
  final bool hideNotificationContent;

  const AppSettings({
    this.languageCode = 'ar',
    this.themeMode = ThemeMode.system,
    this.notificationsEnabled = true,
    this.defaultReminderMinutes = 15,
    this.deadlineAlerts = true,
    this.deadlineHoursBefore = 24,
    this.overdueAlerts = true,
    this.dailyDigest = true,
    this.digestTime = '08:00',
    this.sound = true,
    this.vibrate = true,
    this.keepSignedIn = true,
    this.hideNotificationContent = false,
  });

  TimeOfDay get digestTimeOfDay {
    final p = digestTime.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  AppSettings copyWith({
    String? languageCode,
    ThemeMode? themeMode,
    bool? notificationsEnabled,
    int? defaultReminderMinutes,
    bool? deadlineAlerts,
    int? deadlineHoursBefore,
    bool? overdueAlerts,
    bool? dailyDigest,
    String? digestTime,
    bool? sound,
    bool? vibrate,
    bool? keepSignedIn,
    bool? hideNotificationContent,
  }) =>
      AppSettings(
        languageCode: languageCode ?? this.languageCode,
        themeMode: themeMode ?? this.themeMode,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        defaultReminderMinutes: defaultReminderMinutes ?? this.defaultReminderMinutes,
        deadlineAlerts: deadlineAlerts ?? this.deadlineAlerts,
        deadlineHoursBefore: deadlineHoursBefore ?? this.deadlineHoursBefore,
        overdueAlerts: overdueAlerts ?? this.overdueAlerts,
        dailyDigest: dailyDigest ?? this.dailyDigest,
        digestTime: digestTime ?? this.digestTime,
        sound: sound ?? this.sound,
        vibrate: vibrate ?? this.vibrate,
        keepSignedIn: keepSignedIn ?? this.keepSignedIn,
        hideNotificationContent: hideNotificationContent ?? this.hideNotificationContent,
      );
}

class SettingsRepository {
  final SharedPreferences prefs;
  SettingsRepository(this.prefs);

  static const _session = 'session_user_id';

  AppSettings load() {
    const d = AppSettings();
    return AppSettings(
      languageCode: prefs.getString('lang') ?? d.languageCode,
      themeMode: ThemeMode.values[prefs.getInt('theme') ?? d.themeMode.index],
      notificationsEnabled: prefs.getBool('notif') ?? d.notificationsEnabled,
      defaultReminderMinutes: prefs.getInt('remind_default') ?? d.defaultReminderMinutes,
      deadlineAlerts: prefs.getBool('deadline_alerts') ?? d.deadlineAlerts,
      deadlineHoursBefore: prefs.getInt('deadline_hours') ?? d.deadlineHoursBefore,
      overdueAlerts: prefs.getBool('overdue_alerts') ?? d.overdueAlerts,
      dailyDigest: prefs.getBool('digest') ?? d.dailyDigest,
      digestTime: prefs.getString('digest_time') ?? d.digestTime,
      sound: prefs.getBool('sound') ?? d.sound,
      vibrate: prefs.getBool('vibrate') ?? d.vibrate,
      keepSignedIn: prefs.getBool('keep_signed_in') ?? d.keepSignedIn,
      hideNotificationContent: prefs.getBool('hide_content') ?? d.hideNotificationContent,
    );
  }

  Future<void> save(AppSettings s) async {
    await prefs.setString('lang', s.languageCode);
    await prefs.setInt('theme', s.themeMode.index);
    await prefs.setBool('notif', s.notificationsEnabled);
    await prefs.setInt('remind_default', s.defaultReminderMinutes);
    await prefs.setBool('deadline_alerts', s.deadlineAlerts);
    await prefs.setInt('deadline_hours', s.deadlineHoursBefore);
    await prefs.setBool('overdue_alerts', s.overdueAlerts);
    await prefs.setBool('digest', s.dailyDigest);
    await prefs.setString('digest_time', s.digestTime);
    await prefs.setBool('sound', s.sound);
    await prefs.setBool('vibrate', s.vibrate);
    await prefs.setBool('keep_signed_in', s.keepSignedIn);
    await prefs.setBool('hide_content', s.hideNotificationContent);
  }

  int? get sessionUserId => prefs.getInt(_session);
  Future<void> setSession(int? id) async =>
      id == null ? prefs.remove(_session) : prefs.setInt(_session, id);
}
