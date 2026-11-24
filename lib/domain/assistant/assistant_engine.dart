import '../entities/enums.dart';
import '../entities/task.dart';

/// A task extracted from free text.
class ParsedTask {
  final String title;
  final DateTime? dueDate;
  final bool hasTime;
  final TaskPriority? priority;
  final List<String> tags;
  final int? reminderMinutes;

  const ParsedTask({
    required this.title,
    this.dueDate,
    this.hasTime = false,
    this.priority,
    this.tags = const [],
    this.reminderMinutes,
  });
}

class PlanItem {
  final DateTime start;
  final DateTime end;
  final Task task;
  const PlanItem(this.start, this.end, this.task);
}

/// Actions the UI can apply after the user confirms.
sealed class AssistantAction {
  const AssistantAction();
}

class CreateTasksAction extends AssistantAction {
  final List<ParsedTask> tasks;
  const CreateTasksAction(this.tasks);
}

class CreateProjectAction extends AssistantAction {
  final String projectName;
  final List<String> subtasks;
  const CreateProjectAction(this.projectName, this.subtasks);
}

class ApplyPrioritiesAction extends AssistantAction {
  final Map<Task, TaskPriority> suggestions;
  const ApplyPrioritiesAction(this.suggestions);
}

class ApplyPlanAction extends AssistantAction {
  final List<PlanItem> plan;
  const ApplyPlanAction(this.plan);
}

class AssistantReply {
  final String text;
  final AssistantAction? action;
  const AssistantReply(this.text, {this.action});
}

class AssistantContext {
  final List<Task> tasks;
  final DateTime now;
  final String languageCode; // fallback when the message language is unclear
  const AssistantContext({required this.tasks, required this.now, required this.languageCode});
}

/// The single seam for intelligence. v1 ships [RuleBasedAssistant]; an
/// LLM-backed implementation (OpenAI, Gemini, a self-hosted model …) can
/// implement this interface later and be swapped in via the provider —
/// no UI changes needed. API keys must never be hard-coded in the app.
abstract class AssistantEngine {
  String get name;
  Future<AssistantReply> respond(String message, AssistantContext context);
}
