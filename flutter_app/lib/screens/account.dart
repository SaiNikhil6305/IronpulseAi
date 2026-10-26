import 'package:flutter/material.dart';

import '../config.dart';
import '../data/cloud_repo.dart';
import '../data/repo.dart';
import '../logic/progress.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

enum _Mode { signIn, signUp, verify, forgot, reset }

class _AccountScreenState extends State<AccountScreen> {
  _Mode _mode = _Mode.signIn;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false, _obscure = true;
  String? _error, _info;
  BackupInfo? _backup;
  bool _auto = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final p = await Repo.profile();
    BackupInfo? b;
    if (CloudRepo.signedIn) {
      try {
        b = await CloudRepo.lastBackup();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _backup = b;
      _auto = (p?['cloud_auto_backup'] as int? ?? 1) == 1;
    });
  }

  Future<void> _run(Future<void> Function() f, {String? done}) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await f();
      if (done != null) _info = done;
    } on CloudException catch (e) {
      _error = e.message;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  bool _valid({bool needPassword = true}) {
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim()) &&
        (!needPassword || _password.text.length >= 8);
    if (!ok) {
      setState(() => _error = needPassword
          ? 'Enter a valid email and a password of at least 8 characters.'
          : 'Enter a valid email address.');
    }
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account & backup')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        if (!cloudConfigured)
          const IPCard(
            child: Text('Cloud backup is not set up in this build yet. The app works fully offline - '
                'your data stays on this phone. (Developer: see docs/PHASE9_SETUP.md.)'),
          )
        else if (CloudRepo.signedIn)
          ..._signedIn()
        else
          ..._signedOut(),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: IP.error)),
        ],
        if (_info != null) ...[
          const SizedBox(height: 12),
          Text(_info!, style: const TextStyle(color: IP.success)),
        ],
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      ]),
    );
  }

  List<Widget> _signedIn() {
    final u = CloudRepo.user!;
    final provider = (u.appMetadata['provider'] as String?) ?? 'email';
    return [
      const SectionTitle('Signed in'),
      IPCard(
        child: Row(children: [
          const Icon(Icons.account_circle, size: 40, color: IP.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.email ?? 'Account', style: const TextStyle(fontWeight: FontWeight.w800)),
              Muted(provider == 'google' ? 'Google account' : 'Email account', size: 12),
            ]),
          ),
        ]),
      ),
      const SectionTitle('Cloud backup'),
      IPCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              _backup == null
                  ? 'No backup yet'
                  : 'Last backup: ${fmtDate(_backup!.updatedAt)} '
                      '${_backup!.updatedAt.hour.toString().padLeft(2, '0')}:${_backup!.updatedAt.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Muted('Your workouts, nutrition, weight, goals, settings and AI chats are copied to your private '
              'cloud record. Only you can read it. Access tokens are never uploaded.', size: 12.5),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Back up automatically after each workout'),
            value: _auto,
            onChanged: (v) async {
              await Repo.updateProfile({'cloud_auto_backup': v ? 1 : 0});
              setState(() => _auto = v);
            },
          ),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : () => _run(CloudRepo.backupNow, done: 'Backup complete.'),
                child: const Text('Back up now'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: _busy ? null : _confirmRestore, child: const Text('Restore'))),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: _busy ? null : () => _run(CloudRepo.signOut), child: const Text('Sign out')),
      const SizedBox(height: 8),
      const Muted('Signing out keeps everything on this phone.', size: 12),
      const SectionTitle('Danger zone'),
      OutlinedButton(
        style: OutlinedButton.styleFrom(foregroundColor: IP.error),
        onPressed: _busy ? null : _confirmDeleteCloud,
        child: const Text('Delete my cloud account'),
      ),
      const SizedBox(height: 6),
      const Muted('Deletes your login and cloud backup permanently. Data on this phone is not touched '
          '(use Settings → Delete all my data for that).', size: 12),
    ];
  }

  Future<void> _confirmRestore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from cloud?'),
        content: const Text('This replaces ALL data on this phone with your last cloud backup. '
            'Anything logged here since that backup will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await CloudRepo.restore();
      notifyDataChanged();
    }, done: 'Restored. Your data is back.');
  }

  Future<void> _confirmDeleteCloud() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Delete cloud account?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Your login and cloud backup will be permanently deleted. This cannot be undone.'),
            const SizedBox(height: 12),
            TextField(controller: c, onChanged: (_) => setD(() {}), decoration: const InputDecoration(labelText: 'Type DELETE')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: IP.error, foregroundColor: Colors.white),
              onPressed: c.text.trim() == 'DELETE' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _run(CloudRepo.deleteCloudAccount, done: 'Cloud account deleted.');
  }

  List<Widget> _signedOut() {
    Widget emailField() => TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email'),
        );
    Widget passwordField(String label) => TextField(
          controller: _password,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off)),
          ),
        );
    Widget codeField() => TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(labelText: 'Code from the email', counterText: ''),
        );

    return [
      const SizedBox(height: 4),
      const Muted('Sign in to back up your training to the cloud and restore it on a new phone. '
          'Optional - IronPulse works fully without an account.'),
      const SizedBox(height: 16),
      if (googleConfigured && (_mode == _Mode.signIn || _mode == _Mode.signUp)) ...[
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(CloudRepo.signInWithGoogle, done: 'Signed in with Google.'),
          icon: const Icon(Icons.g_mobiledata, size: 28),
          label: const Text('Continue with Google'),
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: Muted('or use email'))),
      ],
      switch (_mode) {
        _Mode.signIn => Column(children: [
            emailField(),
            const SizedBox(height: 10),
            passwordField('Password'),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        if (_valid()) _run(() => CloudRepo.signIn(_email.text, _password.text), done: 'Signed in.');
                      },
                child: const Text('Sign in'),
              ),
            ),
            TextButton(onPressed: () => setState(() => _mode = _Mode.signUp), child: const Text('Create an account')),
            TextButton(onPressed: () => setState(() => _mode = _Mode.forgot), child: const Text('Forgot password?')),
          ]),
        _Mode.signUp => Column(children: [
            emailField(),
            const SizedBox(height: 10),
            passwordField('Choose a password (8+ characters)'),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        if (!_valid()) return;
                        _run(() async {
                          final signedIn = await CloudRepo.signUp(_email.text, _password.text);
                          if (!signedIn) {
                            setState(() => _mode = _Mode.verify);
                            _info = 'We emailed you a code. Enter it below.';
                          }
                        });
                      },
                child: const Text('Create account'),
              ),
            ),
            TextButton(onPressed: () => setState(() => _mode = _Mode.signIn), child: const Text('I already have an account')),
          ]),
        _Mode.verify => Column(children: [
            Muted('Code sent to ${_email.text.trim()}'),
            const SizedBox(height: 10),
            codeField(),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : () => _run(() => CloudRepo.verifySignupCode(_email.text, _code.text), done: 'Account confirmed.'),
                child: const Text('Confirm'),
              ),
            ),
          ]),
        _Mode.forgot => Column(children: [
            emailField(),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        if (!_valid(needPassword: false)) return;
                        _run(() async {
                          await CloudRepo.sendPasswordReset(_email.text);
                          setState(() => _mode = _Mode.reset);
                          _info = 'If that email has an account, a reset code is on its way.';
                        });
                      },
                child: const Text('Send reset code'),
              ),
            ),
            TextButton(onPressed: () => setState(() => _mode = _Mode.signIn), child: const Text('Back to sign in')),
          ]),
        _Mode.reset => Column(children: [
            codeField(),
            const SizedBox(height: 10),
            passwordField('New password (8+ characters)'),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        if (_valid()) {
                          _run(() => CloudRepo.resetPassword(_email.text, _code.text, _password.text),
                              done: 'Password changed. You are signed in.');
                        }
                      },
                child: const Text('Set new password'),
              ),
            ),
          ]),
      },
    ];
  }
}
