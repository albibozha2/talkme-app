import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../screen_time.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';
import '../diagnostics.dart';

// ---------- two-step sign-in ----------

/// Asks for the authenticator code after the password was accepted. True when signed in.
Future<bool> finishTwoFactorSignIn(
  BuildContext context,
  WidgetRef ref,
  String ticket,
) async {
  while (true) {
    if (!context.mounted) return false;
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CodeDialog(),
    );
    if (code == null || !context.mounted) return false;
    try {
      await ref.read(sessionProvider.notifier).loginWithCode(ticket, code);
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      showError(context, e);
      // Only a mistyped code can be tried again; an expired sign-in or too many tries go back to the password.
      if (!(e is ApiException &&
          e.status == 401 &&
          e.message == trServer('Wrong code. Try again.'))) {
        return false;
      }
    }
  }
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog();

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _done() {
    final c = _code.text.trim();
    if (c.length >= 6) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.shield_outlined, color: AppColors.emerald),
    title: Text(tr('Two-step sign-in')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr('Enter the 6-digit code from your authenticator app.')),
        const SizedBox(height: 14),
        TextField(
          controller: _code,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, letterSpacing: 4),
          decoration: const InputDecoration(hintText: '123456'),
          onSubmitted: (_) => _done(),
        ),
        const SizedBox(height: 10),
        Text(
          tr('Lost your phone? Enter one of your backup codes instead.'),
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Cancel')),
      ),
      FilledButton(onPressed: _done, child: Text(tr('Verify'))),
    ],
  );
}

Future<String?> _askPassword(BuildContext context, String title) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(labelText: tr('Password')),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, c.text),
          child: Text(tr('Continue')),
        ),
      ],
    ),
  );
}

class TwoFactorScreen extends ConsumerStatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  ({String secret, String uri})? _setup;
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() => _run(() async {
    final s = await ref.read(apiProvider).twoFactorSetup();
    if (mounted) setState(() => _setup = s);
  });

  Future<void> _enable() => _run(() async {
    final r = await ref.read(apiProvider).twoFactorEnable(_code.text.trim());
    ref.read(sessionProvider.notifier).setUser(r.user);
    if (!mounted) return;
    setState(() => _setup = null);
    await _showBackupCodes(r.codes);
  });

  Future<void> _disable() async {
    final pw = await _askPassword(context, tr('Turn off two-step sign-in?'));
    if (pw == null || pw.isEmpty) return;
    await _run(() async {
      final u = await ref.read(apiProvider).twoFactorDisable(pw);
      ref.read(sessionProvider.notifier).setUser(u);
      if (mounted) showToast(context, tr('Two-step sign-in is off.'));
    });
  }

  Future<void> _showBackupCodes(List<String> codes) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(tr('Save your backup codes')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'If you lose your phone, each of these codes lets you sign in once. Keep them somewhere safe. They are shown only now.',
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              codes.join('\n'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: codes.join('\n')));
            showToast(context, tr('Copied'));
          },
          label: Text(tr('Copy')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('I saved them')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(sessionProvider).value;
    final muted = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final setup = _setup;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Two-step sign-in'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            me?.twoFactor ?? false
                ? Icons.verified_user_rounded
                : Icons.shield_outlined,
            size: 64,
            color: me?.twoFactor ?? false
                ? AppColors.emerald
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          if (me?.twoFactor ?? false) ...[
            Text(
              tr('Two-step sign-in is on'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                'When you sign in on a new device, you also need a code from your authenticator app.',
              ),
              textAlign: TextAlign.center,
              style: muted,
            ),
            const SizedBox(height: 8),
            Text(
              tr('{0} backup codes left', [me!.backupCodesLeft]),
              textAlign: TextAlign.center,
              style: muted,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _busy ? null : _disable,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.like,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(tr('Turn off')),
            ),
          ] else if (setup == null) ...[
            Text(
              tr('Protect your account'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                'Even if someone learns your password, they can’t sign in without a code from your phone. You need a free authenticator app such as Google Authenticator, Microsoft Authenticator or Authy.',
              ),
              textAlign: TextAlign.center,
              style: muted,
            ),
            const SizedBox(height: 24),
            GradientButton(
              label: tr('Set up'),
              icon: Icons.lock_outline_rounded,
              busy: _busy,
              onPressed: _start,
            ),
          ] else ...[
            Text(
              tr('1. Add TalkMe to your authenticator app'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (!kIsWeb) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(tr('Open authenticator app')),
                onPressed: () async {
                  final ok = await launchUrl(
                    Uri.parse(setup.uri),
                    mode: LaunchMode.externalApplication,
                  ).catchError((Object _) => false);
                  if (!ok && context.mounted) {
                    showToast(
                      context,
                      tr(
                        'No authenticator app found. Install one, or type the key below into it.',
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              Text(
                tr('Or scan this code with the app on another device:'),
                style: muted,
              ),
            ] else
              Text(
                tr('Scan this code with the app on your phone:'),
                style: muted,
              ),
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(data: setup.uri, size: 190),
              ),
            ),
            const SizedBox(height: 10),
            Text(tr('Or type this key:'), style: muted),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    RegExp(r'.{1,4}')
                        .allMatches(setup.secret)
                        .map((m) => m.group(0))
                        .join(' '),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr('Copy'),
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: setup.secret));
                    showToast(context, tr('Copied'));
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              tr('2. Enter the 6-digit code the app shows'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, letterSpacing: 4),
              decoration: const InputDecoration(hintText: '123456'),
              onSubmitted: (_) => _enable(),
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: tr('Turn on'),
              icon: Icons.verified_user_rounded,
              busy: _busy,
              onPressed: _enable,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------- privacy & safety ----------

String dmPolicyLabel(String v) => switch (v) {
  'followers' => tr('Followers'),
  'friends' => tr('Friends'),
  'none' => tr('No one'),
  _ => tr('Everyone'),
};

String mentionPolicyLabel(String v) => switch (v) {
  'following' => tr('People you follow'),
  'none' => tr('No one'),
  _ => tr('Everyone'),
};

/// Bottom sheet with radio choices; returns the chosen value.
Future<T?> chooseOption<T>(
  BuildContext context,
  String title,
  List<(T, String, String?)> options,
  T current,
) => showModalBottomSheet<T>(
  context: context,
  builder: (context) => SafeArea(
    child: RadioGroup<T>(
      groupValue: current,
      onChanged: (v) => Navigator.pop(context, v),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final (value, label, sub) in options)
            RadioListTile<T>(
              value: value,
              title: Text(label),
              subtitle: sub == null ? null : Text(sub),
            ),
        ],
      ),
    ),
  ),
);

