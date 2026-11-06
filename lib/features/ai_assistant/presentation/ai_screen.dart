import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_controller.dart';
import '../../profile/domain/profile.dart';
import '../data/ai_repository.dart';

const aiScopeLabels = {
  'profile': ('Profile basics', 'Experience, equipment, diet preferences, allergies, units'),
  'goals': ('Goals', 'Your fitness goals and active goal titles'),
  'split': ('Workout split', 'Split days and muscle groups'),
  'workouts': ('Recent workouts', 'Last 5 sessions: exercises, sets, top weights'),
  'nutrition': ('Nutrition logs', 'Daily calorie/protein totals for the last 7 days'),
  'progress': ('Progress', 'Streak, recent weigh-ins and personal records'),
};

const _suggestions = [
  'What should I train today?',
  'Give me a push-day workout.',
  'How can I improve my bench press?',
  'Explain progressive overload.',
  'Suggest vegetarian high-protein meals.',
  'Analyze my recent workouts.',
  'Help me plan my next two months.',
  'What exercises target the upper chest?',
  'Why has my strength stopped improving?',
];

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});
  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<AiMessage> _messages = [];
  String? _conversationId;
  bool _sending = false;
  String? _error;
  int? _remaining;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _send([String? text]) async {
    final msg = (text ?? _input.text).trim();
    if (msg.isEmpty || _sending) return;
    final scopes = ref.read(profileProvider)?.aiContextScopes ?? const [];
    setState(() {
      _messages.add(AiMessage(role: 'user', content: msg));
      _sending = true;
      _error = null;
      _input.clear();
    });
    _toBottom();
    try {
      final r = await ref.read(aiRepositoryProvider).send(msg, conversationId: _conversationId, scopes: scopes);
      setState(() {
        _conversationId = r.conversationId;
        _remaining = r.remainingToday;
        _messages.add(AiMessage(role: 'assistant', content: r.reply));
      });
    } on ApiException catch (e) {
      setState(() {
        _messages.removeLast();
        _input.text = msg;
        _error = switch (e.code) {
          'rate_limited' => 'You\'re sending messages quickly — wait a moment and try again.',
          'daily_limit_reached' => e.message,
          'ai_not_configured' => 'IronPulse AI is not configured on the server yet.',
          'ai_timeout' => 'IronPulse AI took too long to respond. Please try again.',
          'network' => 'You\'re offline. IronPulse AI needs an internet connection.',
          _ => e.message,
        };
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _toBottom();
    }
  }

  Future<void> _openHistory() async {
    final repo = ref.read(aiRepositoryProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FutureBuilder<List<AiConversation>>(
        future: repo.conversations(),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return SizedBox(
                height: 200,
                child: Center(child: snap.hasError ? Text('${snap.error}') : const CircularProgressIndicator()));
          }
          final list = snap.data!;
          return ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: Gaps.lg), children: [
            const ListTile(title: Text('Conversations', style: TextStyle(fontWeight: FontWeight.w800))),
            if (list.isEmpty) const ListTile(title: Text('No conversations yet.')),
            for (final c in list)
              ListTile(
                title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(Dates.friendly(c.updatedAt)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final msgs = await repo.messages(c.id);
                  setState(() {
                    _conversationId = c.id;
                    _messages
                      ..clear()
                      ..addAll(msgs);
                    _error = null;
                  });
                  _toBottom();
                },
                trailing: IconButton(
                  tooltip: 'Delete conversation',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await repo.deleteConversation(c.id);
                    if (_conversationId == c.id) setState(_newChat);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) showSnack(context, 'Conversation deleted.');
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }

  void _newChat() {
    _conversationId = null;
    _messages.clear();
    _error = null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final status = ref.watch(aiStatusProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Icon(Icons.auto_awesome, color: AppColors.accent), SizedBox(width: 8), Text('IronPulse AI')]),
        actions: [
          IconButton(tooltip: 'Data shared with AI', icon: const Icon(Icons.privacy_tip_outlined), onPressed: () => showAiPrivacySheet(context)),
          if (auth.canSync && status.value?.available == true) ...[
            IconButton(tooltip: 'Conversations', icon: const Icon(Icons.history), onPressed: _openHistory),
            IconButton(tooltip: 'New chat', icon: const Icon(Icons.add_comment_outlined), onPressed: () => setState(_newChat)),
          ],
        ],
      ),
      body: SafeArea(child: _body(auth, status)),
    );
  }

  Widget _body(AuthState auth, AsyncValue<({bool available, int dailyLimit, int maxChars})?> status) {
    if (!auth.canSync) {
      return EmptyState(
        icon: Icons.cloud_off,
        title: 'IronPulse AI needs an account',
        message: Env.backendConfigured
            ? 'Sign in to use IronPulse AI.'
            : 'This build has no backend configured, so IronPulse AI is unavailable. AI requests always go through '
                'the IronPulse server — the app never contains AI provider keys.',
      );
    }
    if (status.isLoading && !status.hasValue) return const Center(child: CircularProgressIndicator());
    if (status.hasError) {
      return EmptyState(
        icon: Icons.wifi_off,
        title: 'Can\'t reach IronPulse AI',
        message: ApiException.from(status.error!).message,
        action: 'Retry',
        onAction: () => ref.invalidate(aiStatusProvider),
      );
    }
    if (status.value?.available != true) {
      return const EmptyState(
        icon: Icons.settings_suggest_outlined,
        title: 'IronPulse AI is not configured yet',
        message: 'The server has no AI provider set up. No answers are generated until it is — see docs/DEPLOYMENT.md.',
      );
    }
    return Column(children: [
      Expanded(
        child: _messages.isEmpty
            ? ListView(padding: const EdgeInsets.all(Gaps.lg), children: [
                const Text('Ask anything about training, technique or nutrition.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('IronPulse AI gives general fitness guidance — not medical advice. For pain, injury or health '
                    'conditions, see a qualified professional.', style: TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: Gaps.lg),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in _suggestions) ActionChip(label: Text(s), onPressed: () => _send(s)),
                ]),
              ])
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(Gaps.lg),
                itemCount: _messages.length + (_sending ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == _messages.length) return const _TypingBubble();
                  return _Bubble(message: _messages[i]);
                },
              ),
      ),
      if (_error != null)
        Container(
          width: double.infinity,
          color: AppColors.error.withValues(alpha: 0.15),
          padding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.sm),
          child: Row(children: [
            Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error))),
            TextButton(onPressed: _send, child: const Text('Retry')),
          ]),
        ),
      if (_remaining != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('$_remaining messages left today', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.sm, Gaps.md, Gaps.md),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              maxLength: status.value?.maxChars ?? 2000,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(hintText: 'Message IronPulse AI'),
            ),
          ),
          const SizedBox(width: Gaps.sm),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: _sending ? null : _send,
            style: IconButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black, minimumSize: const Size(52, 52)),
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ]),
      ),
    ]);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.role == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        child: Container(
          margin: const EdgeInsets.only(bottom: Gaps.sm),
          padding: const EdgeInsets.all(Gaps.md),
          decoration: BoxDecoration(
            color: mine ? AppColors.accent : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: mine ? null : Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(message.content, style: TextStyle(color: mine ? Colors.black : AppColors.text, height: 1.4)),
            if (!mine)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Copy response',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 16, color: AppColors.textMuted),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: message.content));
                    if (context.mounted) showSnack(context, 'Copied.');
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) => const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.all(Gaps.md),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('IronPulse AI is thinking…', style: TextStyle(color: AppColors.textMuted)),
          ]),
        ),
      );
}

/// Lets the user choose which of their data IronPulse AI may use (default: none).
Future<void> showAiPrivacySheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AiPrivacySheet(),
    );

class _AiPrivacySheet extends ConsumerWidget {
  const _AiPrivacySheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider) ?? Profile.empty;
    final scopes = profile.aiContextScopes.toSet();
    return SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg), children: [
        Text('What IronPulse AI can see', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Gaps.sm),
        const Text(
          'Your messages are sent through the IronPulse server to a third-party AI provider. By default no personal '
          'training data is included. Turn on only what you want used for personalised answers. Conversations are '
          'stored on the server until you delete them.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: Gaps.md),
        for (final e in aiScopeLabels.entries)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e.value.$1),
            subtitle: Text(e.value.$2),
            value: scopes.contains(e.key),
            onChanged: (v) {
              final next = {...scopes};
              v ? next.add(e.key) : next.remove(e.key);
              ref.read(profileRepositoryProvider).save(profile.copyWith({'ai_context_scopes': next.toList()}));
            },
          ),
      ]),
    );
  }
}
