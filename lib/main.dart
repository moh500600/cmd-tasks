import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/platform/database_bootstrap.dart';
import 'data/datasources/app_database.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'data/services/settings_repository.dart';
import 'domain/entities/user.dart';
import 'presentation/providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');

  final prefs = await SharedPreferences.getInstance();
  // sqflite on Android/iOS, sqflite_common_ffi on Windows/Linux (same schema).
  final dbLocation = await resolveDatabase(AppDatabase.fileName);
  final db = await AppDatabase.open(dbLocation.factory, dbLocation.path);

  // Restore the session when "keep me signed in" is on.
  final settingsRepo = SettingsRepository(prefs);
  AppUser? user;
  final sid = settingsRepo.sessionUserId;
  if (sid != null) {
    if (settingsRepo.load().keepSignedIn) {
      user = await AuthRepositoryImpl(db).getUser(sid);
    } else {
      await settingsRepo.setSession(null);
    }
  }

  final container = ProviderContainer(overrides: [
    databaseProvider.overrideWithValue(db),
    sharedPrefsProvider.overrideWithValue(prefs),
    initialUserProvider.overrideWithValue(user),
  ]);
  await container.read(notificationServiceProvider).init();

  runApp(UncontrolledProviderScope(container: container, child: const TasksProApp()));
}
