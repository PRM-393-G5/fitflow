import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:patrol/patrol.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/app_scope.dart';
import 'package:prm/core/widgets/app_card.dart';
import 'package:prm/data/api/api_config.dart';
import 'package:prm/data/api/token_store.dart';
import 'package:prm/features/auth/presentation/login_page.dart';
import 'package:prm/features/navigation/presentation/app_shell.dart';
import 'package:prm/features/onboarding/presentation/onboarding_page.dart';
import 'package:prm/main.dart' as app;

/// The Google account to sign in with when the phone has several:
/// `--dart-define=E2E_GOOGLE_ACCOUNT=you@gmail.com`. Without it the first
/// account in Google's picker is used.
const googleAccount = String.fromEnvironment('E2E_GOOGLE_ACCOUNT');

/// The app package; Google's sheets and system dialogs are anything else.
const _appPackage = 'com.zcode9211.prm';

/// Sign-in and sync go over the network, so finders wait longer than the
/// defaults. Settling stays short: spinners and rest timers never settle.
const _config = PatrolTesterConfig(
  existsTimeout: Duration(seconds: 20),
  visibleTimeout: Duration(seconds: 20),
  settleTimeout: Duration(seconds: 3),
  printLogs: true,
);

/// A test against the real app on a device. Each one starts from a fresh
/// install state (Patrol clears the app's data first), so it signs in.
void e2eTest(String description, PatrolTesterCallback body) =>
    patrolTest(description, config: _config, body);

/// Starts the app exactly as `flutter run` does and signs in with Google.
Future<void> launchSignedIn(PatrolIntegrationTester $) async {
  await launchApp($);
  await signIn($);
}

/// Starts the app; with its data cleared it opens on the login page.
Future<void> launchApp(PatrolIntegrationTester $) async {
  await app.main();
  await $.pumpAndTrySettle();
  await $('Continue with Google').waitUntilVisible();
}

/// Signs in through Google's native account picker, waits for the first
/// cloud sync, and skips onboarding if this account never finished it
/// (unless [skipOnboarding] is false: the test goes through it).
Future<void> signIn(
  PatrolIntegrationTester $, {
  bool skipOnboarding = true,
}) async {
  await $('Continue with Google').tap();
  await $.platform.android.tap(
    AndroidSelector(textContains: googleAccount.isEmpty ? '@' : googleAccount),
    timeout: const Duration(seconds: 30),
  );
  // The first sign-in to FitFlow with an account asks to share the
  // profile once ("Continue"); later ones go straight back to the app.
  await waitUntil(
    $,
    'the app after Google sign-in',
    () => $(AppShell).exists,
    onPoll: () => _tapGoogleContinue($),
  );
  await waitForSync($);
  await $.pumpAndTrySettle();
  if (!skipOnboarding) return;
  if ($(OnboardingPage).exists) await $('Skip for now').tap();
  expect($(OnboardingPage), findsNothing);
}

/// Signs out from Profile and waits for the login page.
Future<void> signOut(PatrolIntegrationTester $) async {
  await openTab($, 'Profile');
  await $(const Key('profile-sign-out')).scrollTo();
  await $(const Key('profile-sign-out')).tap();
  await $(LoginPage).waitUntilVisible();
}

Future<void> _tapGoogleContinue(PatrolIntegrationTester $) async {
  for (final label in const ['Continue', 'Tiếp tục']) {
    final views = await $.platform.android.getNativeViews(
      AndroidSelector(textStartsWith: label),
    );
    for (final view in views.roots) {
      if (view.applicationPackage == _appPackage) continue;
      await $.platform.android.tap(
        AndroidSelector(
          text: view.text,
          applicationPackage: view.applicationPackage,
        ),
      );
      return;
    }
  }
}

/// The app's controller, to wait on its state (never to drive it).
AppController controllerOf(PatrolIntegrationTester $) =>
    AppScope.of($.tester.element(find.byType(AppShell, skipOffstage: false)));

