import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../logic/progress.dart';
import 'account_repo.dart';
import 'db.dart';
import 'seed.dart';
import 'splits.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();
String nowIso() => DateTime.now().toIso8601String();

/// Configurable XP values.
class XpRules {
  static const set = 10;
  static const workout = 25;
  static const weeklyTarget = 30;
}

class WSet {
  final String id;
  int index;
  double? weight;
  int? reps;
  bool done;
  WSet(this.id, this.index, this.weight, this.reps, this.done);

  factory WSet.fromMap(Map<String, Object?> m) => WSet(
        m['id'] as String,
        m['set_index'] as int,
        (m['weight'] as num?)?.toDouble(),
        m['reps'] as int?,
        (m['done'] as int) == 1,
      );
}

class PrevSet {
  final double? weight;
  final int? reps;
  const PrevSet(this.weight, this.reps);
}

class SessionExercise {
  final String id;
  Exercise exercise;
  final List<WSet> sets;
  SessionExercise(this.id, this.exercise, this.sets);
}

class Session {
  final String id;
  final int? dayIndex;
  final String dayName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final String? notes;
  Session(this.id, this.dayIndex, this.dayName, this.startedAt, this.endedAt, this.status, this.notes);

  factory Session.fromMap(Map<String, Object?> m) => Session(
        m['id'] as String,
        m['day_index'] as int?,
        m['day_name'] as String,
        DateTime.parse(m['started_at'] as String),
        m['ended_at'] == null ? null : DateTime.parse(m['ended_at'] as String),
        m['status'] as String,
        m['notes'] as String?,
      );

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);
}

class Summary {
  final String dayName;
  final int exercises, sets, reps, xp;
  final double volume;
  final Duration duration;
  final List<String> prs;
  final String? notes;
  Summary(this.dayName, this.exercises, this.sets, this.reps, this.volume, this.duration, this.xp, this.prs, this.notes);
}

class Stats {
  final int workouts, sets, reps;
  final double volume;
  Stats(this.workouts, this.sets, this.reps, this.volume);
}

class Repo {
  static Future<Database> get _db => AppDb.get();

  // ---------- Profile ----------
  static Future<Map<String, Object?>?> profile() async {
    final r = await (await _db).query('profile', where: 'id = 1');
    return r.isEmpty ? null : r.first;
  }

