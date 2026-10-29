import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/features/squat_form/presentation/squat_form_check_page.dart';

import 'support/e2e.dart';

void main() {
  // Counting reps needs a person in front of the camera; this only checks
  // that the camera opens after the permission prompt, and closes cleanly.
  e2eTest('opens the camera for an AI form check', ($) async {
    await launchSignedIn($);
    final sessions = controllerOf($).sessions.length;

    await $(const Key('open-squat-form-check-home')).scrollTo();
    await $(const Key('open-squat-form-check-home')).tap();
    await grantPermissionIfAsked($);
    await $(CameraPreview).waitUntilVisible();
    expect($(RegExp('^Could not open the camera')), findsNothing);

    await $(find.bySemanticsLabel('Close')).tap();
    // Someone moving in view can get a rep counted: its review comes first.
    final review = $(const Key('form-review-done'));
    if (review.exists) await review.tap();
    await waitUntilGone($, $(SquatFormCheckPage), 'the form check to close');
    expect(
      controllerOf($).sessions,
      hasLength(sessions),
      reason:
          'A rep was counted and saved — point the camera away from '
          'people while this test runs, and delete that session.',
    );
  });
}
