import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasks_pro/domain/assistant/assistant_engine.dart';
import 'package:tasks_pro/domain/assistant/rule_based_assistant.dart';
import 'package:tasks_pro/domain/assistant/task_text_parser.dart';
import 'package:tasks_pro/domain/entities/enums.dart';
import 'package:tasks_pro/domain/entities/task.dart';

void main() {
  // Monday 2 Nov 2026, 10:00
  final now = DateTime(2026, 11, 2, 10, 0);

  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  group('Arabic parsing', () {
    test('بكرة الساعة ٥ → tomorrow 17:00 with reminder', () {
      final p = TaskTextParser.parse('ذكرني بكرة الساعة ٥ أتصل بالعميل', now);
      expect(p.dueDate, DateTime(2026, 11, 3, 17, 0));
      expect(p.hasTime, isTrue);
      expect(p.title, 'أتصل بالعميل');
      expect(p.reminderMinutes, 0);
    });

    test('الساعة ٩ صباحاً + عاجل + tag', () {
      final p = TaskTextParser.parse('أضف مهمة تسليم التقرير بكرة الساعة ٩ صباحاً عاجل #عمل', now);
      expect(p.dueDate, DateTime(2026, 11, 3, 9, 0));
      expect(p.priority, TaskPriority.urgent);
      expect(p.tags, ['عمل']);
      expect(p.title, 'تسليم التقرير');
    });

    test('بعد بكرة العصر', () {
      final p = TaskTextParser.parse('زيارة الوالدة بعد بكرة العصر', now);
      expect(p.dueDate, DateTime(2026, 11, 4, 16, 0));
      expect(p.title, 'زيارة الوالدة');
    });

    test('الساعة ٨ ونص مساء', () {
      final p = TaskTextParser.parse('اجتماع الفريق اليوم الساعة ٨ ونص مساء', now);
      expect(p.dueDate, DateTime(2026, 11, 2, 20, 30));
    });

    test('weekday يوم الخميس', () {
      final p = TaskTextParser.parse('دفع الإيجار يوم الخميس مهم', now);
      expect(p.dueDate!.weekday, DateTime.thursday);
      expect(p.dueDate!.day, 5);
      expect(p.priority, TaskPriority.high);
      expect(p.title, 'دفع الإيجار');
    });

    test('بعد ساعتين relative', () {
      final p = TaskTextParser.parse('ذكرني بعد ساعتين أشرب الدواء', now);
      expect(p.dueDate, now.add(const Duration(hours: 2)));
    });

    test('بعد ٣ أيام', () {
      final p = TaskTextParser.parse('مراجعة العقد بعد ٣ أيام', now);
      expect(p.dueDate!.day, 5);
    });

    test('غير مهم → low (not high)', () {
      final p = TaskTextParser.parse('ترتيب المكتب غير مهم', now);
      expect(p.priority, TaskPriority.low);
      expect(p.title, 'ترتيب المكتب');
    });

    test('مهمة (task) is not a priority word', () {
      final p = TaskTextParser.parse('أضف مهمة شراء خبز', now);
      expect(p.priority, isNull);
      expect(p.title, 'شراء خبز');
    });

    test('date 15/11', () {
      final p = TaskTextParser.parse('تجديد الجواز 15/11', now);
      expect(p.dueDate!.month, 11);
      expect(p.dueDate!.day, 15);
    });
  });

  group('English parsing', () {
    test('tomorrow at 5pm urgent', () {
      final p = TaskTextParser.parse('remind me tomorrow at 5pm to call the client urgent', now);
      expect(p.dueDate, DateTime(2026, 11, 3, 17, 0));
      expect(p.priority, TaskPriority.urgent);
      expect(p.title, 'call the client');
    });

    test('in 3 days, 9:30 am, #home', () {
      final p = TaskTextParser.parse('Fix the sink in 3 days 9:30 am #home', now);
      expect(p.dueDate, DateTime(2026, 11, 5, 9, 30));
      expect(p.tags, ['home']);
      expect(p.title, 'Fix the sink');
    });

    test('next friday', () {
      final p = TaskTextParser.parse('Send invoice on friday important', now);
      expect(p.dueDate!.weekday, DateTime.friday);
      expect(p.priority, TaskPriority.high);
    });

    test('plain title has no date', () {
      final p = TaskTextParser.parse('Buy milk', now);
      expect(p.dueDate, isNull);
      expect(p.title, 'Buy milk');
    });
  });

  group('Project splitting', () {
    test('by lines with bullets', () {
      final s = TaskTextParser.splitIntoSubtasks('- تصميم الواجهة\n- برمجة السلة\n٣- رفع الموقع');
      expect(s, ['تصميم الواجهة', 'برمجة السلة', 'رفع الموقع']);
    });
    test('by sentences and ثم', () {
      final s = TaskTextParser.splitIntoSubtasks('نجمع المتطلبات ثم نصمم الشاشات، ثم نبرمج التطبيق. وبعدين نختبره');
      expect(s.length, 4);
      expect(s.first, 'نجمع المتطلبات');
    });
    test('english then', () {
      final s = TaskTextParser.splitIntoSubtasks('Research competitors, then write the spec. Build the MVP then test it');
      expect(s, ['Research competitors', 'write the spec', 'Build the MVP', 'test it']);
    });
  });

  group('Assistant intents & logic', () {
    Task task(String title, {DateTime? due, TaskPriority p = TaskPriority.medium, TaskStatus s = TaskStatus.todo, DateTime? completedAt}) =>
        Task(id: title.hashCode, userId: 1, title: title, dueDate: due, priority: p, status: s,
            completedAt: completedAt, createdAt: now.subtract(const Duration(days: 3)), updatedAt: now);

    test('intent detection', () {
      expect(RuleBasedAssistant.detectIntent('رتب يومي'), AssistantIntent.planDay);
      expect(RuleBasedAssistant.detectIntent('plan my day'), AssistantIntent.planDay);
      expect(RuleBasedAssistant.detectIntent('لخص الأسبوع'), AssistantIntent.summaryWeek);
      expect(RuleBasedAssistant.detectIntent('وش المهام المتأخرة'), AssistantIntent.overdue);
      expect(RuleBasedAssistant.detectIntent('قسم مشروع الموقع:\nا\nب'), AssistantIntent.splitProject);
      expect(RuleBasedAssistant.detectIntent('اقترح أولويات'), AssistantIntent.priorities);
      expect(RuleBasedAssistant.detectIntent('ذكرني بكرة أتصل بأحمد'), AssistantIntent.createTask);
    });

    test('priority suggestion by deadline', () {
      expect(RuleBasedAssistant.suggestPriority(task('a', due: now.add(const Duration(hours: 5))), now), TaskPriority.urgent);
      expect(RuleBasedAssistant.suggestPriority(task('b', due: now.add(const Duration(days: 2))), now), TaskPriority.high);
      expect(RuleBasedAssistant.suggestPriority(task('c', due: now.add(const Duration(days: 5))), now), TaskPriority.medium);
      expect(RuleBasedAssistant.suggestPriority(task('d', due: now.add(const Duration(days: 30))), now), TaskPriority.low);
    });

    test('plan day orders by urgency and stays within the day', () {
      final tasks = [
        task('later', due: DateTime(2026, 11, 2, 22), p: TaskPriority.low),
        task('overdue', due: DateTime(2026, 11, 1, 12), p: TaskPriority.medium),
        task('urgent', due: DateTime(2026, 11, 2, 12), p: TaskPriority.urgent),
        task('next month', due: DateTime(2026, 12, 2)),
      ];
      final plan = RuleBasedAssistant.planDay(tasks, now);
      expect(plan.map((p) => p.task.title).toList(), ['urgent', 'overdue', 'later']);
      expect(plan.first.start, DateTime(2026, 11, 2, 10, 30));
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].start.isAfter(plan[i - 1].end), isTrue);
      }
    });

    test('respond: create task returns action', () async {
      final r = await RuleBasedAssistant().respond('ذكرني بكرة الساعة ٥ أتصل بالعميل',
          AssistantContext(tasks: const [], now: now, languageCode: 'ar'));
      expect(r.action, isA<CreateTasksAction>());
      expect((r.action as CreateTasksAction).tasks.single.title, 'أتصل بالعميل');
    });

    test('respond: split project', () async {
      final r = await RuleBasedAssistant().respond('قسم مشروع موقع العسل:\nتصميم الواجهة\nبرمجة السلة\nرفع الموقع',
          AssistantContext(tasks: const [], now: now, languageCode: 'ar'));
      final a = r.action as CreateProjectAction;
      expect(a.projectName, 'موقع العسل');
      expect(a.subtasks.length, 3);
    });

    test('respond: overdue detection and summaries', () async {
      final tasks = [
        task('late one', due: now.subtract(const Duration(days: 1))),
        task('done', s: TaskStatus.completed, completedAt: now.subtract(const Duration(hours: 1))),
      ];
      final ctx = AssistantContext(tasks: tasks, now: now, languageCode: 'en');
      final r = await RuleBasedAssistant().respond('overdue tasks', ctx);
      expect(r.text, contains('late one'));
      final s = await RuleBasedAssistant().respond('summarize my day', ctx);
      expect(s.text, contains('Completed today: 1'));
      expect(s.text, contains('Overdue: 1'));
      final w = await RuleBasedAssistant().respond('weekly summary', ctx);
      expect(w.text, contains('Completed: 1'));
    });
  });
}
