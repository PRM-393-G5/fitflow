import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../home/presentation/home_page.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || AppScope.of(context).onboardingDone) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const OnboardingPage()));
    });
  }

  static const _pages = [
    HomePage(),
    WorkoutsPage(),
    ProgressPage(),
    ProfilePage(),
  ];
  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.fitness_center_outlined),
      selectedIcon: Icon(Icons.fitness_center),
      label: 'Workouts',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights),
      label: 'Progress',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final body = IndexedStack(index: _index, children: _pages);
    return Scaffold(
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  NavigationRail(
                    extended: MediaQuery.sizeOf(context).width >= 1100,
                    selectedIndex: _index,
                    onDestinationSelected: (value) =>
                        setState(() => _index = value),
                    leading: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Icon(
                        Icons.bolt,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    destinations: _destinations
                        .map(
                          (item) => NavigationRailDestination(
                            icon: item.icon,
                            selectedIcon: item.selectedIcon,
                            label: Text(item.label),
                          ),
                        )
                        .toList(),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              )
            : body,
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: _destinations,
            ),
    );
  }
}
