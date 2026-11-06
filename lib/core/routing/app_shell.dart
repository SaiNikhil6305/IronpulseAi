import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/workouts/data/active_workout_controller.dart';
import '../theme/app_theme.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeWorkoutProvider).value;
    return Scaffold(
      body: Column(children: [
        Expanded(child: shell),
        if (active != null)
          Material(
            color: AppColors.accent,
            child: InkWell(
              onTap: () => context.push('/workout/active'),
              child: SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.fitness_center, color: Colors.black, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Workout in progress · ${active.name}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
                    ),
                    const Text('RESUME', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
                    const Icon(Icons.chevron_right, color: Colors.black),
                  ]),
                ),
              ),
            ),
          ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined), selectedIcon: Icon(Icons.fitness_center), label: 'Workout'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Progress'),
          NavigationDestination(
              icon: Icon(Icons.restaurant_outlined), selectedIcon: Icon(Icons.restaurant), label: 'Nutrition'),
          NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'IronPulse AI'),
        ],
      ),
    );
  }
}
