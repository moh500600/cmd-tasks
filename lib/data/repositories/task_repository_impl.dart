import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/validators.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/task.dart';
import '../../domain/entities/task_filter.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/task_sections.dart';
import '../datasources/app_database.dart';
import 'tag_repository_impl.dart';

class TaskRepositoryImpl implements TaskRepository {
  final Database db;
  final TagRepositoryImpl tags;

  TaskRepositoryImpl(this.db) : tags = TagRepositoryImpl(db);

  static const _select = '''
    SELECT t.*, p.name AS project_name FROM tasks t
    LEFT JOIN projects p ON p.id = t.project_id
  ''';

  Map<String, Object?> _toRow(Task t) => {
        'user_id': t.userId,
        'project_id': t.projectId,
        'title': t.title.trim(),
        'description': t.description.trim(),
        'notes': t.notes.trim(),
        'start_date': toMillis(t.startDate),
        'due_date': toMillis(t.dueDate),
        'priority': t.priority.index,
        'status': t.status.name,
        'progress': t.progress.clamp(0, 100),
        'archived': t.archived ? 1 : 0,
        'reminder_minutes': t.reminderMinutes,
        'repeat': t.repeat.name,
        'completed_at': toMillis(t.completedAt),
        'created_at': toMillis(t.createdAt),
        'updated_at': toMillis(t.updatedAt),
      };

  Task _fromRow(Map<String, Object?> r) => Task(
        id: r['id'] as int,
        userId: r['user_id'] as int,
        projectId: r['project_id'] as int?,
        projectName: r['project_name'] as String?,
        title: r['title'] as String,
        description: r['description'] as String? ?? '',
        notes: r['notes'] as String? ?? '',
        startDate: fromMillis(r['start_date']),
        dueDate: fromMillis(r['due_date']),
        priority: TaskPriority.fromIndex(r['priority'] as int?),
        status: TaskStatus.fromName(r['status'] as String?),
        progress: r['progress'] as int? ?? 0,
        archived: (r['archived'] as int? ?? 0) == 1,
        reminderMinutes: r['reminder_minutes'] as int?,
        repeat: RepeatRule.fromName(r['repeat'] as String?),
        completedAt: fromMillis(r['completed_at']),
        createdAt: fromMillis(r['created_at'])!,
        updatedAt: fromMillis(r['updated_at'])!,
      );

  void _validate(Task t) {
    final e = Validators.title(t.title);
    if (e != null) throw AppException(e);
    if (t.startDate != null &&
        t.dueDate != null &&
        t.dueDate!.isBefore(t.startDate!)) {
      throw const AppException('err_due_before_start');
    }
    if (t.progress < 0 || t.progress > 100) {
      throw const AppException('v_progress');
    }
  }

  /// Keeps status, progress and completion time consistent.
  Task _normalize(Task t) {
    var n = t;
    if (n.status == TaskStatus.completed) {
      n = n.copyWith(progress: 100, completedAt: n.completedAt ?? DateTime.now());
    } else {
      n = n.copyWith(clearCompletedAt: true);
      if (n.subtasks.isNotEmpty) n = n.copyWith(progress: n.effectiveProgress);
    }
    return n;
  }

