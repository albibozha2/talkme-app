import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../push.dart';
import '../web/web_notify.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/video_pager.dart';
import 'chat_screen.dart';
import 'discover_screen.dart';
import 'live_room_screen.dart';
import 'people_screens.dart';
import 'profile_screen.dart';
import '../i18n.dart';
import 'group_screens.dart';

/// Inbox: direct messages and activity notifications.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key, this.messagesFirst});

  /// Which tab to open on; by default whichever has something new.
  final bool? messagesFirst;

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex:
        (widget.messagesFirst ??
            (ref.read(unreadProvider.notifier).messages > 0 &&
                ref.read(unreadProvider.notifier).notifications == 0))
        ? 0
        : 1,
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(unreadProvider);
    // TikTok layout: activity rows on top, then the conversations.
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(tr('Inbox')),
        actions: [
          IconButton(
            tooltip: tr('New group'),
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () async {
              await startGroupChat(context, ref);
              ref.read(activityProvider.notifier).bump();
            },
          ),
        ],
      ),
      body: const _MessagesTab(activity: true),
    );
  }
}

// ---------------- Messages ----------------

class _MessagesTab extends ConsumerStatefulWidget {
  const _MessagesTab({this.requests = false, this.activity = false});

  /// Show message requests instead of the inbox.
  final bool requests;

  /// Show the activity rows (new followers, activity, system) on top.
  final bool activity;

