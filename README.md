# FitFlow

FitFlow is a Flutter workout-tracking MVP. It ships with built-in workout plans, guides a local workout session, and records progress on the device without requiring an account or network connection. Signing in with Google is optional and adds Firestore backup and multi-device sync.

## Toolchain

- Flutter stable with Dart compatible with `sdk: ^3.13.2` in `pubspec.yaml`
- Verified with Flutter 3.47.2 and Dart 3.13.2
- Android builds: Android SDK, an accepted Android SDK license set, and a JDK compatible with the Flutter/Gradle toolchain
- iOS builds (macOS only): Xcode and CocoaPods as required by Flutter

Check the local installation with:

```sh
flutter doctor -v
```

## Setup and run

```sh
flutter pub get
cp .env.example .env   # then put your OPENAI_API_KEY inside
flutter run
```

`.env` is gitignored and bundled as an asset — without it the build
fails on the missing asset entry, so create it even if empty.
`--dart-define=OPENAI_API_KEY=sk-...` also works.

Select a target explicitly when needed, for example `flutter run -d <device-id>`. Android and iOS currently use the existing `com.zcode9211.prm` application identifier.

## Quality checks and tests

Run the same checks used for handoff:

```sh
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

The debug Android APK is generated at:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

For a distributable Android release, configure a production application ID and release signing before running `flutter build apk --release` or `flutter build appbundle --release`.

## MVP features

- Home dashboard with weekly workout statistics and quick start
- Browse and filter bundled workout plans by category
- Workout details with exercise, set, repetition, and rest guidance
- Active workout flow with set completion, rest countdown, and finish confirmation
- Local workout history and progress summaries
- Activity heatmap, weekly minutes chart, and personal records
- Achievements derived from streaks, volume, and session counts
- Custom workout builder for user-created plans
- AI workout generator that builds a plan from a text prompt (OpenAI, needs `OPENAI_API_KEY` via `--dart-define`)
- Nutrition tab with a TDEE+goal calorie target, AI-suggested daily meal plans, food-photo analysis, and a local daily intake log vs target (same OpenAI key)
- Body weight log with trend chart plus BMI/BMR/TDEE profile
- Onboarding goal/level setup that personalizes suggested workouts
- Weekly schedule that pins a plan to each day
- AI form check for squat, push-up, and plank via on-device pose detection
- Reminder preferences, JSON export/import backup, and a shareable summary image
- Optional Google sign-in with Firestore sync, sign-out and account deletion
- Session detail view per completed workout
- Theme selection (system, light, or dark)
- Metric/imperial preference
- Responsive Material UI for phone and wider layouts

## Firestore rules

Security rules live in `firestore.rules` (templates public read-only, each user limited to `users/{uid}`). Deploy them with `firebase deploy --only firestore:rules`.

## Architecture and directories

The project separates app composition, domain rules, persistence, and feature UI:

- `lib/main.dart`: Flutter entry point and dependency setup
- `lib/app/`: application shell, shared controller, and app scope
- `lib/core/`: theme, responsive layout, and reusable widgets
- `lib/domain/`: framework-independent models, statistics, and repository contracts
- `lib/data/`: bundled seed workouts and the local repository implementation
- `lib/features/`: feature-first presentation for home, workouts, progress, profile, and navigation
- `test/`: repository, statistics, and widget tests
- `android/` and `ios/`: native Flutter platform projects

`WorkoutRepository` keeps presentation code independent of storage. `LocalWorkoutRepository` is the current implementation.

## Local storage

FitFlow uses `shared_preferences` only; no data is sent to a server.

- Bundled workouts are seeded on first access and stored as JSON under `workouts_v1`.
- Completed sessions are stored as JSON under `sessions_v1`.
- Body weight entries are stored as JSON under `body_weights_v1`.
- Theme and unit choices are stored under `theme_mode` and `unit_system`.
- Data is scoped to the app installation and may be removed when the app is uninstalled or its storage is cleared.
- There is currently no sync, export, migration UI, encryption layer, or cross-device recovery.

`shared_preferences` is appropriate for this MVP's small local dataset, but it is not intended for sensitive data or large relational datasets.

## Restore the archived Expo source

The previous Expo project is preserved outside this Flutter repository at:

```text
/home/elior/Documents/prm-expo-source-backup-20260921-221759.tar.gz
```

Expected SHA-256:

```text
5692a1d029cdfdb2cf2231a56491ac72487ed204fc46202271a8ec80dc1e3b8d
```

Restore it into a separate directory so it does not overwrite the active Flutter app:

```sh
sha256sum /home/elior/Documents/prm-expo-source-backup-20260921-221759.tar.gz
mkdir -p /home/elior/Documents/prm-expo-restored
tar -xzf /home/elior/Documents/prm-expo-source-backup-20260921-221759.tar.gz \
  -C /home/elior/Documents/prm-expo-restored --strip-components=1
```

The checksum must match before relying on the archive. Do not extract it over `/home/elior/Documents/prm` unless replacing the Flutter project is explicitly intended.

## Current limitations

- Offline-only: there is no backend API or cloud synchronization.
- No authentication, accounts, or multi-user separation.
- Workout plans are bundled seed data plus locally created custom workouts; there is no remote catalog.
- Local preferences are not a secure store and are not backed up by FitFlow.
- No push notifications, social features, subscriptions, or wearable integrations.
- Release signing and store distribution are not configured; the documented APK is a debug build.

The active project contains Flutter/Dart and native Flutter platform configuration only. Legacy Expo source and assets belong in the external backup described above, not in the active app.
