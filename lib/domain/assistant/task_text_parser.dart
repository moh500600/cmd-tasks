import '../../core/utils/date_x.dart';
import '../../core/utils/validators.dart';
import '../entities/enums.dart';
import 'assistant_engine.dart';

/// Rule-based Arabic / English parser for natural task phrases, e.g.
///  «ذكرني بكرة الساعة ٥ العصر أتصل بالعميل عاجل #عمل»
///  "remind me tomorrow at 5pm to call the client, urgent"
class TaskTextParser {
  static const _b = r'(?<![\p{L}\p{N}])'; // left word boundary (unicode safe)
  static const _e = r'(?![\p{L}\p{N}])'; // right word boundary

  static RegExp _re(String p) => RegExp(p, caseSensitive: false, unicode: true);

  static bool isArabic(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);

  static ParsedTask parse(String input, DateTime now) {
    // Remove tatweel and harakat/tanween so «صباحاً» matches «صباحا».
    var text = normalizeDigits(input).replaceAll(RegExp('[\u0640\u064B-\u065F\u0670]'), '');
    final spans = <(int, int)>[];

    RegExpMatch? take(RegExp re) {
      final m = re.firstMatch(text);
      if (m != null) spans.add((m.start, m.end));
      return m;
    }

    // ---------- tags ----------
    final tags = <String>[];
    for (final m in _re(r'#([\p{L}\p{N}_\-]+)').allMatches(text)) {
      tags.add(m.group(1)!);
      spans.add((m.start, m.end));
    }

    // ---------- priority ----------
    TaskPriority? priority;
    final prioRules = <(TaskPriority, String)>[
      (TaskPriority.low, '$_b(غير مهم[ةه]?|مو مهم|مش مهم|مب مهم|اولوي[ةه] منخفض[ةه]|أولوي[ةه] منخفض[ةه]|منخفض[ةه]? الاولوي[ةه]|low priority|not important|priority low)$_e'),
      (TaskPriority.urgent, '$_b(عاجل[ةه]?|مستعجل[ةه]?|ضروري|ضرورى|طارئ[ةه]?|urgent|asap|critical)$_e'),
      (TaskPriority.high, '$_b(مهم جدا|مهم جداً|مهم|اولوي[ةه] عالي[ةه]|أولوي[ةه] عالي[ةه]|عالي[ةه] الاولوي[ةه]|important|high priority|priority high)$_e'),
      (TaskPriority.medium, '$_b(اولوي[ةه] متوسط[ةه]|أولوي[ةه] متوسط[ةه]|عادي[ةه]?|medium priority|normal priority)$_e'),
    ];
    for (final (p, pattern) in prioRules) {
      if (take(_re(pattern)) != null) {
        priority = p;
        break;
      }
    }

    // ---------- reminder offset ----------
    int? reminder;
    final remBefore = take(_re(r'قبل\s*(\d+)\s*(دقيق[ةه]|دقايق|دقائق|ساع[ةه]|ساعات)|(\d+)\s*(minutes?|mins?|hours?)\s+before'));
    if (remBefore != null) {
      final n = int.parse(remBefore.group(1) ?? remBefore.group(3)!);
      final unit = (remBefore.group(2) ?? remBefore.group(4)!).toLowerCase();
      reminder = (unit.startsWith('ساع') || unit.startsWith('hour')) ? n * 60 : n;
    }
    final wantsReminder = _re('$_b(ذكرني|ذكرنى|فكرني|نبهني|remind me)$_e').hasMatch(text);

    // ---------- date ----------
    final today = dateOnly(now);
    DateTime? day;
    int? relMinutes;
    int? defaultHour;

    RegExpMatch? m;
    if ((m = take(_re('$_b(بعد\\s*بكر[ةه]|بعد\\s*بكرا|بعد\\s*غد|day after tomorrow)$_e'))) != null) {
      day = today.add(const Duration(days: 2));
    } else if ((m = take(_re('$_b(بكر[ةه]|بكرا|غدا|غداً|الغد|tomorrow|tmrw|tmr)$_e'))) != null) {
      day = today.add(const Duration(days: 1));
    } else if ((m = take(_re('$_b(الليل[ةه]|tonight)$_e'))) != null) {
      day = today;
      defaultHour = 21;
    } else if ((m = take(_re('$_b(اليوم|today)$_e'))) != null) {
      day = today;
    }
    if (day == null) {
      if ((m = take(_re(r'(?:بعد|خلال)\s*(\d+)\s*(يوم|ايام|أيام)'))) != null) {
        day = today.add(Duration(days: int.parse(m!.group(1)!)));
      } else if ((m = take(_re('(?:بعد|خلال)\\s*يومين$_e'))) != null) {
        day = today.add(const Duration(days: 2));
      } else if ((m = take(_re(r'in\s+(\d+)\s+days?'))) != null) {
        day = today.add(Duration(days: int.parse(m!.group(1)!)));
      } else if ((m = take(_re('(?:بعد\\s*(?:اسبوع|أسبوع)|$_b(?:الاسبوع|الأسبوع)\\s+(?:الجاي|القادم|الجاي[ةه]|الياي)|next week|in a week)$_e'))) != null) {
        day = today.add(const Duration(days: 7));
      } else if ((m = take(_re(r'(?:بعد|خلال)\s*(\d+)\s*(ساع[ةه]|ساعات)|in\s+(\d+)\s+hours?'))) != null) {
        relMinutes = int.parse(m!.group(1) ?? m.group(3)!) * 60;
      } else if ((m = take(_re('(?:بعد|خلال)\\s*ساعتين$_e'))) != null) {
        relMinutes = 120;
      } else if ((m = take(_re('(?:بعد|خلال)\\s*(?:ساع[ةه]|نص ساع[ةه]|نصف ساع[ةه])$_e|in an hour|in half an hour'))) != null) {
        relMinutes = m!.group(0)!.contains('نص') || m.group(0)!.contains('half') ? 30 : 60;
      } else if ((m = take(_re(r'(?:بعد|خلال)\s*(\d+)\s*(دقيق[ةه]|دقايق|دقائق)|in\s+(\d+)\s+(?:minutes?|mins?)'))) != null) {
        relMinutes = int.parse(m!.group(1) ?? m.group(3)!);
      }
    }
    if (day == null && relMinutes == null) {
      final wd = take(_re(
          '$_b(?:يوم\\s+)?(?:ال)?(سبت|احد|أحد|اثنين|إثنين|ثلاثاء|ثلاثا|اربعاء|أربعاء|اربعا|خميس|جمع[ةه])$_e|$_b(?:on\\s+|next\\s+)?(saturday|sunday|monday|tuesday|wednesday|thursday|friday|sat|sun|mon|tue|wed|thu|fri)$_e'));
      if (wd != null) {
        final target = _weekday((wd.group(1) ?? wd.group(2)!).toLowerCase());
        if (target != null) {
          var diff = (target - today.weekday + 7) % 7;
          if (diff == 0) diff = 7;
          day = today.add(Duration(days: diff));
        }
      }
    }
    if (day == null && relMinutes == null) {
      final dm = take(_re(r'(?<!\d)(\d{1,2})[/\-.](\d{1,2})(?:[/\-.](\d{2,4}))?(?!\d)'));
      if (dm != null) {
        final d = int.parse(dm.group(1)!), mo = int.parse(dm.group(2)!);
        var y = dm.group(3) != null ? int.parse(dm.group(3)!) : today.year;
        if (y < 100) y += 2000;
        if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
          var candidate = DateTime(y, mo, d);
          if (dm.group(3) == null && candidate.isBefore(today)) {
            candidate = DateTime(y + 1, mo, d);
          }
          day = candidate;
        }
      }
    }

