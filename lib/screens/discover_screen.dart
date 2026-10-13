import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/banner_carousel.dart';
import '../widgets/common.dart';
import '../widgets/video_grid.dart';
import 'live_room_screen.dart';
import 'profile_screen.dart';
import '../i18n.dart';
import 'stories_screen.dart';
import '../playback.dart';
import '../features.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key, this.autofocus = false});
  final bool autofocus;

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _term = '';
  bool _loading = false;
  List<AppUser> _users = [];
  List<Video> _videos = [];
  List<LiveInfo> _liveResults = [];
  List<String> _recent = [];
  bool _focused = false;
  final _focus = FocusNode();
  List<({String name, int count})> _tags = [];
  List<AppUser> _suggested = [];
  List<LiveInfo> _lives = [];
  List<BannerItem> _banners = [];
  final _following = <String>{};

  @override
  void initState() {
    super.initState();
    _loadHome();
    SearchHistory.load().then((r) {
      if (mounted) setState(() => _recent = r);
    });
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadHome() async {
    final api = ref.read(apiProvider);
    try {
      final results = await Future.wait([
        api.search(''),
        api.suggestedUsers(),
        api.lives().then((l) => l.items).catchError((Object _) => <LiveInfo>[]),
        api.banners().catchError((Object _) => <BannerItem>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _tags =
            (results[0]
                    as ({
                      List<AppUser> users,
                      List<({String name, int count})> hashtags,
                    }))
                .hashtags;
        _suggested = results[1] as List<AppUser>;
        _lives = results[2] as List<LiveInfo>;
        _banners = results[3] as List<BannerItem>;
      });
    } catch (_) {}
  }

  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(value.trim()),
    );
  }

  Future<void> _search(String term) async {
    setState(() {
      _term = term;
      _loading = term.isNotEmpty;
    });
    if (term.isEmpty) return;
    try {
      final r = await ref.read(apiProvider).searchAll(term);
      if (!mounted || term != _term) return;
      setState(() {
        _users = r.users;
        _tags = r.hashtags;
        _videos = r.videos;
        _liveResults = r.lives;
      });
      if (term.length >= 2) {
        final recent = await SearchHistory.add(term);
        if (mounted) setState(() => _recent = recent);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted && term == _term) setState(() => _loading = false);
    }
  }

  Future<void> _follow(AppUser u) async {
    final on = !_following.contains(u.username);
    setState(
      () => on ? _following.add(u.username) : _following.remove(u.username),
    );
    try {
      final updated = await ref.read(apiProvider).setFollow(u.username, on);
      if (mounted && updated.requested) {
        showToast(context, tr('Follow request sent'));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => on ? _following.remove(u.username) : _following.add(u.username),
        );
        showError(context, e);
      }
    }
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final searching = _term.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadHome,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      if (Navigator.of(context).canPop())
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      Expanded(
                        child: TextField(
                          controller: _query,
                          focusNode: _focus,
                          autofocus: widget.autofocus,
                          onChanged: _onChanged,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: tr(
                              'Search people, videos, lives and #hashtags',
                            ),
                            prefixIcon: const Icon(Icons.search_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide(color: scheme.primary),
                            ),
                            suffixIcon: _query.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () {
                                      _query.clear();
                                      _search('');
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (!searching && _focused && _recent.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: SectionHeader(tr('Recent searches'))),
                          TextButton(
                            onPressed: () async {
                              await SearchHistory.clear();
                              setState(() => _recent = []);
                            },
                            child: Text(tr('Clear')),
                          ),
                        ],
                      ),
                      for (final t in _recent)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.history_rounded),
                          title: Text(t),
                          trailing: IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () async {
                              final r = await SearchHistory.remove(t);
                              if (mounted) setState(() => _recent = r);
                            },
                          ),
                          onTap: () {
                            _query.text = t;
                            _search(t);
                          },
                        ),
                    ],
                  ),
                ),
              if (!searching && Features.on('stories'))
                const SliverToBoxAdapter(child: StoryBar()),
              if (searching) ..._results(scheme) else ..._home(scheme),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _results(ColorScheme scheme) => [
    if (_users.isNotEmpty)
      SliverToBoxAdapter(child: SectionHeader(tr('Accounts'))),
    SliverList.builder(
      itemCount: _users.length,
      itemBuilder: (context, i) {
        final u = _users[i];
        return ListTile(
          leading: Avatar(url: u.avatarUrl, name: u.displayName, radius: 24),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  u.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (u.verified) const VerifiedBadge(),
            ],
          ),
          subtitle: Text('@${u.username} · ${plural(u.followers, 'follower')}'),
          onTap: () => _open(ProfileScreen(username: u.username)),
        );
      },
    ),
    if (_tags.isNotEmpty)
      SliverToBoxAdapter(child: SectionHeader(tr('Hashtags'))),
    SliverList.builder(
      itemCount: _tags.length,
      itemBuilder: (context, i) => _TagTile(
        tag: _tags[i],
        onTap: () => _open(HashtagScreen(tag: _tags[i].name)),
      ),
    ),
    if (_liveResults.isNotEmpty)
      SliverToBoxAdapter(child: SectionHeader(tr('Live now'))),
    SliverList.builder(
      itemCount: _liveResults.length,
      itemBuilder: (context, i) {
        final l = _liveResults[i];
        return ListTile(
          leading: Avatar(
            url: l.host.avatarUrl,
            name: l.host.displayName,
            radius: 22,
            live: true,
          ),
          title: Text(l.title.isEmpty ? l.host.displayName : l.title),
          subtitle: Text(
            '@${l.host.username} · ${tr('{0} watching', [l.viewers])}',
          ),
          onTap: () => _open(LiveRoomScreen.viewer(liveId: l.id)),
        );
      },
    ),
    if (_videos.isNotEmpty)
      SliverToBoxAdapter(child: SectionHeader(tr('Videos'))),
    if (_videos.isNotEmpty)
      VideoGrid(
        key: ValueKey('search-$_term-${_videos.length}'),
        loader: (_) async => PageResult(_videos, null),
      ),
    if (!_loading &&
        _users.isEmpty &&
        _tags.isEmpty &&
        _videos.isEmpty &&
        _liveResults.isEmpty)
      SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            tr('No results for "{0}"', [_term]),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      ),
  ];

  List<Widget> _home(ColorScheme scheme) => [
    if (_banners.isNotEmpty)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: BannerCarousel(
            key: ValueKey(_banners.map((b) => b.id).join(',')),
            items: _banners,
          ),
        ),
      ),
    if (_lives.isNotEmpty) ...[
      SliverToBoxAdapter(child: SectionHeader(tr('Live now'))),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _lives.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final l = _lives[i];
              return GestureDetector(
                onTap: () => _open(LiveRoomScreen.viewer(liveId: l.id)),
                child: SizedBox(
                  width: 72,
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomCenter,
                        children: [
                          Avatar(
                            url: l.host.avatarUrl,
                            name: l.host.displayName,
                            radius: 30,
                            live: true,
                          ),
                          const Positioned(
                            bottom: -6,
                            child: LiveBadge(small: true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l.host.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ],
    if (_suggested.isNotEmpty) ...[
      SliverToBoxAdapter(child: SectionHeader(tr('Suggested accounts'))),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _suggested.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final u = _suggested[i];
              return Container(
                width: 140,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: .3),
                  ),
                ),
                child: InkWell(
                  onTap: () => _open(ProfileScreen(username: u.username)),
                  child: Column(
                    children: [
                      Avatar(
                        url: u.avatarUrl,
                        name: u.displayName,
                        radius: 32,
                        ring: true,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              u.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          if (u.verified) const VerifiedBadge(size: 13),
                        ],
                      ),
                      Text(
                        plural(u.followers, 'follower'),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                      const Spacer(),
                      FollowPill(
                        following: _following.contains(u.username),
                        onTap: () => _follow(u),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ],
    if (_tags.isNotEmpty) ...[
      SliverToBoxAdapter(child: SectionHeader(tr('Popular hashtags'))),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _tags.take(12))
                ActionChip(
                  avatar: Text(
                    '#',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  label: Text('${t.name}  ·  ${compactCount(t.count)}'),
                  onPressed: () => _open(HashtagScreen(tag: t.name)),
                ),
            ],
          ),
        ),
      ),
    ],
    SliverToBoxAdapter(child: SectionHeader(tr('Trending videos'))),
    VideoGrid(loader: ref.read(apiProvider).feed),
    const SliverToBoxAdapter(child: SizedBox(height: 24)),
  ];
}

class _TagTile extends StatelessWidget {
  const _TagTile({required this.tag, required this.onTap});
  final ({String name, int count}) tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: scheme.primary.withValues(alpha: .12),
        child: Text(
          '#',
          style: TextStyle(
            color: scheme.primary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      title: Text(
        '#${tag.name}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(plural(tag.count, 'post')),
      onTap: onTap,
    );
  }
}

class HashtagScreen extends ConsumerWidget {
  const HashtagScreen({super.key, required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 150,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                '#$tag',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary.withValues(alpha: .25),
                      scheme.surface,
                    ],
                  ),
                ),
              ),
            ),
          ),
          VideoGrid(
            loader: (cursor) =>
                ref.read(apiProvider).hashtagVideos(tag, cursor),
          ),
        ],
      ),
    );
  }
}
