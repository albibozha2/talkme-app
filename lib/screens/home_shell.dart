import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/video_pager.dart';
import '../push.dart';
import '../live_pulse.dart';
import '../screen_time.dart';
import '../diagnostics.dart';
import 'safety_screens.dart';
import 'chat_screen.dart';
import '../updater.dart';
import 'discover_screen.dart';
import 'inbox_screen.dart';
import 'live_room_screen.dart';
import 'live_screen.dart';
import 'profile_screen.dart';
import 'upload_screen.dart';
import '../i18n.dart';
import 'stories_screen.dart';
import 'rewards_screen.dart';
import '../playback.dart';
import 'people_screens.dart';
import '../models.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0; // 0 home, 1 discover, 2 live, 3 profile
  bool _routeCovered = false;
  final _feedKey = GlobalKey<_FeedScreenState>();
  LivePulse? _pulse;

  @override
  void dispose() {
    _pulse?.stop();
    ScreenTime.instance
      ..stop()
      ..onLimit = null
      ..onBreak = null;
    super.dispose();
  }

  /// Tells people once that error reports are on, and lets them turn it off right away.
  Future<void> _diagnosticsNotice() async {
    if (!await diagnosticsNoticeDue()) return;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    await diagnosticsNoticeShown();
    if (!mounted) return;
    final off = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.bug_report_outlined),
        title: Text(tr('Help us fix problems')),
        content: Text(
          tr(
            'When something goes wrong, TalkMe sends an error report with your phone model, app version and battery level. You can turn this off anytime in Privacy & safety.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Turn off')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('OK')),
          ),
        ],
      ),
    );
    if (off == true) await Diagnostics.setEnabled(false);
  }

  void _limitReached() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.hourglass_bottom_rounded),
        title: Text(tr('Daily limit reached')),
        content: Text(
          tr('You’ve used TalkMe for {0} today. Your daily limit is {1}.', [
            formatMinutes(ScreenTime.instance.today),
            formatMinutes(Duration(minutes: ScreenTime.instance.limitMinutes)),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _push(const ScreenTimeScreen());
            },
            child: Text(tr('Change limit')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('OK')),
          ),
        ],
      ),
    );
  }

  void _breakTime(int minutes) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.self_improvement_rounded),
        title: Text(tr('Time for a break?')),
        content: Text(
          tr(
            'You’ve been scrolling for {0}. Stretch, drink some water, look away from the screen.',
            [formatMinutes(Duration(minutes: minutes))],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('OK')),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Tapping a push opens the matching screen.
    PushService.instance.onOpen = (data) async {
      if (!mounted) return;
      final liveId = int.tryParse('${data['live_id'] ?? ''}');
      final chatId = int.tryParse('${data['conversation_id'] ?? ''}');
      final videoId = int.tryParse('${data['video_id'] ?? ''}');
      final username = data['username']?.toString();
      final type = data['type']?.toString();
      if (data['type'] == 'message' && chatId != null) {
        try {
          final c = await ref.read(apiProvider).conversationDetails(chatId);
          if (mounted) _push(ChatScreen(conversation: c));
          return;
        } catch (_) {}
        if (!mounted) return;
      }
      if (type == 'follow_request') {
        _push(const FollowRequestsScreen());
        return;
      }
      if (type == 'follow' && username != null && username.isNotEmpty) {
        _push(ProfileScreen(username: username));
        return;
      }
      // Likes, comments, mentions, reposts, gifts on a video: open that video.
      if (videoId != null && type != 'live') {
        try {
          final v = await ref.read(apiProvider).video(videoId);
          if (!mounted) return;
          setState(() => _routeCovered = true);
          await openVideoPager(
            context,
            items: [v],
            index: 0,
            loader: (_) async => PageResult<Video>([], null),
          );
          if (mounted) setState(() => _routeCovered = false);
          return;
        } catch (_) {}
        if (!mounted) return;
      }
      _push(
        data['type'] == 'live' && liveId != null
            ? LiveRoomScreen.viewer(liveId: liveId)
            : InboxScreen(messagesFirst: data['type'] == 'message'),
      );
    };
    PushService.instance.start(
      ProviderScope.containerOf(context, listen: false),
    );
    ScreenTime.instance
      ..onLimit = _limitReached
      ..onBreak = _breakTime
      ..start();
    if (kIsWeb) {
      _pulse = LivePulse(
        ProviderScope.containerOf(context, listen: false),
        (data) => PushService.instance.onOpen?.call(data),
      )..start();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        offerUpdateOnce(context, ref);
        offerDailyReward(context, ref);
        _diagnosticsNotice();
      }
    });
  }

  Future<void> _push(Widget page) async {
    setState(() => _routeCovered = true);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() => _routeCovered = false);
  }

  Future<void> _create() async {
    HapticFeedback.lightImpact();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Create'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _CreateOption(
                      icon: Icons.movie_creation_rounded,
                      title: tr('Post a video'),
                      subtitle: tr('Record or upload'),
                      gradient: AppColors.brandGradient,
                      onTap: () => Navigator.pop(context, 'video'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CreateOption(
                      icon: Icons.podcasts_rounded,
                      title: tr('Go Live'),
                      subtitle: tr('Stream & get gifts'),
                      gradient: AppColors.liveGradient,
                      onTap: () => Navigator.pop(context, 'live'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _CreateOption(
                icon: Icons.amp_stories_rounded,
                title: tr('Story'),
                subtitle: tr('Photo or video for 24 hours'),
                gradient: AppColors.goldGradient,
                onTap: () => Navigator.pop(context, 'story'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == 'video') await _push(const UploadScreen());
    if (choice == 'live') await _push(const GoLiveScreen());
    if (choice == 'story' && mounted) await createStory(context, ref);
  }

  final _opened = <int>{0};

  void _select(int i) {
    if (i == 0 && _tab == 0) _feedKey.currentState?.refresh();
    if (i == 2 && _tab != 2 && _opened.contains(2)) {
      ref.read(activityProvider.notifier).bump(); // fresh inbox each visit
    }
    HapticFeedback.selectionClick();
    setState(() {
      _tab = i;
      _opened.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final onFeed = _tab == 0;
    final scaffold = Scaffold(
      extendBody: onFeed,
      body: IndexedStack(
        index: _tab,
        children: [
          FeedScreen(key: _feedKey, active: onFeed && !_routeCovered),
          const DiscoverScreen(),
          _opened.contains(2) ? const InboxScreen() : const SizedBox(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        dark: onFeed,
        index: _tab,
        inboxCount: ref.watch(unreadProvider),
        onSelect: _select,
        onCreate: _create,
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: onFeed ? darkSystemUi : systemUiFor(Theme.of(context)),
      child: scaffold,
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.dark,
    required this.index,
    required this.inboxCount,
    required this.onSelect,
    required this.onCreate,
  });
  final bool dark;
  final int index;
  final int inboxCount;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = dark ? Colors.black : scheme.surface;
    final idle = dark ? Colors.white70 : scheme.onSurfaceVariant;
    final active = dark ? Colors.white : scheme.onSurface;
    Widget item(
      int i,
      IconData icon,
      IconData selectedIcon,
      String label, {
      int badge = 0,
    }) {
      final on = index == i;
      return Expanded(
        child: InkResponse(
          onTap: () => onSelect(i),
          radius: 36,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: on ? 1.1 : 1,
                duration: const Duration(milliseconds: 180),
                child: Badge(
                  isLabelVisible: badge > 0,
                  label: Text(badge > 99 ? '99+' : '$badge'),
                  backgroundColor: AppColors.like,
                  child: Icon(
                    on ? selectedIcon : icon,
                    color: on ? active : idle,
                    size: 27,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: on ? active : idle,
                  fontSize: 11,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(
            color: dark
                ? Colors.white10
                : scheme.outlineVariant.withValues(alpha: .4),
            width: .5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              item(0, Icons.home_outlined, Icons.home_rounded, tr('Home')),
              item(
                1,
                Icons.explore_outlined,
                Icons.explore_rounded,
                tr('Discover'),
              ),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: onCreate,
                    child: SizedBox(
                      width: 50,
                      height: 32,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: 40,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.emeraldLight,
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            width: 40,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.amber,
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 5,
                            right: 5,
                            top: 0,
                            bottom: 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: dark ? Colors.white : Colors.black,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                color: dark ? Colors.black : Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              item(
                2,
                Icons.inbox_outlined,
                Icons.inbox_rounded,
                tr('Inbox'),
                badge: inboxCount,
              ),
              item(
                3,
                Icons.person_outline_rounded,
                Icons.person_rounded,
                tr('Profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateOption extends StatelessWidget {
  const _CreateOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: gradient,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: Colors.white24,
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(height: 22),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key, required this.active});
  final bool active;

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this, initialIndex: 2)
    ..addListener(() => setState(() {}));
  final _forYou = GlobalKey<VideoPagerState>();
  final _following = GlobalKey<VideoPagerState>();
  final _friends = GlobalKey<VideoPagerState>();
  bool _covered = false;

  void refresh() =>
      [_friends, _following, _forYou][_tabs.index].currentState?.refresh();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(apiProvider);
    return Stack(
      children: [
        TabBarView(
          controller: _tabs,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            VideoPager(
              key: _friends,
              loader: api.friendsFeed,
              active: widget.active && !_covered && _tabs.index == 0,
              empty: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr(
                    'Friends are people you follow who follow you back. Their videos show up here.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
            VideoPager(
              key: _following,
              loader: api.followingFeed,
              active: widget.active && !_covered && _tabs.index == 1,
              empty: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.people_alt_rounded,
                      color: Colors.white54,
                      size: 48,
                    ),
                    SizedBox(height: 12),
                    Text(
                      tr('Follow creators to see their videos here.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            VideoPager(
              key: _forYou,
              loader: api.feed,
              active: widget.active && !_covered && _tabs.index == 2,
            ),
          ],
        ),
        if (!ref.watch(playbackProvider).clear)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    _LiveButton(
                      onTap: () async {
                        setState(() => _covered = true);
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LiveScreen(active: true),
                          ),
                        );
                        if (mounted) setState(() => _covered = false);
                      },
                    ),
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          width: 300,
                          child: TabBar(
                            controller: _tabs,
                            dividerColor: Colors.transparent,
                            indicatorSize: TabBarIndicatorSize.label,
                            indicator: const UnderlineTabIndicator(
                              borderSide: BorderSide(
                                color: Colors.white,
                                width: 3,
                              ),
                              insets: EdgeInsets.symmetric(horizontal: 12),
                              borderRadius: BorderRadius.all(
                                Radius.circular(2),
                              ),
                            ),
                            labelColor: Colors.white,
                            unselectedLabelColor: Colors.white60,
                            labelStyle: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              shadows: [Shadow(blurRadius: 8)],
                            ),
                            unselectedLabelStyle: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                              shadows: [Shadow(blurRadius: 8)],
                            ),
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            tabs: [
                              Tab(text: tr('Friends')),
                              Tab(text: tr('Following')),
                              Tab(text: tr('For You')),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        setState(() => _covered = true);
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const DiscoverScreen(autofocus: true),
                          ),
                        );
                        if (mounted) setState(() => _covered = false);
                      },
                      icon: const Icon(
                        Icons.search_rounded,
                        color: Colors.white,
                        size: 28,
                        shadows: [Shadow(blurRadius: 8)],
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// TikTok-style LIVE entry at the top-left of the feed.
class _LiveButton extends StatelessWidget {
  const _LiveButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tr('Live'),
    child: InkResponse(
      onTap: onTap,
      radius: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.live_tv_rounded,
              color: Colors.white,
              size: 30,
              shadows: [Shadow(blurRadius: 8)],
            ),
            Positioned(
              bottom: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.live,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
