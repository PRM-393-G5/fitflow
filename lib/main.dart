import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_controller.dart';
import 'app/workout_app.dart';
import 'core/widgets/muscle_body_map.dart';
import 'data/api/api_client.dart';
import 'data/api/api_config.dart';
import 'data/api/token_store.dart';
import 'data/backend_auth_service.dart';
import 'data/google_id_tokens.dart';
import 'data/local_workout_repository.dart';
import 'data/openai_service.dart';
import 'data/reminder_service.dart';
import 'data/remote_workout_repository.dart';
import 'data/sync_outbox.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerMuscleMapLicense();
  await dotenv.load(isOptional: true);
  ReminderService? reminders;
  try {
    reminders = ReminderService();
    await reminders.init();
  } catch (e) {
    debugPrint('Notification setup failed: $e');
    reminders = null;
  }
  final preferences = await SharedPreferences.getInstance();
  // Flag of the removed guest mode; nothing reads it any more.
  if (preferences.containsKey('sign_in_skipped_v1')) {
    await preferences.remove('sign_in_skipped_v1');
  }
  final local = LocalWorkoutRepository(preferences);

  // One API client for the whole app: refresh tokens are single-use.
  final tokens = SecureTokenStore();
  final api = ApiClient(
    baseUrl: ApiConfig.baseUrl,
    tokens: tokens,
    // Give up connecting after 15 s, even on slow AI calls (95 s budget).
    httpClient: IOClient(
      HttpClient()..connectionTimeout = const Duration(seconds: 15),
    ),
  );
  // AI calls send the user's token too, so the server knows who used them.
  OpenAiService.defaultApi = api;
  final auth = BackendAuthService(
    api: api,
    tokens: tokens,
    preferences: preferences,
    google: GoogleSignInIdTokens(),
  );
  try {
    await auth.init();
  } catch (e) {
    // Secure storage unavailable — start signed out on the login page.
    debugPrint('Restoring the sign-in session failed: $e');
  }

  final controller = AppController(
    RemoteWorkoutRepository(
      api,
      local,
      preferences,
      SyncOutbox(preferences),
      currentUserId: () => auth.currentUser?.id,
    ),
    preferences,
    reminders: reminders,
    auth: auth,
  );
  await controller.load();
  // Reload when the account changes after startup: a sign-in merges its
  // cloud data; an expired session (signed out by the server) refreshes
  // every screen that showed the account.
  var lastUid = auth.currentUser?.id;
  auth.userChanges.listen((user) {
    if (user?.id != lastUid) controller.load();
    lastUid = user?.id;
  });
  runApp(WorkoutApp(controller: controller));
}