/// Waits until the sync started by signing in has finished.
Future<void> waitForSync(PatrolIntegrationTester $) async {
  final controller = controllerOf($);
  await waitUntil(
    $,
    'the cloud sync',
    () =>
        !controller.loading &&
        !controller.syncing &&
        (controller.lastSyncedAt != null || controller.lastSyncFailed),
  );
  if (controller.lastSyncFailed) {
    fail('Sync failed — is the API reachable at ${ApiConfig.baseUrl}?');
  }
}

/// Pumps frames until [done] is true; fails after [timeout].
Future<void> waitUntil(
  PatrolIntegrationTester $,
  String what,
  FutureOr<bool> Function() done, {
  Duration timeout = const Duration(seconds: 60),
  Future<void> Function()? onPoll,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await done()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for $what');
    await onPoll?.call();
    await $.pump(const Duration(milliseconds: 500));
  }
}

/// Waits until nothing matches [finder] (a page closed, a row removed).
Future<void> waitUntilGone(
  PatrolIntegrationTester $,
  PatrolFinder finder,
  String what,
) => waitUntil(
  $,
  what,
  () => !finder.exists,
  timeout: const Duration(seconds: 20),
);

/// Opens a tab of the bottom navigation bar.
Future<void> openTab(PatrolIntegrationTester $, String label) async {
  await $(FBottomNavigationBarItem).containing(label).tap();
  await $.pumpAndTrySettle();
}

/// Presses Android's back button and lets the page close.
Future<void> goBack(PatrolIntegrationTester $) async {
  await $.platform.android.pressBack();
  await $.pumpAndTrySettle();
}

/// Scrolls [finder] into view, up or down. `scrollTo` only scrolls down;
/// this needs the widget built, which it is on the app's pages (single
/// scroll views, not lazy lists).
Future<void> reveal(PatrolIntegrationTester $, PatrolFinder finder) async {
  await finder.waitUntilExists();
  await $.tester.ensureVisible(finder.first);
  await $.pumpAndTrySettle();
}

/// Whether the first [FButton] matching [button] can be pressed.
bool isEnabled(PatrolIntegrationTester $, PatrolFinder button) =>
    $.tester.widget<FButton>(button.first).onPress != null;

/// The Nutrition tab's card for meal slot [type] ("Breakfast", "Lunch"…).
PatrolFinder mealSlot(PatrolIntegrationTester $, String type) =>
    $(AppCard).containing(Key('nutrition-add-$type'));

/// The logged entry in slot [type] whose dishes include [dish].
PatrolFinder loggedMeal(PatrolIntegrationTester $, String type, String dish) =>
    mealSlot(
      $,
      type,
    ).$(Row).containing(dish).containing(const Key('nutrition-meal-more'));

/// Opens the actions (edit portion, move, remove) of a logged meal.
Future<void> openMealActions(
  PatrolIntegrationTester $,
  String type,
  String dish,
) async {
  final meal = loggedMeal($, type, dish);
  await reveal($, meal);
  await meal.$(const Key('nutrition-meal-more')).tap();
  await $(const Key('nutrition-meal-remove')).waitUntilVisible();
}

/// Grants the runtime permission dialog if one shows up (camera,
/// notifications); every run starts with no permissions granted.
Future<void> grantPermissionIfAsked(PatrolIntegrationTester $) async {
  if (await $.platform.mobile.isPermissionDialogVisible(
    timeout: const Duration(seconds: 5),
  )) {
    await $.platform.mobile.grantPermissionWhenInUse();
  }
}

/// A name no real entry has, so a test only ever touches its own data.
String uniqueName(String prefix) =>
    '$prefix ${DateTime.now().millisecondsSinceEpoch % 1000000}';

/// The signed-in account's data as the API holds it — to check what
/// really reached the server. Uses the app's current access token and
/// never refreshes it (refresh tokens are single-use; that is the app's).
class Cloud {
  const Cloud(this.$);

  final PatrolIntegrationTester $;

