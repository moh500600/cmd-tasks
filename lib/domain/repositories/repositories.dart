import '../entities/enums.dart';
import '../entities/habit.dart';
import '../entities/project.dart';
import '../entities/task.dart';
import '../entities/task_filter.dart';
import '../entities/user.dart';

/// Abstract contracts (domain layer). Implementations live in data/repositories.

class SignUpResult {
  final AppUser user;

  /// Shown once to the user; only its hash is stored.
  final String recoveryCode;
  const SignUpResult(this.user, this.recoveryCode);
}

abstract class AuthRepository {
  Future<SignUpResult> signUp({
    required String name,
    required String email,
    required String password,
    required String securityQuestion,
    required String securityAnswer,
  });
  Future<AppUser> login(String email, String password);
  Future<AppUser?> getUser(int id);
  Future<AppUser> updateProfile(int userId,
      {String? name, String? email, String? avatarPath});
  Future<void> changePassword(int userId, String current, String newPassword);
  Future<String> securityQuestionFor(String email);
  Future<void> resetPassword({
    required String email,
    String? securityAnswer,
    String? recoveryCode,
    required String newPassword,
  });
  Future<String> regenerateRecoveryCode(int userId, String password);
  Future<void> deleteAccount(int userId, String password);
}

abstract class TaskRepository {
  Future<Task> create(Task task);
  Future<Task> update(Task task);
  Future<void> delete(int userId, int taskId);
  Future<Task> duplicate(int userId, int taskId);
  Future<void> setArchived(int userId, int taskId, bool archived);

  /// Changes status. When a repeating task is completed, the next occurrence
  /// is created and returned.
  Future<Task?> setStatus(int userId, int taskId, TaskStatus status);
  Future<void> toggleSubtask(int userId, int subtaskId, bool done);
  Future<Task?> getById(int userId, int taskId);
  Future<List<Task>> getAll(int userId, {bool includeArchived = false});
  Future<List<Task>> section(int userId, TaskSection section, DateTime now);
  Future<List<Task>> search(int userId, TaskFilter filter);
  Future<List<Task>> inRange(int userId, DateTime from, DateTime to);
  Future<List<Task>> byProject(int userId, int projectId);
}

abstract class TagRepository {
  Future<List<Tag>> getAll(int userId);
  Future<Tag> ensure(int userId, String name, {int? color});
  Future<void> delete(int userId, int tagId);
}

abstract class ProjectRepository {
  Future<Project> create(Project project);
  Future<Project> update(Project project);
  Future<void> delete(int userId, int projectId, {bool deleteTasks = false});
  Future<void> setArchived(int userId, int projectId, bool archived);
  Future<List<Project>> getAll(int userId, {bool includeArchived = false});
  Future<Project?> getById(int userId, int projectId);
}

abstract class HabitRepository {
  Future<Habit> create(Habit habit);
  Future<Habit> update(Habit habit);
  Future<void> delete(int userId, int habitId);
  Future<List<Habit>> getAll(int userId, {bool includeArchived = false});
  Future<bool> toggleLog(int userId, int habitId, DateTime day);
  Future<Set<DateTime>> logs(int userId, int habitId);
  Future<Map<int, Set<DateTime>>> allLogs(int userId);
}

abstract class BackupRepository {
  Future<Map<String, dynamic>> export(int userId);
  Future<void> restore(int userId, Map<String, dynamic> data);
}
