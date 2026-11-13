import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_dialog.dart';

/// The ways to add a meal to a slot.
enum AddMealChoice { camera, gallery, manual }

/// Asks how to add a meal to [type] (Breakfast, Lunch…): a photo, one
/// from the gallery, or by hand. The photo options need AI, so they are
/// disabled unless [photosEnabled]. Null when cancelled.
Future<AddMealChoice?> showAddMealChoice(
  BuildContext context, {
  required String type,
  required bool photosEnabled,
}) => showAppDialog<AddMealChoice>(
  context: context,
  title: 'Add to $type',
  actions: [
    FButton(
      key: const Key('slot-add-photo'),
      variant: .outline,
      prefix: const Icon(FLucideIcons.camera),
      onPress: photosEnabled
          ? () => Navigator.pop(context, AddMealChoice.camera)
          : null,
      child: const Text('Take a photo'),
    ),
    FButton(
      key: const Key('slot-add-gallery'),
      variant: .outline,
      prefix: const Icon(FLucideIcons.images),
      onPress: photosEnabled
          ? () => Navigator.pop(context, AddMealChoice.gallery)
          : null,
      child: const Text('Choose from gallery'),
    ),
    FButton(
      key: const Key('slot-add-manual'),
      variant: .outline,
      prefix: const Icon(FLucideIcons.pencil),
      onPress: () => Navigator.pop(context, AddMealChoice.manual),
      child: const Text('Enter manually'),
    ),
    FButton(
      variant: .ghost,
      onPress: () => Navigator.pop(context),
      child: const Text('Cancel'),
    ),
  ],
);
