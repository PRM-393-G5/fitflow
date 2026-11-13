import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/features/nutrition/presentation/add_meal_choice.dart';

/// Pumps a button that opens the choice for [type] and records the answer.
Future<List<AddMealChoice?>> pumpChoice(
  WidgetTester tester, {
  String type = 'Breakfast',
  bool photosEnabled = true,
}) async {
  final answers = <AddMealChoice?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.toApproximateMaterialTheme(),
      builder: (context, child) => FTheme(data: AppTheme.light, child: child!),
      home: Builder(
        builder: (context) => Center(
          child: FButton(
            onPress: () async => answers.add(
              await showAddMealChoice(
                context,
                type: type,
                photosEnabled: photosEnabled,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return answers;
}

void main() {
  testWidgets('names the meal and returns the picked way to add it', (
    tester,
  ) async {
    final answers = await pumpChoice(tester, type: 'Dinner');

    expect(find.text('Add to Dinner'), findsOneWidget);
    await tester.tap(find.byKey(const Key('slot-add-gallery')));
    await tester.pumpAndSettle();

    expect(answers, [AddMealChoice.gallery]);
  });

  testWidgets('Cancel returns nothing', (tester) async {
    final answers = await pumpChoice(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answers, [null]);
  });

  testWidgets('without AI only manual entry is offered', (tester) async {
    await pumpChoice(tester, photosEnabled: false);

    FButton button(String key) => tester.widget<FButton>(find.byKey(Key(key)));
    expect(button('slot-add-photo').onPress, isNull);
    expect(button('slot-add-gallery').onPress, isNull);
    expect(button('slot-add-manual').onPress, isNotNull);
  });
}
