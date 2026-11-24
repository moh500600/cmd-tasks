import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/l10n.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/providers.dart';
import 'presentation/screens/auth/auth_screens.dart';
import 'presentation/screens/home/home_shell.dart';

class TasksProApp extends ConsumerWidget {
  const TasksProApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final user = ref.watch(sessionProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (c) => c.tr('app_name'),
      locale: Locale(settings.languageCode),
      supportedLocales: L10n.supported,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: user == null ? const LoginScreen(key: ValueKey('login')) : HomeShell(key: ValueKey('home-${user.id}')),
      ),
    );
  }
}
