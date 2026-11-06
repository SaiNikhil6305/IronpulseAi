import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/routing/bootstrap.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../data/auth_controller.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootstrapProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Gaps.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Brand(size: 30),
              const SizedBox(height: Gaps.sm),
              const Text('Train Smart. Track Every Rep. Become Stronger.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: Gaps.xxl),
              if (boot.hasError) ...[
                const Icon(Icons.cloud_off, color: AppColors.warning, size: 36),
                const SizedBox(height: Gaps.md),
                Text('We couldn\'t load your account data.\n${boot.error}',
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: Gaps.lg),
                FilledButton(
                    onPressed: () => ref.read(bootstrapProvider.notifier).retry(), child: const Text('Try again')),
                TextButton(
                    onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                    child: const Text('Sign out')),
              ] else
                const CircularProgressIndicator(),
            ]),
          ),
        ),
      ),
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.subtitle, required this.child, this.showBack = false});
  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showBack ? AppBar() : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gaps.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!showBack) ...[const Align(alignment: Alignment.centerLeft, child: Brand()), const SizedBox(height: 40)],
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: Gaps.sm),
                Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 15)),
                const SizedBox(height: Gaps.xl),
                child,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when this build has no backend configuration: explains exactly what's
/// missing and offers device-only mode (real local data, clearly labelled).
class _NotConfiguredCard extends ConsumerWidget {
  const _NotConfiguredCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        borderColor: AppColors.warning.withValues(alpha: 0.5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.settings_suggest_outlined, color: AppColors.warning),
            SizedBox(width: 8),
            Expanded(child: Text('Account sign-in not configured', style: TextStyle(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: Gaps.sm),
          Text(
            'This build was compiled without backend settings (missing: ${Env.missing.join(', ')}). '
            'Email and Google sign-in, cloud backup and IronPulse AI need them — see docs/AUTH_SETUP.md.',
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ]),
      ),
      const SizedBox(height: Gaps.lg),
      LoadingButton(
        label: 'Use on this device only',
        icon: Icons.phone_android,
        onPressed: () => ref.read(authControllerProvider.notifier).enableLocalMode(),
      ),
      const SizedBox(height: Gaps.sm),
      const Text(
        'Device-only mode stores everything in this phone\'s private storage. Nothing is backed up, and '
        'uninstalling the app deletes it.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
    ]);
  }
}

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _googleBusy = false, _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() fn, {bool google = false}) async {
    setState(() => google ? _googleBusy = true : _busy = true);
    try {
      await fn();
    } on AuthFailure catch (e) {
      if (mounted && !e.cancelled) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => google ? _googleBusy = false : _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authControllerProvider.notifier);
    return _AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to pick up right where you left off.',
      child: !Env.backendConfigured
          ? const _NotConfiguredCard()
          : AutofillGroup(
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (Env.googleConfigured) ...[
                    LoadingButton(
                      label: 'Continue with Google',
                      icon: Icons.g_mobiledata_rounded,
                      outlined: true,
                      loading: _googleBusy,
                      onPressed: () => _run(auth.signInWithGoogle, google: true),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: Gaps.lg),
                      child: Row(children: [
                        Expanded(child: Divider()),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: AppColors.textMuted))),
                        Expanded(child: Divider()),
                      ]),
                    ),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: Validators.email,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: Gaps.md),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password.' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: () => context.push('/forgot-password'), child: const Text('Forgot password?')),
                  ),
                  const SizedBox(height: Gaps.sm),
                  LoadingButton(label: 'Sign in', loading: _busy, onPressed: _submit),
                  const SizedBox(height: Gaps.lg),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('New to IronPulse?', style: TextStyle(color: AppColors.textMuted)),
                    TextButton(onPressed: () => context.go('/sign-up'), child: const Text('Create account')),
                  ]),
                ]),
              ),
            ),
    );
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    _run(() => ref.read(authControllerProvider.notifier).signInWithEmail(_email.text, _password.text));
  }
}

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});
  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false, _accepted = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_accepted) {
      showSnack(context, 'Please accept the Terms and Privacy Policy to continue.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final needsConfirm =
          await ref.read(authControllerProvider.notifier).signUpWithEmail(_email.text, _password.text);
      if (!mounted) return;
      if (needsConfirm) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Check your inbox'),
            content: Text('We sent a confirmation link to ${_email.text.trim()}. Open it on this phone, then sign in.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        if (mounted) context.go('/sign-in');
      }
    } on AuthFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Create your account',
      subtitle: 'Welcome to IronPulse. Let\'s build your strongest self.',
      child: !Env.backendConfigured
          ? const _NotConfiguredCard()
          : Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (Env.googleConfigured) ...[
                  LoadingButton(
                    label: 'Sign up with Google',
                    icon: Icons.g_mobiledata_rounded,
                    outlined: true,
                    onPressed: () async {
                      if (!_accepted) {
                        showSnack(context, 'Please accept the Terms and Privacy Policy first.', error: true);
                        return;
                      }
                      try {
                        await ref.read(authControllerProvider.notifier).signInWithGoogle();
                      } on AuthFailure catch (e) {
                        if (context.mounted && !e.cancelled) showSnack(context, e.message, error: true);
                      }
                    },
                  ),
                  const SizedBox(height: Gaps.lg),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: Validators.email,
                ),
                const SizedBox(height: Gaps.md),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password', helperText: '8+ characters with a letter and a number'),
                  validator: Validators.password,
                ),
                const SizedBox(height: Gaps.md),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm password'),
                  validator: Validators.confirm(() => _password.text),
                ),
                const SizedBox(height: Gaps.md),
                CheckboxListTile(
                  value: _accepted,
                  onChanged: (v) => setState(() => _accepted = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Wrap(children: [
                    const Text('I agree to the '),
                    InkWell(onTap: () => context.push('/terms'), child: const Text('Terms', style: TextStyle(color: AppColors.accent))),
                    const Text(' and '),
                    InkWell(
                        onTap: () => context.push('/privacy'),
                        child: const Text('Privacy Policy', style: TextStyle(color: AppColors.accent))),
                  ]),
                ),
                const SizedBox(height: Gaps.md),
                LoadingButton(label: 'Create account', loading: _busy, onPressed: _submit),
                const SizedBox(height: Gaps.lg),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('Already have an account?', style: TextStyle(color: AppColors.textMuted)),
                  TextButton(onPressed: () => context.go('/sign-in'), child: const Text('Sign in')),
                ]),
              ]),
            ),
    );
  }
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false, _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      showBack: true,
      title: 'Reset password',
      subtitle: 'Enter your email and we\'ll send you a secure reset link.',
      child: _sent
          ? AppCard(
              child: Text(
                  'If an account exists for ${_email.text.trim()}, a reset link is on its way. Open it on this phone to choose a new password.'),
            )
          : Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: Validators.email,
                ),
                const SizedBox(height: Gaps.lg),
                LoadingButton(
                  label: 'Send reset link',
                  loading: _busy,
                  onPressed: () async {
                    if (!_form.currentState!.validate()) return;
                    setState(() => _busy = true);
                    try {
                      await ref.read(authControllerProvider.notifier).sendPasswordReset(_email.text);
                      setState(() => _sent = true);
                    } on AuthFailure catch (e) {
                      if (context.mounted) showSnack(context, e.message, error: true);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                ),
              ]),
            ),
    );
  }
}

class NewPasswordScreen extends ConsumerStatefulWidget {
  const NewPasswordScreen({super.key});
  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Choose a new password',
      subtitle: 'Your reset link was verified.',
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
              validator: Validators.password),
          const SizedBox(height: Gaps.md),
          TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              validator: Validators.confirm(() => _password.text)),
          const SizedBox(height: Gaps.lg),
          LoadingButton(
            label: 'Save password',
            loading: _busy,
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              setState(() => _busy = true);
              try {
                await ref.read(authControllerProvider.notifier).setNewPassword(_password.text);
                if (context.mounted) showSnack(context, 'Password updated.');
              } on AuthFailure catch (e) {
                if (context.mounted) showSnack(context, e.message, error: true);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
          ),
        ]),
      ),
    );
  }
}
