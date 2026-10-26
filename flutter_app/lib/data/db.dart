import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'seed.dart';

/// Local SQLite database. All workout data is stored on the phone first (offline-first).
class AppDb {
  static Database? _db;

  /// Test helper: closes and deletes the database.
  static Future<void> resetForTests() => deleteEverything();

  /// Closes and permanently deletes the database file (used by "Delete all my data").
  static Future<void> deleteEverything() async {
    await _db?.close();
    _db = null;
    await deleteDatabase(p.join(await getDatabasesPath(), 'ironpulse.db'));
  }

  static Future<Database> get() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'ironpulse.db'),
      version: 6,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        final b = db.batch();
        b.execute('''CREATE TABLE profile(
          id INTEGER PRIMARY KEY CHECK (id = 1),
          name TEXT NOT NULL,
          weight_kg REAL,
          height_cm REAL,
          experience TEXT,
          goal TEXT,
          weekly_target INTEGER NOT NULL DEFAULT 3,
          rest_seconds INTEGER NOT NULL DEFAULT 90,
          split_key TEXT,
          created_at TEXT NOT NULL)''');
        b.execute('''CREATE TABLE split_days(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          day_index INTEGER NOT NULL,
          name TEXT NOT NULL,
          muscles TEXT NOT NULL)''');
        b.execute('''CREATE TABLE exercises(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          muscle TEXT NOT NULL,
          equipment TEXT NOT NULL,
          instructions TEXT NOT NULL,
          custom INTEGER NOT NULL DEFAULT 0)''');
        // day_name is copied into each session so changing the split never alters history.
        b.execute('''CREATE TABLE sessions(
          id TEXT PRIMARY KEY,
          day_index INTEGER,
          day_name TEXT NOT NULL,
          started_at TEXT NOT NULL,
          ended_at TEXT,
          status TEXT NOT NULL CHECK (status IN ('active','done')),
          notes TEXT)''');
        b.execute('''CREATE TABLE session_exercises(
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
          exercise_id TEXT NOT NULL REFERENCES exercises(id),
          position INTEGER NOT NULL)''');
        b.execute('''CREATE TABLE sets(
          id TEXT PRIMARY KEY,
          session_exercise_id TEXT NOT NULL REFERENCES session_exercises(id) ON DELETE CASCADE,
          set_index INTEGER NOT NULL,
          weight REAL,
          reps INTEGER,
          done INTEGER NOT NULL DEFAULT 0)''');
        // Deterministic primary keys (e.g. "set:<id>", "workout:<id>") make XP idempotent.
        b.execute('''CREATE TABLE xp_tx(
          id TEXT PRIMARY KEY,
          amount INTEGER NOT NULL,
          reason TEXT NOT NULL,
          created_at TEXT NOT NULL)''');
        b.execute('CREATE INDEX idx_sessions_status ON sessions(status, started_at)');
        b.execute('CREATE INDEX idx_se_session ON session_exercises(session_id)');
        b.execute('CREATE INDEX idx_se_exercise ON session_exercises(exercise_id)');
        b.execute('CREATE INDEX idx_sets_se ON sets(session_exercise_id)');
        for (final e in seedExercises) {
          b.insert('exercises', e.toMap());
        }
        await b.commit(noResult: true);
        await _v2(db);
        await _v3(db);
        await _v4(db);
        await _v5(db);
        await _v6(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _v2(db);
        if (oldVersion < 3) await _v3(db);
        if (oldVersion < 4) await _v4(db);
        if (oldVersion < 5) await _v5(db);
        if (oldVersion < 6) await _v6(db);
      },
    );
    return _db!;
  }

  /// Phase 4: checklist, nutrition, weight, goals.
  static Future<void> _v2(Database db) async {
    final b = db.batch();
    b.execute('ALTER TABLE profile ADD COLUMN targets_enabled INTEGER NOT NULL DEFAULT 0');
    b.execute('ALTER TABLE profile ADD COLUMN calorie_target REAL');
    b.execute('ALTER TABLE profile ADD COLUMN protein_target REAL');
    b.execute('''CREATE TABLE checklist_items(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      category TEXT NOT NULL CHECK (category IN ('supplement','food','habit')),
      quantity TEXT,
      protein_g REAL,
      calories REAL,
      active INTEGER NOT NULL DEFAULT 1,
      position INTEGER NOT NULL,
      created_at TEXT NOT NULL)''');
    b.execute('''CREATE TABLE checklist_done(
      item_id TEXT NOT NULL REFERENCES checklist_items(id) ON DELETE CASCADE,
      day TEXT NOT NULL,
      done_at TEXT NOT NULL,
      PRIMARY KEY (item_id, day))''');
    b.execute('''CREATE TABLE food_entries(
      id TEXT PRIMARY KEY,
      day TEXT NOT NULL,
      meal TEXT NOT NULL,
      name TEXT NOT NULL,
      serving TEXT,
      calories REAL,
      protein REAL,
      carbs REAL,
      fat REAL,
      notes TEXT,
      checklist_item_id TEXT,
      created_at TEXT NOT NULL)''');
    b.execute('CREATE INDEX idx_food_day ON food_entries(day)');
    b.execute('''CREATE TABLE weights(
      id TEXT PRIMARY KEY,
      day TEXT NOT NULL UNIQUE,
      weight_kg REAL NOT NULL CHECK (weight_kg > 0),
      notes TEXT,
      created_at TEXT NOT NULL)''');
    b.execute('''CREATE TABLE goals(
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      title TEXT NOT NULL,
      start_day TEXT NOT NULL,
      target_day TEXT NOT NULL,
      start_value REAL,
      target_value REAL,
      status TEXT NOT NULL DEFAULT 'active',
      notes TEXT,
      created_at TEXT NOT NULL)''');
    await b.commit(noResult: true);
  }

  /// Phase 5: weekly gym schedule + reminder preferences.
  static Future<void> _v3(Database db) async {
    final b = db.batch();
    b.execute('''CREATE TABLE gym_schedule(
      weekday INTEGER PRIMARY KEY CHECK (weekday BETWEEN 1 AND 7),
      minutes INTEGER CHECK (minutes IS NULL OR minutes BETWEEN 0 AND 1439))''');
    b.execute("ALTER TABLE profile ADD COLUMN reminder_offsets TEXT NOT NULL DEFAULT '20'");
    b.execute('ALTER TABLE profile ADD COLUMN reminders_enabled INTEGER NOT NULL DEFAULT 0');
    await b.commit(noResult: true);
  }

  /// Phase 6: IronPulse AI chat history (stored only on the phone) + sharing choices.
  static Future<void> _v4(Database db) async {
    final b = db.batch();
    b.execute('''CREATE TABLE ai_conversations(
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL)''');
    b.execute('''CREATE TABLE ai_messages(
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
      role TEXT NOT NULL CHECK (role IN ('user','assistant')),
      content TEXT NOT NULL,
      created_at TEXT NOT NULL)''');
    b.execute('CREATE INDEX idx_ai_msg_conv ON ai_messages(conversation_id, created_at)');
    b.execute('ALTER TABLE profile ADD COLUMN ai_share_training INTEGER NOT NULL DEFAULT 0');
    b.execute('ALTER TABLE profile ADD COLUMN ai_share_nutrition INTEGER NOT NULL DEFAULT 0');
    await b.commit(noResult: true);
  }

  /// Phase 7: daily summaries imported from Health Connect (never raw samples).
  static Future<void> _v5(Database db) async {
    final b = db.batch();
    b.execute('''CREATE TABLE health_daily(
      day TEXT PRIMARY KEY,
      steps INTEGER,
      hr_avg REAL,
      hr_min REAL,
      hr_max REAL,
      resting_hr REAL,
      sleep_minutes INTEGER,
      source TEXT NOT NULL DEFAULT 'health_connect',
      synced_at TEXT NOT NULL)''');
    b.execute('ALTER TABLE profile ADD COLUMN health_enabled INTEGER NOT NULL DEFAULT 0');
    b.execute('ALTER TABLE profile ADD COLUMN health_last_sync TEXT');
    b.execute('ALTER TABLE profile ADD COLUMN health_last_error TEXT');
    await b.commit(noResult: true);
  }

  /// Phase 8: record of privacy choices (what, on/off, policy version, when).
  static Future<void> _v6(Database db) async {
    await db.execute('''CREATE TABLE consent_records(
      id TEXT PRIMARY KEY,
      purpose TEXT NOT NULL,
      granted INTEGER NOT NULL,
      policy_version TEXT NOT NULL,
      created_at TEXT NOT NULL)''');
  }
}
