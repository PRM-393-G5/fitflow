import 'dart:async';

import 'package:prm/features/exercise_demo/presentation/exercise_demo.dart';

/// Runs around every test file under test/. Exercise demos loop forever,
/// which keeps `pumpAndSettle` from settling, so they hold still here;
/// tests of the demo itself switch them back on.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ExerciseDemo.autoplay = false;
  await testMain();
}