  Future<Map<String, String>> _headers() async {
    final session = await SecureTokenStore().read();
    if (session == null) fail('No API session stored — not signed in');
    return {
      'Authorization': 'Bearer ${session.accessToken}',
      'Content-Type': 'application/json',
    };
  }

  Future<dynamic> _get(String path) async {
    final response = await http.get(
      ApiConfig.baseUrl.resolve(path),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      fail('GET $path → ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body);
  }

  /// The signed-in user (`GET /me`).
  Future<Map<String, dynamic>> me() async =>
      Map<String, dynamic>.from(await _get('me') as Map);

  /// Every document of [kind], tombstones (`deleted: true`) included.
  Future<List<Map<String, dynamic>>> docs(String kind) async => [
    for (final doc in await _get('me/docs/$kind') as List)
      Map<String, dynamic>.from(doc as Map),
  ];

  /// The live (not deleted) document of [kind] with [id], if any.
  Future<Map<String, dynamic>?> doc(String kind, String id) async {
    for (final doc in await docs(kind)) {
      if (doc['id'] == id && doc['deleted'] != true) return doc;
    }
    return null;
  }

  /// Waits for the app's outbox to deliver a live [kind] document that
  /// matches [test], and returns it.
  Future<Map<String, dynamic>> waitForDoc(
    String kind,
    String what,
    bool Function(Map<String, dynamic> doc) test,
  ) async {
    Map<String, dynamic>? found;
    await _poll('$what to reach the server', () async {
      for (final doc in await docs(kind)) {
        if (doc['deleted'] != true && test(doc)) {
          found = doc;
          return true;
        }
      }
      return false;
    });
    return found!;
  }

  /// Waits until the server holds [kind] document [id] as deleted.
  Future<void> waitForDeleted(String kind, String id) =>
      _poll('the deletion of $kind/$id to reach the server', () async {
        return await doc(kind, id) == null;
      });

  /// Writes [body] as [kind] document [id] — restores data a test
  /// changed, or plays another device logging something.
  Future<void> put(String kind, String id, Map<String, dynamic> body) =>
      _send('PUT', 'me/docs/$kind/${Uri.encodeComponent(id)}', body);

  /// Deletes [kind] document [id] (cleans up after a failed test).
  Future<void> delete(String kind, String id) =>
      _send('DELETE', 'me/docs/$kind/${Uri.encodeComponent(id)}');

  /// The synced profile, weekly schedule, onboarding and weekly goal
  /// (`GET /me/meta`); null if the account never wrote them.
  Future<Map<String, dynamic>?> meta() async {
    final meta = (await _get('me/meta') as Map)['meta'];
    return meta is Map ? Map<String, dynamic>.from(meta) : null;
  }

  /// Replaces the synced meta as another device would: stamped now, so
  /// it beats every earlier write.
  Future<void> putMeta(Map<String, dynamic> meta) async {
    final body = await _send('PUT', 'me/meta', {
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'meta': meta,
    });
    if ((jsonDecode(body) as Map)['applied'] != true) {
      fail('The server kept a newer meta than this write: $body');
    }
  }

  /// Puts the meta back as it is now when the test ends — for tests that
  /// change the account's schedule or goal.
  Future<void> keepMeta() async {
    final original = await meta();
    addTearDown(() => putMeta(original ?? {}));
  }

  /// Waits until the server's meta passes [test] (the app pushes it in
  /// the background), and returns it.
  Future<Map<String, dynamic>> waitForMeta(
    String what,
    bool Function(Map<String, dynamic> meta) test,
  ) async {
    Map<String, dynamic>? found;
    await _poll('$what to reach the server', () async {
      found = await meta();
      return found != null && test(found!);
    });
    return found!;
  }

  Future<String> _send(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final request = http.Request(method, ApiConfig.baseUrl.resolve(path))
      ..headers.addAll(await _headers());
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode >= 300) {
      fail('$method $path → ${response.statusCode}: ${response.body}');
    }
    return response.body;
  }

  Future<void> _poll(String what, Future<bool> Function() done) =>
      waitUntil($, what, done, timeout: const Duration(seconds: 30));
}