class PrivacySafetyScreen extends ConsumerStatefulWidget {
  const PrivacySafetyScreen({super.key});

  @override
  ConsumerState<PrivacySafetyScreen> createState() =>
      _PrivacySafetyScreenState();
}

class _PrivacySafetyScreenState extends ConsumerState<PrivacySafetyScreen> {
  int _held = 0;

  @override
  void initState() {
    super.initState();
    ScreenTime.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    _countHeld();
  }

  Future<void> _countHeld() async {
    try {
      final n = (await ref.read(apiProvider).heldComments()).length;
      if (mounted) setState(() => _held = n);
    } catch (_) {}
  }

  Future<void> _save(Future<AppUser> Function(Api api) job) async {
    try {
      final u = await job(ref.read(apiProvider));
      ref.read(sessionProvider.notifier).setUser(u);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
    _countHeld();
  }

  Future<void> _download() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Download your data')),
        content: Text(
          tr(
            'You get one file with your profile, videos, comments, followers, messages you sent, coin history and sign-ins. The link works for 15 minutes.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Download')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final url = await ref.read(apiProvider).dataExportLink();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(sessionProvider).value;
    if (me == null) return const Scaffold();
    final words = me.commentFilter.isEmpty
        ? 0
        : me.commentFilter.split(',').length;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Privacy & safety'))),
      body: ListView(
        children: [
          SectionHeader(tr('Interactions')),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline_rounded),
            title: Text(tr('Who can message you')),
            subtitle: Text(dmPolicyLabel(me.dmPolicy)),
            onTap: () async {
              final v = await chooseOption(context, tr('Who can message you'), [
                (
                  'everyone',
                  tr('Everyone'),
                  tr('People you don’t follow land in Message requests'),
                ),
                ('followers', tr('Followers'), null),
                (
                  'friends',
                  tr('Friends'),
                  tr('People you follow who follow you back'),
                ),
                ('none', tr('No one'), null),
              ], me.dmPolicy);
              if (v != null) _save((api) => api.updateSettings(dmPolicy: v));
            },
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email_rounded),
            title: Text(tr('Who can mention you')),
            subtitle: Text(mentionPolicyLabel(me.mentionPolicy)),
            onTap: () async {
              final v = await chooseOption(context, tr('Who can mention you'), [
                ('everyone', tr('Everyone'), null),
                ('following', tr('People you follow'), null),
                ('none', tr('No one'), null),
              ], me.mentionPolicy);
              if (v != null) {
                _save((api) => api.updateSettings(mentionPolicy: v));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.filter_alt_outlined),
            title: Text(tr('Comment filters')),
            subtitle: Text(words == 0 ? tr('Off') : tr('{0} words', [words])),
            onTap: () => _push(const CommentFilterScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.rate_review_outlined),
            title: Text(tr('Comments to review')),
            trailing: _held > 0
                ? Badge(label: Text('$_held'), backgroundColor: AppColors.amber)
                : null,
            onTap: () => _push(const HeldCommentsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.do_not_disturb_on_outlined),
            title: Text(tr('Restricted accounts')),
            onTap: () => _push(const RestrictedAccountsScreen()),
          ),
          SectionHeader(tr('Account security')),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(tr('Two-step sign-in')),
            subtitle: Text(me.twoFactor ? tr('On') : tr('Off')),
            onTap: () => _push(const TwoFactorScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.devices_rounded),
            title: Text(tr("Where you're signed in")),
            onTap: () => _push(const SessionsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: Text(tr('Download your data')),
            onTap: _download,
          ),
          SectionHeader(tr('Help improve TalkMe')),
          SwitchListTile(
            secondary: const Icon(Icons.bug_report_outlined),
            title: Text(tr('Share diagnostics')),
            subtitle: Text(
              tr(
                'When something goes wrong, send a report with your phone model, app version and battery level, so we can fix it.',
              ),
            ),
            value: Diagnostics.enabled,
            onChanged: (on) async {
              await Diagnostics.setEnabled(on);
              if (mounted) setState(() {});
            },
          ),
          SectionHeader(tr('Wellbeing')),
          ListTile(
            leading: const Icon(Icons.hourglass_bottom_rounded),
            title: Text(tr('Screen time')),
            subtitle: Text(
              tr('Today: {0}', [formatMinutes(ScreenTime.instance.today)]),
            ),
            onTap: () => _push(const ScreenTimeScreen()),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------- comment filters ----------

class CommentFilterScreen extends ConsumerStatefulWidget {
  const CommentFilterScreen({super.key});

  @override
  ConsumerState<CommentFilterScreen> createState() =>
      _CommentFilterScreenState();
}

class _CommentFilterScreenState extends ConsumerState<CommentFilterScreen> {
  late final List<String> _words;
  final _input = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final f = ref.read(sessionProvider).value?.commentFilter ?? '';
    _words = f.isEmpty ? [] : f.split(',');
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    for (final w in _input.text.split(',')) {
      final t = w.trim().toLowerCase();
      if (t.length >= 2 && !_words.contains(t)) _words.add(t);
    }
    _input.clear();
    setState(() {});
  }

  Future<void> _save() async {
    _add();
    setState(() => _busy = true);
    try {
      final u = await ref
          .read(apiProvider)
          .updateSettings(commentFilter: _words.join(','));
      ref.read(sessionProvider.notifier).setUser(u);
      if (mounted) {
        showToast(context, tr('Saved'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('Comment filters')),
      actions: [
        TextButton(onPressed: _busy ? null : _save, child: Text(tr('Save'))),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          tr(
            'Comments on your videos that contain these words wait for your approval in “Comments to review”. The writer still sees their comment and isn’t told.',
          ),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _input,
          decoration: InputDecoration(
            labelText: tr('Add a word or phrase'),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: _add,
            ),
          ),
          onSubmitted: (_) => _add(),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in _words)
              InputChip(
                label: Text(w),
                onDeleted: () => setState(() => _words.remove(w)),
              ),
          ],
        ),
      ],
    ),
  );
}

class HeldCommentsScreen extends ConsumerStatefulWidget {
  const HeldCommentsScreen({super.key});

