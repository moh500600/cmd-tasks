import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/validators.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

String? _v(BuildContext c, String? Function(String?) f, String? value) {
  final e = f(value);
  return e == null ? null : c.tr(e);
}

class _AuthScaffold extends ConsumerWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _AuthScaffold({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final lang = ref.watch(settingsProvider).languageCode;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.language_rounded),
            label: Text(lang == 'ar' ? 'English' : 'العربية'),
            onPressed: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(languageCode: lang == 'ar' ? 'en' : 'ar')),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [cs.primary, const Color(0xFF8B5CF6)]),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: const Icon(Icons.task_alt_rounded, color: Colors.white, size: 46),
                  ),
                ),
                const SizedBox(height: 18),
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 28),
                child,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false, _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await guard(context, () async {
      final u = await ref.read(authRepositoryProvider).login(_email.text, _pass.text);
      await ref.read(sessionProvider.notifier).signIn(u);
      await ref.read(notificationServiceProvider).requestPermissions();
      await ref.read(actionsProvider).rescheduleNotifications();
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
        title: context.tr('app_name'),
        subtitle: context.tr('login_subtitle'),
        child: Form(
          key: _form,
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(labelText: context.tr('email'), prefixIcon: const Icon(Icons.alternate_email_rounded)),
                validator: (v) => _v(context, Validators.email, v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: context.tr('password'),
                  prefixIcon: const Icon(Icons.lock_rounded),
                  suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded), onPressed: () => setState(() => _obscure = !_obscure)),
                ),
                validator: (v) => _v(context, Validators.required, v),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                  child: Text(context.tr('forgot_password')),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(context.tr('login')),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(context.tr('no_account')),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
                  child: Text(context.tr('signup')),
                ),
              ]),
            ]),
          ),
        ),
      );
}

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _answer = TextEditingController();
  String? _question;
  bool _busy = false, _obscure = true;

  static const questions = ['sq_city', 'sq_school', 'sq_friend', 'sq_food'];

  @override
  void dispose() {
    for (final c in [_name, _email, _pass, _pass2, _answer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _signup() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await guard(context, () async {
      final r = await ref.read(authRepositoryProvider).signUp(
            name: _name.text,
            email: _email.text,
            password: _pass.text,
            securityQuestion: context.tr(_question!),
            securityAnswer: _answer.text,
          );
      if (!mounted) return;
      await showRecoveryCodeDialog(context, r.recoveryCode);
      final session = ref.read(sessionProvider.notifier);
      final notif = ref.read(notificationServiceProvider);
      final actions = ref.read(actionsProvider);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      await session.signIn(r.user);
      await notif.requestPermissions();
      await actions.rescheduleNotifications();
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
        title: context.tr('create_account'),
        subtitle: context.tr('signup_subtitle'),
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: context.tr('full_name'), prefixIcon: const Icon(Icons.person_rounded)),
              validator: (v) => _v(context, Validators.name, v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: context.tr('email'), prefixIcon: const Icon(Icons.alternate_email_rounded)),
              validator: (v) => _v(context, Validators.email, v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pass,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: context.tr('password'),
                helperText: context.tr('password_hint'),
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded), onPressed: () => setState(() => _obscure = !_obscure)),
              ),
              validator: (v) => _v(context, Validators.password, v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pass2,
              obscureText: _obscure,
              decoration: InputDecoration(labelText: context.tr('confirm_password'), prefixIcon: const Icon(Icons.lock_outline_rounded)),
              validator: (v) => v != _pass.text ? context.tr('v_password_match') : null,
            ),
            const SizedBox(height: 20),
            Text(context.tr('recovery_setup'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _question,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('security_question'), prefixIcon: const Icon(Icons.help_rounded)),
              items: [for (final q in questions) DropdownMenuItem(value: q, child: Text(context.tr(q)))],
              onChanged: (v) => setState(() => _question = v),
              validator: (v) => v == null ? context.tr('v_required') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _answer,
              decoration: InputDecoration(labelText: context.tr('security_answer'), prefixIcon: const Icon(Icons.key_rounded)),
              validator: (v) => _v(context, Validators.required, v),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _signup,
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(context.tr('signup')),
            ),
          ]),
        ),
      );
}

Future<void> showRecoveryCodeDialog(BuildContext context, String code) => showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.key_rounded, size: 36),
        title: Text(ctx.tr('recovery_code')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(ctx.tr('recovery_code_info')),
          const SizedBox(height: 16),
          SelectableText(code, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 2)),
        ]),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded),
            label: Text(ctx.tr('copy')),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              showSnack(ctx, ctx.tr('copied'));
            },
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('saved_it'))),
        ],
      ),
    );

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _answer = TextEditingController();
  final _code = TextEditingController();
  final _pass = TextEditingController();
  String? _question;
  bool _useCode = false;

  @override
  void dispose() {
    for (final c in [_email, _answer, _code, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _findQuestion() async {
    final e = Validators.email(_email.text);
    if (e != null) {
      showSnack(context, context.tr(e), error: true);
      return;
    }
    await guard(context, () async {
      final q = await ref.read(authRepositoryProvider).securityQuestionFor(_email.text);
      setState(() => _question = q);
    });
  }

  Future<void> _reset() async {
    if (!_form.currentState!.validate()) return;
    final ok = await guard(context, () => ref.read(authRepositoryProvider).resetPassword(
          email: _email.text,
          securityAnswer: _useCode ? null : _answer.text,
          recoveryCode: _useCode ? _code.text : null,
          newPassword: _pass.text,
        ), successKey: 'password_reset_done');
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
        title: context.tr('reset_password'),
        subtitle: context.tr('reset_subtitle'),
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              enabled: _question == null,
              decoration: InputDecoration(labelText: context.tr('email'), prefixIcon: const Icon(Icons.alternate_email_rounded)),
              validator: (v) => _v(context, Validators.email, v),
            ),
            const SizedBox(height: 12),
            if (_question == null)
              FilledButton(onPressed: _findQuestion, child: Text(context.tr('continue')))
            else ...[
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(context.tr('security_question'))),
                  ButtonSegment(value: true, label: Text(context.tr('recovery_code'))),
                ],
                selected: {_useCode},
                onSelectionChanged: (s) => setState(() => _useCode = s.first),
              ),
              const SizedBox(height: 12),
              if (!_useCode) ...[
                Text(_question!, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _answer,
                  decoration: InputDecoration(labelText: context.tr('security_answer'), prefixIcon: const Icon(Icons.key_rounded)),
                  validator: (v) => _v(context, Validators.required, v),
                ),
              ] else
                TextFormField(
                  controller: _code,
                  textDirection: TextDirection.ltr,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'XXXX-XXXX-XXXX', prefixIcon: Icon(Icons.password_rounded)),
                  validator: (v) => _v(context, Validators.required, v),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass,
                obscureText: true,
                decoration: InputDecoration(labelText: context.tr('new_password'), prefixIcon: const Icon(Icons.lock_reset_rounded)),
                validator: (v) => _v(context, Validators.password, v),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _reset, child: Text(context.tr('reset_password'))),
            ],
          ]),
        ),
      );
}
