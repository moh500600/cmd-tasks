import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/validators.dart';
import '../../domain/entities/habit.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/app_database.dart';

class HabitRepositoryImpl implements HabitRepository {
  final Database db;
  HabitRepositoryImpl(this.db);

  Habit _fromRow(Map<String, Object?> r) => Habit(
        id: r['id'] as int,
        userId: r['user_id'] as int,
        name: r['name'] as String,
        description: r['description'] as String? ?? '',
        iconCode: r['icon'] as int,
        color: r['color'] as int,
        daysMask: r['days_mask'] as int,
        reminderTime: r['reminder_time'] as String?,
        archived: (r['archived'] as int? ?? 0) == 1,
        createdAt: fromMillis(r['created_at'])!,
      );

  Map<String, Object?> _toRow(Habit h) => {
        'user_id': h.userId,
        'name': h.name.trim(),
        'description': h.description.trim(),
        'icon': h.iconCode,
        'color': h.color,
        'days_mask': h.daysMask,
        'reminder_time': h.reminderTime,
        'archived': h.archived ? 1 : 0,
        'created_at': toMillis(h.createdAt),
      };

  void _validate(Habit h) {
    final e = Validators.title(h.name);
    if (e != null) throw AppException(e);
    if (h.daysMask <= 0 || h.daysMask > 0x7F) throw const AppException('v_days');
    if (h.reminderTime != null &&
        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(h.reminderTime!)) {
      throw const AppException('v_time');
    }
  }

  Future<void> _owned(int userId, int habitId) async {
    final r = await db.query('habits',
        columns: ['id'], where: 'id = ? AND user_id = ?', whereArgs: [habitId, userId]);
    if (r.isEmpty) throw const AppException('err_not_found');
  }

  @override
  Future<Habit> create(Habit habit) async {
    _validate(habit);
    final id = await db.insert('habits', _toRow(habit));
    return habit.copyWith(id: id);
  }

  @override
  Future<Habit> update(Habit habit) async {
    _validate(habit);
    final row = _toRow(habit)..remove('created_at');
    final n = await db.update('habits', row,
        where: 'id = ? AND user_id = ?', whereArgs: [habit.id, habit.userId]);
    if (n == 0) throw const AppException('err_not_found');
    return habit;
  }

  @override
  Future<void> delete(int userId, int habitId) async {
    await db.delete('habits', where: 'id = ? AND user_id = ?', whereArgs: [habitId, userId]);
  }

  @override
  Future<List<Habit>> getAll(int userId, {bool includeArchived = false}) async {
    final rows = await db.query('habits',
        where: 'user_id = ? ${includeArchived ? '' : 'AND archived = 0'}',
        whereArgs: [userId],
        orderBy: 'created_at');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<bool> toggleLog(int userId, int habitId, DateTime day) async {
    await _owned(userId, habitId);
    final key = ymd(day);
    final n = await db.delete('habit_logs',
        where: 'habit_id = ? AND date = ?', whereArgs: [habitId, key]);
    if (n > 0) return false;
    await db.insert('habit_logs', {'habit_id': habitId, 'date': key});
    return true;
  }

  @override
  Future<Set<DateTime>> logs(int userId, int habitId) async {
    await _owned(userId, habitId);
    final rows = await db.query('habit_logs',
        columns: ['date'], where: 'habit_id = ?', whereArgs: [habitId]);
    return rows.map((r) => parseYmd(r['date'] as String)).toSet();
  }

  @override
  Future<Map<int, Set<DateTime>>> allLogs(int userId) async {
    final rows = await db.rawQuery('''
      SELECT l.habit_id, l.date FROM habit_logs l JOIN habits h ON h.id = l.habit_id
      WHERE h.user_id = ?''', [userId]);
    final map = <int, Set<DateTime>>{};
    for (final r in rows) {
      (map[r['habit_id'] as int] ??= {}).add(parseYmd(r['date'] as String));
    }
    return map;
  }
}
