import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/desktop_files.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/l10n/l10n.dart';
import '../../../data/services/settings_repository.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../profile/profile_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final actions = ref.read(actionsProvider);

    Future<void> upd(AppSettings Function(AppSettings) f, {bool reschedule = false}) async {
      await n.update(f);
      if (reschedule) await actions.rescheduleNotifications();
    }

    Widget group(String title, List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader(title),
          Card(child: Column(children: children)),
        ]);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
        group(context.tr('appearance'), [
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: Text(context.tr('language')),
            trailing: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 'ar', label: Text('العربية')), ButtonSegment(value: 'en', label: Text('English'))],
              selected: {s.languageCode},
              onSelectionChanged: (v) => upd((x) => x.copyWith(languageCode: v.first), reschedule: true),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_rounded),
            title: Text(context.tr('theme')),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: ThemeMode.system, label: Text(context.tr('theme_system')), icon: const Icon(Icons.brightness_auto_rounded)),
                  ButtonSegment(value: ThemeMode.light, label: Text(context.tr('theme_light')), icon: const Icon(Icons.light_mode_rounded)),
                  ButtonSegment(value: ThemeMode.dark, label: Text(context.tr('theme_dark')), icon: const Icon(Icons.dark_mode_rounded)),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => upd((x) => x.copyWith(themeMode: v.first)),
              ),
            ),
          ),
        ]),
        group(context.tr('notifications'), [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_rounded),
            title: Text(context.tr('enable_notifications')),
            value: s.notificationsEnabled,
            onChanged: (v) async {
              if (v) await ref.read(notificationServiceProvider).requestPermissions();
              await upd((x) => x.copyWith(notificationsEnabled: v), reschedule: true);
            },
          ),
          ListTile(
            enabled: s.notificationsEnabled,
            leading: const Icon(Icons.alarm_rounded),
            title: Text(context.tr('default_reminder')),
            trailing: DropdownButton<int>(
              value: s.defaultReminderMinutes,
              underline: const SizedBox(),
              items: [
                for (final m in [0, 5, 10, 15, 30, 60, 120, 1440])
                  DropdownMenuItem(
                    value: m,
                    child: Text(m == 0
                        ? context.tr('at_due_time')
                        : m >= 60
                            ? (m >= 1440 ? context.trf('days_before', {'n': m ~/ 1440}) : context.trf('hours_before', {'n': m ~/ 60}))
                            : context.trf('minutes_before', {'n': m})),
                  ),
              ],
              onChanged: s.notificationsEnabled ? (v) => upd((x) => x.copyWith(defaultReminderMinutes: v)) : null,
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.hourglass_bottom_rounded),
            title: Text(context.tr('deadline_alerts')),
            subtitle: Text(context.trf('deadline_alerts_sub', {'n': s.deadlineHoursBefore})),
            value: s.deadlineAlerts,
            onChanged: s.notificationsEnabled ? (v) => upd((x) => x.copyWith(deadlineAlerts: v), reschedule: true) : null,
          ),
          if (s.deadlineAlerts)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 6, children: [
                for (final h in [1, 3, 6, 12, 24, 48])
                  ChoiceChip(
                    label: Text(context.trf('hours_n', {'n': h})),
                    selected: s.deadlineHoursBefore == h,
                    onSelected: (_) => upd((x) => x.copyWith(deadlineHoursBefore: h), reschedule: true),
                  ),
              ]),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.warning_amber_rounded),
            title: Text(context.tr('overdue_alerts')),
            value: s.overdueAlerts,
            onChanged: s.notificationsEnabled ? (v) => upd((x) => x.copyWith(overdueAlerts: v), reschedule: true) : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wb_sunny_rounded),
            title: Text(context.tr('daily_digest')),
            subtitle: Text(context.trf('daily_digest_sub', {'t': s.digestTime})),
            value: s.dailyDigest,
            onChanged: s.notificationsEnabled ? (v) => upd((x) => x.copyWith(dailyDigest: v), reschedule: true) : null,
          ),
          if (s.dailyDigest)
            ListTile(
              leading: const SizedBox(),
              title: Text(context.tr('digest_time')),
              trailing: Text(s.digestTime, style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: s.digestTimeOfDay);
                if (t != null) {
                  await upd((x) => x.copyWith(digestTime: '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'), reschedule: true);
                }
              },
            ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_rounded),
            title: Text(context.tr('notification_sound')),
            value: s.sound,
            onChanged: s.notificationsEnabled ? (v) => upd((x) => x.copyWith(sound: v), reschedule: true) : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration_rounded),
            title: Text(context.tr('vibration')),
            value: s.vibrate,
            onChanged: s.notificationsEnabled ? (v) => upd((x) => x.copyWith(vibrate: v), reschedule: true) : null,
          ),
          ListTile(
            leading: const Icon(Icons.notification_add_rounded),
            title: Text(context.tr('test_notification')),
            onTap: () async {
              final ar = context.isAr;
              await ref.read(notificationServiceProvider).requestPermissions();
              await ref.read(notificationServiceProvider).showTest(s, ar);
            },
          ),
        ]),
        group(context.tr('account'), [
          ListTile(
            leading: const Icon(Icons.person_rounded),
            title: Text(context.tr('profile')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ]),
        group(context.tr('privacy'), [
          SwitchListTile(
            secondary: const Icon(Icons.login_rounded),
            title: Text(context.tr('keep_signed_in')),
            subtitle: Text(context.tr('keep_signed_in_sub')),
            value: s.keepSignedIn,
            onChanged: (v) => upd((x) => x.copyWith(keepSignedIn: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_rounded),
            title: Text(context.tr('hide_notification_content')),
            value: s.hideNotificationContent,
            onChanged: (v) => upd((x) => x.copyWith(hideNotificationContent: v), reschedule: true),
          ),
          ListTile(
            leading: const Icon(Icons.shield_rounded),
            title: Text(context.tr('privacy_info')),
            subtitle: Text(context.tr('privacy_info_sub')),
          ),
        ]),
        group(context.tr('backup_data'), [
          ListTile(
            leading: const Icon(Icons.backup_rounded),
            title: Text(context.tr('backup_create')),
            subtitle: Text(context.tr('backup_create_sub')),
            onTap: () => guard(context, () async {
              final data = await ref.read(backupRepositoryProvider).export(actions.uid);
              final f = await ref.read(exportServiceProvider).backupJson(data);
              if (!context.mounted) return;
              await shareOrSaveFile(context, f, subject: 'CMD Tasks backup');
            }, successKey: 'backup_done'),
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore_rounded),
            title: Text(context.tr('backup_restore')),
            subtitle: Text(context.tr('backup_restore_sub')),
            onTap: () async {
              final file = await FilePicker.pickFile(type: FileType.any);
              if (file == null || !context.mounted) return;
              if (!await confirm(context, context.tr('backup_restore'), context.tr('backup_restore_confirm'), okKey: 'restore', destructive: true)) return;
              if (!context.mounted) return;
              await guard(context, () async {
                Map<String, dynamic> data;
                try {
                  data = jsonDecode(utf8.decode(await file.xFile.readAsBytes())) as Map<String, dynamic>;
                } catch (e) {
                  throw AppException('err_backup_invalid', e);
                }
                await ref.read(backupRepositoryProvider).restore(actions.uid, data);
                await actions.afterRestore();
              }, successKey: 'restore_done');
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_view_rounded),
            title: Text(context.tr('export_excel')),
            onTap: () => guard(context, () async {
              final tasks = await ref.read(taskRepositoryProvider).getAll(actions.uid, includeArchived: true);
              if (!context.mounted) return;
              final f = await ref.read(exportServiceProvider).tasksExcel(tasks, context.isAr);
              if (!context.mounted) return;
              await shareOrSaveFile(context, f);
            }),
          ),
        ]),
        group(context.tr('about'), [
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(context.tr('app_name')),
            subtitle: Text('v1.0.0 • ${context.tr('about_sub')}'),
          ),
        ]),
      ]),
    );
  }
}
