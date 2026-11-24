import 'package:sqflite/sqflite.dart';

/// SQLite schema with proper relations and cascading foreign keys.
///
/// users 1─* projects 1─* tasks 1─* subtasks
///                         tasks *─* tags (task_tags)
///                         tasks 1─* attachments
/// users 1─* habits 1─* habit_logs
///
class AppDatabase {
  static const int version = 1;
  static const String fileName = 'tasks_pro.db';

  static Future<Database> open(DatabaseFactory factory, String path) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, v) async {
          await createSchema(db);
        },
      ),
    );
  }

  static Future<void> createSchema(DatabaseExecutor db) async {
    const statements = <String>[
      '''CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE COLLATE NOCASE,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        security_question TEXT NOT NULL,
        security_answer_hash TEXT NOT NULL,
        recovery_code_hash TEXT NOT NULL,
        avatar_path TEXT,
        created_at INTEGER NOT NULL
      )''',
      '''CREATE TABLE projects(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        icon INTEGER NOT NULL,
        color INTEGER NOT NULL,
        image_path TEXT,
        start_date INTEGER,
        end_date INTEGER,
        budget REAL,
        spent REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )''',
      '''CREATE TABLE tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        start_date INTEGER,
        due_date INTEGER,
        priority INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'todo',
        progress INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        reminder_minutes INTEGER,
        repeat TEXT NOT NULL DEFAULT 'none',
        completed_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''',
      'CREATE INDEX idx_tasks_user_due ON tasks(user_id, due_date)',
      'CREATE INDEX idx_tasks_project ON tasks(project_id)',
      '''CREATE TABLE subtasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        position INTEGER NOT NULL DEFAULT 0
      )''',
      'CREATE INDEX idx_subtasks_task ON subtasks(task_id)',
      '''CREATE TABLE tags(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name TEXT NOT NULL COLLATE NOCASE,
        color INTEGER NOT NULL,
        UNIQUE(user_id, name)
      )''',
      '''CREATE TABLE task_tags(
        task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
        PRIMARY KEY(task_id, tag_id)
      )''',
      '''CREATE TABLE attachments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        path_or_url TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''',
      '''CREATE TABLE habits(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        icon INTEGER NOT NULL,
        color INTEGER NOT NULL,
        days_mask INTEGER NOT NULL DEFAULT 127,
        reminder_time TEXT,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )''',
      '''CREATE TABLE habit_logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        habit_id INTEGER NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
        date TEXT NOT NULL,
        UNIQUE(habit_id, date)
      )''',
    ];
    for (final sql in statements) {
      await db.execute(sql);
    }
  }
}

int? toMillis(DateTime? d) => d?.millisecondsSinceEpoch;
DateTime? fromMillis(Object? v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
