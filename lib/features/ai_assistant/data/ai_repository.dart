import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_service.dart';
import '../../auth/data/auth_controller.dart';

class AiMessage {
  const AiMessage({required this.role, required this.content, this.id, this.createdAt});
  final String? id;
  final String role; // user | assistant
  final String content;
  final DateTime? createdAt;

  factory AiMessage.fromJson(Map<String, dynamic> j) => AiMessage(
        id: j['id'] as String?,
        role: j['role'] as String,
        content: j['content'] as String,
        createdAt: j['created_at'] == null ? null : DateTime.parse(j['created_at'] as String),
      );
}

class AiConversation {
  const AiConversation({required this.id, required this.title, required this.updatedAt});
  final String id;
  final String title;
  final DateTime updatedAt;
}

class AiReply {
  const AiReply(this.conversationId, this.reply, this.remainingToday, this.scopesUsed);
  final String conversationId;
  final String reply;
  final int remainingToday;
  final List<String> scopesUsed;
}

/// IronPulse AI goes through the backend only. The app never holds a provider key.
class AiRepository {
  AiRepository(this.api);
  final ApiClient api;

  Future<({bool available, int dailyLimit, int maxChars})> status() async {
    final r = await api.get('/v1/ai/status') as Map;
    return (
      available: r['available'] == true,
      dailyLimit: (r['daily_limit'] as num?)?.toInt() ?? 0,
      maxChars: (r['max_input_chars'] as num?)?.toInt() ?? 2000
    );
  }

  Future<AiReply> send(String message, {String? conversationId, List<String> scopes = const []}) async {
    final r = await api.post('/v1/ai/messages', {
      'message': message,
      'conversation_id': conversationId,
      'context_scopes': scopes,
    }) as Map;
    return AiReply('${r['conversation_id']}', r['reply'] as String, (r['remaining_today'] as num).toInt(),
        [for (final s in (r['context_scopes_used'] as List? ?? const [])) '$s']);
  }

  Future<List<AiConversation>> conversations() async {
    final r = await api.get('/v1/ai/conversations') as List;
    return [
      for (final c in r)
        AiConversation(id: '${c['id']}', title: '${c['title']}', updatedAt: DateTime.parse('${c['updated_at']}'))
    ];
  }

  Future<List<AiMessage>> messages(String conversationId) async {
    final r = await api.get('/v1/ai/conversations/$conversationId/messages') as List;
    return [for (final m in r) AiMessage.fromJson(Map<String, dynamic>.from(m))];
  }

  Future<void> deleteConversation(String id) => api.delete('/v1/ai/conversations/$id');
}

final aiRepositoryProvider = Provider<AiRepository>((ref) => AiRepository(ref.watch(apiClientProvider)));

/// null = unavailable in this build/mode (no backend or device-only).
final aiStatusProvider = FutureProvider<({bool available, int dailyLimit, int maxChars})?>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.canSync) return null;
  return ref.read(aiRepositoryProvider).status();
});
