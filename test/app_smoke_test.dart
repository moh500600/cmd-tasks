// UI smoke test: boots the real app on an in-memory database, signs up,
// creates data through the UI layer and renders every main screen in both
// languages. With SCREENSHOTS=1 it also writes PNGs to build/screens/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tasks_pro/app.dart';
import 'package:tasks_pro/core/security/password_hasher.dart';
import 'package:tasks_pro/data/datasources/app_database.dart';
import 'package:tasks_pro/data/repositories/auth_repository_impl.dart';
import 'package:tasks_pro/domain/entities/enums.dart';
import 'package:tasks_pro/domain/entities/habit.dart';
import 'package:tasks_pro/domain/entities/project.dart';
import 'package:tasks_pro/domain/entities/task.dart';
import 'package:tasks_pro/presentation/providers/providers.dart';
import 'package:tasks_pro/presentation/screens/assistant/assistant_screen.dart';
import 'package:tasks_pro/presentation/screens/reports/reports_screen.dart';
import 'package:tasks_pro/presentation/screens/settings/settings_screen.dart';
import 'package:tasks_pro/presentation/screens/tasks/task_detail_screen.dart';
import 'package:tasks_pro/presentation/screens/tasks/task_edit_screen.dart';

final shots = Platform.environment['SCREENSHOTS'] == '1';
final _boundary = GlobalKey();

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final tajawal = FontLoader('Tajawal');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    tajawal.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Tajawal-$w.ttf').readAsBytesSync())));
  }
  await tajawal.load();
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 900));
  if (!shots) return;
  await tester.runAsync(() async {
    final b = _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2.5);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('build/screens/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  sqfliteFfiInit();

  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
    // Real fonts always: the default test font is wider than Tajawal and makes
    // tight rows overflow, which is a test artefact, not an app bug.
    await _loadFonts();
  });

  for (final lang in ['ar', 'en']) {
    testWidgets('app boots, signs in and renders all screens ($lang)', (tester) async {
      if (shots) debugDisableShadows = false; // real soft shadows in screenshots
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.7;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({'lang': lang, 'theme': ThemeMode.light.index});
      final prefs = await SharedPreferences.getInstance();
      late Database db;
      late int uid;
      await tester.runAsync(() async {
        db = await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
        final auth = AuthRepositoryImpl(db, hasher: const PasswordHasher(iterations: 10));
        uid = (await auth.signUp(name: lang == 'ar' ? 'محمد نضال' : 'Mohammad', email: 'm@x.com', password: 'secret1',
                securityQuestion: 'q', securityAnswer: 'a'))
            .user
            .id;
      });

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(key: _boundary, child: const TasksProApp()),
      ));
      await tester.pump();
      expect(find.byType(TextFormField), findsWidgets); // login screen
      await _shot(tester, '${lang}_00_login');

      // Sign in through the session and seed realistic data via the actions layer.
      final ar = lang == 'ar';
      await tester.runAsync(() async {
        final user = await AuthRepositoryImpl(db).getUser(uid);
        await container.read(sessionProvider.notifier).signIn(user!);
        final a = container.read(actionsProvider);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final p = await a.saveProject(Project(userId: uid, name: ar ? 'موقع سلمان للعسل' : 'Honey store website',
            description: ar ? 'متجر إلكتروني للعسل اليمني' : 'Online store', budget: 1500, spent: 600,
            iconCode: Icons.shopping_cart_rounded.codePoint, color: 0xFFF59E0B, endDate: today.add(const Duration(days: 12)), createdAt: now));
        await a.saveProject(Project(userId: uid, name: ar ? 'تطبيق روائع المساج' : 'Spa booking app', iconCode: Icons.phone_android_rounded.codePoint,
            color: 0xFF14B8A6, status: ProjectStatus.planning, createdAt: now));
        Task t(String ar1, String en1, DateTime? due, TaskPriority pr, {TaskStatus s = TaskStatus.todo, int? project, List<String> subs = const [], List<String> tags = const []}) =>
            Task(userId: uid, title: ar ? ar1 : en1, dueDate: due, priority: pr, status: s, projectId: project,
                subtasks: [for (final (i, x) in subs.indexed) Subtask(title: x, done: i == 0)],
                tags: [for (final x in tags) Tag(name: x)], reminderMinutes: due == null ? null : 15, createdAt: now, updatedAt: now);
        final list = [
          t('جعل الموقع متناسب مع اللابتوب', 'Make the site laptop-responsive', today.add(const Duration(hours: 16)), TaskPriority.urgent,
              s: TaskStatus.inProgress, project: p.id, subs: [ar ? 'الصفحة الرئيسية' : 'Home page', ar ? 'صفحة المنتج' : 'Product page', ar ? 'السلة' : 'Cart'], tags: [ar ? 'عمل' : 'work']),
          t('رفع الموقع على الاستضافة', 'Deploy site to hosting', today.add(const Duration(days: 1, hours: 11)), TaskPriority.high, project: p.id, tags: [ar ? 'عمل' : 'work']),
          t('رسم النظام للعميل', 'Draw the system diagram', today.add(const Duration(days: 3, hours: 10)), TaskPriority.medium),
          t('تحصيل المبلغ من العميل', 'Collect payment from client', today.subtract(const Duration(days: 1)).add(const Duration(hours: 14)), TaskPriority.high, tags: [ar ? 'مالية' : 'finance']),
          t('حل مشكلة جوجل', 'Fix the Google issue', today.add(const Duration(hours: 20)), TaskPriority.medium),
          t('شراء أغراض البيت', 'Buy groceries', null, TaskPriority.low),
        ];
        for (final x in list) {
          await a.saveTask(x);
        }
        for (var i = 1; i <= 6; i++) {
          final done = await a.saveTask(t('مهمة منجزة $i', 'Finished task $i', today.subtract(Duration(days: i)), TaskPriority.medium));
          await a.setStatus(done, TaskStatus.completed);
        }
        final h = await a.saveHabit(Habit(userId: uid, name: ar ? 'قراءة القرآن' : 'Read Quran', iconCode: Icons.menu_book_rounded.codePoint,
            color: 0xFF16A34A, createdAt: today.subtract(const Duration(days: 20)), reminderTime: '05:30'));
        final h2 = await a.saveHabit(Habit(userId: uid, name: ar ? 'رياضة ٣٠ دقيقة' : 'Workout 30 min', iconCode: Icons.fitness_center_rounded.codePoint,
            color: 0xFFEF4444, daysMask: 1 | 4 | 16 | 32, createdAt: today.subtract(const Duration(days: 20))));
        for (var i = 0; i < 9; i++) {
          await a.toggleHabit(h, today.subtract(Duration(days: i)));
          if (i % 2 == 0) await a.toggleHabit(h2, today.subtract(Duration(days: i)));
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(NavigationBar), findsOneWidget);
      await _shot(tester, '${lang}_01_dashboard');

      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
          await tester.pump(const Duration(milliseconds: 120));
        }
      }

      final navLabels = ar ? ['المهام', 'التقويم', 'المشاريع', 'العادات'] : ['Tasks', 'Calendar', 'Projects', 'Habits'];
      for (final (i, label) in navLabels.indexed) {
        await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
        await settle();
        await _shot(tester, '${lang}_0${i + 2}_${['tasks', 'calendar', 'projects', 'habits'][i]}');
      }
      // Overdue section chip in tasks screen
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(navLabels[0])));
      await settle();

      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      Future<void> open(Widget w, String name) async {
        nav.push(MaterialPageRoute(builder: (_) => w));
        await settle();
        await _shot(tester, name);
        nav.pop();
        await settle();
      }

      final tasks = await tester.runAsync(() => container.read(taskRepositoryProvider).getAll(uid));
      final first = tasks!.firstWhere((x) => x.subtasks.isNotEmpty);
      await open(TaskDetailScreen(taskId: first.id!), '${lang}_06_task_detail');
      await open(TaskEditScreen(initial: first), '${lang}_07_task_edit');
      await open(const ReportsScreen(), '${lang}_08_reports');
      await open(const SettingsScreen(), '${lang}_10_settings');

      // Assistant: send a real message through the rule-based engine.
      nav.push(MaterialPageRoute(builder: (_) => const AssistantScreen()));
      await settle();
      await tester.enterText(find.byType(TextField).last, ar ? 'ذكرني بكرة الساعة ٥ العصر أتصل بالعميل عاجل #عمل' : 'remind me tomorrow at 5pm to call the client urgent #work');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await settle();
      await tester.enterText(find.byType(TextField).last, ar ? 'رتب يومي' : 'plan my day');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await settle();
      expect(find.byType(FilledButton), findsWidgets);
      await _shot(tester, '${lang}_09_assistant');
      nav.pop();
      await settle();

      // Dark theme dashboard
      await tester.runAsync(() => container.read(settingsProvider.notifier).update((s) => s.copyWith(themeMode: ThemeMode.dark)));
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(ar ? 'الرئيسية' : 'Dashboard')));
      await settle();
      await _shot(tester, '${lang}_11_dashboard_dark');

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => db.close());
      debugDisableShadows = true;
    });
  }
}
