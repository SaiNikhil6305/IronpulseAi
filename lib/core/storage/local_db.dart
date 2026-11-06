import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// A queued write that must reach the backend. Ops are idempotent PUT/DELETE
/// requests keyed by client-generated ids, so replaying them is always safe.
class OutboxOp {
  OutboxOp({
    required this.opId,
    required this.method,
    required this.path,
    this.body,
    this.coalesceKey,
    this.seq,
    this.attempts = 0,
    this.lastError,
    this.failedPermanently = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  final int? seq;
  final String opId;
  final String method; // PUT | DELETE | POST
  final String path;
  final Map<String, dynamic>? body;

  /// Pending ops with the same key are replaced by newer ones (e.g. successive
  /// snapshots of the same workout), which keeps the queue small.
  final String? coalesceKey;
  final int attempts;
  final String? lastError;
  final bool failedPermanently;
  final DateTime createdAt;

  static OutboxOp fromRow(Map<String, Object?> r) => OutboxOp(
        seq: r['seq'] as int,
        opId: r['op_id'] as String,
        method: r['method'] as String,
        path: r['path'] as String,
        body: r['body'] == null ? null : jsonDecode(r['body'] as String) as Map<String, dynamic>,
        coalesceKey: r['coalesce_key'] as String?,
        attempts: r['attempts'] as int,
        lastError: r['last_error'] as String?,
        failedPermanently: (r['failed'] as int) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int, isUtc: true),
      );
}

/// On-device SQLite store.
///
/// * `docs` — JSON documents grouped by collection (sessions, meals, ...). The
///   app reads from here, so every screen works offline.
/// * `outbox` — pending writes for the sync service.
class LocalDb {
  LocalDb._(this.db);

  final Database db;
  final _changes = StreamController<String>.broadcast();

  /// Emits the collection name after every write ('*' for bulk changes).
  Stream<String> get changes => _changes.stream;

  static const _version = 1;

  static Future<LocalDb> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'ironpulse.db');
    final db = await f.openDatabase(dbPath,
        options: OpenDatabaseOptions(
          version: _version,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE docs(
              collection TEXT NOT NULL, id TEXT NOT NULL, data TEXT NOT NULL, updated_at INTEGER NOT NULL,
              PRIMARY KEY(collection, id))''');
            await db.execute('''CREATE TABLE outbox(
              seq INTEGER PRIMARY KEY AUTOINCREMENT, op_id TEXT NOT NULL UNIQUE, method TEXT NOT NULL,
              path TEXT NOT NULL, body TEXT, coalesce_key TEXT, attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT, failed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)''');
            await db.execute('CREATE INDEX ix_outbox_key ON outbox(coalesce_key)');
          },
        ));
    return LocalDb._(db);
  }

  void _notify(String collection) {
    if (!_changes.isClosed) _changes.add(collection);
  }

  // ---- Documents ----------------------------------------------------------
  Future<void> putDoc(String collection, String id, Map<String, dynamic> data) async {
    await db.insert(
      'docs',
      {
        'collection': collection,
        'id': id,
        'data': jsonEncode(data),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify(collection);
  }

  Future<Map<String, dynamic>?> getDoc(String collection, String id) async {
    final rows = await db.query('docs',
        columns: ['data'], where: 'collection = ? AND id = ?', whereArgs: [collection, id], limit: 1);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['data'] as String) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listDocs(String collection) async {
    final rows = await db.query('docs', columns: ['data'], where: 'collection = ?', whereArgs: [collection]);
    return [for (final r in rows) jsonDecode(r['data'] as String) as Map<String, dynamic>];
  }

  Future<void> deleteDoc(String collection, String id) async {
    await db.delete('docs', where: 'collection = ? AND id = ?', whereArgs: [collection, id]);
    _notify(collection);
  }

  /// Replace a collection with server data, keeping ids in [keep] (documents
  /// with local changes that have not been uploaded yet).
  Future<void> replaceCollection(String collection, Map<String, Map<String, dynamic>> docs,
      {Set<String> keep = const {}, bool deleteMissing = true}) async {
    await db.transaction((txn) async {
      if (deleteMissing) {
        final existing = await txn.query('docs', columns: ['id'], where: 'collection = ?', whereArgs: [collection]);
        for (final r in existing) {
          final id = r['id'] as String;
          if (!docs.containsKey(id) && !keep.contains(id)) {
            await txn.delete('docs', where: 'collection = ? AND id = ?', whereArgs: [collection, id]);
          }
        }
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final e in docs.entries) {
        if (keep.contains(e.key)) continue;
        await txn.insert('docs', {'collection': collection, 'id': e.key, 'data': jsonEncode(e.value), 'updated_at': now},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    _notify(collection);
  }

  // ---- Outbox -------------------------------------------------------------
  Future<void> enqueue(OutboxOp op) async {
    await db.transaction((txn) async {
      if (op.coalesceKey != null) {
        await txn.delete('outbox', where: 'coalesce_key = ? AND failed = 0', whereArgs: [op.coalesceKey]);
      }
      await txn.insert('outbox', {
        'op_id': op.opId,
        'method': op.method,
        'path': op.path,
        'body': op.body == null ? null : jsonEncode(op.body),
        'coalesce_key': op.coalesceKey,
        'attempts': 0,
        'failed': 0,
        'created_at': op.createdAt.millisecondsSinceEpoch,
      });
    });
    _notify('outbox');
  }

  Future<List<OutboxOp>> pendingOps({bool includeFailed = false}) async {
    final rows = await db.query('outbox', where: includeFailed ? null : 'failed = 0', orderBy: 'seq ASC');
    return rows.map(OutboxOp.fromRow).toList();
  }

  Future<void> removeOp(String opId) async {
    await db.delete('outbox', where: 'op_id = ?', whereArgs: [opId]);
    _notify('outbox');
  }

  Future<void> recordAttempt(String opId, String error, {bool permanent = false}) async {
    await db.rawUpdate('UPDATE outbox SET attempts = attempts + 1, last_error = ?, failed = ? WHERE op_id = ?',
        [error, permanent ? 1 : 0, opId]);
    _notify('outbox');
  }

  Future<void> retryFailed() async {
    await db.update('outbox', {'failed': 0});
    _notify('outbox');
  }

  Future<({int pending, int failed})> outboxCounts() async {
    final rows = await db.rawQuery('SELECT failed, COUNT(*) AS n FROM outbox GROUP BY failed');
    var pending = 0, failed = 0;
    for (final r in rows) {
      if (r['failed'] == 1) {
        failed = r['n'] as int;
      } else {
        pending = r['n'] as int;
      }
    }
    return (pending: pending, failed: failed);
  }

  /// Ids referenced by not-yet-uploaded ops; hydration must not overwrite them.
  Future<Set<String>> idsWithPendingChanges() async {
    final rows = await db.query('outbox', columns: ['path']);
    final ids = <String>{};
    final re = RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');
    for (final r in rows) {
      ids.addAll(re.allMatches(r['path'] as String).map((m) => m.group(0)!));
    }
    return ids;
  }

  Future<void> clearAll() async {
    await db.delete('docs');
    await db.delete('outbox');
    _notify('*');
  }

  Future<void> close() async {
    await _changes.close();
    await db.close();
  }
}
