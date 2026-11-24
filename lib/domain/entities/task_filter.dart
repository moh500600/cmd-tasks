import 'enums.dart';

/// Advanced search / filter criteria.
class TaskFilter {
  final String query; // matches title, description, notes
  final int? projectId;
  final Set<TaskPriority> priorities;
  final Set<TaskStatus> statuses;
  final Set<int> tagIds;
  final DateTime? from; // due date >= from
  final DateTime? to; // due date <= to
  final bool includeArchived;
  final TaskSort sort;
  final bool ascending;

  const TaskFilter({
    this.query = '',
    this.projectId,
    this.priorities = const {},
    this.statuses = const {},
    this.tagIds = const {},
    this.from,
    this.to,
    this.includeArchived = false,
    this.sort = TaskSort.dueDate,
    this.ascending = true,
  });

  bool get isEmpty =>
      query.isEmpty &&
      projectId == null &&
      priorities.isEmpty &&
      statuses.isEmpty &&
      tagIds.isEmpty &&
      from == null &&
      to == null;

  int get activeCount =>
      (projectId != null ? 1 : 0) +
      (priorities.isNotEmpty ? 1 : 0) +
      (statuses.isNotEmpty ? 1 : 0) +
      (tagIds.isNotEmpty ? 1 : 0) +
      ((from != null || to != null) ? 1 : 0);

  TaskFilter copyWith({
    String? query,
    int? projectId,
    bool clearProject = false,
    Set<TaskPriority>? priorities,
    Set<TaskStatus>? statuses,
    Set<int>? tagIds,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    bool? includeArchived,
    TaskSort? sort,
    bool? ascending,
  }) =>
      TaskFilter(
        query: query ?? this.query,
        projectId: clearProject ? null : (projectId ?? this.projectId),
        priorities: priorities ?? this.priorities,
        statuses: statuses ?? this.statuses,
        tagIds: tagIds ?? this.tagIds,
        from: clearFrom ? null : (from ?? this.from),
        to: clearTo ? null : (to ?? this.to),
        includeArchived: includeArchived ?? this.includeArchived,
        sort: sort ?? this.sort,
        ascending: ascending ?? this.ascending,
      );
}
