import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/cloud_repo.dart';
import 'data/db.dart';
import 'data/notifications.dart';
import 'data/repo.dart';
import 'screens/ai.dart';
import 'screens/home.dart';
import 'screens/nutrition.dart';
import 'screens/onboarding.dart';
import 'screens/progress_screen.dart';
import 'screens/workout_flow.dart';
import 'screens/workout_tab.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: IP.surface,
  ));
  await AppDb.get();
  try {
    await CloudRepo.init(); // no-op unless Supabase keys were provided at build time
  } catch (_) {
    // Cloud is optional: the app keeps working offline.
  }
  try {
    await Notifs.init();
  } catch (_) {
    // Notifications are optional; the app works without them.
  }
  Notifs.onTap = (payload) {
    final ctx = navigatorKey.currentContext;
    if (payload == 'start' && ctx != null) startWorkout(ctx);
  };
  runApp(const IronPulseApp());
}

final navigatorKey = GlobalKey<NavigatorState>();

class IronPulseApp extends StatelessWidget {
  const IronPulseApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IronPulse',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Gate(),
      );
}

/// Sends new users to onboarding, returning users straight to the app.
class Gate extends StatelessWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: Future.wait<Object?>([Repo.profile(), Repo.splitDays()]),
        builder: (context, snap) {
          if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final profile = snap.data![0];
          final days = snap.data![1] as List;
          if (profile == null || days.isEmpty) return OnboardingScreen(hasProfile: profile != null);
          return const Shell();
        },
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await Notifs.reschedule(); // refresh reminder text with the latest rotation and history
        final payload = await Notifs.launchPayload();
        if (payload == 'start' && mounted) startWorkout(context);
      } catch (_) {}
    });
  }

  void goTo(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 0,
      onPopInvoked: (didPop) {
        if (!didPop) setState(() => _tab = 0); // Android back goes to Home before exiting.
      },
      child: Scaffold(
        body: IndexedStack(index: _tab, children: [
          HomeScreen(onNavigate: goTo),
          const WorkoutTab(),
          const ProgressScreen(),
          const NutritionScreen(),
          const AiScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: goTo,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.fitness_center_outlined), selectedIcon: Icon(Icons.fitness_center), label: 'Workout'),
            NavigationDestination(
                icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Progress'),
            NavigationDestination(
                icon: Icon(Icons.restaurant_outlined), selectedIcon: Icon(Icons.restaurant), label: 'Nutrition'),
            NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'AI'),
          ],
        ),
      ),
    );
  }
}