  @override
  ConsumerState<HeldCommentsScreen> createState() => _HeldCommentsScreenState();
}

class _HeldCommentsScreenState extends ConsumerState<HeldCommentsScreen> {
  List<Comment>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiProvider).heldComments();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _act(Comment c, bool approve) async {
    try {
      final api = ref.read(apiProvider);
      approve ? await api.approveComment(c.id) : await api.deleteComment(c.id);
      if (mounted) setState(() => _items!.remove(c));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Comments to review'))),
      body: items == null
          ? Center(
              child: _error != null
                  ? Text('$_error')
                  : const CircularProgressIndicator(),
            )
          : items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr(
                    'Nothing to review. Comments caught by your filters or from restricted accounts show up here.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              ),
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = items[i];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Avatar(
                            url: c.user.avatarUrl,
                            name: c.user.displayName,
                            radius: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '@${c.user.username}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  c.fromRestricted
                                      ? tr('Restricted account')
                                      : tr('Matched your filter'),
                                  style: TextStyle(fontSize: 12, color: muted),
                                ),
                              ],
                            ),
                          ),
                          if (c.thumbUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                c.thumbUrl!,
                                width: 36,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const SizedBox(),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(c.body),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _act(c, false),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.like,
                            ),
                            child: Text(tr('Delete')),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => _act(c, true),
                            child: Text(tr('Approve')),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ---------- restrict ----------

/// Confirms and restricts / unrestricts [u]. Returns the updated user.
Future<AppUser?> toggleRestrict(
  BuildContext context,
  WidgetRef ref,
  AppUser u,
) async {
  if (!u.restricted) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Restrict {0}?', [u.displayName])),
        content: Text(
          tr(
            'Their new comments on your videos wait for your approval, and their messages go to Message requests. They can still see your videos and aren’t told.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Restrict')),
          ),
        ],
      ),
    );
    if (ok != true) return null;
  }
  try {
    final updated = await ref
        .read(apiProvider)
        .setRestricted(u.username, !u.restricted);
    if (context.mounted) {
      showToast(
        context,
        updated.restricted ? tr('Restricted') : tr('No longer restricted'),
      );
    }
    return updated;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}

