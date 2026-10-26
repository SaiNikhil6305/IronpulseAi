import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../data/ai_repo.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _suggestions = [
  'What should I train today?',
  'Give me a push-day workout',
  'How can I improve my bench press?',
  'Explain progressive overload',
  'Suggest vegetarian high-protein meals',
  'Analyze my recent workouts',
  'Help me plan my next two months',
  'What exercises target the upper chest?',
  'Why has my strength stopped improving?',
];

class AiScreen extends StatefulWidget {
  const AiScreen({super.key});
  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  String? _conv;
  List<AiMessage> _msgs = [];
  AiConfig? _cfg;
  bool _sending = false;
  String? _error;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final c = await AiRepo.config();
    if (mounted) setState(() => _cfg = c);
  }

  Future<void> _open(String? id) async {
    final m = id == null ? <AiMessage>[] : await AiRepo.messages(id);
    setState(() {
      _conv = id;
      _msgs = m;
      _error = null;
    });
    _toBottom();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
      _msgs = [..._msgs, AiMessage('pending', 'user', text, DateTime.now())];
    });
    _toBottom();
    String? conv = _conv;
    try {
      conv = await AiRepo.send(_conv, text);
    } on AiException catch (e) {
      _error = e.message;
      conv ??= (await AiRepo.conversations()).firstOrNull?.id;
    }
    if (!mounted) return;
    final msgs = conv == null ? _msgs : await AiRepo.messages(conv);
    setState(() {
      _conv = conv;
      _msgs = msgs;
      _sending = false;
    });
    _toBottom();
  }

  Future<void> _retry() async {
    // Resend the last user message as a new turn.
    final last = _msgs.lastWhere((m) => m.role == 'user', orElse: () => AiMessage('', 'user', '', DateTime.now()));
    if (last.content.isNotEmpty) await _send(last.content);
  }

  Future<void> _history() async {
    final list = await AiRepo.conversations();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.7,
        child: Column(children: [
          ListTile(
            title: const Text('Conversations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            trailing: list.isEmpty
                ? null
                : TextButton(
                    onPressed: () async {
                      await AiRepo.deleteAll();
                      if (ctx.mounted) Navigator.pop(ctx);
                      _open(null);
                    },
                    child: const Text('Delete all', style: TextStyle(color: IP.error)),
                  ),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(icon: Icons.forum_outlined, title: 'No conversations', body: 'Your chats stay on this phone.')
                : ListView(children: [
                    for (final c in list)
                      ListTile(
                        title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${c.updated.day}/${c.updated.month}'),
                        selected: c.id == _conv,
                        onTap: () {
                          Navigator.pop(ctx);
                          _open(c.id);
                        },
                        trailing: IconButton(
                          tooltip: 'Delete conversation',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await AiRepo.deleteConversation(c.id);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (c.id == _conv) _open(null);
                          },
                        ),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    return Scaffold(
      appBar: AppBar(
        title: const Text('IronPulse AI'),
        actions: [
          IconButton(tooltip: 'New chat', onPressed: () => _open(null), icon: const Icon(Icons.add_comment_outlined)),
          IconButton(tooltip: 'History', onPressed: _history, icon: const Icon(Icons.history)),
          IconButton(
            tooltip: 'AI settings & privacy',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const AiSettingsScreen()));
              _loadConfig();
            },
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: cfg == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(
                child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                  if (!cfg.complete) _setupCard(),
                  if (_msgs.isEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Ask anything about training, recovery or nutrition.',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Muted('General guidance only - not medical advice. For pain or injury, see a professional.',
                        size: 12.5),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final s in _suggestions)
                        ActionChip(label: Text(s), onPressed: cfg.complete ? () => _send(s) : null),
                    ]),
                  ],
                  for (final m in _msgs) _bubble(m),
                  if (_sending)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Muted('IronPulse AI is thinking…'),
                      ]),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: IPCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Icon(Icons.error_outline, color: IP.error, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!)),
                          ]),
                          TextButton(onPressed: _sending ? null : _retry, child: const Text('Try again')),
                        ]),
                      ),
                    ),
                ]),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: const BoxDecoration(color: IP.surface, border: Border(top: BorderSide(color: IP.border))),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        enabled: cfg.complete,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 2000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: cfg.complete ? 'Message IronPulse AI' : 'Connect IronPulse AI in settings',
                          counterText: '',
                          isDense: true,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: IP.accent, foregroundColor: Colors.black),
                      onPressed: cfg.complete && !_sending ? () => _send() : null,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }

  Widget _setupCard() => IPCard(
        highlight: true,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const AiSettingsScreen()));
          _loadConfig();
        },
        child: const Row(children: [
          Icon(Icons.link, color: IP.accent),
          SizedBox(width: 12),
          Expanded(
              child: Text('IronPulse AI is not connected. Tap to add your server address and access token. '
                  'Until then, no answers are generated.')),
        ]),
      );

  Widget _bubble(AiMessage m) {
    final user = m.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: m.content));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: BoxDecoration(
            color: user ? IP.accent.withOpacity(0.16) : IP.surface,
            border: Border.all(color: user ? IP.accent.withOpacity(0.4) : IP.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (user)
              SelectableText(m.content, style: const TextStyle(height: 1.35))
            else
              // Renders **bold**, lists and headings from the model. Links are shown but not opened.
              MarkdownBody(
                data: m.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: const TextStyle(height: 1.35, fontSize: 14.5),
                  strong: const TextStyle(fontWeight: FontWeight.w800),
                  code: const TextStyle(fontFamily: 'monospace', backgroundColor: IP.surface2),
                  tableBorder: TableBorder.all(color: IP.border),
                ),
              ),
            if (!user)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copy',
                  iconSize: 16,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: m.content));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                  },
                  icon: const Icon(Icons.copy, color: IP.muted),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});
  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  bool _training = false, _nutrition = false, _obscure = true, _checking = false;
  String? _status;
  bool? _ok;
  String? _preview;

  @override
  void initState() {
    super.initState();
    () async {
      final c = await AiRepo.config();
      final (t, n) = await AiRepo.sharing();
      if (!mounted) return;
      setState(() {
        _url.text = c.url;
        _token.text = c.token;
        _training = t;
        _nutrition = n;
      });
    }();
  }

  Future<void> _saveAndTest() async {
    setState(() => _checking = true);
    await AiRepo.saveConfig(_url.text, _token.text);
    final (ok, detail) = await AiRepo.checkStatus();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _ok = ok;
      _status = detail;
    });
  }

  Future<void> _setSharing(bool t, bool n) async {
    await AiRepo.saveSharing(t, n);
    setState(() {
      _training = t;
      _nutrition = n;
      _preview = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI settings & privacy')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        const SectionTitle('Connection'),
        TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Server address')),
        const SizedBox(height: 10),
        TextField(
          controller: _token,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Access token',
            suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off)),
          ),
        ),
        const SizedBox(height: 6),
        const Muted('The token is stored in your phone\'s secure storage. Use the same value as IRONPULSE_AI_TOKEN '
            'in the server\'s .env file. Over USB, keep the address http://127.0.0.1:8000.', size: 12),
        const SizedBox(height: 12),
        FilledButton(onPressed: _checking ? null : _saveAndTest, child: Text(_checking ? 'Checking…' : 'Save & test connection')),
        if (_status != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(_ok == true ? Icons.check_circle : Icons.error_outline, color: _ok == true ? IP.success : IP.warning),
            const SizedBox(width: 8),
            Expanded(child: Text(_status!)),
          ]),
        ],
        const SectionTitle('What IronPulse AI can see'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Share my training summary'),
          subtitle: const Text('Goal, experience, split, weekly target, last 3 workouts (exercise, weight, reps)'),
          value: _training,
          onChanged: (v) => _setSharing(v, _nutrition),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Share my nutrition summary'),
          subtitle: const Text('7-day average calories and protein, protein target'),
          value: _nutrition,
          onChanged: (v) => _setSharing(_training, v),
        ),
        const Muted('Both are off by default. Never shared: your name, weight history, photos, checklist, or full logs. '
            'The summary is attached to each message you send and is not stored by the server.', size: 12),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            final c = await AiRepo.buildContext();
            setState(() => _preview = c ?? 'Nothing is shared - sharing is off.');
          },
          child: const Text('Preview exactly what is sent'),
        ),
        if (_preview != null) ...[const SizedBox(height: 8), IPCard(child: SelectableText(_preview!, style: const TextStyle(fontSize: 12.5)))],
        const SectionTitle('Privacy'),
        const Muted('• Chat history is stored only on this phone. Delete chats from the History button.\n'
            '• Messages go to your IronPulse AI server, which forwards them to the configured model '
            '(by default a local Ollama model on your own PC, so nothing leaves your computer).\n'
            '• The server does not log message content.\n'
            '• IronPulse AI gives general fitness information, not medical advice.', size: 12.5),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: IP.error),
          onPressed: () async {
            await AiRepo.deleteAll();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All AI chats deleted')));
            }
          },
          child: const Text('Delete all AI chats'),
        ),
      ]),
    );
  }
}