  Future<void> _writeChildren(Transaction txn, int taskId, Task t) async {
    // Upsert sub-tasks so their ids stay stable across edits.
    final keep = t.subtasks.where((s) => s.id != null).map((s) => s.id!).toList();
    await txn.delete('subtasks',
        where: keep.isEmpty
            ? 'task_id = ?'
            : 'task_id = ? AND id NOT IN (${List.filled(keep.length, '?').join(',')})',
        whereArgs: [taskId, ...keep]);
    for (var i = 0; i < t.subtasks.length; i++) {
      final s = t.subtasks[i];
      if (s.title.trim().isEmpty) continue;
      final row = {
        'task_id': taskId,
        'title': s.title.trim(),
        'done': s.done ? 1 : 0,
        'position': i,
      };
      if (s.id != null) {
        await txn.update('subtasks', row, where: 'id = ? AND task_id = ?', whereArgs: [s.id, taskId]);
      } else {
        await txn.insert('subtasks', row);
      }
    }
    await txn.delete('task_tags', where: 'task_id = ?', whereArgs: [taskId]);
    for (final tag in t.tags.toSet()) {
      final saved = await tags.ensureIn(txn, t.userId, tag.name, color: tag.color);
      await txn.insert('task_tags', {'task_id': taskId, 'tag_id': saved.id},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await txn.delete('attachments', where: 'task_id = ?', whereArgs: [taskId]);
    for (final a in t.attachments) {
      await txn.insert('attachments', {
        'task_id': taskId,
        'type': a.type.name,
        'name': a.name,
        'path_or_url': a.pathOrUrl,
        'created_at': toMillis(a.createdAt),
      });
    }
  }

  Future<void> _ensureProjectOwned(DatabaseExecutor ex, int userId, int? projectId) async {
    if (projectId == null) return;
    final r = await ex.query('projects',
        columns: ['id'], where: 'id = ? AND user_id = ?', whereArgs: [projectId, userId]);
    if (r.isEmpty) throw const AppException('err_not_found');
  }

  @override
  Future<Task> create(Task task) async {
    _validate(task);
    final now = DateTime.now();
    final t = _normalize(task.copyWith(createdAt: now, updatedAt: now));
    final id = await db.transaction((txn) async {
      await _ensureProjectOwned(txn, t.userId, t.projectId);
      final row = _toRow(t);
      final id = await txn.insert('tasks', row);
      await _writeChildren(txn, id, t);
      return id;
    });
    return (await getById(t.userId, id))!;
  }

  @override
  Future<Task> update(Task task) async {
    if (task.id == null) throw const AppException('err_not_found');
    _validate(task);
    final t = _normalize(task.copyWith(updatedAt: DateTime.now()));
    await db.transaction((txn) async {
      await _ensureProjectOwned(txn, t.userId, t.projectId);
      final row = _toRow(t)..remove('created_at');
      final n = await txn.update('tasks', row,
          where: 'id = ? AND user_id = ?', whereArgs: [t.id, t.userId]);
      if (n == 0) throw const AppException('err_not_found');
      await _writeChildren(txn, t.id!, t);
    });
    return (await getById(t.userId, t.id!))!;
  }

  @override
  Future<void> delete(int userId, int taskId) async {
    final n = await db.delete('tasks',
        where: 'id = ? AND user_id = ?', whereArgs: [taskId, userId]);
    if (n == 0) throw const AppException('err_not_found');
  }

  @override
  Future<Task> duplicate(int userId, int taskId) async {
    final t = await getById(userId, taskId);
    if (t == null) throw const AppException('err_not_found');
    return create(Task(
      userId: userId,
      projectId: t.projectId,
      title: '${t.title} (2)',
      description: t.description,
      notes: t.notes,
      startDate: t.startDate,
      dueDate: t.dueDate,
      priority: t.priority,
      status: TaskStatus.todo,
      progress: 0,
      reminderMinutes: t.reminderMinutes,
      repeat: t.repeat,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      subtasks: t.subtasks.map((s) => Subtask(title: s.title)).toList(),
      tags: t.tags,
      attachments: t.attachments,
    ));
  }

  @override
  Future<void> setArchived(int userId, int taskId, bool archived) async {
    final n = await db.update(
        'tasks',
        {
          'archived': archived ? 1 : 0,
          'updated_at': toMillis(DateTime.now()),
        },
        where: 'id = ? AND user_id = ?',
        whereArgs: [taskId, userId]);
    if (n == 0) throw const AppException('err_not_found');
  }

  @override
  Future<Task?> setStatus(int userId, int taskId, TaskStatus status) async {
    final t = await getById(userId, taskId);
    if (t == null) throw const AppException('err_not_found');
    final wasCompleted = t.isCompleted;
    var updated = t.copyWith(status: status);
    if (status != TaskStatus.completed && wasCompleted) {
      updated = updated.copyWith(progress: 0);
    }
    if (status == TaskStatus.inProgress && updated.progress == 0 && updated.subtasks.isEmpty) {
      updated = updated.copyWith(progress: 10);
    }
    await update(updated);
    if (status == TaskStatus.completed &&
        !wasCompleted &&
        t.repeat != RepeatRule.none &&
        t.dueDate != null) {
      final next = t.repeat.next(t.dueDate)!;
      final shift = next.difference(t.dueDate!);
      return create(Task(
        userId: userId,
        projectId: t.projectId,
        title: t.title,
        description: t.description,
        notes: t.notes,
        startDate: t.startDate?.add(shift),
        dueDate: next,
        priority: t.priority,
        reminderMinutes: t.reminderMinutes,
        repeat: t.repeat,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        subtasks: t.subtasks.map((s) => Subtask(title: s.title)).toList(),
        tags: t.tags,
      ));
    }
    return null;
  }

  @override
  Future<void> toggleSubtask(int userId, int subtaskId, bool done) async {
    final rows = await db.rawQuery('''
      SELECT s.task_id FROM subtasks s JOIN tasks t ON t.id = s.task_id
      WHERE s.id = ? AND t.user_id = ?''', [subtaskId, userId]);
    if (rows.isEmpty) throw const AppException('err_not_found');
    final taskId = rows.first['task_id'] as int;
    await db.update('subtasks', {'done': done ? 1 : 0},
        where: 'id = ?', whereArgs: [subtaskId]);
    final t = await getById(userId, taskId);
    if (t == null) return;
    var status = t.status;
    final allDone = t.subtasks.isNotEmpty && t.subtasks.every((s) => s.done);
    if (allDone) {
      status = TaskStatus.completed;
    } else if (t.isCompleted) {
      status = TaskStatus.inProgress;
    } else if (status == TaskStatus.todo && t.subtasks.any((s) => s.done)) {
      status = TaskStatus.inProgress;
    }
    await update(t.copyWith(status: status));
  }

  Future<List<Task>> _hydrate(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return [];
    final tasks = rows.map(_fromRow).toList();
    final ids = tasks.map((t) => t.id!).toList();
    final ph = List.filled(ids.length, '?').join(',');
    final subRows = await db.rawQuery(
        'SELECT * FROM subtasks WHERE task_id IN ($ph) ORDER BY position', ids);
    final tagRows = await db.rawQuery('''
      SELECT tt.task_id, g.id, g.name, g.color FROM task_tags tt
      JOIN tags g ON g.id = tt.tag_id WHERE tt.task_id IN ($ph) ORDER BY g.name''', ids);
    final attRows = await db.rawQuery(
        'SELECT * FROM attachments WHERE task_id IN ($ph) ORDER BY id', ids);
    final subs = <int, List<Subtask>>{};
    for (final r in subRows) {
      (subs[r['task_id'] as int] ??= []).add(Subtask(
        id: r['id'] as int,
        taskId: r['task_id'] as int,
        title: r['title'] as String,
        done: (r['done'] as int) == 1,
        position: r['position'] as int,
      ));
    }
    final tg = <int, List<Tag>>{};
    for (final r in tagRows) {
      (tg[r['task_id'] as int] ??= []).add(
          Tag(id: r['id'] as int, name: r['name'] as String, color: r['color'] as int));
    }
    final at = <int, List<Attachment>>{};
    for (final r in attRows) {
      (at[r['task_id'] as int] ??= []).add(Attachment(
        id: r['id'] as int,
        taskId: r['task_id'] as int,
        type: AttachmentType.fromName(r['type'] as String?),
        name: r['name'] as String,
        pathOrUrl: r['path_or_url'] as String,
        createdAt: fromMillis(r['created_at'])!,
      ));
    }
    return tasks
        .map((t) => t.copyWith(
              subtasks: subs[t.id] ?? const [],
              tags: tg[t.id] ?? const [],
              attachments: at[t.id] ?? const [],
            ))
        .toList();
  }

  @override
  Future<Task?> getById(int userId, int taskId) async {
    final rows = await db.rawQuery(
        '$_select WHERE t.id = ? AND t.user_id = ?', [taskId, userId]);
    final list = await _hydrate(rows);
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<List<Task>> getAll(int userId, {bool includeArchived = false}) async {
    final rows = await db.rawQuery(
        '$_select WHERE t.user_id = ? ${includeArchived ? '' : 'AND t.archived = 0'} ORDER BY t.due_date IS NULL, t.due_date',
        [userId]);
    return _hydrate(rows);
  }

  @override
  Future<List<Task>> section(int userId, TaskSection section, DateTime now) async {
    final all = await getAll(userId, includeArchived: section == TaskSection.archived);
    return TaskSections.filter(all, section, now);
  }

  @override
  Future<List<Task>> search(int userId, TaskFilter f) async {
    final where = <String>['t.user_id = ?'];
    final args = <Object?>[userId];
    if (!f.includeArchived) where.add('t.archived = 0');
    final q = f.query.trim();
    if (q.isNotEmpty) {
      where.add('''(t.title LIKE ? OR t.description LIKE ? OR t.notes LIKE ?
          OR p.name LIKE ? OR EXISTS (SELECT 1 FROM task_tags x JOIN tags g ON g.id = x.tag_id
          WHERE x.task_id = t.id AND g.name LIKE ?))''');
      final like = '%$q%';
      args.addAll([like, like, like, like, like]);
    }
    if (f.projectId != null) {
      where.add('t.project_id = ?');
      args.add(f.projectId);
    }
    if (f.priorities.isNotEmpty) {
      where.add('t.priority IN (${List.filled(f.priorities.length, '?').join(',')})');
      args.addAll(f.priorities.map((p) => p.index));
    }
    if (f.statuses.isNotEmpty) {
      where.add('t.status IN (${List.filled(f.statuses.length, '?').join(',')})');
      args.addAll(f.statuses.map((s) => s.name));
    }
    if (f.tagIds.isNotEmpty) {
      where.add('''EXISTS (SELECT 1 FROM task_tags x WHERE x.task_id = t.id
          AND x.tag_id IN (${List.filled(f.tagIds.length, '?').join(',')}))''');
      args.addAll(f.tagIds);
    }
    if (f.from != null) {
      where.add('t.due_date >= ?');
      args.add(toMillis(DateTime(f.from!.year, f.from!.month, f.from!.day)));
    }
    if (f.to != null) {
      where.add('t.due_date <= ?');
      args.add(toMillis(DateTime(f.to!.year, f.to!.month, f.to!.day, 23, 59, 59)));
    }
    final dir = f.ascending ? 'ASC' : 'DESC';
    final order = switch (f.sort) {
      TaskSort.dueDate => 't.due_date IS NULL, t.due_date $dir',
      TaskSort.priority => 't.priority $dir, t.due_date',
      TaskSort.createdAt => 't.created_at $dir',
      TaskSort.title => 't.title COLLATE NOCASE $dir',
      TaskSort.progress => 't.progress $dir',
    };
    final rows = await db.rawQuery(
        '$_select WHERE ${where.join(' AND ')} ORDER BY $order', args);
    return _hydrate(rows);
  }

  @override
  Future<List<Task>> inRange(int userId, DateTime from, DateTime to) async {
    final rows = await db.rawQuery(
        '$_select WHERE t.user_id = ? AND t.archived = 0 AND t.due_date >= ? AND t.due_date < ? ORDER BY t.due_date',
        [userId, toMillis(from), toMillis(to)]);
    return _hydrate(rows);
  }

  @override
  Future<List<Task>> byProject(int userId, int projectId) async {
    final rows = await db.rawQuery(
        '$_select WHERE t.user_id = ? AND t.project_id = ? ORDER BY t.due_date IS NULL, t.due_date',
        [userId, projectId]);
    return _hydrate(rows);
  }
}