class RestrictedAccountsScreen extends ConsumerStatefulWidget {
  const RestrictedAccountsScreen({super.key});

  @override
  ConsumerState<RestrictedAccountsScreen> createState() =>
      _RestrictedAccountsScreenState();
}

class _RestrictedAccountsScreenState
    extends ConsumerState<RestrictedAccountsScreen> {
  List<AppUser>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiProvider).restrictedAccounts();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Restricted accounts'))),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr(
                      'Restricted people can still see your videos. Their new comments wait for your approval and their messages go to Message requests. They aren’t told.',
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(tr('No restricted accounts.'))),
                  ),
                for (final u in items)
                  ListTile(
                    leading: Avatar(url: u.avatarUrl, name: u.displayName),
                    title: Text(u.displayName),
                    subtitle: Text('@${u.username}'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(username: u.username),
                      ),
                    ),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final r = await toggleRestrict(
                          context,
                          ref,
                          AppUser.fromJson({
                            'id': u.id,
                            'username': u.username,
                            'restricted': true,
                          }),
                        );
                        if (r != null) _load();
                      },
                      child: Text(tr('Unrestrict')),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ---------- screen time ----------

class ScreenTimeScreen extends StatefulWidget {
  const ScreenTimeScreen({super.key});

  @override
  State<ScreenTimeScreen> createState() => _ScreenTimeScreenState();
}

class _ScreenTimeScreenState extends State<ScreenTimeScreen> {
  final st = ScreenTime.instance;

