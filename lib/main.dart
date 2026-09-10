import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_controller.dart';
import 'app/workout_app.dart';
import 'data/local_workout_repository.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase không khả dụng (thiếu config/mạng) — app vẫn chạy local-first.
    debugPrint('Firebase khởi tạo thất bại: $e');
  }
  final preferences = await SharedPreferences.getInstance();
  final controller = AppController(
    LocalWorkoutRepository(preferences),
    preferences,
  );
  await controller.load();
  runApp(WorkoutApp(controller: controller));
}
