import 'enums.dart';

class Project {
  final int? id;
  final int userId;
  final String name;
  final String description;
  final int iconCode; // Material icon code point
  final int color;
  final String? imagePath;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? budget;
  final double spent;
  final ProjectStatus status;
  final bool archived;
  final DateTime createdAt;

  // Aggregates (filled by repository queries).
  final int totalTasks;
  final int completedTasks;
  final int overdueTasks;

  const Project({
    this.id,
    required this.userId,
    required this.name,
    this.description = '',
    this.iconCode = 0xe2c7, // Icons.folder
    this.color = 0xFF5B5BD6,
    this.imagePath,
    this.startDate,
    this.endDate,
    this.budget,
    this.spent = 0,
    this.status = ProjectStatus.active,
    this.archived = false,
    required this.createdAt,
    this.totalTasks = 0,
    this.completedTasks = 0,
    this.overdueTasks = 0,
  });

  double get progress => totalTasks == 0 ? 0 : completedTasks / totalTasks;

  double? get budgetUsage =>
      (budget == null || budget == 0) ? null : (spent / budget!);

  Project copyWith({
    int? id,
    String? name,
    String? description,
    int? iconCode,
    int? color,
    String? imagePath,
    DateTime? startDate,
    DateTime? endDate,
    double? budget,
    bool clearBudget = false,
    double? spent,
    ProjectStatus? status,
    bool? archived,
  }) =>
      Project(
        id: id ?? this.id,
        userId: userId,
        name: name ?? this.name,
        description: description ?? this.description,
        iconCode: iconCode ?? this.iconCode,
        color: color ?? this.color,
        imagePath: imagePath ?? this.imagePath,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        budget: clearBudget ? null : (budget ?? this.budget),
        spent: spent ?? this.spent,
        status: status ?? this.status,
        archived: archived ?? this.archived,
        createdAt: createdAt,
        totalTasks: totalTasks,
        completedTasks: completedTasks,
        overdueTasks: overdueTasks,
      );
}
