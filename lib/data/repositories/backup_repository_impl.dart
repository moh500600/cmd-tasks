import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/repositories/repositories.dart';

/// JSON backup/restore of everything that belongs to one user.
/// IDs are remapped on restore so a backup can be restored into any account.
class BackupRepositoryImpl implements BackupRepository {
  final Database db;
  BackupRepositoryImpl(this.db);

  static const formatVersion = 1;

  @override
  Future<Map<String, dynamic>> export(int userId) async {
    Future<List<Map<String, Object?>>> q(String sql) => db.rawQuery(sql, [userId]);
    return {
      'app': 'tasks_pro',
      'format': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'projects': await q('SELECT * FROM projects WHERE user_id = ?'),
      'tasks': await q('SELECT * FROM tasks WHERE user_id = ?'),
      'subtasks': await q(
          'SELECT s.* FROM subtasks s JOIN tasks t ON t.id = s.task_id WHERE t.user_id = ?'),
      'tags': await q('SELECT * FROM tags WHERE user_id = ?'),
      'task_tags': await q(
          'SELECT x.* FROM task_tags x JOIN tasks t ON t.id = x.task_id WHERE t.user_id = ?'),
      'attachments': await q(
          'SELECT a.* FROM attachments a JOIN tasks t ON t.id = a.task_id WHERE t.user_id = ?'),
      'habits': await q('SELECT * FROM habits WHERE user_id = ?'),
      'habit_logs': await q(
          'SELECT l.* FROM habit_logs l JOIN habits h ON h.id = l.habit_id WHERE h.user_id = ?'),
    };
  }

  @override
  Future<void> restore(int userId, Map<String, dynamic> data) async {
    if (data['app'] != 'tasks_pro' || data['format'] is! int) {
      throw const AppException('err_backup_invalid');
    }
    List<Map<String, dynamic>> list(String k) =>
        ((data[k] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map)
              )
            .toList();
    try {
      await db.transaction((txn) async {
        // Replace the user's current data.
        await txn.delete('projects', where: 'user_id = ?', whereArgs: [userId]);
        await txn.delete('tasks', where: 'user_id = ?', whereArgs: [userId]);
        await txn.delete('tags', where: 'user_id = ?', whereArgs: [userId]);
        await txn.delete('habits', where: 'user_id = ?', whereArgs: [userId]);

        final projectIds = <int, int>{};
        for (final r in list('projects')) {
          final old = r.remove('id') as int;
          r['user_id'] = userId;
          projectIds[old] = await txn.insert('projects', r);
        }
        final taskIds = <int, int>{};
        for (final r in list('tasks')) {
          final old = r.remove('id') as int;
          r['user_id'] = userId;
          r['project_id'] = projectIds[r['project_id']];
          taskIds[old] = await txn.insert('tasks', r);
        }
        for (final r in list('subtasks')) {
          r.remove('id');
          final t = taskIds[r['task_id']];
          if (t == null) continue;
          r['task_id'] = t;
          await txn.insert('subtasks', r);
        }
        final tagIds = <int, int>{};
        for (final r in list('tags')) {
          final old = r.remove('id') as int;
          r['user_id'] = userId;
          tagIds[old] = await txn.insert('tags', r,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        for (final r in list('task_tags')) {
          final t = taskIds[r['task_id']], g = tagIds[r['tag_id']];
          if (t == null || g == null) continue;
          await txn.insert('task_tags', {'task_id': t, 'tag_id': g},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        for (final r in list('attachments')) {
          r.remove('id');
          final t = taskIds[r['task_id']];
          if (t == null) continue;
          r['task_id'] = t;
          await txn.insert('attachments', r);
        }
        final habitIds = <int, int>{};
        for (final r in list('habits')) {
          final old = r.remove('id') as int;
          r['user_id'] = userId;
          habitIds[old] = await txn.insert('habits', r);
        }
        for (final r in list('habit_logs')) {
          r.remove('id');
          final h = habitIds[r['habit_id']];
          if (h == null) continue;
          r['habit_id'] = h;
          await txn.insert('habit_logs', r, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      });
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('err_backup_invalid', e);
    }
  }
}
