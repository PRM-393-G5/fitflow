import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_controller.dart';
import 'app/workout_app.dart';
import 'data/firestore_workout_repository.dart';
import 'data/local_workout_repository.dart';
import 'data/reminder_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } catch (e) {
    // Firebase không khả dụng (thiếu config/mạng) — app vẫn chạy local-first.
    debugPrint('Firebase khởi tạo thất bại: $e');
  }
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
  final controller = AppController(
    firebaseReady
        ? FirestoreWorkoutRepository(
            FirebaseFirestore.instance,
            local,
            preferences,
          )
        : local,
    preferences,
    reminders: reminders,
  );
  await controller.load();
  runApp(WorkoutApp(controller: controller));
}