    // ---------- time ----------
    int? hour;
    var minute = 0;
    const periodAr =
        r'(صباحا|صباحاً|صباح|الصبح|الفجر|ص|الظهر|ظهرا|ظهراً|العصر|عصرا|عصراً|مساء|مساءا|مساءً|المسا|المساء|المغرب|العشاء|بالليل|الليل|ليلا|ليلاً|م)';
    final tAr = take(_re('(?:الساع[ةه]|ساع[ةه]|الساعه)\\s*(\\d{1,2})(?:[:.](\\d{2}))?\\s*(ونص|و نص|والنص|وربع|و ربع|الا ربع|إلا ربع|الا ثلث|وثلث)?\\s*(?:$periodAr$_e)?'));
    String? period;
    if (tAr != null) {
      hour = int.parse(tAr.group(1)!);
      minute = tAr.group(2) != null ? int.parse(tAr.group(2)!) : 0;
      final frac = tAr.group(3);
      if (frac != null) {
        if (frac.contains('نص')) minute = 30;
        if (frac.contains('ربع')) minute = frac.contains('ال') || frac.contains('إل') ? -15 : 15;
        if (frac.contains('ثلث')) minute = frac.contains('ال') ? -20 : 20;
      }
      period = tAr.group(4);
    } else {
      final tEn = take(_re(r'(?:at\s+)?(?<![\d/])(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)(?![\p{L}])|at\s+(\d{1,2})(?::(\d{2}))?(?![\d\p{L}])|(?<![\d/])(\d{1,2}):(\d{2})(?![\d/])'));
      if (tEn != null) {
        hour = int.parse(tEn.group(1) ?? tEn.group(4) ?? tEn.group(6)!);
        minute = int.parse(tEn.group(2) ?? tEn.group(5) ?? tEn.group(7) ?? '0');
        period = tEn.group(3);
      }
    }
    if (period == null) {
      final p = take(_re('$_b(الصبح|صباحا|صباحاً|الظهر|العصر|المغرب|العشاء|بالليل|في الليل|morning|noon|afternoon|evening)$_e'));
      if (p != null) {
        period = p.group(1);
        hour ??= switch (period!.toLowerCase()) {
          'الصبح' || 'صباحا' || 'صباحاً' || 'morning' => 9,
          'الظهر' || 'noon' => 12,
          'العصر' || 'afternoon' => 16,
          'المغرب' => 18,
          'evening' => 19,
          'العشاء' => 20,
          _ => 21,
        };
        if (hour >= 12) period = null; // already 24h
      }
    }
    if (hour != null) {
      final pm = period != null &&
          RegExp(r'^(م|مساء|مساءا|مساءً|المسا|المساء|العصر|عصرا|عصراً|المغرب|العشاء|بالليل|الليل|ليلا|ليلاً|pm|p\.m\.)$')
              .hasMatch(period.toLowerCase());
      final am = period != null &&
          RegExp(r'^(ص|صباحا|صباحاً|صباح|الصبح|الفجر|am|a\.m\.)$').hasMatch(period.toLowerCase());
      final noon = period != null && RegExp(r'^(الظهر|ظهرا|ظهراً)$').hasMatch(period);
      if (pm && hour < 12) hour += 12;
      if (am && hour == 12) hour = 0;
      if (noon && hour <= 5) hour += 12;
      if (!pm && !am && !noon && hour >= 1 && hour <= 7) hour += 12; // «الساعة ٥» → 5 PM
      if (minute < 0) {
        hour = (hour - 1) % 24;
        minute = 60 + minute;
      }
      if (hour > 23 || minute > 59) {
        hour = null;
        minute = 0;
      }
    }

