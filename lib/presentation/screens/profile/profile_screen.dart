import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/platform/desktop_files.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/validators.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../auth/auth_screens.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<String?> _askPassword(BuildContext context, String title, {String? body}) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (body != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(body)),
          TextField(controller: c, obscureText: true, autofocus: true, decoration: InputDecoration(labelText: ctx.tr('password'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ctx.tr('ok'))),
        ],
      ),
    );
    return (r == null || r.isEmpty) ? null : r;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    if (user == null) return const Scaffold();
    final auth = ref.read(authRepositoryProvider);
    final session = ref.read(sessionProvider.notifier);
    final stats = ref.watch(dashboardProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('profile'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: GestureDetector(
            onTap: () => guard(context, () async {
              final x = await pickImageFile(source: ImageSource.gallery, imageQuality: 85, maxWidth: 600);
              if (x == null) return;
              final path = await ref.read(fileStorageProvider).saveBytes(await x.readAsBytes(), x.name, folder: 'avatars');
              final old = user.avatarPath;
              session.refreshUser(await auth.updateProfile(user.id, avatarPath: path));
              await ref.read(fileStorageProvider).delete(old);
            }, successKey: 'saved_msg'),
            child: Stack(children: [
              UserAvatar(path: user.avatarPath, name: user.name, radius: 52),
              const PositionedDirectional(end: 0, bottom: 0, child: CircleAvatar(radius: 16, child: Icon(Icons.photo_camera_rounded, size: 18))),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text(user.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        Text(user.email, textAlign: TextAlign.center, textDirection: TextDirection.ltr),
        Text(context.trf('member_since', {'d': fmtDate(context, user.createdAt)}), textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        if (stats != null) ...[
          const SizedBox(height: 16),
          Row(children: [
            for (final (label, v) in [
              (context.tr('stat_total'), stats.total),
              (context.tr('stat_completed'), stats.completed),
              (context.tr('stat_overdue'), stats.overdue),
            ])
              Expanded(
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      Text('$v', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      Text(label, style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: Text(context.tr('edit_profile')),
              onTap: () => showDialog(context: context, builder: (_) => const _EditProfileDialog()),
            ),
            ListTile(
              leading: const Icon(Icons.lock_reset_rounded),
              title: Text(context.tr('change_password')),
              onTap: () => showDialog(context: context, builder: (_) => const _ChangePasswordDialog()),
            ),
            ListTile(
              leading: const Icon(Icons.key_rounded),
              title: Text(context.tr('new_recovery_code')),
              onTap: () async {
                final pw = await _askPassword(context, context.tr('new_recovery_code'));
                if (pw == null || !context.mounted) return;
                await guard(context, () async {
                  final code = await auth.regenerateRecoveryCode(user.id, pw);
                  if (context.mounted) await showRecoveryCodeDialog(context, code);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: Text(context.tr('logout')),
              onTap: () async {
                if (await confirm(context, context.tr('logout'), context.tr('logout_confirm'))) {
                  await session.signOut();
                  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                }
              },
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.delete_forever_rounded, color: Theme.of(context).colorScheme.error),
            title: Text(context.tr('delete_account'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            subtitle: Text(context.tr('delete_account_sub')),
            onTap: () async {
              final pw = await _askPassword(context, context.tr('delete_account'), body: context.tr('delete_account_confirm'));
              if (pw == null || !context.mounted) return;
              final ok = await guard(context, () async {
                await auth.deleteAccount(user.id, pw);
                await ref.read(fileStorageProvider).delete(user.avatarPath);
                await session.signOut();
              }, successKey: 'account_deleted');
              if (ok && context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ),
      ]),
    );
  }
}

class _EditProfileDialog extends ConsumerStatefulWidget {
  const _EditProfileDialog();

  @override
  ConsumerState<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends ConsumerState<_EditProfileDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: ref.read(sessionProvider)!.name);
  late final _email = TextEditingController(text: ref.read(sessionProvider)!.email);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.tr('edit_profile')),
        content: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: context.tr('full_name')),
              validator: (v) => Validators.name(v) == null ? null : context.tr(Validators.name(v)!),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _email,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: context.tr('email')),
              validator: (v) => Validators.email(v) == null ? null : context.tr(Validators.email(v)!),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              final ok = await guard(context, () async {
                final u = await ref.read(authRepositoryProvider).updateProfile(ref.read(sessionProvider)!.id, name: _name.text, email: _email.text);
                ref.read(sessionProvider.notifier).refreshUser(u);
              }, successKey: 'saved_msg');
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: Text(context.tr('save')),
          ),
        ],
      );
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _cur = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.tr('change_password')),
        content: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: _cur, obscureText: true, decoration: InputDecoration(labelText: context.tr('current_password')),
                validator: (v) => (v == null || v.isEmpty) ? context.tr('v_required') : null),
            const SizedBox(height: 10),
            TextFormField(controller: _new, obscureText: true, decoration: InputDecoration(labelText: context.tr('new_password')),
                validator: (v) => Validators.password(v) == null ? null : context.tr(Validators.password(v)!)),
            const SizedBox(height: 10),
            TextFormField(controller: _new2, obscureText: true, decoration: InputDecoration(labelText: context.tr('confirm_password')),
                validator: (v) => v != _new.text ? context.tr('v_password_match') : null),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              final ok = await guard(context,
                  () => ref.read(authRepositoryProvider).changePassword(ref.read(sessionProvider)!.id, _cur.text, _new.text),
                  successKey: 'password_changed');
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: Text(context.tr('save')),
          ),
        ],
      );
}
