import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'repo.dart';

/// Version of the in-app Privacy Policy / Terms. Bump when the text changes materially.
const policyVersion = '2026-10-26';

const consentLabels = {
  'ai_share_training': 'Share training summary with IronPulse AI',
  'ai_share_nutrition': 'Share nutrition summary with IronPulse AI',
  'health_connect': 'Read Health Connect data',
  'reminders': 'Workout reminder notifications',
};

class ConsentRecord {
  final String purpose;
  final bool granted;
  final String version;
  final DateTime at;
  ConsentRecord(this.purpose, this.granted, this.version, this.at);
}

class AccountRepo {
  static Future<Database> get _db => AppDb.get();

  // ---------- Consent ledger ----------
  /// Appends a record each time an optional purpose is switched on or off (never overwritten).
  static Future<void> recordConsent(String purpose, bool granted) async {
    final db = await _db;
    final last = await db.query('consent_records',
        where: 'purpose = ?', whereArgs: [purpose], orderBy: 'created_at DESC', limit: 1);
    if (last.isEmpty && !granted) return; // never turned on -> nothing to withdraw
    if (last.isNotEmpty && (last.first['granted'] as int == 1) == granted) return; // no change
    await db.insert('consent_records', {
      'id': newId(),
      'purpose': purpose,
      'granted': granted ? 1 : 0,
      'policy_version': policyVersion,
      'created_at': nowIso(),
    });
  }

  static Future<List<ConsentRecord>> consentHistory() async {
    final r = await (await _db).query('consent_records', orderBy: 'created_at DESC');
    return r
        .map((m) => ConsentRecord(m['purpose'] as String, (m['granted'] as int) == 1, m['policy_version'] as String,
            DateTime.parse(m['created_at'] as String)))
        .toList();
  }

  // ---------- Export ----------
  static const _exportTables = [
    'profile', 'split_days', 'sessions', 'session_exercises', 'sets', 'xp_tx', 'checklist_items',
    'checklist_done', 'food_entries', 'weights', 'goals', 'gym_schedule', 'ai_conversations', 'ai_messages',
    'health_daily', 'consent_records',
  ];

  /// Everything the app stores about the user, as one JSON document (secrets excluded).
  static Future<Map<String, Object?>> exportData() async {
    final db = await _db;
    final out = <String, Object?>{
      'app': 'IronPulse',
      'exported_at': nowIso(),
      'policy_version': policyVersion,
      'note': 'Access tokens are stored in secure storage and are intentionally not exported.',
    };
    for (final t in _exportTables) {
      out[t] = await db.query(t);
    }
    out['custom_exercises'] = await db.query('exercises', where: 'custom = 1');
    return out;
  }

  /// Flat workout log: one row per completed set - opens in Excel / Google Sheets.
  static Future<String> workoutsCsv() async {
    final rows = await (await _db).rawQuery('''
      SELECT ss.started_at, ss.day_name, e.name AS exercise, s.set_index + 1 AS set_no, s.weight, s.reps
      FROM sets s JOIN session_exercises se ON se.id = s.session_exercise_id
      JOIN sessions ss ON ss.id = se.session_id JOIN exercises e ON e.id = se.exercise_id
      WHERE ss.status = 'done' AND s.done = 1
      ORDER BY ss.started_at, se.position, s.set_index''');
    return toCsv(['date', 'workout', 'exercise', 'set', 'weight_kg', 'reps'],
        rows.map((r) => [r['started_at'], r['day_name'], r['exercise'], r['set_no'], r['weight'], r['reps']]));
  }

  static Future<String> foodCsv() async {
    final rows = await (await _db).query('food_entries', orderBy: 'day, created_at');
    return toCsv(['day', 'meal', 'food', 'serving', 'calories', 'protein_g', 'carbs_g', 'fat_g'],
        rows.map((r) => [r['day'], r['meal'], r['name'], r['serving'], r['calories'], r['protein'], r['carbs'], r['fat']]));
  }

  static Future<String> weightsCsv() async {
    final rows = await (await _db).query('weights', orderBy: 'day');
    return toCsv(['day', 'weight_kg', 'notes'], rows.map((r) => [r['day'], r['weight_kg'], r['notes']]));
  }

  static String toCsv(List<String> header, Iterable<List<Object?>> rows) {
    String cell(Object? v) {
      final s = v?.toString() ?? '';
      // Quote when needed; prefix formula-like text so spreadsheets don't execute it.
      final safe = RegExp(r'^[=+\-@]').hasMatch(s) && double.tryParse(s) == null ? "'$s" : s;
      return RegExp(r'[",\n\r]').hasMatch(safe) ? '"${safe.replaceAll('"', '""')}"' : safe;
    }

    return [header.map(cell).join(','), ...rows.map((r) => r.map(cell).join(','))].join('\r\n');
  }

  /// Writes the export files to the app's private temp folder and returns their paths for sharing.
  static Future<List<String>> writeExportFiles() async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'ironpulse_export'));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final files = {
      'ironpulse-data-$stamp.json': const JsonEncoder.withIndent('  ').convert(await exportData()),
      'ironpulse-workouts-$stamp.csv': await workoutsCsv(),
      'ironpulse-food-$stamp.csv': await foodCsv(),
      'ironpulse-weight-$stamp.csv': await weightsCsv(),
    };
    final paths = <String>[];
    for (final e in files.entries) {
      final f = File(p.join(dir.path, e.key));
      await f.writeAsString(e.value);
      paths.add(f.path);
    }
    return paths;
  }

  // ---------- Delete everything ----------
  /// Permanently erases all IronPulse data on this phone. Callers cancel reminders and revoke
  /// Health Connect first (see SettingsScreen); this removes the database, tokens and export files.
  static Future<void> deleteAllLocalData() async {
    await const FlutterSecureStorage().deleteAll();
    try {
      final tmp = Directory(p.join((await getTemporaryDirectory()).path, 'ironpulse_export'));
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
    await AppDb.deleteEverything();
  }
}
