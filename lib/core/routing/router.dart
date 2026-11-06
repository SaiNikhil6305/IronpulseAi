import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai_assistant/presentation/ai_screen.dart';
import '../../features/auth/data/auth_controller.dart';
import '../../features/auth/presentation/auth_screens.dart';
import '../../features/checklist/presentation/checklist_screens.dart';
import '../../features/exercises/presentation/exercise_screens.dart';
import '../../features/gamification/presentation/achievements_screen.dart';
import '../../features/goals/presentation/goals_screens.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/notifications/presentation/schedule_screen.dart';
import '../../features/nutrition/presentation/nutrition_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/profile/domain/profile.dart';
import '../../features/progress/presentation/progress_screen.dart';
import '../../features/settings/presentation/settings_screens.dart';
import '../../features/wearables/presentation/wearables_screen.dart';
import '../../features/workouts/presentation/history_screens.dart';
import '../../features/workouts/presentation/logger_screen.dart';
import '../../features/workouts/presentation/split_screens.dart';
import '../../features/workouts/presentation/summary_screen.dart';
import '../../features/workouts/presentation/workout_tab.dart';
import '../../features/workouts/domain/split.dart';
import 'app_shell.dart';
import 'bootstrap.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Bridges Riverpod state to GoRouter's refreshListenable.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
    ref.listen(bootstrapProvider, (_, _) => notifyListeners());
    ref.listen(profileProvider, (_, _) => notifyListeners());
    ref.listen(profileLoadedProvider, (_, _) => notifyListeners());
  }
}

const _authPaths = {'/sign-in', '/sign-up', '/forgot-password'};

/// Pure redirect logic (unit-tested).
String? resolveRedirect({
  required String location,
  required AuthState auth,
  required AsyncValue<bool> bootstrap,
  required bool profileLoaded,
  required Profile? profile,
}) {
  if (auth.status == AuthStatus.unknown) return location == '/splash' ? null : '/splash';
  if (!auth.isSignedIn) return _authPaths.contains(location) ? null : '/sign-in';
  if (auth.recovering) return location == '/new-password' ? null : '/new-password';
  if (bootstrap.isLoading || bootstrap.hasError || !profileLoaded) {
    return location == '/splash' ? null : '/splash';
  }
  final onboarded = profile?.onboardingCompleted == true;
  if (!onboarded) return location.startsWith('/onboarding') ? null : '/onboarding';
  if (location == '/splash' || _authPaths.contains(location) || location.startsWith('/onboarding') ||
      location == '/new-password') {
    return '/home';
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  GoRoute page(String path, Widget Function(GoRouterState s) build) => GoRoute(
        path: path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, s) => build(s),
      );

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) => resolveRedirect(
      location: state.matchedLocation,
      auth: ref.read(authControllerProvider),
      bootstrap: ref.read(bootstrapProvider),
      profileLoaded: ref.read(profileLoadedProvider),
      profile: ref.read(profileProvider),
    ),
    routes: [
      page('/splash', (_) => const SplashScreen()),
      page('/sign-in', (_) => const SignInScreen()),
      page('/sign-up', (_) => const SignUpScreen()),
      page('/forgot-password', (_) => const ForgotPasswordScreen()),
      page('/new-password', (_) => const NewPasswordScreen()),
      page('/onboarding', (_) => const OnboardingScreen()),
      page('/onboarding/split', (_) => const SplitSelectScreen(onboarding: true)),
      page('/onboarding/split-edit', (s) => SplitEditorScreen(initial: s.extra as WorkoutSplit?, onboarding: true)),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/workout', builder: (_, _) => const WorkoutTab())]),
          StatefulShellBranch(routes: [GoRoute(path: '/progress', builder: (_, _) => const ProgressScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/nutrition', builder: (_, _) => const NutritionScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/ai', builder: (_, _) => const AiScreen())]),
        ],
      ),
      page('/workout/active', (_) => const LoggerScreen()),
      page('/workout/summary/:id', (s) => SummaryScreen(sessionId: s.pathParameters['id']!)),
      page('/workout/history', (_) => const HistoryScreen()),
      page('/workout/session/:id', (s) => SessionDetailScreen(sessionId: s.pathParameters['id']!)),
      page('/exercises', (_) => const ExerciseLibraryScreen()),
      page('/exercises/:id', (s) => ExerciseDetailScreen(exerciseId: Uri.decodeComponent(s.pathParameters['id']!))),
      page('/split', (_) => const SplitSelectScreen()),
      page('/split/edit', (s) => SplitEditorScreen(initial: s.extra as WorkoutSplit?)),
      page('/settings', (_) => const SettingsScreen()),
      page('/profile', (_) => const ProfileEditScreen()),
      page('/schedule', (_) => const ScheduleScreen()),
      page('/checklist', (_) => const ChecklistManageScreen()),
      page('/goals', (_) => const GoalsScreen()),
      page('/weight', (_) => const WeightScreen()),
      page('/photos', (_) => const PhotosScreen()),
      page('/wearables', (_) => const WearablesScreen()),
      page('/achievements', (_) => const AchievementsScreen()),
      page('/privacy', (_) => const LegalScreen(kind: LegalKind.privacy)),
      page('/terms', (_) => const LegalScreen(kind: LegalKind.terms)),
      page('/sync', (_) => const SyncStatusScreen()),
    ],
  );
});