  static Future<void> createProfile(Map<String, Object?> m) async {
    await (await _db).insert('profile', {...m, 'id': 1, 'created_at': nowIso()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateProfile(Map<String, Object?> m) async {
    await (await _db).update('profile', m, where: 'id = 1');
  }

  // ---------- Split ----------
  static Future<List<SplitDay>> splitDays() async {
    final r = await (await _db).query('split_days', orderBy: 'day_index');
    return r
        .map((m) => SplitDay(m['name'] as String,
            (m['muscles'] as String).split(',').where((s) => s.isNotEmpty).toList()))
        .toList();
  }

  /// Replaces the plan only. Past sessions keep their own day names, so history is untouched.
  static Future<void> saveSplit(String key, List<SplitDay> days) async {
    final db = await _db;
    await db.transaction((t) async {
      await t.delete('split_days');
      for (var i = 0; i < days.length; i++) {
        await t.insert('split_days', {'day_index': i, 'name': days[i].name, 'muscles': days[i].muscles.join(',')});
      }
      await t.update('profile', {'split_key': key}, where: 'id = 1');
    });
  }

  /// Next day in the rotation, based on the last completed session.
  static Future<(int, SplitDay)?> nextDay() async {
    final days = await splitDays();
    if (days.isEmpty) return null;
    final r = await (await _db).query('sessions',
        columns: ['day_index'],
        where: "status = 'done' AND day_index IS NOT NULL",
        orderBy: 'started_at DESC',
        limit: 1);
    var i = 0;
    if (r.isNotEmpty) i = ((r.first['day_index'] as int) + 1) % days.length;
    return (i, days[i]);
  }

  // ---------- Exercises ----------
  static Future<List<Exercise>> exercises({String query = '', String? muscle}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (query.isNotEmpty) {
      where.add('name LIKE ?');
      args.add('%$query%');
    }
    if (muscle != null) {
      where.add('muscle = ?');
      args.add(muscle);
    }
    final r = await (await _db).query('exercises',
        where: where.isEmpty ? null : where.join(' AND '), whereArgs: args, orderBy: 'muscle, name');
    return r.map(Exercise.fromMap).toList();
  }

  static Future<List<String>> defaultExerciseIds(List<String> muscles, {int perMuscle = 2}) async {
    final db = await _db;
    final ids = <String>[];
    for (final m in muscles) {
      final r = await db.query('exercises',
          columns: ['id'], where: 'muscle = ?', whereArgs: [m], orderBy: 'custom, rowid', limit: perMuscle);
      ids.addAll(r.map((e) => e['id'] as String));
    }
    return ids;
  }

  static Future<void> addCustomExercise(String name, String muscle, String equipment) async {
    await (await _db).insert(
        'exercises',
        Exercise('custom-${newId()}', name.trim(), muscle, equipment.trim().isEmpty ? 'Other' : equipment.trim(),
                'Custom exercise.', custom: true)
            .toMap());
  }

  // ---------- Sessions ----------
  static Future<Session?> activeSession() async {
    final r = await (await _db).query('sessions', where: "status = 'active'", limit: 1);
    return r.isEmpty ? null : Session.fromMap(r.first);
  }

  static Future<Session> session(String id) async {
    final r = await (await _db).query('sessions', where: 'id = ?', whereArgs: [id]);
    return Session.fromMap(r.first);
  }

  static Future<String> startSession({int? dayIndex, required String dayName, required List<String> exerciseIds}) async {
    final db = await _db;
    final sid = newId();
    await db.transaction((t) async {
      await t.insert('sessions',
          {'id': sid, 'day_index': dayIndex, 'day_name': dayName, 'started_at': nowIso(), 'status': 'active'});
      var pos = 0;
      for (final ex in exerciseIds) {
        await _insertSessionExercise(t, sid, ex, pos++);
      }
    });
    return sid;
  }

  static Future<void> _insertSessionExercise(DatabaseExecutor t, String sid, String exId, int pos) async {
    final seId = newId();
    await t.insert('session_exercises', {'id': seId, 'session_id': sid, 'exercise_id': exId, 'position': pos});
    final prev = await _previousSets(t, exId);
    final n = prev.isEmpty ? 3 : prev.length;
    // Sets start empty on purpose: last session's numbers are shown as hints, never assumed.
    for (var i = 0; i < n; i++) {
      await t.insert('sets', {'id': newId(), 'session_exercise_id': seId, 'set_index': i, 'done': 0});
    }
  }

  static Future<List<SessionExercise>> loadSession(String sid) async {
    final db = await _db;
    final rows = await db.rawQuery(
        'SELECT se.id AS se_id, e.* FROM session_exercises se JOIN exercises e ON e.id = se.exercise_id '
        'WHERE se.session_id = ? ORDER BY se.position',
        [sid]);
    final out = <SessionExercise>[];
    for (final r in rows) {
      final sets = await db.query('sets',
          where: 'session_exercise_id = ?', whereArgs: [r['se_id']], orderBy: 'set_index');
      out.add(SessionExercise(r['se_id'] as String, Exercise.fromMap(r), sets.map(WSet.fromMap).toList()));
    }
    return out;
  }

  /// Completed sets from the most recent finished session containing this exercise.
  static Future<List<PrevSet>> previousSets(String exerciseId) async => _previousSets(await _db, exerciseId);

  static Future<List<PrevSet>> _previousSets(DatabaseExecutor e, String exerciseId) async {
    final r = await e.rawQuery('''
      SELECT s.weight, s.reps FROM sets s
      JOIN session_exercises se ON se.id = s.session_exercise_id
      WHERE s.done = 1 AND se.id = (
        SELECT se2.id FROM session_exercises se2
        JOIN sessions ss2 ON ss2.id = se2.session_id
        WHERE se2.exercise_id = ? AND ss2.status = 'done'
          AND EXISTS (SELECT 1 FROM sets s2 WHERE s2.session_exercise_id = se2.id AND s2.done = 1)
        ORDER BY ss2.started_at DESC LIMIT 1)
      ORDER BY s.set_index''', [exerciseId]);
    return r.map((m) => PrevSet((m['weight'] as num?)?.toDouble(), m['reps'] as int?)).toList();
  }

  static Future<WSet> addSet(String seId) async {
    final db = await _db;
    final last = await db.query('sets',
        where: 'session_exercise_id = ?', whereArgs: [seId], orderBy: 'set_index DESC', limit: 1);
    final idx = last.isEmpty ? 0 : (last.first['set_index'] as int) + 1;
    final s = WSet(newId(), idx, last.isEmpty ? null : (last.first['weight'] as num?)?.toDouble(),
        last.isEmpty ? null : last.first['reps'] as int?, false);
    await db.insert('sets',
        {'id': s.id, 'session_exercise_id': seId, 'set_index': idx, 'weight': s.weight, 'reps': s.reps, 'done': 0});
    return s;
  }

  static Future<void> updateSet(String id, double? weight, int? reps) async {
    await (await _db).update('sets', {'weight': weight, 'reps': reps}, where: 'id = ?', whereArgs: [id]);
  }

  /// Marks a set done/undone. XP uses the id "set:<setId>", so re-checking can never pay twice,
  /// and unchecking removes it again, keeping the ledger equal to completed sets.
  static Future<void> setDone(String id, bool done) async {
    final db = await _db;
    await db.update('sets', {'done': done ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    if (done) {
      final r = await db.query('sets', columns: ['reps'], where: 'id = ?', whereArgs: [id]);
      final reps = r.first['reps'] as int?;
      if (reps != null && reps > 0) await _award(db, 'set:$id', XpRules.set, 'Completed set');
    } else {
      await db.delete('xp_tx', where: 'id = ?', whereArgs: ['set:$id']);
    }
  }

  static Future<void> removeSet(String id) async {
    final db = await _db;
    await db.delete('xp_tx', where: 'id = ?', whereArgs: ['set:$id']);
    await db.delete('sets', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> addExerciseToSession(String sid, String exId) async {
    final db = await _db;
    final r = await db.rawQuery(
        'SELECT COALESCE(MAX(position), -1) + 1 AS p FROM session_exercises WHERE session_id = ?', [sid]);
    await _insertSessionExercise(db, sid, exId, r.first['p'] as int);
  }

  static Future<void> replaceExercise(String seId, String exId) async {
    await (await _db).update('session_exercises', {'exercise_id': exId}, where: 'id = ?', whereArgs: [seId]);
  }

  static Future<void> removeExercise(String seId) async {
    final db = await _db;
    await db.rawDelete(
        "DELETE FROM xp_tx WHERE id IN (SELECT 'set:' || id FROM sets WHERE session_exercise_id = ?)", [seId]);
    await db.delete('session_exercises', where: 'id = ?', whereArgs: [seId]);
  }

  static Future<void> discardSession(String sid) async {
    final db = await _db;
    await db.rawDelete(
        "DELETE FROM xp_tx WHERE id IN (SELECT 'set:' || s.id FROM sets s "
        'JOIN session_exercises se ON se.id = s.session_exercise_id WHERE se.session_id = ?)',
        [sid]);
    await db.delete('sessions', where: 'id = ?', whereArgs: [sid]);
  }

  /// Finishes a workout. Returns null (and discards it) if no valid set was completed.
  /// Safe to call twice: the status check and deterministic XP ids prevent double rewards.
  static Future<Summary?> finishSession(String sid, String? notes) async {
    final db = await _db;
    final s = await session(sid);
    final data = await loadSession(sid);
    final valid = [for (final e in data) ...e.sets.where((x) => x.done && (x.reps ?? 0) > 0)];
    if (s.status == 'active' && valid.isEmpty) {
      await discardSession(sid);
      return null;
    }
    final end = s.endedAt ?? DateTime.now();
    var bonus = 0;
    await db.transaction((t) async {
      if (s.status == 'active') {
        // Keep history clean: drop unfinished sets and empty exercises.
        await t.rawDelete(
            'DELETE FROM sets WHERE done = 0 AND session_exercise_id IN '
            '(SELECT id FROM session_exercises WHERE session_id = ?)',
            [sid]);
        await t.rawDelete(
            'DELETE FROM session_exercises WHERE session_id = ? AND id NOT IN (SELECT session_exercise_id FROM sets)',
            [sid]);
        await t.update('sessions', {'status': 'done', 'ended_at': end.toIso8601String(), 'notes': notes},
            where: 'id = ?', whereArgs: [sid]);
      }
      if (await _award(t, 'workout:$sid', XpRules.workout, 'Completed workout')) bonus += XpRules.workout;

      final target = (await t.query('profile', columns: ['weekly_target'])).first['weekly_target'] as int;
      final monday = weekStart(s.startedAt);
      final next = monday.add(const Duration(days: 7));
      final c = await t.rawQuery(
          "SELECT COUNT(*) AS c FROM sessions WHERE status = 'done' AND started_at >= ? AND started_at < ?",
          [monday.toIso8601String(), next.toIso8601String()]);
      if ((c.first['c'] as int) >= target &&
          await _award(t, 'week:${weekKey(s.startedAt)}', XpRules.weeklyTarget, 'Hit weekly training target')) {
        bonus += XpRules.weeklyTarget;
      }
    });

    final prs = <String>[];
    for (final e in data) {
      final weights = e.sets.where((x) => x.done && x.weight != null).map((x) => x.weight!);
      if (weights.isEmpty) continue;
      final best = weights.reduce((a, b) => a > b ? a : b);
      final prior = await db.rawQuery('''
        SELECT MAX(s.weight) AS w FROM sets s
        JOIN session_exercises se ON se.id = s.session_exercise_id
        JOIN sessions ss ON ss.id = se.session_id
        WHERE se.exercise_id = ? AND ss.status = 'done' AND s.done = 1 AND ss.id != ? AND ss.started_at < ?''',
          [e.exercise.id, sid, s.startedAt.toIso8601String()]);
      final w = (prior.first['w'] as num?)?.toDouble();
      if (w != null && best > w) {
        final label = '${e.exercise.name}: ${fmtW(best)} kg (was ${fmtW(w)} kg)';
        prs.add(label);
        // Zero-XP ledger entry records the PR once (keeps XP about consistency, not just heavier weight).
        await _award(db, 'pr:$sid:${e.exercise.id}', 0, 'Personal record - $label');
      }
    }

    return Summary(
      s.dayName,
      data.where((e) => e.sets.any((x) => x.done)).length,
      valid.length,
      valid.fold(0, (a, x) => a + (x.reps ?? 0)),
      valid.fold(0.0, (a, x) => a + (x.weight ?? 0) * (x.reps ?? 0)),
      end.difference(s.startedAt),
      valid.length * XpRules.set + bonus,
      prs,
      notes,
    );
  }

  /// Inserts an XP transaction once. Returns true only if it was newly added.
  static Future<bool> _award(DatabaseExecutor e, String id, int amount, String reason) async {
    final exists = await e.query('xp_tx', columns: ['id'], where: 'id = ?', whereArgs: [id]);
    if (exists.isNotEmpty) return false;
    await e.insert('xp_tx', {'id': id, 'amount': amount, 'reason': reason, 'created_at': nowIso()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return true;
  }

  // ---------- History & stats ----------
  static Future<List<Session>> doneSessions({int? limit}) async {
    final r = await (await _db).query('sessions', where: "status = 'done'", orderBy: 'started_at DESC', limit: limit);
    return r.map(Session.fromMap).toList();
  }

  static Future<List<DateTime>> sessionDates() async {
    final r = await (await _db).query('sessions', columns: ['started_at'], where: "status = 'done'");
    return r.map((m) => DateTime.parse(m['started_at'] as String)).toList();
  }

  static Future<int> xpTotal() async {
    final r = await (await _db).rawQuery('SELECT COALESCE(SUM(amount), 0) AS t FROM xp_tx');
    return r.first['t'] as int;
  }

  static Future<List<Map<String, Object?>>> xpHistory({int limit = 30}) async =>
      (await _db).query('xp_tx', orderBy: 'created_at DESC', limit: limit);

  static Future<Stats> stats({DateTime? since}) async {
    final db = await _db;
    final cond = since == null ? '' : 'AND ss.started_at >= ?';
    final args = since == null ? <Object?>[] : [since.toIso8601String()];
    final w = await db.rawQuery("SELECT COUNT(*) AS c FROM sessions ss WHERE status = 'done' $cond", args);
    final s = await db.rawQuery('''
      SELECT COUNT(*) AS n, COALESCE(SUM(s.reps), 0) AS r, COALESCE(SUM(COALESCE(s.weight, 0) * s.reps), 0) AS v
      FROM sets s JOIN session_exercises se ON se.id = s.session_exercise_id
      JOIN sessions ss ON ss.id = se.session_id
      WHERE ss.status = 'done' AND s.done = 1 $cond''', args);
    return Stats(w.first['c'] as int, s.first['n'] as int, s.first['r'] as int, (s.first['v'] as num).toDouble());
  }

  static Future<List<(String, double)>> personalBests() async {
    final r = await (await _db).rawQuery('''
      SELECT e.name AS name, MAX(s.weight) AS w
      FROM sets s JOIN session_exercises se ON se.id = s.session_exercise_id
      JOIN sessions ss ON ss.id = se.session_id JOIN exercises e ON e.id = se.exercise_id
      WHERE s.done = 1 AND ss.status = 'done' AND s.weight IS NOT NULL AND s.weight > 0
      GROUP BY e.id ORDER BY e.name''');
    return r.map((m) => (m['name'] as String, (m['w'] as num).toDouble())).toList();
  }

  static Future<int> prCount() async {
    final r = await (await _db).rawQuery("SELECT COUNT(*) AS c FROM xp_tx WHERE id LIKE 'pr:%'");
    return r.first['c'] as int;
  }
}

String fmtW(double? w) {
  if (w == null) return '-';
  return w == w.roundToDouble() ? w.toInt().toString() : w.toStringAsFixed(1);
}

/// Weekly gym schedule and reminder preferences.
class ScheduleRepo {
  static Future<Database> get _db => AppDb.get();

  /// weekday (1-7) -> minutes after midnight, or null for rest. Missing days are rest days.
  static Future<Map<int, int?>> schedule() async {
    final r = await (await _db).query('gym_schedule');
    final m = <int, int?>{for (var d = 1; d <= 7; d++) d: null};
    for (final row in r) {
      m[row['weekday'] as int] = row['minutes'] as int?;
    }
    return m;
  }

  static Future<void> saveSchedule(Map<int, int?> s) async {
    final db = await _db;
    await db.transaction((t) async {
      await t.delete('gym_schedule');
      for (final e in s.entries) {
        await t.insert('gym_schedule', {'weekday': e.key, 'minutes': e.value});
      }
    });
  }

  static Future<(bool, List<int>)> reminderPrefs() async {
    final p = await Repo.profile();
    final offs = ((p?['reminder_offsets'] as String?) ?? '20')
        .split(',')
        .where((s) => s.isNotEmpty)
        .map(int.parse)
        .toList();
    return ((p?['reminders_enabled'] as int? ?? 0) == 1, offs);
  }

  static Future<void> saveReminderPrefs(bool enabled, List<int> offsets) async {
    await Repo.updateProfile({'reminders_enabled': enabled ? 1 : 0, 'reminder_offsets': offsets.join(',')});
    await AccountRepo.recordConsent('reminders', enabled);
  }
}
