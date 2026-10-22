import 'package:material_ui/material_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_controller.dart';
import 'app/workout_app.dart';
import 'data/api/api_client.dart';
import 'data/api/api_config.dart';
import 'data/api/token_store.dart';
import 'data/backend_auth_service.dart';
import 'data/google_id_tokens.dart';
import 'data/local_workout_repository.dart';
import 'data/reminder_service.dart';
import 'data/remote_workout_repository.dart';
import 'data/sync_outbox.dart';
import 'features/progress/presentation/muscle_map_card.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerMuscleMapLicense();
  await dotenv.load(isOptional: true);
  ReminderService? reminders;
  try {
    reminders = ReminderService();
    await reminders.init();
  } catch (e) {
    debugPrint('Notifications khởi tạo thất bại: $e');
    reminders = null;
  }
  final preferences = await SharedPreferences.getInstance();
  final local = LocalWorkoutRepository(preferences);

  // One API client for the whole app: refresh tokens are single-use.
  final tokens = SecureTokenStore();
  final api = ApiClient(baseUrl: ApiConfig.baseUrl, tokens: tokens);
  final auth = BackendAuthService(
    api: api,
    tokens: tokens,
    preferences: preferences,
    google: GoogleSignInIdTokens(),
  );
  try {
    await auth.init();
  } catch (e) {
    // Secure storage unavailable — start signed out; local data still works.
    debugPrint('Khôi phục phiên đăng nhập thất bại: $e');
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
