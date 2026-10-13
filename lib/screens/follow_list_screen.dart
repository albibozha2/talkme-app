import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';

/// Someone's followers or the people they follow (tap the numbers on a profile).
class FollowListScreen extends ConsumerStatefulWidget {
  const FollowListScreen({
    super.key,
    required this.username,
    required this.followers,
  });
  final String username;
  final bool followers;

  @override
  ConsumerState<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends ConsumerState<FollowListScreen> {
  final _items = <AppUser>[];
  final _following = <int, bool>{};
  String? _cursor;
  bool _done = false, _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(apiProvider)
          .followList(
            widget.username,
            widget.followers ? 'followers' : 'following',
            _cursor,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        for (final u in page.items) {
          _following[u.id] = u.isFollowing ?? false;
        }
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(AppUser u) async {
    final on = !(_following[u.id] ?? false);
    setState(() => _following[u.id] = on);
    try {
      final r = await ref.read(apiProvider).setFollow(u.username, on);
      if (!mounted) return;
      setState(() => _following[u.id] = r.isFollowing ?? on);
      if (r.requested) showToast(context, tr('Follow request sent'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _following[u.id] = !on);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(sessionProvider).value?.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.followers ? tr('Followers') : tr('Following')),
      ),
      body: _items.isEmpty
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Text(_error?.toString() ?? tr('Nobody here yet.')),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 400) _load();
                return false;
              },
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final u = _items[i];
                  return ListTile(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(username: u.username),
                      ),
                    ),
                    leading: Avatar(url: u.avatarUrl, name: u.displayName),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            u.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (u.verified) const VerifiedBadge(size: 13),
                      ],
                    ),
                    subtitle: Text('@${u.username}'),
                    trailing: me == u.id
                        ? null
                        : FollowPill(
                            following: _following[u.id] ?? false,
                            onTap: () => _toggle(u),
                          ),
                  );
                },
              ),
            ),
    );
  }
}
