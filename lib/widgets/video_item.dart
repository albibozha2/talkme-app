import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../models.dart';
import '../screens/chat_screen.dart';
import '../screens/comments_sheet.dart';
import '../screens/discover_screen.dart';
import '../screens/live_room_screen.dart';
import '../screens/profile_screen.dart';
import '../state.dart';
import '../theme.dart';
import 'common.dart';
import 'gifts.dart';
import 'overlays.dart';
import '../i18n.dart';
import '../screens/stories_screen.dart';
import '../filters.dart';
import '../playback.dart';
import 'duet_view.dart';
import 'folder_picker.dart';
import 'progress_bar.dart';

import 'package:flutter/foundation.dart';

import '../screens/duet_screen.dart';
import '../screens/sound_screen.dart';

/// Shared across all videos: muting one mutes the feed.
final mutedProvider = NotifierProvider<MutedNotifier, bool>(MutedNotifier.new);

class MutedNotifier extends Notifier<bool> {
  @override
  bool build() => kIsWeb;
  void toggle() => state = !state;
}

class VideoItem extends ConsumerStatefulWidget {
  const VideoItem({
    super.key,
    required this.video,
    required this.controller,
    required this.onDeleted,
    required this.onPausedForNavigation,
  });

  final Video video;
  final VideoPlayerController? controller;
  final VoidCallback onDeleted;
  final void Function(bool paused) onPausedForNavigation;

  @override
  ConsumerState<VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends ConsumerState<VideoItem>
    with SingleTickerProviderStateMixin {
  late final _heart = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  final _gifts = GlobalKey<GiftOverlayState>();
  bool _userPaused = false;
  bool _busy = false;

  Video get v => widget.video;
  bool get _mine => ref.read(sessionProvider).value?.id == v.user.id;

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  /// Runs an optimistic toggle; [apply] flips local state, the call confirms it.
  Future<void> _optimistic(
    void Function(bool undo) apply,
    Future<void> Function() call,
  ) async {
    if (_busy) return;
    _busy = true;
    HapticFeedback.lightImpact();
    setState(() => apply(false));
    try {
      await call();
    } catch (e) {
      if (mounted) {
        setState(() => apply(true));
        showError(context, e);
      }
    } finally {
      _busy = false;
    }
  }

  void _toggleLike({bool onlyLike = false}) {
    if (onlyLike && v.liked) return;
    final on = !v.liked;
    _optimistic(
      (undo) {
        final value = undo ? !on : on;
        v.liked = value;
        v.likes += value ? 1 : -1;
      },
      () async {
        final likes = await ref.read(apiProvider).setLike(v.id, on);
        if (mounted) setState(() => v.likes = likes);
      },
    );
  }

  void _toggleSave() {
    final on = !v.saved;
    _optimistic((undo) => v.saved = undo ? !on : on, () async {
      await ref.read(apiProvider).setSaved(v.id, on);
      if (mounted && on) showToast(context, tr('Saved to your collection'));
    });
  }

  void _toggleFollow() {
    final on = !v.authorFollowing;
    _optimistic(
      (undo) => v.authorFollowing = undo ? !on : on,
      () => ref.read(apiProvider).setFollow(v.user.username, on),
    );
  }

  Future<void> _share() async {
    final base = ref.read(apiProvider).server.replaceAll(RegExp(r'/api$'), '');
    final caption = v.caption.isEmpty ? '' : '${v.caption}\n';
    await SharePlus.instance.share(
      ShareParams(
        text: tr('{0}@{1} on TalkMe\n{2}/v/{3}', [
          caption,
          v.user.username,
          base,
          v.id,
        ]),
        subject: tr('Watch this on TalkMe'),
      ),
    );
  }

  Future<void> _gift() async {
    if (_mine) {
      showToast(context, tr("You can't send gifts to yourself"));
      return;
    }
    await showGiftSheet(
      context,
      videoId: v.id,
      onSent: (sent) => _gifts.currentState?.show(sent),
    );
  }

  void _togglePause() {
    final c = widget.controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() => _userPaused = c.value.isPlaying);
    c.value.isPlaying ? c.pause() : c.play();
  }