  @override
  void initState() {
    super.initState();
    st.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  String _limitLabel(int m) =>
      m == 0 ? tr('Off') : formatMinutes(Duration(minutes: m));

  @override
  Widget build(BuildContext context) {
    final days = st.lastDays(7);
    final maxSec = days
        .map((d) => d.$2.inSeconds)
        .fold<int>(60, (a, b) => b > a ? b : a);
    final scheme = Theme.of(context).colorScheme;
    final week = days.fold<Duration>(Duration.zero, (a, d) => a + d.$2);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Screen time'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Today'),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                Text(
                  formatMinutes(st.today),
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  tr('Daily average this week: {0}', [
                    formatMinutes(week ~/ 7),
                  ]),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (day, used) in days)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                height: 4 + 100 * used.inSeconds / maxSec,
                                decoration: BoxDecoration(
                                  gradient: AppColors.brandGradient,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                weekdayShort(day),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Counted on this device while the app is open.'),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(tr('Daily limit')),
            subtitle: Text(_limitLabel(st.limitMinutes)),
            onTap: () async {
              final v = await chooseOption<int>(context, tr('Daily limit'), [
                for (final m in [0, 30, 45, 60, 90, 120, 180])
                  (m, _limitLabel(m), null),
              ], st.limitMinutes);
              if (v != null) {
                await st.setLimit(v);
                setState(() {});
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.self_improvement_rounded),
            title: Text(tr('Break reminder')),
            subtitle: Text(
              st.breakMinutes == 0
                  ? tr('Off')
                  : tr('Every {0}', [
                      formatMinutes(Duration(minutes: st.breakMinutes)),
                    ]),
            ),
            onTap: () async {
              final v = await chooseOption<int>(context, tr('Break reminder'), [
                for (final m in [0, 10, 20, 30, 45, 60])
                  (
                    m,
                    m == 0
                        ? tr('Off')
                        : tr('Every {0}', [
                            formatMinutes(Duration(minutes: m)),
                          ]),
                    null,
                  ),
              ], st.breakMinutes);
              if (v != null) {
                await st.setBreak(v);
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }
}

String weekdayShort(DateTime d) => [
  tr('Mon'),
  tr('Tue'),
  tr('Wed'),
  tr('Thu'),
  tr('Fri'),
  tr('Sat'),
  tr('Sun'),
][d.weekday - 1];

// ---------- where you're signed in ----------

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  List<SessionInfo>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiProvider).sessions();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _end([SessionInfo? s]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          s == null
              ? tr('Sign out of all other devices?')
              : tr('Sign out this device?'),
        ),
        content: Text(
          s == null
              ? tr(
                  'Everyone signed in to your account on another device has to sign in again.',
                )
              : s.device,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Sign out')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).endSession(s?.id);
      if (mounted) showToast(context, tr('Signed out'));
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  IconData _icon(String device) {
    final d = device.toLowerCase();
    if (d.contains('web') || d.contains('windows') || d.contains('macos')) {
      return Icons.computer_rounded;
    }
    if (d.contains('ios')) return Icons.phone_iphone_rounded;
    return Icons.phone_android_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final muted = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 12.5,
    );
    final others = items?.where((s) => !s.current).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(tr("Where you're signed in"))),
      body: items == null
          ? Center(
              child: _error != null
                  ? Text('$_error')
                  : const CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      tr(
                        "If you see a device you don't recognise, sign it out and change your password.",
                      ),
                      style: muted,
                    ),
                  ),
                  for (final s in items)
                    ListTile(
                      leading: CircleAvatar(child: Icon(_icon(s.device))),
                      title: Text(
                        s.device.isEmpty ? tr('Unknown device') : s.device,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        [
                          if (s.place.isNotEmpty) s.place,
                          s.current
                              ? tr('This device')
                              : tr('Active {0}', [
                                  timeAgo(s.lastActive ?? s.signedIn),
                                ]),
                        ].join(' · '),
                        style: s.current
                            ? const TextStyle(
                                color: AppColors.emerald,
                                fontWeight: FontWeight.w600,
                              )
                            : null,
                      ),
                      trailing: s.current
                          ? null
                          : IconButton(
                              tooltip: tr('Sign out'),
                              icon: const Icon(Icons.logout_rounded),
                              onPressed: () => _end(s),
                            ),
                    ),
                  if (others > 1)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.like,
                          minimumSize: const Size.fromHeight(46),
                        ),
                        icon: const Icon(Icons.logout_rounded),
                        label: Text(tr('Sign out of all other devices')),
                        onPressed: () => _end(),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
