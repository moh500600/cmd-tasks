import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/utils/date_x.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/backup_repository_impl.dart';
import '../../data/repositories/habit_repository_impl.dart';
import '../../data/repositories/project_repository_impl.dart';
import '../../data/repositories/tag_repository_impl.dart';
import '../../data/repositories/task_repository_impl.dart';
import '../../data/services/export_service.dart';
import '../../data/services/file_storage_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/settings_repository.dart';
import '../../domain/assistant/assistant_engine.dart';
import '../../domain/assistant/rule_based_assistant.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/project.dart';
import '../../domain/entities/task.dart';
import '../../domain/entities/task_filter.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/stats_calculator.dart';
import '../../domain/services/task_sections.dart';

// ---------------------------------------------------------------- infra
final databaseProvider = Provider<Database>((ref) => throw UnimplementedError('override in main'));
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main'));
final initialUserProvider = Provider<AppUser?>((ref) => null);

final settingsRepositoryProvider = Provider((ref) => SettingsRepository(ref.watch(sharedPrefsProvider)));
final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepositoryImpl(ref.watch(databaseProvider)));
final taskRepositoryProvider = Provider<TaskRepository>((ref) => TaskRepositoryImpl(ref.watch(databaseProvider)));
final tagRepositoryProvider = Provider<TagRepository>((ref) => TagRepositoryImpl(ref.watch(databaseProvider)));
final projectRepositoryProvider = Provider<ProjectRepository>((ref) => ProjectRepositoryImpl(ref.watch(databaseProvider)));
final habitRepositoryProvider = Provider<HabitRepository>((ref) => HabitRepositoryImpl(ref.watch(databaseProvider)));
final backupRepositoryProvider = Provider<BackupRepository>((ref) => BackupRepositoryImpl(ref.watch(databaseProvider)));
final fileStorageProvider = Provider((ref) => FileStorageService());
final exportServiceProvider = Provider((ref) => ExportService(ref.watch(fileStorageProvider)));
final notificationServiceProvider = Provider((ref) => NotificationService());

/// Swap this for an LLM-backed engine in a later phase.
final assistantEngineProvider = Provider<AssistantEngine>((ref) => RuleBasedAssistant());

// ---------------------------------------------------------------- settings
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsRepositoryProvider).load();

  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await ref.read(settingsRepositoryProvider).save(state);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ---------------------------------------------------------------- session
class SessionNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() => ref.read(initialUserProvider);

  Future<void> signIn(AppUser user) async {
    await ref.read(settingsRepositoryProvider).setSession(user.id);
    state = user;
  }

  void refreshUser(AppUser user) => state = user;

  Future<void> signOut() async {
    await ref.read(settingsRepositoryProvider).setSession(null);
    await ref.read(notificationServiceProvider).cancelAll();
    state = null;
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, AppUser?>(SessionNotifier.new);

/// Bumped after every write so dependent queries refresh.
class RevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final revisionProvider = NotifierProvider<RevisionNotifier, int>(RevisionNotifier.new);

int _uid(Ref ref) {
  ref.watch(revisionProvider);
  final u = ref.watch(sessionProvider);
  if (u == null) throw StateError('not signed in');
  return u.id;
}

// ---------------------------------------------------------------- queries
final allTasksProvider = FutureProvider<List<Task>>((ref) async {
  final uid = _uid(ref);
  return ref.watch(taskRepositoryProvider).getAll(uid, includeArchived: true);
});

final sectionTasksProvider = FutureProvider.family<List<Task>, TaskSection>((ref, section) async {
  final all = await ref.watch(allTasksProvider.future);
  return TaskSections.filter(all, section, DateTime.now());
});

final sectionCountsProvider = FutureProvider<Map<TaskSection, int>>((ref) async {
  final all = await ref.watch(allTasksProvider.future);
  final now = DateTime.now();
  return {for (final s in TaskSection.values) s: all.where((t) => TaskSections.matches(t, s, now)).length};
});

final dashboardProvider = FutureProvider<DashboardStats>((ref) async {
  final all = await ref.watch(allTasksProvider.future);
  return StatsCalculator.dashboard(all, DateTime.now());
});

final taskProvider = FutureProvider.family<Task?, int>((ref, id) async {
  final uid = _uid(ref);
  return ref.watch(taskRepositoryProvider).getById(uid, id);
});

final tagsProvider = FutureProvider<List<Tag>>((ref) async {
  final uid = _uid(ref);
  return ref.watch(tagRepositoryProvider).getAll(uid);
});

final projectsProvider = FutureProvider.family<List<Project>, bool>((ref, includeArchived) async {
  final uid = _uid(ref);
  return ref.watch(projectRepositoryProvider).getAll(uid, includeArchived: includeArchived);
});

final projectProvider = FutureProvider.family<Project?, int>((ref, id) async {
  final uid = _uid(ref);
  return ref.watch(projectRepositoryProvider).getById(uid, id);
});

final projectTasksProvider = FutureProvider.family<List<Task>, int>((ref, id) async {
  final uid = _uid(ref);
  return ref.watch(taskRepositoryProvider).byProject(uid, id);
});

final habitsProvider = FutureProvider<List<Habit>>((ref) async {
  final uid = _uid(ref);
  return ref.watch(habitRepositoryProvider).getAll(uid);
});

final habitLogsProvider = FutureProvider<Map<int, Set<DateTime>>>((ref) async {
  final uid = _uid(ref);
  return ref.watch(habitRepositoryProvider).allLogs(uid);
});

class SearchFilterNotifier extends Notifier<TaskFilter> {
  @override
  TaskFilter build() => const TaskFilter();
  void set(TaskFilter f) => state = f;
}

final searchFilterProvider = NotifierProvider<SearchFilterNotifier, TaskFilter>(SearchFilterNotifier.new);

final searchResultsProvider = FutureProvider<List<Task>>((ref) async {
  final uid = _uid(ref);
  final f = ref.watch(searchFilterProvider);
  return ref.watch(taskRepositoryProvider).search(uid, f);
});

// ---------------------------------------------------------------- actions
/// Write-side façade used by the UI: persists, refreshes and reschedules.
class AppActions {
  final Ref ref;
  AppActions(this.ref);

  int get uid => ref.read(sessionProvider)!.id;
  bool get ar => ref.read(settingsProvider).languageCode == 'ar';
  TaskRepository get _tasks => ref.read(taskRepositoryProvider);
  NotificationService get _notif => ref.read(notificationServiceProvider);

  void _bump() {
    ref.read(revisionProvider.notifier).bump();
  }

  Future<Task> saveTask(Task t) async {
    final saved = t.id == null ? await _tasks.create(t) : await _tasks.update(t);
    await _notif.scheduleTask(saved, ref.read(settingsProvider), ar);
    _bump();
    return saved;
  }

  Future<void> deleteTask(Task t) async {
    await _tasks.delete(uid, t.id!);
    await _notif.cancelTask(t.id!);
    for (final a in t.attachments) {
      if (a.type != AttachmentType.link) {
        // Only delete the file when no other task still references it.
        final others = await ref.read(databaseProvider).query('attachments',
            where: 'path_or_url = ?', whereArgs: [a.pathOrUrl]);
        if (others.isEmpty) await ref.read(fileStorageProvider).delete(a.pathOrUrl);
      }
    }
    _bump();
  }

  Future<Task> duplicateTask(Task t) async {
    final d = await _tasks.duplicate(uid, t.id!);
    await _notif.scheduleTask(d, ref.read(settingsProvider), ar);
    _bump();
    return d;
  }

  Future<void> archiveTask(Task t, bool archived) async {
    await _tasks.setArchived(uid, t.id!, archived);
    if (archived) {
      await _notif.cancelTask(t.id!);
    } else {
      final fresh = await _tasks.getById(uid, t.id!);
      if (fresh != null) await _notif.scheduleTask(fresh, ref.read(settingsProvider), ar);
    }
    _bump();
  }

  /// Returns the next occurrence when a repeating task was completed.
  Future<Task?> setStatus(Task t, TaskStatus s) async {
    final next = await _tasks.setStatus(uid, t.id!, s);
    final fresh = await _tasks.getById(uid, t.id!);
    if (fresh != null) await _notif.scheduleTask(fresh, ref.read(settingsProvider), ar);
    if (next != null) await _notif.scheduleTask(next, ref.read(settingsProvider), ar);
    _bump();
    return next;
  }

  Future<void> toggleSubtask(Subtask s, bool done) async {
    await _tasks.toggleSubtask(uid, s.id!, done);
    _bump();
  }

  Future<void> setPriority(Task t, TaskPriority p) async {
    final fresh = await _tasks.getById(uid, t.id!);
    if (fresh == null) return;
    await _tasks.update(fresh.copyWith(priority: p));
    _bump();
  }

  Future<Project> saveProject(Project p) async {
    final repo = ref.read(projectRepositoryProvider);
    final saved = p.id == null ? await repo.create(p) : await repo.update(p);
    _bump();
    return saved;
  }

  Future<void> deleteProject(Project p, {bool deleteTasks = false}) async {
    await ref.read(projectRepositoryProvider).delete(uid, p.id!, deleteTasks: deleteTasks);
    _bump();
  }

  Future<void> archiveProject(Project p, bool archived) async {
    await ref.read(projectRepositoryProvider).setArchived(uid, p.id!, archived);
    _bump();
  }

  Future<Habit> saveHabit(Habit h) async {
    final repo = ref.read(habitRepositoryProvider);
    final saved = h.id == null ? await repo.create(h) : await repo.update(h);
    await _notif.scheduleHabit(saved, ref.read(settingsProvider), ar);
    _bump();
    return saved;
  }

  Future<void> deleteHabit(Habit h) async {
    await ref.read(habitRepositoryProvider).delete(uid, h.id!);
    await _notif.cancelHabit(h.id!);
    _bump();
  }

  Future<bool> toggleHabit(Habit h, DateTime day) async {
    final r = await ref.read(habitRepositoryProvider).toggleLog(uid, h.id!, day);
    _bump();
    return r;
  }

  Future<void> rescheduleNotifications() async {
    final u = ref.read(sessionProvider);
    if (u == null) return;
    final tasks = await _tasks.getAll(u.id);
    final habits = await ref.read(habitRepositoryProvider).getAll(u.id);
    final now = DateTime.now();
    await _notif.rescheduleAll(tasks, habits, ref.read(settingsProvider), ar,
        todayCount: TaskSections.filter(tasks, TaskSection.today, now).length,
        overdueCount: TaskSections.filter(tasks, TaskSection.overdue, now).length);
  }

  Future<void> afterRestore() async {
    _bump();
    await rescheduleNotifications();
  }

  Task blankTask({DateTime? due, int? projectId}) {
    final s = ref.read(settingsProvider);
    final now = DateTime.now();
    return Task(
      userId: uid,
      title: '',
      dueDate: due,
      projectId: projectId,
      reminderMinutes: due != null ? s.defaultReminderMinutes : null,
      createdAt: now,
      updatedAt: now,
    );
  }

  DateTime defaultDueFor(DateTime day) {
    final now = DateTime.now();
    if (isSameDay(day, now)) {
      final h = (now.hour + 1).clamp(0, 23);
      return DateTime(day.year, day.month, day.day, h);
    }
    return DateTime(day.year, day.month, day.day, 9);
  }
}

final actionsProvider = Provider((ref) => AppActions(ref));

/// Locale helper for widgets that only need the language.
final localeProvider = Provider<Locale>((ref) => Locale(ref.watch(settingsProvider).languageCode));
