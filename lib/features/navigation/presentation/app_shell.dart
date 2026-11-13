import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../home/presentation/home_page.dart';
import '../../nutrition/presentation/add_meal_choice.dart';
import '../../nutrition/presentation/nutrition_page.dart';
import '../../onboarding/presentation/onboarding_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../progress/presentation/progress_page.dart';
import '../../workouts/presentation/workouts_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// Photos Home asks for, taken on the Nutrition tab.
  final _photoRequests = ValueNotifier<MealPhotoRequest?>(null);

  @override
  void dispose() {
    _photoRequests.dispose();
    super.dispose();
  }

  bool _onboardingShown = false;

  /// Shows onboarding once local data has loaded and any cloud merge has
  /// finished — a returning user's synced profile must arrive first, or
  /// they would be onboarded again (and "Skip" would overwrite it).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (_onboardingShown ||
        controller.loading ||
        controller.syncing ||
        controller.onboardingDone) {
      return;
    }
    _onboardingShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || AppScope.of(context).onboardingDone) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const OnboardingPage()));
    });
  }

  static const _nutritionTab = 2;
  static const _destinations = [
    (icon: FLucideIcons.house, label: 'Home'),
    (icon: FLucideIcons.dumbbell, label: 'Workouts'),
    (icon: FLucideIcons.utensils, label: 'Nutrition'),
    (icon: FLucideIcons.chartNoAxesColumnIncreasing, label: 'Progress'),
    (icon: FLucideIcons.circleUser, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final body = IndexedStack(
      index: _index,
      children: [
        HomePage(
          onOpenNutrition: () => setState(() => _index = _nutritionTab),
          onMealPhoto: (request) {
            setState(() => _index = _nutritionTab);
            _photoRequests.value = request;
          },
        ),
        const WorkoutsPage(),
        NutritionPage(photoRequests: _photoRequests),
        const ProgressPage(),
        const ProfilePage(),
      ],
    );
    return FScaffold(
      childPad: false,
      sidebar: wide
          ? NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1100,
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              leading: Padding(
                padding: const EdgeInsets.all(16),
                child: Icon(
                  FLucideIcons.zap,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              destinations: _destinations
                  .map(
                    (item) => NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.icon),
                      label: Text(item.label),
                    ),
                  )
                  .toList(),
            )
          : null,
      footer: wide
          ? null
          : FBottomNavigationBar(
              safeAreaBottom: true,
              index: _index,
              onChange: (value) => setState(() => _index = value),
              children: [
                for (final item in _destinations)
                  FBottomNavigationBarItem(
                    icon: Icon(item.icon),
                    label: Text(item.label),
                  ),
              ],
            ),
      child: SafeArea(child: body),
    );
  }
}
