import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/enums.dart';

String priorityLabel(BuildContext c, TaskPriority p) => c.tr('prio_${p.name}');
String statusLabel(BuildContext c, TaskStatus s) => c.tr('status_${s.name}');
String sectionLabel(BuildContext c, TaskSection s) => c.tr('sec_${s.name}');
String projectStatusLabel(BuildContext c, ProjectStatus s) => c.tr('pstatus_${s.name}');
String repeatLabel(BuildContext c, RepeatRule r) => c.tr('repeat_${r.name}');

Color priorityColor(TaskPriority p) => AppTheme.priorityColors[p.index];
Color statusColor(TaskStatus s) => AppTheme.statusColors[s.name]!;

IconData sectionIcon(TaskSection s) => switch (s) {
      TaskSection.today => Icons.today_rounded,
      TaskSection.tomorrow => Icons.wb_twilight_rounded,
      TaskSection.thisWeek => Icons.date_range_rounded,
      TaskSection.upcoming => Icons.upcoming_rounded,
      TaskSection.overdue => Icons.warning_amber_rounded,
      TaskSection.completed => Icons.check_circle_rounded,
      TaskSection.postponed => Icons.pause_circle_rounded,
      TaskSection.archived => Icons.archive_rounded,
      TaskSection.all => Icons.list_alt_rounded,
    };

String fmtDate(BuildContext c, DateTime d) => DateFormat('EEE d MMM yyyy', c.lang).format(d);
String fmtShortDate(BuildContext c, DateTime d) => DateFormat('d MMM', c.lang).format(d);
String fmtTime(BuildContext c, DateTime d) => DateFormat('h:mm a', c.lang).format(d);
String fmtDateTime(BuildContext c, DateTime d) => DateFormat('EEE d MMM – h:mm a', c.lang).format(d);

String errorText(BuildContext c, Object e) {
  if (e is AppException) return c.tr(e.code);
  return c.tr('err_generic');
}

void showSnack(BuildContext c, String msg, {bool error = false}) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Theme.of(c).colorScheme.error : null,
    ));
}

/// Runs [fn], shows a translated error on failure and an optional success
/// message. Returns true on success.
Future<bool> guard(BuildContext context, Future<void> Function() fn, {String? successKey}) async {
  try {
    await fn();
    if (successKey != null && context.mounted) showSnack(context, context.tr(successKey));
    return true;
  } catch (e, st) {
    debugPrint('guard error: $e\n$st');
    if (context.mounted) showSnack(context, errorText(context, e), error: true);
    return false;
  }
}

Future<bool> confirm(BuildContext c, String title, String body, {String? okKey, bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.tr(okKey ?? 'ok')),
        ),
      ],
    ),
  );
  return r ?? false;
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.5), shape: BoxShape.circle),
            child: Icon(icon, size: 44, color: cs.primary),
          ),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class AsyncView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  const AsyncView({super.key, required this.value, required this.builder});

  @override
  Widget build(BuildContext context) => value.when(
        data: builder,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline, text: errorText(context, e)),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 3)],
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          ?trailing,
        ]),
      );
}

class UserAvatar extends StatelessWidget {
  final String? path;
  final String name;
  final double radius;
  const UserAvatar({super.key, this.path, required this.name, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final file = path != null ? File(path!) : null;
    final has = file != null && file.existsSync();
    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primaryContainer,
      backgroundImage: has ? FileImage(file) : null,
      child: has
          ? null
          : Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w700, color: cs.primary)),
    );
  }
}

/// Picks a date then an optional time.
Future<DateTime?> pickDateTime(BuildContext context, {DateTime? initial, bool withTime = true}) async {
  final now = DateTime.now();
  final d = await showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: DateTime(now.year - 5),
    lastDate: DateTime(now.year + 10),
  );
  if (d == null || !context.mounted) return null;
  if (!withTime) return DateTime(d.year, d.month, d.day);
  final t = await showTimePicker(
    context: context,
    initialTime: initial != null ? TimeOfDay.fromDateTime(initial) : const TimeOfDay(hour: 9, minute: 0),
  );
  return DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0);
}

class ColorPickerRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const ColorPickerRow({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final c in AppTheme.palette)
            GestureDetector(
              onTap: () => onChanged(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: value == c ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3),
                ),
                child: value == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
              ),
            ),
        ],
      );
}

/// A curated list of Material icons for projects / habits (const for tree-shaking).
const kPickableIcons = <IconData>[
  Icons.folder_rounded, Icons.work_rounded, Icons.home_rounded, Icons.school_rounded,
  Icons.code_rounded, Icons.shopping_cart_rounded, Icons.favorite_rounded, Icons.fitness_center_rounded,
  Icons.menu_book_rounded, Icons.mosque_rounded, Icons.water_drop_rounded, Icons.bedtime_rounded,
  Icons.directions_run_rounded, Icons.restaurant_rounded, Icons.attach_money_rounded, Icons.flight_rounded,
  Icons.brush_rounded, Icons.phone_android_rounded, Icons.campaign_rounded, Icons.lightbulb_rounded,
  Icons.check_circle_rounded, Icons.self_improvement_rounded, Icons.local_cafe_rounded, Icons.people_rounded,
];

IconData iconFromCode(int code) =>
    kPickableIcons.firstWhere((i) => i.codePoint == code, orElse: () => Icons.folder_rounded);

class IconPickerRow extends StatelessWidget {
  final int value;
  final int color;
  final ValueChanged<int> onChanged;
  const IconPickerRow({super.key, required this.value, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final i in kPickableIcons)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onChanged(i.codePoint),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: value == i.codePoint ? Color(color).withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: value == i.codePoint ? Color(color) : Theme.of(context).dividerColor),
                ),
                child: Icon(i, color: value == i.codePoint ? Color(color) : null),
              ),
            ),
        ],
      );
}

