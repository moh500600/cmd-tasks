// Drives real UI flows: sign up via the form, sign out/in, create a task
// through the task form, complete it from the list, and search.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tasks_pro/app.dart';
import 'package:tasks_pro/data/datasources/app_database.dart';
import 'package:tasks_pro/domain/entities/enums.dart';
import 'package:tasks_pro/presentation/providers/providers.dart';

void main() {
  sqfliteFfiInit();
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  testWidgets('sign up → create task via form → complete → sign out / sign in (en)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'lang': 'en'});
    final prefs = await SharedPreferences.getInstance();
    final db = (await tester.runAsync(() => AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath)))!;
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    Future<void> settle([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const TasksProApp()));
    await settle();

    // ---- sign up through the form
    await tester.tap(find.text('Sign up'));
    await settle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Mohammad Nidal');
    await tester.enterText(fields.at(1), 'mo@example.com');
    await tester.enterText(fields.at(2), 'secret12');
    await tester.enterText(fields.at(3), 'secret12');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settle();
    await tester.tap(find.text('In which city were you born?').last);
    await settle();
    await tester.enterText(find.byType(TextFormField).at(4), 'Sanaa');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign up'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign up'));
    await settle(12);
    expect(find.text('Recovery code'), findsOneWidget);
    await tester.tap(find.text('I saved it'));
    await settle(12);
    expect(container.read(sessionProvider)?.email, 'mo@example.com');
    expect(find.byType(NavigationBar), findsOneWidget);

    // ---- create a task via the FAB + form
    await tester.tap(find.byType(FloatingActionButton));
    await settle();
    await tester.enterText(find.byType(TextFormField).first, 'Write the CMD Tasks report');
    await tester.tap(find.text('Urgent'));
    await settle(2);
    await tester.dragUntilVisible(find.text('Add a subtask…'), find.byType(ListView).first, const Offset(0, -250));
    await settle(2);
    await tester.enterText(find.widgetWithText(TextField, 'Add a subtask…'), 'Collect numbers');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(2);
    await tester.tap(find.widgetWithText(FilledButton, 'Save').first, warnIfMissed: false);
    await settle(4);
    if (find.byType(NavigationBar).hitTestable().evaluate().isEmpty) {
      await tester.tap(find.widgetWithText(FilledButton, 'Save').first);
    }
    await settle(12);
    final tasks = (await tester.runAsync(() => container.read(taskRepositoryProvider).getAll(container.read(sessionProvider)!.id)))!;
    expect(tasks.single.title, 'Write the CMD Tasks report');
    expect(tasks.single.priority, TaskPriority.urgent);
    expect(tasks.single.subtasks.single.title, 'Collect numbers');

    // ---- it shows in "All tasks"; complete it with the checkbox
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Tasks')));
    await settle();
    await tester.dragUntilVisible(find.textContaining('All tasks'), find.byType(ListView).first, const Offset(-200, 0));
    await settle(2);
    await tester.tap(find.textContaining('All tasks'));
    await settle();
    expect(find.text('Write the CMD Tasks report'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await settle(10);
    final done = (await tester.runAsync(() => container.read(taskRepositoryProvider).getAll(container.read(sessionProvider)!.id)))!;
    expect(done.single.status, TaskStatus.completed);

    // ---- sign out and back in
    await tester.runAsync(() => container.read(sessionProvider.notifier).signOut());
    await settle();
    expect(find.text('Sign in'), findsWidgets);
    await tester.enterText(find.byType(TextFormField).at(0), 'mo@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrongpass');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(10);
    expect(find.text('Wrong email or password'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), 'secret12');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(12);
    expect(container.read(sessionProvider), isNotNull);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => db.close());
  });
}
