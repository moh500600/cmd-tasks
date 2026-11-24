import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/validators.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/app_database.dart';

class ProjectRepositoryImpl implements ProjectRepository {
  final Database db;
  ProjectRepositoryImpl(this.db);

  static String _aggregateSql(String where) => '''
    SELECT p.*,
      (SELECT COUNT(*) FROM tasks t WHERE t.project_id = p.id AND t.archived = 0) AS total_tasks,
      (SELECT COUNT(*) FROM tasks t WHERE t.project_id = p.id AND t.archived = 0 AND t.status = 'completed') AS completed_tasks,
      (SELECT COUNT(*) FROM tasks t WHERE t.project_id = p.id AND t.archived = 0
         AND t.status IN ('todo','inProgress') AND t.due_date IS NOT NULL AND t.due_date < ?) AS overdue_tasks
    FROM projects p WHERE $where ORDER BY p.archived, p.created_at DESC''';

  Project _fromRow(Map<String, Object?> r) => Project(
        id: r['id'] as int,
        userId: r['user_id'] as int,
        name: r['name'] as String,
        description: r['description'] as String? ?? '',
        iconCode: r['icon'] as int,
        color: r['color'] as int,
        imagePath: r['image_path'] as String?,
        startDate: fromMillis(r['start_date']),
        endDate: fromMillis(r['end_date']),
        budget: (r['budget'] as num?)?.toDouble(),
        spent: (r['spent'] as num?)?.toDouble() ?? 0,
        status: ProjectStatus.fromName(r['status'] as String?),
        archived: (r['archived'] as int? ?? 0) == 1,
        createdAt: fromMillis(r['created_at'])!,
        totalTasks: r['total_tasks'] as int? ?? 0,
        completedTasks: r['completed_tasks'] as int? ?? 0,
        overdueTasks: r['overdue_tasks'] as int? ?? 0,
      );

  Map<String, Object?> _toRow(Project p) => {
        'user_id': p.userId,
        'name': p.name.trim(),
        'description': p.description.trim(),
        'icon': p.iconCode,
        'color': p.color,
        'image_path': p.imagePath,
        'start_date': toMillis(p.startDate),
        'end_date': toMillis(p.endDate),
        'budget': p.budget,
        'spent': p.spent,
        'status': p.status.name,
        'archived': p.archived ? 1 : 0,
        'created_at': toMillis(p.createdAt),
      };

  void _validate(Project p) {
    final e = Validators.title(p.name);
    if (e != null) throw AppException(e);
    if (p.startDate != null && p.endDate != null && p.endDate!.isBefore(p.startDate!)) {
      throw const AppException('err_due_before_start');
    }
    if ((p.budget ?? 0) < 0 || p.spent < 0) throw const AppException('v_number');
  }

  @override
  Future<Project> create(Project project) async {
    _validate(project);
    final id = await db.insert('projects', _toRow(project));
    return (await getById(project.userId, id))!;
  }

  @override
  Future<Project> update(Project project) async {
    _validate(project);
    final row = _toRow(project)..remove('created_at');
    final n = await db.update('projects', row,
        where: 'id = ? AND user_id = ?', whereArgs: [project.id, project.userId]);
    if (n == 0) throw const AppException('err_not_found');
    return (await getById(project.userId, project.id!))!;
  }

  @override
  Future<void> delete(int userId, int projectId, {bool deleteTasks = false}) async {
    await db.transaction((txn) async {
      if (deleteTasks) {
        await txn.delete('tasks',
            where: 'project_id = ? AND user_id = ?', whereArgs: [projectId, userId]);
      }
      final n = await txn.delete('projects',
          where: 'id = ? AND user_id = ?', whereArgs: [projectId, userId]);
      if (n == 0) throw const AppException('err_not_found');
    });
  }

  @override
  Future<void> setArchived(int userId, int projectId, bool archived) async {
    await db.update('projects', {'archived': archived ? 1 : 0},
        where: 'id = ? AND user_id = ?', whereArgs: [projectId, userId]);
  }

  @override
  Future<List<Project>> getAll(int userId, {bool includeArchived = false}) async {
    final rows = await db.rawQuery(
        _aggregateSql('p.user_id = ? ${includeArchived ? '' : 'AND p.archived = 0'}'),
        [toMillis(DateTime.now()), userId]);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Project?> getById(int userId, int projectId) async {
    final rows = await db.rawQuery(_aggregateSql('p.user_id = ? AND p.id = ?'),
        [toMillis(DateTime.now()), userId, projectId]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }
}
