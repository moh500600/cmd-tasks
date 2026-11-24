import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/task.dart';
import '../../domain/repositories/repositories.dart';

class TagRepositoryImpl implements TagRepository {
  final Database db;
  TagRepositoryImpl(this.db);

  static const palette = [
    0xFF5B5BD6, 0xFF0EA5E9, 0xFF16A34A, 0xFFF59E0B,
    0xFFEF4444, 0xFFEC4899, 0xFF8B5CF6, 0xFF14B8A6,
  ];

  @override
  Future<List<Tag>> getAll(int userId) async {
    final rows = await db.query('tags',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'name COLLATE NOCASE');
    return rows
        .map((r) => Tag(id: r['id'] as int, name: r['name'] as String, color: r['color'] as int))
        .toList();
  }

  @override
  Future<Tag> ensure(int userId, String name, {int? color}) =>
      ensureIn(db, userId, name, color: color);

  Future<Tag> ensureIn(DatabaseExecutor ex, int userId, String name, {int? color}) async {
    final n = name.trim().replaceAll('#', '');
    if (n.isEmpty) throw const AppException('v_required');
    final rows = await ex.query('tags',
        where: 'user_id = ? AND name = ?', whereArgs: [userId, n], limit: 1);
    if (rows.isNotEmpty) {
      final r = rows.first;
      return Tag(id: r['id'] as int, name: r['name'] as String, color: r['color'] as int);
    }
    final c = color ?? palette[n.hashCode.abs() % palette.length];
    final id = await ex.insert('tags', {'user_id': userId, 'name': n, 'color': c});
    return Tag(id: id, name: n, color: c);
  }

  @override
  Future<void> delete(int userId, int tagId) async {
    await db.delete('tags', where: 'id = ? AND user_id = ?', whereArgs: [tagId, userId]);
  }
}
