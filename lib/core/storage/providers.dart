import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_db.dart';

/// Overridden in main() / tests with an opened database.
final localDbProvider = Provider<LocalDb>((ref) => throw UnimplementedError('localDbProvider not overridden'));

/// Overridden in main() / tests. Non-sensitive settings only.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('prefsProvider not overridden'));

/// Re-emits whenever [collection] changes so read models can recompute.
final collectionTickProvider = StreamProvider.family<int, String>((ref, collection) {
  final db = ref.watch(localDbProvider);
  var n = 0;
  return db.changes.where((c) => c == collection || c == '*').map((_) => ++n);
});

/// All documents of a collection, kept fresh automatically.
final docsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, collection) async {
  ref.watch(collectionTickProvider(collection));
  return ref.watch(localDbProvider).listDocs(collection);
});

/// A single document (e.g. ('meta', 'profile')).
final docProvider = FutureProvider.family<Map<String, dynamic>?, (String, String)>((ref, key) async {
  ref.watch(collectionTickProvider(key.$1));
  return ref.watch(localDbProvider).getDoc(key.$1, key.$2);
});

/// Collection names used across the app.
class Col {
  const Col._();
  static const meta = 'meta';
  static const sessions = 'sessions';
  static const sessionSync = 'session_sync';
  static const userExercises = 'user_exercises';
  static const checklistItems = 'checklist_items';
  static const checklistCompletions = 'checklist_completions';
  static const meals = 'meals';
  static const goals = 'goals';
  static const weights = 'weights';
  static const photos = 'photos';
  static const healthDaily = 'health_daily';
}

/// Well-known document ids inside [Col.meta].
class Meta {
  const Meta._();
  static const profile = 'profile';
  static const split = 'active_split';
  static const schedule = 'schedule';
  static const notificationPrefs = 'notification_prefs';
  static const nutritionTargets = 'nutrition_targets';
  static const activeSessionId = 'active_session_id';
  static const gamification = 'gamification_server';
  static const onboardingDraft = 'onboarding_draft';
  static const restTimer = 'rest_timer';
  static const wearable = 'wearable_health_connect';
}