  Future<void> _push(Widget page) async {
    widget.onPausedForNavigation(true);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted && !_userPaused) widget.onPausedForNavigation(false);
  }

  void _openAuthor() {
    final liveId = v.user.liveId;
    if (liveId == null && v.user.hasStory && !_mine) {
      widget.onPausedForNavigation(true);
      openUserStories(context, v.user.username).whenComplete(() {
        if (mounted && !_userPaused) widget.onPausedForNavigation(false);
      });
      return;
    }
    _push(
      liveId != null && !_mine
          ? LiveRoomScreen.viewer(liveId: liveId)
          : ProfileScreen(username: v.user.username),
    );
  }

  Future<void> _openComments() async {
    await showCommentsSheet(context, v);
    if (mounted) setState(() {});
  }

  void _toggleRepost() {
    final on = !v.reposted;
    _optimistic(
      (undo) {
        final value = undo ? !on : on;
        v.reposted = value;
        v.reposts += value ? 1 : -1;
      },
      () async {
        final n = await ref.read(apiProvider).setRepost(v.id, on);
        if (!mounted) return;
        setState(() => v.reposts = n);
        showToast(
          context,
          on ? tr('Reposted to your followers') : tr('Repost removed'),
        );
      },
    );
  }

  Future<void> _privacySettings() async {
    var visibility = v.visibility;
    var comments = v.allowComments;
    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('Privacy settings'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: visibility,
                onChanged: (x) => setSheet(() => visibility = x ?? visibility),
                child: Column(
                  children: [
                    for (final (value, label, icon) in visibilityOptions(
                      subscribers:
                          ref.read(sessionProvider).value?.subPrice != null ||
                          v.visibility == 'subscribers',
                    ))
                      RadioListTile<String>(
                        value: value,
                        title: Text(label),
                        secondary: Icon(icon),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                value: comments,
                onChanged: (x) => setSheet(() => comments = x),
                title: Text(tr('Allow comments')),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: GradientButton(
                  label: tr('Save'),
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (save != true || !mounted) return;
    try {
      final updated = await ref
          .read(apiProvider)
          .videoSettings(v.id, visibility: visibility, allowComments: comments);
      if (!mounted) return;
      setState(() {
        v.visibility = updated.visibility;
        v.allowComments = updated.allowComments;
      });
      showToast(context, tr('Saved'));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _more() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_mine) ...[
              ListTile(
                leading: Icon(
                  v.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                ),
                title: Text(
                  v.pinned ? tr('Unpin from profile') : tr('Pin to profile'),
                ),
                onTap: () => Navigator.pop(context, 'pin'),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: Text(tr('Privacy settings')),
                subtitle: Text(visibilityLabel(v.visibility)),
                onTap: () => Navigator.pop(context, 'privacy'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(tr('Delete video')),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ] else ...[
              if (v.visibility == 'public')
                ListTile(
                  leading: Icon(
                    Icons.repeat_rounded,
                    color: v.reposted ? AppColors.amber : null,
                  ),
                  title: Text(v.reposted ? tr('Remove repost') : tr('Repost')),
                  onTap: () => Navigator.pop(context, 'repost'),
                ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(tr('Report video')),
                onTap: () => Navigator.pop(context, 'report'),
              ),
            ],
            if (!_mine) ...[
              ListTile(
                leading: const Icon(Icons.heart_broken_outlined),
                title: Text(tr('Not interested')),
                onTap: () => Navigator.pop(context, 'ni'),
              ),
              ListTile(
                leading: const Icon(Icons.person_off_outlined),
                title: Text(
                  tr("Don't show videos from {0}", ['@${v.user.username}']),
                ),
                onTap: () => Navigator.pop(context, 'hide_author'),
              ),
            ],
            // Duet: record yourself beside this video (phones only: browsers block the camera on http).
            if (!kIsWeb &&
                v.allowDuet &&
                v.duetOf == null &&
                v.visibility == 'public' &&
                v.status == 'published')
              ListTile(
                leading: const Icon(Icons.vertical_split_rounded),
                title: Text(tr('Duet')),
                subtitle: Text(
                  tr('Record yourself side by side with this video'),
                ),
                onTap: () => Navigator.pop(context, 'duet'),
              ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(tr('Add to folder')),
              onTap: () => Navigator.pop(context, 'folder'),
            ),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: Text(tr('Playback speed')),
              trailing: Text('${ref.read(playbackProvider).speed}×'),
              onTap: () => Navigator.pop(context, 'speed'),
            ),
            ListTile(
              leading: const Icon(Icons.fullscreen_rounded),
              title: Text(tr('Clear mode')),
              subtitle: Text(tr('Hide buttons and text')),
              onTap: () => Navigator.pop(context, 'clear'),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.swipe_up_alt_rounded),
              title: Text(tr('Auto-scroll')),
              subtitle: Text(tr('Go to the next video when one ends')),
              value: ref.read(playbackProvider).autoScroll,
              onChanged: (_) => Navigator.pop(context, 'autoscroll'),
            ),
            ListTile(
              leading: const Icon(Icons.send_rounded),
              title: Text(tr('Send to a friend')),
              onTap: () => Navigator.pop(context, 'dm'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(tr('Share')),
              onTap: () => Navigator.pop(context, 'share'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'ni':
      case 'hide_author':
        try {
          await ref
              .read(apiProvider)
              .notInterested(v.id, author: choice == 'hide_author');
          if (!mounted) return;
          showToast(
            context,
            choice == 'ni'
                ? tr("Got it. You'll see fewer videos like this.")
                : tr("You won't see videos from {0} in For You.", [
                    '@${v.user.username}',
                  ]),
          );
          widget.onDeleted();
        } catch (e) {
          if (mounted) showError(context, e);
        }
      case 'folder':
        final saved = await showFolderPicker(context, ref, v.id);
        if (saved && mounted) setState(() => v.saved = true);
      case 'speed':
        final speed = await showModalBottomSheet<double>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final x in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                  ListTile(
                    title: Text(x == 1.0 ? tr('Normal') : '$x×'),
                    trailing: ref.read(playbackProvider).speed == x
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.pop(context, x),
                  ),
              ],
            ),
          ),
        );
        if (speed != null) ref.read(playbackProvider.notifier).setSpeed(speed);
      case 'clear':
        ref.read(playbackProvider.notifier).setClear(true);
      case 'autoscroll':
        final on = !ref.read(playbackProvider).autoScroll;
        ref.read(playbackProvider.notifier).setAutoScroll(on);
        if (mounted) {
          showToast(context, on ? tr('Auto-scroll on') : tr('Auto-scroll off'));
        }
      case 'pin':
        final on = !v.pinned;
        try {
          await ref.read(apiProvider).setVideoPinned(v.id, on);
          if (!mounted) return;
          setState(() => v.pinned = on);
          ref.read(myVideosVersionProvider.notifier).bump();
          showToast(
            context,
            on ? tr('Pinned to your profile') : tr('Unpinned'),
          );
        } catch (e) {
          if (mounted) showError(context, e);
        }
      case 'repost':
        _toggleRepost();
      case 'privacy':
        await _privacySettings();
      case 'report':
        await showReportDialog(context, ref, 'video', v.id);
      case 'dm':
        await showSendVideoSheet(context, ref, v);
      case 'duet':
        await _push(DuetScreen(original: v));
      case 'share':
        await _share();
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('Delete this video?')),
            content: Text(
              tr("It will be removed for everyone. You can't undo this."),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('Cancel')),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr('Delete')),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        try {
          await ref.read(apiProvider).deleteVideo(v.id);
          ref.read(myVideosVersionProvider.notifier).bump();
          widget.onDeleted();
        } catch (e) {
          if (mounted) showError(context, e);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final muted = ref.watch(mutedProvider);
    // With added music, the original sound plays at the level the creator chose.
    c?.setVolume(muted ? 0 : (v.sound?.originalVolume ?? 100) / 100);
    final prefs = ref.watch(playbackProvider);
    // The creator's speed (e.g. 2x) times the viewer's own playback speed setting.
    final speed = (prefs.speed * v.speed).clamp(.25, 3.0).toDouble();
    if (c != null && c.value.isInitialized && c.value.playbackSpeed != speed) {
      c.setPlaybackSpeed(speed);
    }
    final clear = prefs.clear;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topInset = MediaQuery.paddingOf(context).top;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: _togglePause,
          onDoubleTap: () {
            _heart.forward(from: 0);
            _toggleLike(onlyLike: true);
          },
          child: ColoredBox(
            color: Colors.black,
            child: c != null
                ? ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (context, value, _) => Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: !value.isInitialized
                              ? withFilter(v.filter, _Thumb(url: v.thumbUrl))
                              : v.duetOf != null
                              ? DuetView(
                                  main: c,
                                  source: v.duetOf!,
                                  filter: v.filter,
                                  muted: muted,
                                )
                              : _VideoSurface(
                                  controller: c,
                                  value: value,
                                  filter: v.filter,
                                ),
                        ),
                        // Still loading, or waiting for more of the video.
                        if (!value.isInitialized ||
                            (value.isBuffering && value.isPlaying))
                          const _Waiting(),
                      ],
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      withFilter(v.filter, _Thumb(url: v.thumbUrl)),
                      const _Waiting(),
                    ],
                  ),
          ),
        ),
        if (!clear)
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .18, .55, 1],
                  colors: [
                    Color(0x80000000),
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xB3000000),
                  ],
                ),
              ),
            ),
          ),
        if (v.overlays.isNotEmpty)
          IgnorePointer(child: OverlayLayer(overlays: v.overlays)),
        if (_userPaused)
          IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 56,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        IgnorePointer(
          child: Center(child: _HeartBurst(animation: _heart)),
        ),
        GiftOverlay(key: _gifts),
        if (c != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: clear ? 0 : bottomInset,
            child: VideoProgressBar(controller: c),
          ),
        if (clear)
          Positioned(
            right: 12,
            top: topInset + 12,
            child: ActionChip(
              avatar: const Icon(Icons.fullscreen_exit_rounded, size: 18),
              label: Text(tr('Exit clear mode')),
              onPressed: () =>
                  ref.read(playbackProvider.notifier).setClear(false),
            ),
          ),
        // Sound toggle: only in the browser, where videos start muted.
        if (!clear && kIsWeb)
          Positioned(
            right: 10,
            top: topInset + 54,
            child: _RoundIconButton(
              icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              onTap: () => ref.read(mutedProvider.notifier).toggle(),
            ),
          ),
        // Right action rail (TikTok order).
        if (!clear)
          Positioned(
            right: 4,
            bottom: 20 + bottomInset,
            child: Column(
              children: [
                _AuthorButton(
                  user: v.user,
                  showFollow: !_mine && !v.authorFollowing,
                  onOpen: _openAuthor,
                  onFollow: _toggleFollow,
                ),
                const SizedBox(height: 10),
                _Action(
                  icon: Icons.favorite_rounded,
                  color: v.liked ? AppColors.like : Colors.white,
                  label: compactCount(v.likes),
                  onTap: _toggleLike,
                  semantics: v.liked ? tr('Unlike') : tr('Like'),
                ),
                _Action(
                  icon: Icons.textsms_rounded,
                  label: v.allowComments ? compactCount(v.comments) : tr('Off'),
                  onTap: v.allowComments ? _openComments : null,
                  semantics: tr('Comments'),
                ),
                _Action(
                  icon: Icons.bookmark_rounded,
                  color: v.saved ? AppColors.amber : Colors.white,
                  label: v.saved ? tr('Saved') : tr('Save'),
                  onTap: _toggleSave,
                  semantics: tr('Save'),
                ),
                _Action(
                  icon: Icons.reply_rounded,
                  flip: true,
                  label: v.reposts > 0 ? compactCount(v.reposts) : tr('Share'),
                  onTap: _share,
                  semantics: tr('Share'),
                ),
                _GiftAction(onTap: _gift),
                const SizedBox(height: 6),
                if (c == null)
                  _SoundDisc(user: v.user, spinning: false, onTap: _more)
                else
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (context, value, _) => _SoundDisc(
                      user: v.user,
                      spinning: value.isPlaying,
                      onTap: _more,
                    ),
                  ),
              ],
            ),
          ),
        // Author + caption.
        if (!clear)
          Positioned(
            left: 14,
            right: 86,
            bottom: 18 + bottomInset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (v.repostedBy != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () => _push(ProfileScreen(username: v.repostedBy)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.repeat_rounded,
                            size: 15,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            tr('{0} reposted', ['@${v.repostedBy}']),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (v.visibility != 'public')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          v.visibility == 'private'
                              ? Icons.lock_rounded
                              : Icons.people_alt_rounded,
                          size: 14,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          visibilityLabel(v.visibility),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                GestureDetector(
                  onTap: _openAuthor,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '@${v.user.username}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            shadows: [
                              Shadow(blurRadius: 6, color: Colors.black45),
                            ],
                          ),
                        ),
                      ),
                      if (v.user.verified) const VerifiedBadge(),
                      Text(
                        '  ·  ${timeAgo(v.createdAt)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          shadows: [
                            Shadow(blurRadius: 6, color: Colors.black45),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (v.user.liveId != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _openAuthor,
                    child: Row(
                      children: [
                        LiveBadge(),
                        SizedBox(width: 6),
                        Text(
                          tr('Tap to watch'),
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
                if (v.caption.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _Caption(
                    text: v.caption,
                    onTag: (tag) => _push(HashtagScreen(tag: tag)),
                    onMention: (name) => _push(ProfileScreen(username: name)),
                  ),
                ],
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: v.sound?.sound.id == null
                      ? null
                      : () => _push(SoundScreen(soundId: v.sound!.sound.id!)),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.music_note_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          v.sound != null
                              ? v.sound!.sound.label
                              : tr('Original sound · {0}', [
                                  v.user.displayName,
                                ]),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            shadows: [
                              Shadow(blurRadius: 6, color: Colors.black45),
                            ],
                          ),
                        ),
                      ),
                      if (v.views > 0) ...[
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.play_arrow_rounded,
                          size: 15,
                          color: Colors.white70,
                        ),
                        Text(
                          compactCount(v.views),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (v.status != 'published') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      switch (v.status) {
                        'pending' => tr('Waiting for review'),
                        'processing' => tr('Processing…'),
                        'hidden' => tr('Hidden by moderators'),
                        _ => v.status,
                      },
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _HeartBurst extends StatelessWidget {
  const _HeartBurst({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final t = animation.value;
      if (t == 0 || t == 1) return const SizedBox.shrink();
      final scale = Curves.elasticOut.transform((t * 1.6).clamp(0, 1));
      return Opacity(
        opacity: t < .7 ? 1 : (1 - t) / .3,
        child: Transform.rotate(
          angle: -.15,
          child: Transform.scale(
            scale: scale,
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                colors: [Color(0xFFFF6B8B), AppColors.like],
              ).createShader(r),
              child: const Icon(
                Icons.favorite_rounded,
                size: 120,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({
    required this.controller,
    required this.value,
    this.filter,
  });
  final VideoPlayerController controller;
  final VideoPlayerValue value;
  final String? filter;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final portrait = value.aspectRatio < 1;
    final fit = portrait && (screen.aspectRatio - value.aspectRatio).abs() < .25
        ? BoxFit.cover
        : BoxFit.contain;
    return RepaintBoundary(
      child: SizedBox.expand(
        child: FittedBox(
          fit: fit,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: value.size.width,
            height: value.size.height,
            child: withFilter(filter, VideoPlayer(controller)),
          ),
        ),
      ),
    );
  }
}

/// A small spinner, shown only if loading takes more than a moment (no flicker on fast loads).
class _Waiting extends StatefulWidget {
  const _Waiting();

  @override
  State<_Waiting> createState() => _WaitingState();
}

class _WaitingState extends State<_Waiting> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: _show ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: Center(
        child: Container(
          width: 52,
          height: 52,
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: Color(0x66000000),
            shape: BoxShape.circle,
          ),
          child: const CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null) return const SizedBox.expand();
    final w =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return SizedBox.expand(
      child: CachedNetworkImage(
        imageUrl: url!,
        fit: BoxFit.cover,
        memCacheWidth: w,
        fadeInDuration: Duration.zero,
      ),
    );
  }
}

class _Caption extends StatefulWidget {
  const _Caption({
    required this.text,
    required this.onTag,
    required this.onMention,
  });
  final String text;
  final void Function(String tag) onTag;
  final void Function(String username) onMention;

  @override
  State<_Caption> createState() => _CaptionState();
}

class _CaptionState extends State<_Caption> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final parts = <InlineSpan>[];
    widget.text.splitMapJoin(
      RegExp(r'#[\p{L}\p{N}_]+|@[A-Za-z0-9_.]{3,30}', unicode: true),
      onMatch: (m) {
        final tag = m[0]!.substring(1);
        final mention = m[0]!.startsWith('@');
        parts.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => mention
                  ? widget.onMention(tag.toLowerCase())
                  : widget.onTag(tag.toLowerCase()),
              child: Text(
                m[0]!,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),
        );
        return '';
      },
      onNonMatch: (s) {
        parts.add(TextSpan(text: s));
        return '';
      },
    );
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      child: Text.rich(
        TextSpan(children: parts),
        maxLines: _open ? 12 : 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: .28),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.semantics,
    this.color,
    this.flip = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String semantics;
  final Color? color;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    Widget glyph = Icon(
      icon,
      key: ValueKey(icon),
      size: 36,
      color: color ?? Colors.white,
      shadows: const [Shadow(blurRadius: 8, color: Colors.black45)],
    );
    if (flip) glyph = Transform.flip(flipX: true, child: glyph);
    return Semantics(
      button: true,
      label: semantics,
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, a) =>
                    ScaleTransition(scale: a, child: child),
                child: glyph,
              ),
              if (label.isNotEmpty)
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gift button with a gentle pulse so it's noticed.
class _GiftAction extends StatefulWidget {
  const _GiftAction({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_GiftAction> createState() => _GiftActionState();
}

class _GiftActionState extends State<_GiftAction>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tr('Send a gift'),
    child: InkResponse(
      onTap: widget.onTap,
      radius: 30,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        child: Column(
          children: [
            ScaleTransition(
              scale: Tween(begin: .92, end: 1.08).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: AppColors.goldGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.amber.withValues(alpha: .5),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.card_giftcard_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tr('Gift'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The author's photo at the top of the rail, with a "+" to follow (TikTok style).
class _AuthorButton extends StatelessWidget {
  const _AuthorButton({
    required this.user,
    required this.showFollow,
    required this.onOpen,
    required this.onFollow,
  });
  final AppUser user;
  final bool showFollow;
  final VoidCallback onOpen, onFollow;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 54,
    height: 62,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        GestureDetector(
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              gradient: user.hasStory ? AppColors.goldGradient : null,
            ),
            child: Avatar(
              url: user.avatarUrl,
              name: user.displayName,
              radius: 24,
              live: user.liveId != null,
            ),
          ),
        ),
        if (showFollow)
          Positioned(
            bottom: 0,
            child: GestureDetector(
              onTap: onFollow,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: AppColors.like,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 17,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Spinning record with the author's photo (TikTok's sound disc). Tap: more options.
class _SoundDisc extends StatefulWidget {
  const _SoundDisc({
    required this.user,
    required this.spinning,
    required this.onTap,
  });
  final AppUser user;
  final bool spinning;
  final VoidCallback onTap;

  @override
  State<_SoundDisc> createState() => _SoundDiscState();
}

class _SoundDiscState extends State<_SoundDisc>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didUpdateWidget(_SoundDisc old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    if (widget.spinning && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.spinning && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tr('More'),
    child: GestureDetector(
      onTap: widget.onTap,
      child: RotationTransition(
        turns: _spin,
        child: Container(
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(9),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [Color(0xFF3A3A3A), Color(0xFF111111)],
            ),
          ),
          child: Avatar(
            url: widget.user.avatarUrl,
            name: widget.user.displayName,
            radius: 14,
          ),
        ),
      ),
    ),
  );
}
