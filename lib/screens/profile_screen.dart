import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/video_grid.dart';
import '../config.dart';
import '../updater.dart';
import 'chat_screen.dart';
import 'edit_profile_screen.dart';
import 'people_screens.dart';
import 'live_room_screen.dart';
import 'wallet_screen.dart';
import '../i18n.dart';
import '../vip.dart';
import '../widgets/language_picker.dart';

import 'package:url_launcher/url_launcher.dart';

import 'follow_list_screen.dart';
import 'stories_screen.dart';
import '../widgets/invite_sheet.dart';
import 'rewards_screen.dart';
import 'leaderboard_screen.dart';
import 'live_extras.dart';
import 'history_screen.dart';
import '../thumbs.dart';
import '../video_cache.dart';
import 'creator_screens.dart';
import 'safety_screens.dart';

/// Any user's profile. Pass [username] = null for the signed-in user's own tab.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.username});
  final String? username;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  AppUser? _user;

  /// Selected favourites folder on the Saved tab (null = all).
  int? _folder;
  Object? _error;
  bool _busy = false;
  int _tab = 0; // 0 videos, 1 saved

  String? get _username =>
      widget.username ?? ref.read(sessionProvider).value?.username;
  bool get _isMe =>
      _user != null && _user!.id == ref.read(sessionProvider).value?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = _username;
    if (name == null) return;
    try {
      final api = ref.read(apiProvider);
      final u = await api.user(name);
      if (mounted) setState(() => _user = u);
      // Keep the session copy (coins etc.) fresh on the own-profile tab.
      if (widget.username == null) {
        final me = await api.me();
        ref.read(sessionProvider.notifier).setUser(me);
        _fillThumbnails(me.username);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Once per app run: makes cover pictures for my videos that have none (the server
  /// can't), from the video file, and uploads them. Up to 20 at a time, in the background.
  static bool _thumbsChecked = false;

  Future<void> _fillThumbnails(String username) async {
    if (_thumbsChecked) return;
    _thumbsChecked = true;
    var done = 0;
    try {
      final api = ref.read(apiProvider);
      String? cursor;
      for (var page = 0; page < 3 && done < 20; page++) {
        final r = await api.userVideos(username, cursor);
        for (final v in r.items) {
          if (done >= 20) break;
          if (v.thumbUrl != null || v.hlsUrl != null) continue;
          // Phones read the downloaded file; the browser reads the video from the site.
          final file = kIsWeb
              ? null
              : await VideoCache.instance.download(v.videoUrl);
          final thumb = kIsWeb
              ? await makeThumbnail(v.videoUrl)
              : file == null
              ? null
              : await makeThumbnail(file.path);
          if (thumb == null) continue;
          if (await api
                  .setVideoThumb(v.id, thumb)
                  .catchError((Object _) => null) !=
              null) {
            done++;
          }
        }
        cursor = r.nextCursor;
        if (cursor == null) break;
      }
    } catch (_) {}
    if (done > 0 && mounted) {
      ref.read(myVideosVersionProvider.notifier).bump();
    }
  }

  Future<void> _toggleFollow() async {
    final u = _user!;
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(apiProvider)
          .setFollow(u.username, !((u.isFollowing ?? false) || u.requested));
      if (mounted) {
        setState(() => _user = updated);
        if (updated.requested) showToast(context, tr('Follow request sent'));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _load();
  }

  Future<void> _menu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.qr_code_2_rounded),
                title: Text(
                  _isMe ? tr('QR code & invite friends') : tr('Share profile'),
                ),
                onTap: () => Navigator.pop(context, 'qr'),
              ),
              if (_isMe) ...[
                if (!kIsWeb)
                  ListTile(
                    leading: const Icon(Icons.system_update_rounded),
                    title: Text(tr('Check for updates')),
                    subtitle: Text(tr('Version {0}', [AppConfig.appVersion])),
                    onTap: () => Navigator.pop(context, 'update'),
                  ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(tr('Edit profile')),
                  onTap: () => Navigator.pop(context, 'edit'),
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(tr('Wallet')),
                  onTap: () => Navigator.pop(context, 'wallet'),
                ),
                ListTile(
                  leading: const Icon(Icons.insights_rounded),
                  title: Text(tr('Creator tools')),
                  onTap: () => Navigator.pop(context, 'creator'),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(tr('Privacy & safety')),
                  onTap: () => Navigator.pop(context, 'safety'),
                ),
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: Text(tr('Watch history')),
                  onTap: () => Navigator.pop(context, 'history'),
                ),
                ListTile(
                  leading: const Icon(Icons.person_off_outlined),
                  title: Text(tr('Hidden accounts')),
                  onTap: () => Navigator.pop(context, 'hidden'),
                ),
                ListTile(
                  leading: const Icon(Icons.card_giftcard_rounded),
                  title: Text(tr('Daily rewards')),
                  onTap: () => Navigator.pop(context, 'rewards'),
                ),
                ListTile(
                  leading: const Icon(Icons.emoji_events_outlined),
                  title: Text(tr('Leaderboards')),
                  onTap: () => Navigator.pop(context, 'leaders'),
                ),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(tr('Live moderators')),
                  onTap: () => Navigator.pop(context, 'mods'),
                ),
                ListTile(
                  leading: const Icon(Icons.how_to_reg_outlined),
                  title: Text(tr('Follow requests')),
                  onTap: () => Navigator.pop(context, 'requests'),
                ),
                ListTile(
                  leading: const Icon(Icons.block_rounded),
                  title: Text(tr('Blocked accounts')),
                  onTap: () => Navigator.pop(context, 'blocked'),
                ),
                ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: Text(tr('Language')),
                  subtitle: Text(languages[currentLanguage]!),
                  onTap: () => Navigator.pop(context, 'language'),
                ),
                ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: Text(tr('Sign out')),
                  onTap: () => Navigator.pop(context, 'logout'),
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.do_not_disturb_on_outlined),
                  title: Text(
                    _user!.restricted ? tr('Unrestrict') : tr('Restrict'),
                  ),
                  onTap: () => Navigator.pop(context, 'restrict'),
                ),
                ListTile(
                  leading: const Icon(Icons.block_rounded),
                  title: Text(_user!.blocked ? tr('Unblock') : tr('Block')),
                  onTap: () => Navigator.pop(context, 'block'),
                ),
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(tr('Report user')),
                  onTap: () => Navigator.pop(context, 'report'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        await _push(const EditProfileScreen());
      case 'wallet':
        await _push(const WalletScreen());
      case 'creator':
        await _push(const CreatorToolsScreen());
      case 'safety':
        await _push(const PrivacySafetyScreen());
      case 'restrict':
        final u = await toggleRestrict(context, ref, _user!);
        if (u != null && mounted) setState(() => _user = u);
      case 'history':
        await _push(const HistoryScreen());
      case 'hidden':
        await _push(const HiddenAccountsScreen());
      case 'rewards':
        await _push(const RewardsScreen());
      case 'leaders':
        await _push(const LeaderboardScreen());
      case 'mods':
        await _push(const LiveModsScreen());
      case 'qr':
        await showProfileQr(context, ref, _user!, mine: _isMe);
      case 'language':
        await showLanguagePicker(context, ref);
      case 'update':
        await checkForUpdates(context, ref);
      case 'logout':
        await ref.read(sessionProvider.notifier).logout();
      case 'report':
        await showReportDialog(context, ref, 'user', _user!.id);
      case 'requests':
        await _push(const FollowRequestsScreen());
      case 'blocked':
        await _push(const BlockedAccountsScreen());
      case 'block':
        await _toggleBlock();
    }
  }

  Future<void> _toggleBlock() async {
    final u = _user!;
    if (!u.blocked) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Block {0}?', [u.displayName])),
          content: Text(
            tr(
              "They won't be able to find your profile, see your videos, message you or join your lives. "
              "You'll stop following each other. They won't be told.",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.like,
                minimumSize: const Size(88, 40),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Block')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      final updated = await ref
          .read(apiProvider)
          .setBlocked(u.username, !u.blocked);
      if (mounted) {
        setState(() => _user = updated);
        showToast(
          context,
          updated.blocked
              ? tr('{0} is blocked', [u.displayName])
              : tr('{0} is unblocked', [u.displayName]),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = widget.username == null
        ? ref.watch(myVideosVersionProvider)
        : 0;
    ref.listen(sessionProvider, (prev, next) {
      if (widget.username == null &&
          next.value != null &&
          prev?.value?.id != next.value?.id) {
        _load();
      }
    });
    final u = _user;
    final scheme = Theme.of(context).colorScheme;
    final coins = ref.watch(sessionProvider).value?.coins ?? 0;

    if (u == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _error != null
              ? Text('$_error')
              : const CircularProgressIndicator(),
        ),
      );
    }
    final api = ref.read(apiProvider);
    final PageLoader<Video> loader = switch (_tab) {
      1 when _isMe => (cursor) => api.savedVideos(cursor, folder: _folder),
      2 => (cursor) => api.userReposts(u.username, cursor),
      _ => (cursor) => api.userVideos(u.username, cursor),
    };

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          ref.read(myVideosVersionProvider.notifier).bump();
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 0,
              centerTitle: true,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      u.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  if (u.verified) const VerifiedBadge(size: 16),
                ],
              ),
              leading: Navigator.of(context).canPop()
                  ? null
                  : const SizedBox.shrink(),
              actions: [
                if (_isMe)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Center(
                      child: CoinChip(
                        coins: coins,
                        onTap: () => _push(const WalletScreen()),
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: _menu,
                  icon: const Icon(Icons.more_vert_rounded),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: u.liveId != null && !_isMe
                              ? () => _push(
                                  LiveRoomScreen.viewer(liveId: u.liveId!),
                                )
                              : (u.hasStory
                                    ? () => openUserStories(
                                        context,
                                        u.username,
                                      ).then((_) => _load())
                                    : (_isMe
                                          ? () => createStory(context, ref)
                                          : null)),
                          child: Container(
                            padding: EdgeInsets.all(u.hasStory ? 3 : 0),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: u.hasStory && !u.storySeen
                                  ? AppColors.brandGradient
                                  : null,
                              color: u.hasStory && u.storySeen
                                  ? Colors.grey.shade500
                                  : null,
                            ),
                            child: Avatar(
                              url: u.avatarUrl,
                              name: u.displayName,
                              radius: 48,
                              ring: !u.hasStory,
                              live: u.liveId != null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                '@${u.username}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (u.verified) const VerifiedBadge(size: 17),
                            if (u.level > 0) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => showVipTiers(
                                  context,
                                  level: u.level,
                                  giftsSent: u.giftsSent,
                                ),
                                child: LevelBadge(level: u.level),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          constraints: const BoxConstraints(maxWidth: 340),
                          child: Row(
                            children: [
                              _Stat(
                                compactCount(u.following),
                                tr('Following'),
                                onTap: u.canView || _isMe
                                    ? () => _push(
                                        FollowListScreen(
                                          username: u.username,
                                          followers: false,
                                        ),
                                      )
                                    : null,
                              ),
                              _divider(scheme),
                              _Stat(
                                compactCount(u.followers),
                                tr('Followers'),
                                onTap: u.canView || _isMe
                                    ? () => _push(
                                        FollowListScreen(
                                          username: u.username,
                                          followers: true,
                                        ),
                                      )
                                    : null,
                              ),
                              _divider(scheme),
                              _Stat(compactCount(u.likesTotal), tr('Likes')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (_isMe)
                          Row(
                            children: [
                              Expanded(
                                child: _GreyButton(
                                  label: tr('Edit profile'),
                                  onTap: () => _push(const EditProfileScreen()),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _GreyButton(
                                  label: tr('Share profile'),
                                  onTap: () => showProfileQr(
                                    context,
                                    ref,
                                    u,
                                    mine: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _GreyButton(
                                icon: Icons.account_balance_wallet_outlined,
                                tooltip: tr('Wallet'),
                                onTap: () => _push(const WalletScreen()),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: u.blocked
                                    ? OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size.fromHeight(
                                            48,
                                          ),
                                          foregroundColor: AppColors.like,
                                        ),
                                        onPressed: _toggleBlock,
                                        icon: const Icon(
                                          Icons.block_rounded,
                                          size: 18,
                                        ),
                                        label: Text(tr('Unblock')),
                                      )
                                    : (u.isFollowing ?? false) || u.requested
                                    ? _GreyButton(
                                        label: u.requested
                                            ? tr('Requested')
                                            : tr('Following'),
                                        icon: u.requested
                                            ? null
                                            : Icons.check_rounded,
                                        onTap: _busy ? null : _toggleFollow,
                                      )
                                    : SizedBox(
                                        height: 44,
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.like,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            textStyle: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                          onPressed: _busy
                                              ? null
                                              : _toggleFollow,
                                          child: Text(tr('Follow')),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _GreyButton(
                                  label: tr('Message'),
                                  onTap: () => ChatScreen.openWith(
                                    context,
                                    ref,
                                    u.username,
                                  ),
                                ),
                              ),
                              if (u.liveId != null) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: GradientButton(
                                    label: tr('Watch live'),
                                    icon: Icons.podcasts_rounded,
                                    gradient: AppColors.liveGradient,
                                    onPressed: () => _push(
                                      LiveRoomScreen.viewer(liveId: u.liveId!),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        if (!_isMe && !u.blocked && u.subPrice != null) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(44),
                                foregroundColor: AppColors.amberDeep,
                                side: const BorderSide(color: AppColors.amber),
                              ),
                              icon: const Icon(Icons.workspace_premium_rounded),
                              label: Text(
                                u.subscribed
                                    ? tr('Subscribed · until {0}', [
                                        shortDate(u.subscribedUntil!),
                                      ])
                                    : tr('Subscribe · {0} coins/month', [
                                        u.subPrice!,
                                      ]),
                              ),
                              onPressed: () async {
                                if (await showSubscribeSheet(context, ref, u) !=
                                    null) {
                                  _load();
                                }
                              },
                            ),
                          ),
                        ],
                        if (u.bio.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            u.bio,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: .85),
                            ),
                          ),
                        ],
                        if (u.website.isNotEmpty || u.instagram.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 14,
                            children: [
                              if (u.website.isNotEmpty)
                                _LinkChip(
                                  icon: Icons.link_rounded,
                                  text: u.website.replaceFirst(
                                    RegExp(r'^https?://(www\.)?'),
                                    '',
                                  ),
                                  url: u.website,
                                ),
                              if (u.instagram.isNotEmpty)
                                _LinkChip(
                                  icon: Icons.camera_alt_outlined,
                                  text: '@${u.instagram}',
                                  url: 'https://instagram.com/${u.instagram}',
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (_isMe || (u.canView && !u.blocked))
                          _ProfileTabs(
                            selected: _tab,
                            showSaved: _isMe,
                            onSelect: (t) => setState(() => _tab = t),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!u.blocked)
              SliverToBoxAdapter(
                child: LiveEventsList(
                  key: ValueKey('events-${u.username}-$version'),
                  username: u.username,
                ),
              ),
            if (_isMe && _tab == 1)
              SliverToBoxAdapter(
                child: FolderChips(
                  selected: _folder,
                  onSelect: (f) => setState(() => _folder = f),
                ),
              ),
            if (!_isMe && (u.blocked || !u.canView))
              SliverToBoxAdapter(
                child: _LockedNotice(
                  blocked: u.blocked,
                  requested: u.requested,
                ),
              )
            else
              VideoGrid(
                key: ValueKey('${u.username}-$_tab-$version-$_folder'),
                loader: loader,
                emptyText: switch (_tab) {
                  1 => tr('Videos you save appear here.'),
                  2 => tr('No reposts yet'),
                  _ when _isMe => tr(
                    'Post your first video with the + button.',
                  ),
                  _ => tr('No videos yet'),
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => Container(
    width: 1,
    height: 28,
    color: scheme.outlineVariant.withValues(alpha: .5),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {this.onTap});
  final String value, label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    ),
  );
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.icon, required this.text, required this.url});
  final IconData icon;
  final String text, url;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () =>
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.emeraldLight),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.emeraldLight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shown instead of the video grid for private accounts and blocked people.
class _LockedNotice extends StatelessWidget {
  const _LockedNotice({required this.blocked, required this.requested});
  final bool blocked, requested;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: scheme.primary.withValues(alpha: .12),
            child: Icon(
              blocked ? Icons.block_rounded : Icons.lock_rounded,
              color: scheme.primary,
              size: 32,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            blocked
                ? tr('You blocked this account')
                : tr('This account is private'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            blocked
                ? tr('Unblock to see their videos again.')
                : requested
                ? tr('Your follow request is waiting for approval.')
                : tr('Follow to see their videos and lives.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// TikTok's flat grey profile button (text and/or icon).
class _GreyButton extends StatelessWidget {
  const _GreyButton({this.label, this.icon, this.tooltip, required this.onTap});
  final String? label;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final child = Material(
      color: dark ? const Color(0xFF2A2A2D) : const Color(0xFFF1F1F2),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          width: label == null ? 48 : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) Icon(icon, size: 20, color: scheme.onSurface),
              if (icon != null && label != null) const SizedBox(width: 6),
              if (label != null)
                Flexible(
                  child: Text(
                    label!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// Icon tabs with an underline: videos, reposts, saved (TikTok profile).
class _ProfileTabs extends StatelessWidget {
  const _ProfileTabs({
    required this.selected,
    required this.showSaved,
    required this.onSelect,
  });
  final int selected;
  final bool showSaved;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(int value, IconData icon, String label) {
      final on = selected == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: InkWell(
            onTap: () => onSelect(value),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: on ? scheme.onSurface : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Icon(
                icon,
                size: 24,
                color: on ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
      ),
      child: Row(
        children: [
          tab(0, Icons.grid_on_rounded, tr('Videos')),
          tab(2, Icons.repeat_rounded, tr('Reposts')),
          if (showSaved) tab(1, Icons.bookmark_border_rounded, tr('Saved')),
        ],
      ),
    );
  }
}