    // ---------- combine ----------
    DateTime? due;
    var hasTime = false;
    if (relMinutes != null) {
      due = now.add(Duration(minutes: relMinutes));
      hasTime = true;
    } else if (day != null || hour != null) {
      final base = day ?? today;
      if (hour != null) {
        due = DateTime(base.year, base.month, base.day, hour, minute);
        hasTime = true;
        if (day == null && due.isBefore(now)) due = due.add(const Duration(days: 1));
      } else {
        due = DateTime(base.year, base.month, base.day, defaultHour ?? 23, defaultHour != null ? 0 : 59);
        hasTime = defaultHour != null;
      }
    }

    // ---------- title ----------
    spans.sort((a, b) => b.$1.compareTo(a.$1));
    for (final (s, e) in spans) {
      text = text.replaceRange(s, e, ' ');
    }
    final title = cleanTitle(text);

    return ParsedTask(
      title: title,
      dueDate: due,
      hasTime: hasTime,
      priority: priority,
      tags: tags,
      reminderMinutes: reminder ?? ((wantsReminder && due != null) ? 0 : null),
    );
  }

  static final _lead = RegExp(
      r'^(?:\s|[,،:.\-]|ذكرني|ذكرنى|فكرني|نبهني|أضف|اضف|ضيف|ضف|سجل|سجلي|أنشئ|انشئ|اعمل|سوي|سو|حط|خلني|لازم|عندي|مهم[ةه]\s+جديد[ةه]|مهم[ةه]|جديد[ةه]|إني|اني|أني|إن|ان|أن|بان|بأن|اذكرني|remind me to|remind me|please|add a task to|add task|add|create a task|create task|create|new task|task|todo|to do|i need to|i have to|need to|to)(?=\s|$|[,،:])',
      caseSensitive: false,
      unicode: true);
  static final _edge = RegExp(
      r'(^|\s)(?:في|على|يوم|الساع[ةه]|و|ب|on|at|by|in|the|and)(?=\s*$)|^(?:في|على|يوم|on|at|by|and)\s',
      caseSensitive: false,
      unicode: true);

  static String cleanTitle(String raw) {
    var t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    String prev;
    do {
      prev = t;
      t = t.replaceFirst(_lead, '').trim();
      t = t.replaceAll(_edge, ' ').trim();
      t = t.replaceAll(RegExp(r'^[,،:.\-–!؟?\s]+|[,،:.\-–\s]+$'), '').trim();
    } while (t != prev && t.isNotEmpty);
    // «بالعميل» after «أتصل» is fine; strip a lone leading «ب» glued to a verb.
    return t.replaceAll(RegExp(r'\s+'), ' ');
  }

  static int? _weekday(String w) {
    if (w.contains('سبت') || w.startsWith('sat')) return DateTime.saturday;
    if (w.contains('احد') || w.contains('أحد') || w.startsWith('sun')) return DateTime.sunday;
    if (w.contains('اثنين') || w.contains('إثنين') || w.startsWith('mon')) return DateTime.monday;
    if (w.contains('ثلاث') || w.startsWith('tue')) return DateTime.tuesday;
    if (w.contains('ربع') || w.startsWith('wed')) return DateTime.wednesday;
    if (w.contains('خميس') || w.startsWith('thu')) return DateTime.thursday;
    if (w.contains('جمع') || w.startsWith('fri')) return DateTime.friday;
    return null;
  }

  /// Splits a project description into sub-task titles: first by lines,
  /// otherwise by sentence separators and connectors (ثم / بعدين / then …).
  static List<String> splitIntoSubtasks(String text) {
    final normalized = normalizeDigits(text).trim();
    var parts = normalized
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length < 2) {
      parts = normalized
          .split(RegExp(r'[.;؛!?؟]+|،\s*(?:و\s*)?(?:ثم|بعدين|بعدها)?|,\s*(?:and\s+)?(?:then)?|\s(?:ثم|بعدين|وبعدين|وبعدها|بعد كذا|وبعد كذا|then|after that|and then)\s', unicode: true))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final bullet = RegExp(r'^(?:[-*•▪◦–]|\d+[\-.)]|[\u0660-\u0669]+[\-.)])\s*', unicode: true);
    return parts
        .map((s) => s.replaceFirst(bullet, '').trim())
        .map((s) => s.replaceFirst(RegExp(r'^(?:و|and)\s+', unicode: true), '').trim())
        .where((s) => s.length > 1)
        .toList();
  }
}
