import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tasks_pro/core/errors/app_exception.dart';
import 'package:tasks_pro/core/security/password_hasher.dart';
import 'package:tasks_pro/data/datasources/app_database.dart';
import 'package:tasks_pro/data/repositories/auth_repository_impl.dart';
import 'package:tasks_pro/data/repositories/backup_repository_impl.dart';
import 'package:tasks_pro/data/repositories/habit_repository_impl.dart';
import 'package:tasks_pro/data/repositories/project_repository_impl.dart';
import 'package:tasks_pro/data/repositories/task_repository_impl.dart';
import 'package:tasks_pro/domain/entities/enums.dart';
import 'package:tasks_pro/domain/entities/habit.dart';
import 'package:tasks_pro/domain/entities/project.dart';
import 'package:tasks_pro/domain/entities/task.dart';
import 'package:tasks_pro/domain/entities/task_filter.dart';
import 'package:tasks_pro/domain/services/habit_stats_calculator.dart';
import 'package:tasks_pro/domain/services/stats_calculator.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late AuthRepositoryImpl auth;
  late TaskRepositoryImpl tasks;
  late ProjectRepositoryImpl projects;
  late HabitRepositoryImpl habits;
  late int uid;
  late int otherUid;

  Task newTask(String title, {DateTime? due, TaskPriority p = TaskPriority.medium, int? projectId, List<Subtask> subs = const [], List<Tag> tags = const []}) =>
      Task(userId: uid, title: title, dueDate: due, priority: p, projectId: projectId,
          subtasks: subs, tags: tags, createdAt: DateTime.now(), updatedAt: DateTime.now());

  setUp(() async {
    db = await AppDatabase.open(databaseFactoryFfi, inMemoryDatabasePath);
    auth = AuthRepositoryImpl(db, hasher: const PasswordHasher(iterations: 50));
    tasks = TaskRepositoryImpl(db);
    projects = ProjectRepositoryImpl(db);
    habits = HabitRepositoryImpl(db);
    uid = (await auth.signUp(name: 'محمد', email: 'm@test.com', password: 'secret1',
            securityQuestion: 'q', securityAnswer: 'Sanaa')).user.id;
    otherUid = (await auth.signUp(name: 'Other', email: 'o@test.com', password: 'secret2',
            securityQuestion: 'q', securityAnswer: 'a')).user.id;
  });

  tearDown(() async => db.close());

  group('AuthRepository', () {
    test('passwords are hashed, login works, wrong password fails', () async {
      final row = (await db.query('users', where: 'id = ?', whereArgs: [uid])).first;
      expect(row['password_hash'], isNot('secret1'));
      expect((await auth.login('M@test.com', 'secret1')).id, uid);
      expect(() => auth.login('m@test.com', 'nope00'), throwsA(isA<AppException>()));
    });

    test('duplicate email rejected and validation enforced', () async {
      expect(() => auth.signUp(name: 'x y', email: 'm@test.com', password: '123456', securityQuestion: 'q', securityAnswer: 'a'),
          throwsA(predicate((e) => e is AppException && e.code == 'err_email_taken')));
      expect(() => auth.signUp(name: 'xy', email: 'bad', password: '123456', securityQuestion: 'q', securityAnswer: 'a'),
          throwsA(predicate((e) => e is AppException && e.code == 'v_email')));
      expect(() => auth.signUp(name: 'xy', email: 'n@n.com', password: '123', securityQuestion: 'q', securityAnswer: 'a'),
          throwsA(predicate((e) => e is AppException && e.code == 'v_password_short')));
    });

    test('reset via security answer (case-insensitive) and recovery code', () async {
      await auth.resetPassword(email: 'm@test.com', securityAnswer: ' sanaa ', newPassword: 'newpass1');
      expect((await auth.login('m@test.com', 'newpass1')).id, uid);
      final r = await auth.signUp(name: 'Code', email: 'c@test.com', password: 'secret3', securityQuestion: 'q', securityAnswer: 'a');
      await auth.resetPassword(email: 'c@test.com', recoveryCode: r.recoveryCode.toLowerCase(), newPassword: 'another1');
      expect((await auth.login('c@test.com', 'another1')).id, r.user.id);
      expect(() => auth.resetPassword(email: 'c@test.com', securityAnswer: 'wrong', newPassword: 'x123456'),
          throwsA(isA<AppException>()));
    });

    test('change password and delete account cascades', () async {
      await auth.changePassword(uid, 'secret1', 'secret9');
      expect((await auth.login('m@test.com', 'secret9')).id, uid);
      await tasks.create(newTask('t1', tags: const [Tag(name: 'work')]));
      await habits.create(Habit(userId: uid, name: 'Read', createdAt: DateTime.now()));
      await auth.deleteAccount(uid, 'secret9');
      expect(await auth.getUser(uid), isNull);
      expect((await db.query('tasks')).length, 0);
      expect((await db.query('tags')).length, 0);
      expect((await db.query('habits')).length, 0);
    });
  });

  group('TaskRepository', () {
    test('create with subtasks/tags/attachments, progress from subtasks', () async {
      final t = await tasks.create(newTask('Report',
          subs: const [Subtask(title: 'a', done: true), Subtask(title: 'b')],
          tags: const [Tag(name: 'work'), Tag(name: 'Work')]).copyWith(attachments: [
        Attachment(type: AttachmentType.link, name: 'Docs', pathOrUrl: 'https://x.com', createdAt: DateTime.now())
      ]));
      expect(t.id, isNotNull);
      expect(t.subtasks.length, 2);
      expect(t.tags.length, 1); // case-insensitive dedupe
      expect(t.attachments.single.pathOrUrl, 'https://x.com');
      expect(t.progress, 50);
    });

    test('validation: empty title and due before start', () async {
      expect(() => tasks.create(newTask('  ')), throwsA(isA<AppException>()));
      expect(() => tasks.create(newTask('x', due: DateTime(2026, 1, 1)).copyWith(startDate: DateTime(2026, 2, 1))),
          throwsA(predicate((e) => e is AppException && e.code == 'err_due_before_start')));
    });

    test('user isolation', () async {
      final t = await tasks.create(newTask('mine'));
      expect(await tasks.getById(otherUid, t.id!), isNull);
      expect(await tasks.getAll(otherUid), isEmpty);
      expect(() => tasks.delete(otherUid, t.id!), throwsA(isA<AppException>()));
      final foreign = await projects.create(Project(userId: otherUid, name: 'theirs', createdAt: DateTime.now()));
      expect(() => tasks.create(newTask('x', projectId: foreign.id)), throwsA(isA<AppException>()));
    });

    test('duplicate, archive, status completion and repeat', () async {
      final t = await tasks.create(newTask('Weekly', due: DateTime(2026, 11, 2, 9)).copyWith(repeat: RepeatRule.weekly));
      final d = await tasks.duplicate(uid, t.id!);
      expect(d.title, 'Weekly (2)');
      await tasks.setArchived(uid, d.id!, true);
      expect((await tasks.getAll(uid)).length, 1);
      expect((await tasks.getAll(uid, includeArchived: true)).length, 2);
      final next = await tasks.setStatus(uid, t.id!, TaskStatus.completed);
      final done = await tasks.getById(uid, t.id!);
      expect(done!.isCompleted, isTrue);
      expect(done.completedAt, isNotNull);
      expect(done.progress, 100);
      expect(next!.dueDate, DateTime(2026, 11, 9, 9));
    });

    test('toggling all subtasks completes the task', () async {
      final t = await tasks.create(newTask('S', subs: const [Subtask(title: 'a'), Subtask(title: 'b')]));
      await tasks.toggleSubtask(uid, t.subtasks[0].id!, true);
      expect((await tasks.getById(uid, t.id!))!.status, TaskStatus.inProgress);
      await tasks.toggleSubtask(uid, t.subtasks[1].id!, true);
      expect((await tasks.getById(uid, t.id!))!.status, TaskStatus.completed);
    });

    test('sections', () async {
      final now = DateTime.now();
      await tasks.create(newTask('today', due: DateTime(now.year, now.month, now.day, 23, 58)));
      await tasks.create(newTask('tomorrow', due: DateTime(now.year, now.month, now.day + 1, 10)));
      await tasks.create(newTask('late', due: now.subtract(const Duration(days: 2))));
      final p = await tasks.create(newTask('postponed'));
      await tasks.setStatus(uid, p.id!, TaskStatus.postponed);
      expect((await tasks.section(uid, TaskSection.today, now)).map((e) => e.title), contains('today'));
      expect((await tasks.section(uid, TaskSection.tomorrow, now)).single.title, 'tomorrow');
      expect((await tasks.section(uid, TaskSection.overdue, now)).single.title, 'late');
      expect((await tasks.section(uid, TaskSection.postponed, now)).single.title, 'postponed');
      expect((await tasks.section(uid, TaskSection.all, now)).length, 4);
    });

    test('advanced search and sort', () async {
      final proj = await projects.create(Project(userId: uid, name: 'Honey site', createdAt: DateTime.now()));
      await tasks.create(newTask('Design UI', p: TaskPriority.high, projectId: proj.id, due: DateTime(2026, 11, 10), tags: const [Tag(name: 'design')]));
      await tasks.create(newTask('Write copy', p: TaskPriority.low, due: DateTime(2026, 11, 5)).copyWith(description: 'marketing text'));
      await tasks.create(newTask('Deploy', p: TaskPriority.urgent, projectId: proj.id, due: DateTime(2026, 12, 1)));
      expect((await tasks.search(uid, const TaskFilter(query: 'marketing'))).single.title, 'Write copy');
      expect((await tasks.search(uid, const TaskFilter(query: 'honey'))).length, 2); // by project name
      expect((await tasks.search(uid, const TaskFilter(query: 'design'))).single.title, 'Design UI');
      expect((await tasks.search(uid, TaskFilter(projectId: proj.id))).length, 2);
      expect((await tasks.search(uid, const TaskFilter(priorities: {TaskPriority.urgent}))).single.title, 'Deploy');
      expect((await tasks.search(uid, TaskFilter(from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 30)))).length, 2);
      final byPrio = await tasks.search(uid, const TaskFilter(sort: TaskSort.priority, ascending: false));
      expect(byPrio.first.title, 'Deploy');
      final tagId = (await tasks.tags.getAll(uid)).single.id!;
      expect((await tasks.search(uid, TaskFilter(tagIds: {tagId}))).single.title, 'Design UI');
      expect(await tasks.search(otherUid, const TaskFilter(query: 'Design')), isEmpty);
    });
  });

  group('ProjectRepository', () {
    test('aggregates progress and delete sets task project to null', () async {
      final p = await projects.create(Project(userId: uid, name: 'App', budget: 1000, spent: 250, createdAt: DateTime.now()));
      final a = await tasks.create(newTask('a', projectId: p.id));
      await tasks.create(newTask('b', projectId: p.id));
      await tasks.setStatus(uid, a.id!, TaskStatus.completed);
      final loaded = (await projects.getById(uid, p.id!))!;
      expect(loaded.totalTasks, 2);
      expect(loaded.completedTasks, 1);
      expect(loaded.progress, 0.5);
      expect(loaded.budgetUsage, 0.25);
      await projects.delete(uid, p.id!);
      expect((await tasks.getById(uid, a.id!))!.projectId, isNull);
    });
  });

  group('Habits', () {
    test('toggle logs and streak/monthly stats', () async {
      final h = await habits.create(Habit(userId: uid, name: 'Quran', createdAt: DateTime(2026, 10, 1)));
      final today = DateTime(2026, 11, 5);
      for (var i = 0; i < 4; i++) {
        await habits.toggleLog(uid, h.id!, today.subtract(Duration(days: i)));
      }
      expect(await habits.toggleLog(uid, h.id!, today), isFalse); // untoggle today
      final logs = await habits.logs(uid, h.id!);
      final s = HabitStatsCalculator.compute(h, logs, today);
      expect(s.currentStreak, 3); // today pending, previous 3 done
      expect(s.bestStreak, 3);
      expect(s.monthlyRate, closeTo(3 / 5, 0.001));
      expect(() => habits.toggleLog(otherUid, h.id!, today), throwsA(isA<AppException>()));
    });

    test('streak respects scheduled weekdays', () {
      // Only Mondays (bit0) and Wednesdays (bit2).
      final h = Habit(id: 1, userId: uid, name: 'Gym', daysMask: 1 | 4, createdAt: DateTime(2026, 10, 1));
      final logs = {DateTime(2026, 10, 26), DateTime(2026, 10, 28), DateTime(2026, 11, 2)};
      final s = HabitStatsCalculator.compute(h, logs, DateTime(2026, 11, 3)); // Tuesday
      expect(s.currentStreak, 3);
    });
  });

  group('Stats & backup', () {
    test('dashboard stats', () async {
      final now = DateTime.now();
      final a = await tasks.create(newTask('a', due: DateTime(now.year, now.month, now.day, 23, 59), p: TaskPriority.urgent));
      await tasks.create(newTask('b', due: DateTime(now.year, now.month, now.day, 23, 59)));
      await tasks.create(newTask('late', due: now.subtract(const Duration(days: 1))));
      await tasks.setStatus(uid, a.id!, TaskStatus.completed);
      final s = StatsCalculator.dashboard(await tasks.getAll(uid), now);
      expect(s.total, 3);
      expect(s.completed, 1);
      expect(s.overdue, 1);
      expect(s.notStarted, 2);
      expect(s.dailyRate, 0.5);
      expect(s.completedLast7Days.last, 1);
    });

    test('backup export → restore into another account', () async {
      final p = await projects.create(Project(userId: uid, name: 'P', createdAt: DateTime.now()));
      await tasks.create(newTask('backup me', projectId: p.id, subs: const [Subtask(title: 's')], tags: const [Tag(name: 'x')]));
      final h = await habits.create(Habit(userId: uid, name: 'H', createdAt: DateTime.now()));
      await habits.toggleLog(uid, h.id!, DateTime.now());
      final backup = BackupRepositoryImpl(db);
      final data = await backup.export(uid);
      await backup.restore(otherUid, data);
      final restored = await tasks.getAll(otherUid);
      expect(restored.single.title, 'backup me');
      expect(restored.single.subtasks.single.title, 's');
      expect(restored.single.tags.single.name, 'x');
      expect(restored.single.projectName, 'P');
      expect((await habits.allLogs(otherUid)).values.single.length, 1);
      expect((await tasks.getAll(uid)).length, 1); // source untouched
      expect(() => backup.restore(otherUid, {'app': 'other'}), throwsA(isA<AppException>()));
    });
  });
}
