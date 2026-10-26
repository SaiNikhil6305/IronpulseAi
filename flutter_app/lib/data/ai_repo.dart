import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../logic/progress.dart';
import 'account_repo.dart';
import 'db.dart';
import 'nutrition_repo.dart';
import 'repo.dart';
import 'seed.dart';

class AiMessage {
  final String id, role, content;
  final DateTime at;
  AiMessage(this.id, this.role, this.content, this.at);
}

class AiConversation {
  final String id, title;
  final DateTime updated;
  AiConversation(this.id, this.title, this.updated);
}

class AiConfig {
  final String url, token;
  const AiConfig(this.url, this.token);
  bool get complete => url.isNotEmpty && token.isNotEmpty;
}

class AiException implements Exception {
  final String message;
  AiException(this.message);
  @override
  String toString() => message;
}

/// Chat history lives only on the phone. The server is stateless.
class AiRepo {
  static Future<Database> get _db => AppDb.get();
  static const _storage = FlutterSecureStorage();
  static const defaultUrl = 'http://127.0.0.1:8000';

  // ---------- Connection settings (token in Android Keystore / iOS Keychain) ----------
  static Future<AiConfig> config() async => AiConfig(
        await _storage.read(key: 'ai_url') ?? defaultUrl,
        await _storage.read(key: 'ai_token') ?? '',
      );

  static Future<void> saveConfig(String url, String token) async {
    await _storage.write(key: 'ai_url', value: url.trim().replaceAll(RegExp(r'/+$'), ''));
    await _storage.write(key: 'ai_token', value: token.trim());
  }

  // ---------- Sharing choices ----------
  static Future<(bool, bool)> sharing() async {
    final p = await Repo.profile();
    return ((p?['ai_share_training'] as int? ?? 0) == 1, (p?['ai_share_nutrition'] as int? ?? 0) == 1);
  }

  static Future<void> saveSharing(bool training, bool nutrition) async {
    await Repo.updateProfile({'ai_share_training': training ? 1 : 0, 'ai_share_nutrition': nutrition ? 1 : 0});
    await AccountRepo.recordConsent('ai_share_training', training);
    await AccountRepo.recordConsent('ai_share_nutrition', nutrition);
  }

  /// The only personal data ever sent, and only when the user switched sharing on.
  /// Deliberately small: no name, no body photos, no exact dates beyond "days ago".
  static Future<String?> buildContext() async {
    final (training, nutrition) = await sharing();
    if (!training && !nutrition) return null;
    final lines = <String>[];
    final p = await Repo.profile();
    if (training) {
      if (p?['goal'] != null) lines.add('Goal: ${p!['goal']}');
      if (p?['experience'] != null) lines.add('Experience: ${p!['experience']}');
      final days = await Repo.splitDays();
      if (days.isNotEmpty) {
        lines.add('Split: ${days.map((d) => '${d.name} (${d.muscles.map(muscleLabel).join(', ')})').join('; ')}');
      }
      final next = await Repo.nextDay();
      if (next != null) lines.add('Next planned workout: ${next.$2.name}');
      final s = streaks(await Repo.sessionDates(), p?['weekly_target'] as int? ?? 3);
      lines.add('Weekly target: ${s.target} workouts; this week: ${s.thisWeek}; streak: ${s.current} weeks');
      final recent = await Repo.doneSessions(limit: 3);
      for (final r in recent) {
        final ago = DateTime.now().difference(r.startedAt).inDays;
        final exs = await Repo.loadSession(r.id);
        final parts = exs.map((e) {
          final sets = e.sets.where((x) => x.done).map((x) => '${fmtW(x.weight)}x${x.reps}').join(', ');
          return '${e.exercise.name}: $sets';
        }).join('; ');
        lines.add('Workout ${ago == 0 ? 'today' : '$ago days ago'} - ${r.dayName}: $parts');
      }
      if (recent.isEmpty) lines.add('No workouts logged yet.');
    }
    if (nutrition) {
      final (avg, days) = await NutritionRepo.weeklyAverage(DateTime.now());
      final t = await NutritionRepo.targets();
      if (days == 0) {
        lines.add('Nutrition: nothing logged in the last 7 days.');
      } else {
        lines.add('Nutrition 7-day average over $days logged days: ${avg.calories.round()} kcal, '
            '${avg.protein.round()} g protein (user-entered, may be incomplete)');
      }
      if (t.enabled && t.protein != null) lines.add('Protein target: ${t.protein!.round()} g');
    }
    final text = lines.join('\n');
    return text.length > 3900 ? text.substring(0, 3900) : text;
  }

