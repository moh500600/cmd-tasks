import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../assistant/assistant_screen.dart';
import '../calendar/calendar_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../habits/habits_screen.dart';
import '../profile/profile_screen.dart';
import '../projects/project_edit_screen.dart';
import '../projects/projects_screen.dart';
import '../reports/reports_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../tasks/task_edit_screen.dart';
import '../tasks/tasks_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  final _calendarKey = GlobalKey<CalendarScreenState>();

  @override
  void initState() {
    super.initState();
    // Refresh scheduled notifications (digest counts, new day) on launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(actionsProvider).rescheduleNotifications();
    });
  }

  void _push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  void _onFab() {
    switch (_index) {
      case 2:
        final day = _calendarKey.currentState?.selectedDay ?? DateTime.now();
        _push(TaskEditScreen(initialDue: ref.read(actionsProvider).defaultDueFor(day)));
      case 3:
        _push(const ProjectEditScreen());
      case 4:
        _push(const HabitEditScreen());
      default:
        _push(const TaskEditScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final dests = [
      (Icons.dashboard_outlined, Icons.dashboard_rounded, context.tr('nav_dashboard')),
      (Icons.task_alt_outlined, Icons.task_alt_rounded, context.tr('nav_tasks')),
      (Icons.calendar_month_outlined, Icons.calendar_month_rounded, context.tr('nav_calendar')),
      (Icons.folder_outlined, Icons.folder_rounded, context.tr('nav_projects')),
      (Icons.self_improvement_outlined, Icons.self_improvement_rounded, context.tr('nav_habits')),
    ];
    final pages = [
      const DashboardScreen(),
      const TasksScreen(),
      CalendarScreen(key: _calendarKey),
      const ProjectsScreen(),
      const HabitsScreen(),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final fabLabel = switch (_index) { 3 => 'new_project', 4 => 'new_habit', _ => 'new_task' };

    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(dests[_index].$3),
        actions: [
          IconButton(tooltip: context.tr('search'), icon: const Icon(Icons.search_rounded), onPressed: () => _push(const SearchScreen())),
          IconButton(tooltip: context.tr('assistant'), icon: const Icon(Icons.auto_awesome_rounded), onPressed: () => _push(const AssistantScreen())),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Builder(
              builder: (ctx) => GestureDetector(
                onTap: () => Scaffold.of(ctx).openEndDrawer(),
                child: UserAvatar(path: user?.avatarPath, name: user?.name ?? '', radius: 17),
              ),
            ),
          ),
        ],
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: ListView(children: [
            ListTile(
              leading: UserAvatar(path: user?.avatarPath, name: user?.name ?? ''),
              title: Text(user?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(user?.email ?? ''),
              onTap: () {
                Navigator.pop(context);
                _push(const ProfileScreen());
              },
            ),
            const Divider(),
            for (final (icon, key, page) in [
              (Icons.auto_awesome_rounded, 'assistant', const AssistantScreen() as Widget),
              (Icons.insights_rounded, 'reports', const ReportsScreen() as Widget),
              (Icons.search_rounded, 'search', const SearchScreen() as Widget),
              (Icons.settings_rounded, 'settings', const SettingsScreen() as Widget),
              (Icons.person_rounded, 'profile', const ProfileScreen() as Widget),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(context.tr(key)),
                onTap: () {
                  Navigator.pop(context);
                  _push(page);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: Text(context.tr('logout')),
              onTap: () async {
                Navigator.pop(context);
                if (await confirm(context, context.tr('logout'), context.tr('logout_confirm'))) {
                  await ref.read(sessionProvider.notifier).signOut();
                }
              },
            ),
          ]),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'main-fab',
        onPressed: _onFab,
        icon: const Icon(Icons.add_rounded),
        label: Text(context.tr(fabLabel)),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [for (final d in dests) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3)],
            ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: _index,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3))],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
    );
  }
}
