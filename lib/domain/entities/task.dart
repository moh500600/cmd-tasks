import 'enums.dart';

class Subtask {
  final int? id;
  final int? taskId;
  final String title;
  final bool done;
  final int position;

  const Subtask({
    this.id,
    this.taskId,
    required this.title,
    this.done = false,
    this.position = 0,
  });

  Subtask copyWith({int? id, int? taskId, String? title, bool? done, int? position}) =>
      Subtask(
        id: id ?? this.id,
        taskId: taskId ?? this.taskId,
        title: title ?? this.title,
        done: done ?? this.done,
        position: position ?? this.position,
      );
}

class Tag {
  final int? id;
  final String name;
  final int color;

  const Tag({this.id, required this.name, this.color = 0xFF5B5BD6});

  @override
  bool operator ==(Object other) =>
      other is Tag && other.name.toLowerCase() == name.toLowerCase();

  @override
  int get hashCode => name.toLowerCase().hashCode;
}

class Attachment {
  final int? id;
  final int? taskId;
  final AttachmentType type;
  final String name;

  /// Absolute file path inside the app directory, or a URL for links.
  final String pathOrUrl;
  final DateTime createdAt;

  const Attachment({
    this.id,
    this.taskId,
    required this.type,
    required this.name,
    required this.pathOrUrl,
    required this.createdAt,
  });
}

class Task {
  final int? id;
  final int userId;
  final int? projectId;
  final String? projectName;
  final String title;
  final String description;
  final String notes;
  final DateTime? startDate;
  final DateTime? dueDate;
  final TaskPriority priority;
  final TaskStatus status;
  final int progress; // 0..100
  final bool archived;
  final int? reminderMinutes; // minutes before due date; null = no reminder
  final RepeatRule repeat;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Subtask> subtasks;
  final List<Tag> tags;
  final List<Attachment> attachments;

  const Task({
    this.id,
    required this.userId,
    this.projectId,
    this.projectName,
    required this.title,
    this.description = '',
    this.notes = '',
    this.startDate,
    this.dueDate,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.todo,
    this.progress = 0,
    this.archived = false,
    this.reminderMinutes,
    this.repeat = RepeatRule.none,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.subtasks = const [],
    this.tags = const [],
    this.attachments = const [],
  });

  bool get isCompleted => status == TaskStatus.completed;

  bool isOverdueAt(DateTime now) =>
      !archived &&
      !isCompleted &&
      status != TaskStatus.postponed &&
      dueDate != null &&
      dueDate!.isBefore(now);

  /// Progress derived from subtasks when present, otherwise the manual value.
  int get effectiveProgress {
    if (isCompleted) return 100;
    if (subtasks.isEmpty) return progress;
    final done = subtasks.where((s) => s.done).length;
    return ((done / subtasks.length) * 100).round();
  }

  Task copyWith({
    int? id,
    int? userId,
    int? projectId,
    bool clearProject = false,
    String? title,
    String? description,
    String? notes,
    DateTime? startDate,
    bool clearStart = false,
    DateTime? dueDate,
    bool clearDue = false,
    TaskPriority? priority,
    TaskStatus? status,
    int? progress,
    bool? archived,
    int? reminderMinutes,
    bool clearReminder = false,
    RepeatRule? repeat,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Subtask>? subtasks,
    List<Tag>? tags,
    List<Attachment>? attachments,
  }) =>
      Task(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        projectId: clearProject ? null : (projectId ?? this.projectId),
        projectName: clearProject ? null : projectName,
        title: title ?? this.title,
        description: description ?? this.description,
        notes: notes ?? this.notes,
        startDate: clearStart ? null : (startDate ?? this.startDate),
        dueDate: clearDue ? null : (dueDate ?? this.dueDate),
        priority: priority ?? this.priority,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        archived: archived ?? this.archived,
        reminderMinutes:
            clearReminder ? null : (reminderMinutes ?? this.reminderMinutes),
        repeat: repeat ?? this.repeat,
        completedAt:
            clearCompletedAt ? null : (completedAt ?? this.completedAt),
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        subtasks: subtasks ?? this.subtasks,
        tags: tags ?? this.tags,
        attachments: attachments ?? this.attachments,
      );
}