  // ---------- Conversations ----------
  static Future<List<AiConversation>> conversations() async {
    final r = await (await _db).query('ai_conversations', orderBy: 'updated_at DESC');
    return r
        .map((m) => AiConversation(m['id'] as String, m['title'] as String, DateTime.parse(m['updated_at'] as String)))
        .toList();
  }

  static Future<List<AiMessage>> messages(String conversationId) async {
    final r = await (await _db)
        .query('ai_messages', where: 'conversation_id = ?', whereArgs: [conversationId], orderBy: 'created_at');
    return r
        .map((m) => AiMessage(m['id'] as String, m['role'] as String, m['content'] as String,
            DateTime.parse(m['created_at'] as String)))
        .toList();
  }

  static Future<String> _ensureConversation(String? id, String firstMessage) async {
    if (id != null) return id;
    final newConv = newId();
    final title = firstMessage.length > 40 ? '${firstMessage.substring(0, 40)}…' : firstMessage;
    await (await _db).insert('ai_conversations', {'id': newConv, 'title': title, 'created_at': nowIso(), 'updated_at': nowIso()});
    return newConv;
  }

  static Future<void> _add(String conv, String role, String content) async {
    final db = await _db;
    await db.insert('ai_messages', {'id': newId(), 'conversation_id': conv, 'role': role, 'content': content, 'created_at': nowIso()});
    await db.update('ai_conversations', {'updated_at': nowIso()}, where: 'id = ?', whereArgs: [conv]);
  }

  static Future<void> deleteConversation(String id) async =>
      (await _db).delete('ai_conversations', where: 'id = ?', whereArgs: [id]);

  static Future<void> deleteAll() async => (await _db).delete('ai_conversations');

  /// Saves the user message, calls the server, saves the reply. Returns the conversation id.
  /// If the request fails, the user's message stays saved so they can retry.
  static Future<String> send(String? conversationId, String text, {http.Client? client}) async {
    final cfg = await config();
    if (!cfg.complete) throw AiException('IronPulse AI is not connected yet. Add your server address and access token.');
    final conv = await _ensureConversation(conversationId, text);
    await _add(conv, 'user', text);
    final history = await messages(conv);
    final recent = history.length > 12 ? history.sublist(history.length - 12) : history;
    final body = jsonEncode({
      'messages': [for (final m in recent) {'role': m.role, 'content': m.content.length > 4000 ? m.content.substring(0, 4000) : m.content}],
      if (await buildContext() case final ctx?) 'context': ctx,
    });
    final c = client ?? http.Client();
    try {
      final r = await c
          .post(Uri.parse('${cfg.url}/v1/chat'),
              headers: {'authorization': 'Bearer ${cfg.token}', 'content-type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 120));
      final data = _decode(r.body);
      if (r.statusCode != 200) {
        final msg = (data?['error'] as Map?)?['message'] as String?;
        throw AiException(switch (r.statusCode) {
          401 => 'The access token was rejected. Check it in AI settings.',
          429 => msg ?? 'Too many messages. Wait a moment.',
          _ => msg ?? 'The AI server returned an error (${r.statusCode}).',
        });
      }
      final reply = (data?['reply'] as String?)?.trim() ?? '';
      if (reply.isEmpty) throw AiException('The AI returned an empty answer. Try again.');
      await _add(conv, 'assistant', reply);
      return conv;
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw AiException('No answer after 2 minutes. The model may be too slow for this PC - try a smaller one.');
    } on SocketException {
      throw AiException('Cannot reach the AI server at ${cfg.url}. Check your internet connection and try again.');
    } on http.ClientException {
      throw AiException('Cannot reach the AI server at ${cfg.url}.');
    } finally {
      if (client == null) c.close();
    }
  }

  static Map<String, dynamic>? _decode(String s) {
    try {
      final v = jsonDecode(s);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Checks the server and model. Returns (ok, human-readable detail).
  static Future<(bool, String)> checkStatus() async {
    final cfg = await config();
    if (!cfg.complete) return (false, 'Not connected yet.');
    try {
      final r = await http
          .get(Uri.parse('${cfg.url}/v1/status'), headers: {'authorization': 'Bearer ${cfg.token}'})
          .timeout(const Duration(seconds: 75)); // a sleeping free cloud server needs ~1 min to wake
      if (r.statusCode == 401) return (false, 'Access token rejected.');
      final d = _decode(r.body);
      if (r.statusCode != 200 || d == null) return (false, 'Server error (${r.statusCode}).');
      return (d['ok'] == true, d['ok'] == true ? 'Connected · ${d['model']}' : '${d['detail']}');
    } catch (_) {
      return (false, 'Cannot reach ${cfg.url}. Check the address and your internet connection '
          '(for a PC server: start it and run adb reverse).');
    }
  }
}
