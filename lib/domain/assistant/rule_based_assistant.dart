import 'package:intl/intl.dart';

import '../../core/utils/date_x.dart';
import '../../core/utils/validators.dart';
import '../entities/enums.dart';
import '../entities/task.dart';
import '../services/stats_calculator.dart';
import '../services/task_sections.dart';
import 'assistant_engine.dart';
import 'task_text_parser.dart';

enum AssistantIntent {
  greeting,
  help,
  splitProject,
  planDay,
  summaryDay,
  summaryWeek,
  overdue,
  priorities,
  productivity,
  bestTime,
  createTask,
}

/// Offline, deterministic assistant (v1). Works in Arabic and English.
class RuleBasedAssistant implements AssistantEngine {
  @override
  String get name => 'rule-based-v1';

  static RegExp _r(String p) => RegExp(p, caseSensitive: false, unicode: true);

  static AssistantIntent detectIntent(String message) {
    final m = normalizeDigits(message).trim();
    final lines = m.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).length;
    if (_r(r'(قسم|قسّم|تقسيم|فصل|فصّل|جزئ|جزّئ|break\s*down|split|breakdown)').hasMatch(m) ||
        (lines >= 3 && _r(r'(مشروع|project)').hasMatch(m))) {
      return AssistantIntent.splitProject;
    }
    if (_r(r'(رتب|رتّب|نظم|نظّم|خطط|خطّط|جدول|plan|schedule|organi[sz]e)').hasMatch(m)) {
      return AssistantIntent.planDay;
    }
    if (_r(r'(لخص|لخّص|ملخص|تلخيص|summar)').hasMatch(m)) {
      return _r(r'(اسبوع|أسبوع|الاسبوع|week)').hasMatch(m)
          ? AssistantIntent.summaryWeek
          : AssistantIntent.summaryDay;
    }
    if (_r(r'(متأخر|متاخر|فاتت|فات موعد|overdue|late tasks)').hasMatch(m)) {
      return AssistantIntent.overdue;
    }
    if (_r(r'(اولوي|أولوي|الأولويات|ابدأ بايش|ابدا بايش|وش ابدا|prioriti|what first)').hasMatch(m) &&
        !_r(r'(ذكرني|أضف|اضف|add|remind)').hasMatch(m)) {
      return AssistantIntent.priorities;
    }
    if (_r(r'(انتاجي|إنتاجي|حلل|حلّل|تحليل|اداء|أداء|productiv|analy[sz]|performance)').hasMatch(m)) {
      return AssistantIntent.productivity;
    }
    if (_r(r'(افضل وقت|أفضل وقت|انسب وقت|أنسب وقت|best time|when should)').hasMatch(m)) {
      return AssistantIntent.bestTime;
    }
    if (_r(r'^(مساعد[ةه]|ساعدني|help|\?|ايش تقدر|وش تقدر|what can you)').hasMatch(m)) {
      return AssistantIntent.help;
    }
    if (_r(r'^(مرحبا|السلام عليكم|سلام|هلا|اهلا|أهلا|hi|hello|hey)[\s!.؟?]*$').hasMatch(m)) {
      return AssistantIntent.greeting;
    }
    return AssistantIntent.createTask;
  }

  @override
  Future<AssistantReply> respond(String message, AssistantContext ctx) async {
    final ar = TaskTextParser.isArabic(message) ||
        (!RegExp(r'[A-Za-z]').hasMatch(message) && ctx.languageCode == 'ar');
    String t(String a, String e) => ar ? a : e;
    final now = ctx.now;
    final open = ctx.tasks.where((x) => !x.archived && !x.isCompleted).toList();

    switch (detectIntent(message)) {
      case AssistantIntent.greeting:
        return AssistantReply(t('أهلاً! 👋 اكتب مهمة مثل «ذكرني بكرة الساعة ٥ أتصل بالعميل» أو اطلب «رتب يومي».',
            'Hi! 👋 Type a task like "remind me tomorrow at 5pm to call the client" or ask "plan my day".'));
      case AssistantIntent.help:
        return AssistantReply(_help(ar));
      case AssistantIntent.splitProject:
        return _split(message, ar);
      case AssistantIntent.planDay:
        return _plan(open, now, ar);
      case AssistantIntent.summaryDay:
        return AssistantReply(_summaryDay(ctx.tasks, now, ar));
      case AssistantIntent.summaryWeek:
        return AssistantReply(_summaryWeek(ctx.tasks, now, ar));
      case AssistantIntent.overdue:
        final overdue = TaskSections.filter(ctx.tasks, TaskSection.overdue, now);
        if (overdue.isEmpty) return AssistantReply(t('ما عندك مهام متأخرة 👏', 'No overdue tasks 👏'));
        final lines = overdue.take(10).map((x) =>
            '• ${x.title} — ${t('متأخرة', 'late by')} ${_ago(now.difference(x.dueDate!), ar)}');
        return AssistantReply(
            '${t('عندك ${overdue.length} مهام متأخرة:', 'You have ${overdue.length} overdue tasks:')}\n${lines.join('\n')}\n\n${t('أقترح ترفع أولويتها أو تعيد جدولتها.', 'Consider raising their priority or rescheduling them.')}',
            action: ApplyPrioritiesAction({for (final x in overdue) x: TaskPriority.urgent}));
      case AssistantIntent.priorities:
        return _priorities(open, now, ar);
      case AssistantIntent.productivity:
        return AssistantReply(_productivity(ctx.tasks, now, ar));
      case AssistantIntent.bestTime:
        return AssistantReply(_bestTime(ctx.tasks, ar));
      case AssistantIntent.createTask:
        return _create(message, now, ar);
    }
  }

  // ---------------- intents ----------------

  AssistantReply _create(String message, DateTime now, bool ar) {
    String t(String a, String e) => ar ? a : e;
    // Several lines without a split keyword → several tasks.
    final lines = message.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    final parsed = lines.map((l) => TaskTextParser.parse(l, now)).where((p) => p.title.isNotEmpty).toList();
    if (parsed.isEmpty) {
      return AssistantReply(t('ما فهمت عنوان المهمة 🤔 جرّب: «أضف مهمة تسليم التقرير بكرة الساعة ١٠ صباحاً مهم»',
          'I could not find a task title 🤔 Try: "add submit report tomorrow at 10am important"'));
    }
    final df = DateFormat(ar ? 'EEEE d MMMM – h:mm a' : 'EEE d MMM – h:mm a', ar ? 'ar' : 'en');
    final dfDay = DateFormat(ar ? 'EEEE d MMMM' : 'EEE d MMM', ar ? 'ar' : 'en');
    final desc = parsed.map((p) {
      final parts = <String>['📝 ${p.title}'];
      if (p.dueDate != null) parts.add('📅 ${(p.hasTime ? df : dfDay).format(p.dueDate!)}');
      if (p.priority != null) parts.add('⚡ ${_prioName(p.priority!, ar)}');
      if (p.tags.isNotEmpty) parts.add('🏷️ ${p.tags.map((e) => '#$e').join(' ')}');
      if (p.reminderMinutes != null) parts.add('🔔 ${t('تذكير', 'reminder')}');
      return parts.join('\n');
    }).join('\n\n');
    return AssistantReply(
        '${t(parsed.length == 1 ? 'جاهزة للإضافة:' : 'جاهز لإضافة ${parsed.length} مهام:', parsed.length == 1 ? 'Ready to add:' : 'Ready to add ${parsed.length} tasks:')}\n\n$desc',
        action: CreateTasksAction(parsed));
  }

  AssistantReply _split(String message, bool ar) {
    String t(String a, String e) => ar ? a : e;
    final lines = message.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    var header = lines.first;
    var body = lines.length > 1 ? lines.skip(1).join('\n') : '';
    // "قسم مشروع X: a، ثم b، ثم c" on one line.
    if (body.isEmpty && header.contains(RegExp(r'[:：]'))) {
      final i = header.indexOf(RegExp(r'[:：]'));
      body = header.substring(i + 1);
      header = header.substring(0, i);
    }
    var name = header
        .replaceAll(RegExp(r'(قسّم|قسم|تقسيم|فصّل|فصل|جزّئ|جزئ|لي|break\s*down|split|breakdown|into tasks|الى مهام|إلى مهام|مهام|the|my|please)', caseSensitive: false, unicode: true), ' ')
        .replaceAll(RegExp(r'^\s*(مشروع|project)\s*', caseSensitive: false, unicode: true), '')
        .replaceAll(RegExp(r'[:：]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final subtasks = TaskTextParser.splitIntoSubtasks(body.isEmpty ? header : body);
    if (name.isEmpty) name = t('مشروع جديد', 'New project');
    if (subtasks.length < 2) {
      return AssistantReply(t(
          'اكتب اسم المشروع في السطر الأول وكل خطوة في سطر، أو افصل الخطوات بـ «ثم». مثال:\nقسم مشروع موقع العسل:\nتصميم الواجهة\nبرمجة السلة\nرفع الموقع',
          'Put the project name on the first line and each step on its own line (or separate with "then"). Example:\nsplit project Honey site:\ndesign UI\nbuild cart\ndeploy'));
    }
    return AssistantReply(
        '${t('قسمت «$name» إلى ${subtasks.length} مهام:', 'Split "$name" into ${subtasks.length} tasks:')}\n${subtasks.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}',
        action: CreateProjectAction(name, subtasks));
  }

  static TaskPriority suggestPriority(Task task, DateTime now) {
    final due = task.dueDate;
    if (due == null) return task.priority;
    final h = due.difference(now).inHours;
    if (h < 24) return TaskPriority.urgent;
    if (h < 72) return TaskPriority.high;
    if (h < 24 * 7) return TaskPriority.medium;
    return TaskPriority.low;
  }

  AssistantReply _priorities(List<Task> open, DateTime now, bool ar) {
    String t(String a, String e) => ar ? a : e;
    final suggestions = <Task, TaskPriority>{};
    for (final task in open) {
      final s = suggestPriority(task, now);
      if (s != task.priority) suggestions[task] = s;
    }
    if (suggestions.isEmpty) {
      return AssistantReply(t('أولوياتك متناسقة مع المواعيد النهائية 👍', 'Your priorities already match your deadlines 👍'));
    }
    final lines = suggestions.entries.take(12).map((e) =>
        '• ${e.key.title}: ${_prioName(e.key.priority, ar)} → ${_prioName(e.value, ar)}');
    return AssistantReply(
        '${t('اقتراحات حسب قرب الموعد النهائي:', 'Suggestions based on how close each deadline is:')}\n${lines.join('\n')}',
        action: ApplyPrioritiesAction(suggestions));
  }

  static List<PlanItem> planDay(List<Task> open, DateTime now) {
    final today = dateOnly(now);
    final endOfDay = DateTime(today.year, today.month, today.day, 23, 0);
    final candidates = open.where((t) {
      if (t.status == TaskStatus.postponed) return false;
      if (t.dueDate == null) return t.priority.index >= TaskPriority.high.index || t.status == TaskStatus.inProgress;
      return !dateOnly(t.dueDate!).isAfter(today.add(const Duration(days: 1)));
    }).toList();
    double score(Task t) {
      var s = t.priority.index * 10.0;
      if (t.dueDate != null) {
        final h = t.dueDate!.difference(now).inMinutes / 60.0;
        s += h < 0 ? 30 : (h < 4 ? 20 : (h < 12 ? 12 : 5));
      }
      if (t.status == TaskStatus.inProgress) s += 4;
      return s;
    }
    candidates.sort((a, b) => score(b).compareTo(score(a)));
    var cursor = DateTime(now.year, now.month, now.day, now.hour, now.minute < 30 ? 30 : 0)
        .add(Duration(hours: now.minute < 30 ? 0 : 1));
    final dayStart = DateTime(today.year, today.month, today.day, 8);
    if (cursor.isBefore(dayStart)) cursor = dayStart;
    final plan = <PlanItem>[];
    for (final t in candidates) {
      final remainingSubs = t.subtasks.where((s) => !s.done).length;
      var minutes = switch (t.priority) {
        TaskPriority.urgent || TaskPriority.high => 60,
        TaskPriority.medium => 45,
        TaskPriority.low => 30,
      };
      if (remainingSubs > 0) minutes = (remainingSubs * 20).clamp(30, 120);
      // Keep a lunch/prayer break around 13:00–14:00.
      if (cursor.hour == 13) cursor = DateTime(cursor.year, cursor.month, cursor.day, 14);
      final end = cursor.add(Duration(minutes: minutes));
      if (end.isAfter(endOfDay)) break;
      plan.add(PlanItem(cursor, end, t));
      cursor = end.add(const Duration(minutes: 10));
    }
    return plan;
  }

  AssistantReply _plan(List<Task> open, DateTime now, bool ar) {
    String t(String a, String e) => ar ? a : e;
    final plan = planDay(open, now);
    if (plan.isEmpty) {
      return AssistantReply(t('ما فيه مهام لليوم تحتاج جدولة. يومك فاضي ✨ أضف مهمة وأرتبها لك.',
          'Nothing needs scheduling today ✨ Add a task and I will slot it in.'));
    }
    final tf = DateFormat('h:mm a', ar ? 'ar' : 'en');
    final lines = plan.map((p) => '🕒 ${tf.format(p.start)} – ${tf.format(p.end)}  ${p.task.title}${p.task.priority.index >= 2 ? ' ⚡' : ''}');
    return AssistantReply(
        '${t('خطة يومك المقترحة (الأهم والأقرب موعداً أولاً، مع استراحات):', 'Suggested plan (most important & nearest deadlines first, with breaks):')}\n${lines.join('\n')}\n\n${t('اضغط «تطبيق» لتعيين أوقات البدء.', 'Tap "Apply" to set the start times.')}',
        action: ApplyPlanAction(plan));
  }

  String _summaryDay(List<Task> tasks, DateTime now, bool ar) {
    String t(String a, String e) => ar ? a : e;
    final today = TaskSections.filter(tasks, TaskSection.today, now);
    final doneToday = tasks.where((x) => x.completedAt != null && isSameDay(x.completedAt, now)).length;
    final overdue = TaskSections.filter(tasks, TaskSection.overdue, now).length;
    final tomorrow = TaskSections.filter(tasks, TaskSection.tomorrow, now).length;
    final b = StringBuffer(t('📋 ملخص اليوم:\n', "📋 Today's summary:\n"));
    b.writeln(t('• مهام اليوم المتبقية: ${today.length}', '• Remaining today: ${today.length}'));
    b.writeln(t('• أنجزت اليوم: $doneToday', '• Completed today: $doneToday'));
    b.writeln(t('• متأخرة: $overdue', '• Overdue: $overdue'));
    b.writeln(t('• مهام بكرة: $tomorrow', '• Due tomorrow: $tomorrow'));
    if (today.isNotEmpty) {
      b.writeln(t('\nالأهم الآن:', '\nTop now:'));
      for (final x in today.take(3)) {
        b.writeln('• ${x.title} (${_prioName(x.priority, ar)})');
      }
    }
    return b.toString().trim();
  }

  String _summaryWeek(List<Task> tasks, DateTime now, bool ar) {
    String t(String a, String e) => ar ? a : e;
    final start = startOfWeek(now);
    final r = StatsCalculator.period(tasks, start, start.add(const Duration(days: 7)), now);
    final prev = StatsCalculator.period(tasks, start.subtract(const Duration(days: 7)), start, now);
    final remaining = TaskSections.filter(tasks, TaskSection.thisWeek, now).length;
    final ch = StatsCalculator.change(r.completed, prev.completed);
    final b = StringBuffer(t('📊 ملخص الأسبوع:\n', '📊 Weekly summary:\n'));
    b.writeln(t('• أنجزت: ${r.completed} مهمة', '• Completed: ${r.completed}'));
    b.writeln(t('• متبقي هذا الأسبوع: $remaining', '• Remaining this week: $remaining'));
    b.writeln(t('• متأخرة: ${r.overdue}', '• Overdue: ${r.overdue}'));
    b.writeln(t('• نسبة الإنتاجية: ${(r.productivityRate * 100).round()}٪', '• Productivity: ${(r.productivityRate * 100).round()}%'));
    if (ch != null) {
      b.writeln(t('• مقارنة بالأسبوع الماضي: ${ch >= 0 ? '+' : ''}${ch.round()}٪', '• vs last week: ${ch >= 0 ? '+' : ''}${ch.round()}%'));
    }
    return b.toString().trim();
  }

  String _productivity(List<Task> tasks, DateTime now, bool ar) {
    String t(String a, String e) => ar ? a : e;
    final today = dateOnly(now).add(const Duration(days: 1));
    final last = StatsCalculator.period(tasks, today.subtract(const Duration(days: 7)), today, now);
    final prev = StatsCalculator.period(tasks, today.subtract(const Duration(days: 14)), today.subtract(const Duration(days: 7)), now);
    final month = StatsCalculator.period(tasks, today.subtract(const Duration(days: 30)), today, now);
    final b = StringBuffer(t('📈 تحليل إنتاجيتك:\n', '📈 Productivity analysis:\n'));
    b.writeln(t('• آخر ٧ أيام: ${last.completed} مهمة (قبلها ${prev.completed})', '• Last 7 days: ${last.completed} tasks (previous: ${prev.completed})'));
    b.writeln(t('• معدل الإنجاز في المواعيد: ${(last.productivityRate * 100).round()}٪', '• On-time completion rate: ${(last.productivityRate * 100).round()}%'));
    if (month.avgCompletionTime != null) {
      b.writeln(t('• متوسط وقت إنجاز المهمة: ${_dur(month.avgCompletionTime!, ar)}', '• Average time to complete: ${_dur(month.avgCompletionTime!, ar)}'));
    }
    final best = month.bestWeekday;
    if (best != null) {
      b.writeln(t('• أفضل يوم إنتاجية: ${_weekdayName(best, ar)}', '• Most productive day: ${_weekdayName(best, ar)}'));
    }
    final overdue = TaskSections.filter(tasks, TaskSection.overdue, now).length;
    b.writeln();
    if (last.completed > prev.completed) {
      b.write(t('أداء ممتاز، إنتاجيتك في ارتفاع 🚀', 'Great work — your output is rising 🚀'));
    } else if (overdue > 3) {
      b.write(t('عندك $overdue مهام متأخرة؛ جرّب «رتب يومي» وركّز على ٣ مهام فقط.', 'You have $overdue overdue tasks; try "plan my day" and focus on 3 tasks.'));
    } else {
      b.write(t('حافظ على الاستمرارية: مهمتين يومياً تكفي لبناء عادة قوية 💪', 'Stay consistent: two tasks a day builds momentum 💪'));
    }
    return b.toString().trim();
  }

  String _bestTime(List<Task> tasks, bool ar) {
    String t(String a, String e) => ar ? a : e;
    final hours = List<int>.filled(24, 0);
    for (final x in tasks) {
      if (x.completedAt != null) hours[x.completedAt!.hour]++;
    }
    final total = hours.fold<int>(0, (a, b) => a + b);
    if (total < 5) {
      return t('ما عندي بيانات كافية بعد (أنجز ٥ مهام على الأقل). عموماً الصباح ٩–١١ أفضل للمهام الصعبة، والعصر للمهام الخفيفة.',
          'Not enough data yet (complete at least 5 tasks). Generally 9–11 AM suits deep work and afternoons suit lighter tasks.');
    }
    var bestStart = 0, bestSum = -1;
    for (var h = 0; h < 22; h++) {
      final s = hours[h] + hours[h + 1] + hours[h + 2];
      if (s > bestSum) {
        bestSum = s;
        bestStart = h;
      }
    }
    final tf = DateFormat('h a', ar ? 'ar' : 'en');
    final a = tf.format(DateTime(2000, 1, 1, bestStart));
    final b = tf.format(DateTime(2000, 1, 1, (bestStart + 3) % 24));
    return t('بناءً على $total مهمة أنجزتها، أفضل وقت لك بين $a و $b ⏰ خلّ المهام العاجلة والصعبة في هذي الفترة.',
        'Based on $total completed tasks, your peak window is $a – $b ⏰ Schedule urgent and hard tasks then.');
  }

  String _help(bool ar) => ar
      ? '''أقدر أساعدك في:
• إنشاء مهمة: «ذكرني بكرة الساعة ٥ العصر أتصل بالعميل عاجل #عمل»
• تقسيم مشروع: «قسم مشروع الموقع:» ثم كل خطوة في سطر
• «اقترح أولويات» حسب المواعيد
• «رتب يومي» لجدول مقترح
• «لخص يومي» أو «ملخص الأسبوع»
• «المهام المتأخرة»
• «حلل إنتاجيتي» و«أفضل وقت للعمل»
🎤 وتقدر تتكلم بدل الكتابة.'''
      : '''I can help you:
• Create tasks: "remind me tomorrow at 5pm to call the client urgent #work"
• Split a project: "split project Website:" then one step per line
• "suggest priorities" by deadline
• "plan my day"
• "summarize my day" / "weekly summary"
• "overdue tasks"
• "analyze my productivity", "best time to work"
🎤 You can also speak instead of typing.''';

  // ---------------- helpers ----------------

  static String _prioName(TaskPriority p, bool ar) => switch (p) {
        TaskPriority.low => ar ? 'منخفضة' : 'Low',
        TaskPriority.medium => ar ? 'متوسطة' : 'Medium',
        TaskPriority.high => ar ? 'عالية' : 'High',
        TaskPriority.urgent => ar ? 'عاجلة' : 'Urgent',
      };

  static String _weekdayName(int wd, bool ar) =>
      DateFormat('EEEE', ar ? 'ar' : 'en').format(DateTime(2024, 1, wd)); // 2024-01-01 is Monday

  static String _ago(Duration d, bool ar) {
    if (d.inDays >= 1) return ar ? '${d.inDays} يوم' : '${d.inDays}d';
    if (d.inHours >= 1) return ar ? '${d.inHours} ساعة' : '${d.inHours}h';
    return ar ? '${d.inMinutes} دقيقة' : '${d.inMinutes}m';
  }

  static String _dur(Duration d, bool ar) {
    if (d.inDays >= 1) return ar ? '${d.inDays} يوم و ${d.inHours % 24} ساعة' : '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) return ar ? '${d.inHours} ساعة' : '${d.inHours}h ${d.inMinutes % 60}m';
    return ar ? '${d.inMinutes} دقيقة' : '${d.inMinutes}m';
  }
}
