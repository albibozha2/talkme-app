import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';
import '../i18n.dart';

/// People who asked to follow your private account.
class FollowRequestsScreen extends ConsumerStatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  ConsumerState<FollowRequestsScreen> createState() =>
      _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends ConsumerState<FollowRequestsScreen> {
  List<AppUser>? _items;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiProvider).followRequests();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _answer(AppUser u, bool approve) async {
    setState(() => _busy.add(u.username));
    try {
      await ref.read(apiProvider).answerFollowRequest(u.username, approve);
      if (mounted) {
        setState(() => _items!.removeWhere((x) => x.id == u.id));
        showToast(
          context,
          approve
              ? tr('{0} now follows you', [u.displayName])
              : tr('Request removed'),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(u.username));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Follow requests'))),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? _EmptyPeople(
              icon: Icons.how_to_reg_rounded,
              text: tr('No pending requests.'),
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final u = items[i];
                final busy = _busy.contains(u.username);
                return ListTile(
                  leading: Avatar(
                    url: u.avatarUrl,
                    name: u.displayName,
                    radius: 24,
                  ),
                  title: Text(
                    u.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('@${u.username}'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(username: u.username),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 36,
                        width: 84,
                        child: GradientButton(
                          label: tr('Accept'),
                          busy: busy,
                          onPressed: () => _answer(u, true),
                        ),
                      ),
                      IconButton(
                        onPressed: busy ? null : () => _answer(u, false),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: tr('Decline'),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Accounts you blocked, with Unblock.
class BlockedAccountsScreen extends ConsumerStatefulWidget {
  const BlockedAccountsScreen({super.key});

  @override
  ConsumerState<BlockedAccountsScreen> createState() =>
      _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends ConsumerState<BlockedAccountsScreen> {
  List<AppUser>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiProvider).blockedUsers();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _unblock(AppUser u) async {
    try {
      await ref.read(apiProvider).setBlocked(u.username, false);
      if (mounted) {
        setState(() => _items!.removeWhere((x) => x.id == u.id));
        showToast(context, tr('{0} is unblocked', [u.displayName]));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Blocked accounts'))),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? _EmptyPeople(
              icon: Icons.block_rounded,
              text: tr("You haven't blocked anyone."),
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final u = items[i];
                return ListTile(
                  leading: Avatar(
                    url: u.avatarUrl,
                    name: u.displayName,
                    radius: 24,
                  ),
                  title: Text(
                    u.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('@${u.username}'),
                  trailing: OutlinedButton(
                    onPressed: () => _unblock(u),
                    child: Text(tr('Unblock')),
                  ),
                );
              },
            ),
    );
  }
}

class _EmptyPeople extends StatelessWidget {
  const _EmptyPeople({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: AppColors.emerald.withValues(alpha: .12),
            child: Icon(icon, size: 36, color: AppColors.emerald),
          ),
          const SizedBox(height: 14),
          Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