  @override
  ConsumerState<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends ConsumerState<_MessagesTab> {
  List<Conversation>? _items;
  Object? _error;
  int _requests = 0;
  Map<String, int> _groupCounts = const {};
  Map<String, String?> _groupLatest = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiProvider);
      final items = await api.conversations(requests: widget.requests);
      final requests = widget.requests
          ? 0
          : await api.messageRequests().catchError((Object _) => 0);
      if (widget.activity) {
        try {
          final g = await api.notificationGroups();
          _groupCounts = g.counts;
          _groupLatest = g.latest;
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _items = items;
          _requests = requests;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _open(Conversation c) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)));
    _load();
    ref.read(unreadProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activityProvider, (_, _) => _load());
    final items = _items;
    final scheme = Theme.of(context).colorScheme;
    if (items == null) {
      return Center(
        child: _error != null
            ? Text('$_error')
            : const CircularProgressIndicator(),
      );
    }
    final header = widget.requests
        ? <Widget>[]
        : <Widget>[
            if (widget.activity) ...[
              for (final (group, title, icon, color, empty) in [
                (
                  'followers',
                  tr('New followers'),
                  Icons.people_alt_rounded,
                  const Color(0xFF3B82F6),
                  tr('See who followed you'),
                ),
                (
                  'activity',
                  tr('Activity'),
                  Icons.notifications_rounded,
                  AppColors.like,
                  tr('Likes, comments, mentions and gifts'),
                ),
                (
                  'system',
                  tr('System notifications'),
                  Icons.campaign_rounded,
                  const Color(0xFF8B5CF6),
                  tr('Lives, battles and news from TalkMe'),
                ),
              ])
                ListTile(
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: color,
                    child: Icon(icon, color: Colors.white),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    (_groupLatest[group] ?? '').isNotEmpty
                        ? trServer(_groupLatest[group]!)
                        : empty,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: (_groupCounts[group] ?? 0) > 0
                      ? Badge(
                          label: Text('${_groupCounts[group]}'),
                          backgroundColor: AppColors.like,
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: Text(title)),
                          body: _NotificationsTab(group: group),
                        ),
                      ),
                    );
                    _load();
                  },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Text(
                  tr('Messages'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
            if (!widget.activity)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.group_add_rounded),
                        label: Text(tr('New group')),
                        onPressed: () async {
                          await startGroupChat(context, ref);
                          _load();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            if (_requests > 0)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.amber.withValues(alpha: .2),
                  child: const Icon(
                    Icons.mark_email_unread_rounded,
                    color: AppColors.amber,
                  ),
                ),
                title: Text(
                  tr('Message requests'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  tr('{0} people want to message you', [_requests]),
                ),
                trailing: Badge(
                  label: Text('$_requests'),
                  backgroundColor: AppColors.amber,
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(tr('Message requests'))),
                        body: const _MessagesTab(requests: true),
                      ),
                    ),
                  );
                  _load();
                  ref.read(unreadProvider.notifier).refresh();
                },
              ),
          ];
    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty && header.isEmpty
          ? ListView(
              children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * .25),
                Center(child: Text(tr('No message requests.'))),
              ],
            )
          : items.isEmpty
          ? ListView(
              children: [
                ...header,
                SizedBox(height: MediaQuery.sizeOf(context).height * .12),
                _Empty(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: tr('No messages yet'),
                  body: tr(
                    'Open someone\'s profile and tap Message to start a chat.',
                  ),
                  action: (
                    tr('Find people'),
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DiscoverScreen(autofocus: true),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              itemCount: items.length + header.length,
              itemBuilder: (context, index) {
                if (index < header.length) return header[index];
                final c = items[index - header.length];
                final bold = c.unread > 0;
                return ListTile(
                  onTap: () => _open(c),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: ChatAvatar(conversation: c),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: bold
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!c.isGroup && c.user.verified)
                        const VerifiedBadge(size: 13),
                    ],
                  ),
                  subtitle: Text(
                    '${c.lastMine ? tr('You: ') : ''}${trServer(c.lastBody ?? '')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bold ? scheme.onSurface : scheme.onSurfaceVariant,
                      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (c.lastAt != null)
                        Text(
                          timeAgo(c.lastAt!),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.outline,
                          ),
                        ),
                      if (bold) ...[
                        const SizedBox(height: 4),
                        Badge(
                          label: Text('${c.unread}'),
                          backgroundColor: AppColors.emerald,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ---------------- Notifications ----------------

class _NotificationsTab extends ConsumerStatefulWidget {
  const _NotificationsTab({this.group});

  /// followers, activity or system (null = all).
  final String? group;

  @override
  ConsumerState<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends ConsumerState<_NotificationsTab> {
  final _items = <AppNotification>[];
  final _scroll = ScrollController();
  String? _cursor;
  bool _loading = false, _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _load();
    });
    ref.listenManual(activityProvider, (_, _) => _load(reset: true));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (_done && !reset)) return;
    setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      final page = await api.notifications(
        reset ? null : _cursor,
        group: widget.group,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
        _error = null;
      });
      if (reset && page.items.any((n) => !n.read)) {
        await api.markAllRead(group: widget.group);
        ref.read(unreadProvider.notifier).refresh();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(AppNotification n) async {
    final nav = Navigator.of(context);
    if (n.type == 'follow_request') {
      await nav.push(
        MaterialPageRoute(builder: (_) => const FollowRequestsScreen()),
      );
    } else if (n.liveId != null && n.type == 'live') {
      await nav.push(
        MaterialPageRoute(
          builder: (_) => LiveRoomScreen.viewer(liveId: n.liveId!),
        ),
      );
    } else if (n.videoId != null) {
      try {
        final v = await ref.read(apiProvider).video(n.videoId!);
        if (!mounted) return;
        await openVideoPager(
          context,
          items: [v],
          index: 0,
          loader: (_) async => PageResult([v], null),
        );
      } catch (e) {
        if (mounted) showError(context, e);
      }
    } else if (n.actor != null) {
      await nav.push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(username: n.actor!.username),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (canAskPopUp)
        ListTile(
          leading: const Icon(Icons.notifications_active_rounded),
          title: Text(tr('Turn on notifications')),
          subtitle: Text(
            tr(
              'Get notified about messages, follows and lives, even when TalkMe is closed.',
            ),
          ),
          trailing: FilledButton(
            onPressed: () async {
              if (await askPopUpPermission()) {
                await PushService.instance.startWeb();
              }
              if (mounted) setState(() {});
            },
            child: Text(tr('Turn on')),
          ),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: _items.isEmpty
              ? ListView(
                  children: [
                    SizedBox(height: MediaQuery.sizeOf(context).height * .18),
                    _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _Empty(
                            icon: Icons.notifications_none_rounded,
                            title: _error != null
                                ? '$_error'
                                : tr('No notifications yet'),
                            body: tr(
                              'Likes, comments, follows and gifts show up here.',
                            ),
                          ),
                  ],
                )
              : ListView.separated(
                  controller: _scroll,
                  itemCount: _items.length + (_done ? 0 : 1),
                  separatorBuilder: (_, _) => const Divider(indent: 76),
                  itemBuilder: (context, i) {
                    if (i == _items.length) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return _Tile(n: _items[i], onTap: () => _open(_items[i]));
                  },
                ),
        ),
      ),
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title, body;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: scheme.primary.withValues(alpha: .12),
            child: Icon(icon, size: 40, color: scheme.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: 200,
              child: GradientButton(label: action!.$1, onPressed: action!.$2),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  static const _badge = {
    'like': (Icons.favorite_rounded, AppColors.like),
    'comment': (Icons.mode_comment_rounded, Color(0xFF3B82F6)),
    'follow': (Icons.person_add_alt_1_rounded, AppColors.emerald),
    'gift': (Icons.card_giftcard_rounded, AppColors.amber),
    'live': (Icons.podcasts_rounded, AppColors.live),
    'follow_request': (Icons.how_to_reg_rounded, Color(0xFF3B82F6)),
    'battle': (Icons.bolt_rounded, AppColors.amberDeep),
    'system': (Icons.campaign_rounded, Color(0xFF8B5CF6)),
    'mention': (Icons.alternate_email_rounded, Color(0xFF3B82F6)),
    'repost': (Icons.repeat_rounded, AppColors.emerald),
    'subscribe': (Icons.workspace_premium_rounded, AppColors.amber),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = _badge[n.type] ?? _badge['system']!;
    final px = (52 * MediaQuery.devicePixelRatioOf(context)).round();
    return Material(
      color: n.read
          ? Colors.transparent
          : scheme.primary.withValues(alpha: .06),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  n.actor != null
                      ? Avatar(
                          url: n.actor!.avatarUrl,
                          name: n.actor!.displayName,
                          radius: 24,
                        )
                      : const BrandMark(size: 48),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.surface, width: 2),
                      ),
                      child: Icon(icon, size: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: TextStyle(
                        fontWeight: n.read ? FontWeight.w500 : FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (n.body.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          n.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text(
                      timeAgo(n.createdAt),
                      style: TextStyle(color: scheme.outline, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (n.thumbUrl != null) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: n.thumbUrl!,
                    width: 40,
                    height: 52,
                    fit: BoxFit.cover,
                    memCacheWidth: px,
                  ),
                ),
              ] else if (n.type == 'follow' && n.actor != null)
                const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
