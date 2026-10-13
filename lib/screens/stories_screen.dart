import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';

import 'package:flutter/foundation.dart';

import '../sound_sync.dart';
import '../widgets/sound_picker.dart';
import '../features.dart';

/// Bumped after posting or deleting a story, so story bars reload.
final storiesVersionProvider = NotifierProvider<StoriesVersion, int>(
  StoriesVersion.new,
);

class StoriesVersion extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

/// Avatar with a coloured ring when there's a story (grey once seen). Tap opens the stories.
class StoryAvatar extends ConsumerWidget {
  const StoryAvatar({
    super.key,
    required this.user,
    this.radius = 22,
    this.onTapNoStory,
  });
  final AppUser user;
  final double radius;
  final VoidCallback? onTapNoStory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = Avatar(
      url: user.avatarUrl,
      name: user.displayName,
      radius: radius,
    );
    if (!user.hasStory) {
      return GestureDetector(onTap: onTapNoStory, child: avatar);
    }
    return GestureDetector(
      onTap: () => openUserStories(context, user.username),
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: user.storySeen ? null : AppColors.brandGradient,
          color: user.storySeen ? Colors.grey.shade600 : null,
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
          child: avatar,
        ),
      ),
    );
  }
}

Future<void> openUserStories(BuildContext context, String username) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    final g = await container.read(apiProvider).userStories(username);
    if (!context.mounted) return;
    if (g.stories.isEmpty) {
      showToast(context, tr('No stories right now'));
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => StoryViewer(groups: [g])));
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Row of story circles: "Your story" first, then people you follow.
class StoryBar extends ConsumerStatefulWidget {
  const StoryBar({super.key, this.onDark = false});
  final bool onDark;

  @override
  ConsumerState<StoryBar> createState() => _StoryBarState();
}

class _StoryBarState extends ConsumerState<StoryBar> {
  List<StoryGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final g = await ref.read(apiProvider).storyFeed();
      if (mounted) setState(() => _groups = g);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(storiesVersionProvider, (_, _) => _load());
    final me = ref.watch(sessionProvider).value;
    if (me == null) return const SizedBox.shrink();
    final mine = _groups.where((g) => g.user.id == me.id).firstOrNull;
    final others = _groups.where((g) => g.user.id != me.id).toList();
    final textColor = widget.onDark
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    Widget circle(
      StoryGroup? g,
      AppUser user,
      String label, {
      bool add = false,
    }) => GestureDetector(
      onTap: () async {
        if (g == null) {
          await createStory(context, ref);
        } else {
          final list = [?mine, ...others];
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StoryViewer(groups: list, start: list.indexOf(g)),
            ),
          );
          if (mounted) setState(() {});
        }
      },
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: g != null && !g.allSeen
                        ? AppColors.brandGradient
                        : null,
                    color: g == null
                        ? Colors.transparent
                        : (g.allSeen ? Colors.grey.shade600 : null),
                  ),
                  child: Avatar(
                    url: user.avatarUrl,
                    name: user.displayName,
                    radius: 27,
                  ),
                ),
                if (add)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: GestureDetector(
                      onTap: () => createStory(context, ref),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.emerald,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: textColor),
            ),
          ],
        ),
      ),
    );
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          circle(mine, me, tr('Your story'), add: true),
          for (final g in others) circle(g, g.user, g.user.username),
        ],
      ),
    );
  }
}

// ---------- posting ----------

Future<void> createStory(BuildContext context, WidgetRef ref) async {
  if (!Features.on('stories')) {
    showToast(context, tr('Stories are turned off right now.'));
    return;
  }
  final source = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('New story'), style: Theme.of(context).textTheme.titleLarge),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr('Take a photo')),
            onTap: () => Navigator.pop(context, 'photo'),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: Text(tr('Record a video')),
            onTap: () => Navigator.pop(context, 'video'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr('Choose from gallery')),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
        ],
      ),
    ),
  );
  if (source == null) return;
  final picker = ImagePicker();
  final XFile? file = switch (source) {
    'photo' => await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1440,
      imageQuality: 88,
    ),
    'video' => await picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: 60),
    ),
    _ => await picker.pickMedia(maxWidth: 1440, imageQuality: 88),
  };
  if (file == null || !context.mounted) return;
  final lower = file.path.toLowerCase();
  final isVideo =
      source == 'video' || RegExp(r'\.(mp4|mov|3gp|webm|mkv)$').hasMatch(lower);
  final posted = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => _StoryComposer(path: file.path, isVideo: isVideo),
    ),
  );
  if (posted == true) {
    ref.read(storiesVersionProvider.notifier).bump();
  }
}

class _StoryComposer extends ConsumerStatefulWidget {
  const _StoryComposer({required this.path, required this.isVideo});
  final String path;
  final bool isVideo;

  @override
  ConsumerState<_StoryComposer> createState() => _StoryComposerState();
}

class _StoryComposerState extends ConsumerState<_StoryComposer> {
  final _caption = TextEditingController();
  VideoPlayerController? _video;
  double? _progress;
  SoundUse? _sound;
  SoundSync? _sync;

  void _startSound() {
    _sync?.dispose();
    _sync = null;
    final use = _sound;
    if (use == null) {
      _video?.setVolume(1);
      return;
    }
    _sync = SoundSync(use: use, video: _video, muted: () => false)..start();
    if (_video == null) _sync!.play();
  }

  Future<void> _chooseSound() async {
    final s = await pickSound(context);
    if (s == null || !mounted) return;
    setState(
      () =>
          _sound = SoundUse(sound: s, originalVolume: widget.isVideo ? 30 : 0),
    );
    _startSound();
  }

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _video =
          (kIsWeb
                ? VideoPlayerController.networkUrl(Uri.parse(widget.path))
                : VideoPlayerController.file(File(widget.path)))
            ..initialize().then((_) {
              _video!
                ..setLooping(true)
                ..play();
              if (mounted) setState(() {});
            });
    }
  }

  @override
  void dispose() {
    _sync?.dispose();
    _video?.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final v = _video;
    final seconds = v != null && v.value.isInitialized
        ? v.value.duration.inMilliseconds / 1000
        : 0.0;
    if (widget.isVideo && seconds > 61) {
      showError(context, tr('Story videos can be up to 60 seconds.'));
      return;
    }
    await v?.pause();
    setState(() => _progress = 0);
    try {
      await ref
          .read(apiProvider)
          .createStory(
            path: widget.path,
            isVideo: widget.isVideo,
            duration: seconds,
            caption: _caption.text.trim(),
            sound: _sound,
            onProgress: (a, b) {
              if (mounted && b > 0) setState(() => _progress = a / b);
            },
          );
      if (!mounted) return;
      showToast(context, tr('Your story is up for 24 hours'));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _progress = null);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(tr('New story')),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: widget.isVideo
                  ? (v != null && v.value.isInitialized
                        ? AspectRatio(
                            aspectRatio: v.value.aspectRatio,
                            child: VideoPlayer(v),
                          )
                        : const CircularProgressIndicator())
                  : (kIsWeb
                        ? Image.network(widget.path, fit: BoxFit.contain)
                        : Image.file(File(widget.path), fit: BoxFit.contain)),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  if (_sound == null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _progress == null ? _chooseSound : null,
                        icon: const Icon(Icons.music_note_rounded),
                        label: Text(tr('Add sound')),
                      ),
                    )
                  else
                    Theme(
                      data: ThemeData.dark(),
                      child: SoundSettingsCard(
                        use: _sound!,
                        photo: !widget.isVideo,
                        videoSeconds:
                            (_video?.value.duration.inMilliseconds ?? 0) / 1000,
                        onChanged: (u) {
                          setState(() => _sound = u);
                          _sync?.update(u);
                        },
                        onChange: _chooseSound,
                        onRemove: () {
                          setState(() => _sound = null);
                          _startSound();
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _caption,
                    maxLength: 200,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: tr('Add a caption…'),
                      hintStyle: const TextStyle(color: Colors.white54),
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_progress != null)
                    LinearProgressIndicator(
                      value: _progress,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    )
                  else
                    GradientButton(
                      label: tr('Share story'),
                      icon: Icons.send_rounded,
                      onPressed: _share,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- viewing ----------

/// Full-screen stories: tap right/left to move, hold to pause, swipe down to close.
class StoryViewer extends ConsumerStatefulWidget {
  const StoryViewer({super.key, required this.groups, this.start = 0});
  final List<StoryGroup> groups;
  final int start;

  @override
  ConsumerState<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends ConsumerState<StoryViewer>
    with SingleTickerProviderStateMixin {
  late final _pages = PageController(initialPage: widget.start);
  late int _group = widget.start;
  int _index = 0;
  late final _timer = AnimationController(vsync: this);
  VideoPlayerController? _video;
  SoundSync? _music;
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();

  StoryGroup get g => widget.groups[_group];
  Story get story => g.stories[_index];
  bool get _mine => ref.read(sessionProvider).value?.id == g.user.id;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _timer.addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
    _replyFocus.addListener(() => _replyFocus.hasFocus ? _pause() : _resume());
    // Start at the first story not seen yet.
    final firstUnseen = g.stories.indexWhere((s) => !s.seen);
    _index = firstUnseen < 0 ? 0 : firstUnseen;
    _show();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _timer.dispose();
    _music?.dispose();
    _video?.dispose();
    _pages.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _show() async {
    _timer.stop();
    _music?.dispose();
    _music = null;
    final old = _video;
    _video = null;
    await old?.dispose();
    final s = story;
    if (!s.seen && !_mine) {
      s.seen = true;
      ref.read(apiProvider).viewStory(s.id).ignore();
    }
    if (s.isVideo) {
      final c = VideoPlayerController.networkUrl(Uri.parse(s.url));
      _video = c;
      if (mounted) setState(() {});
      try {
        await c.initialize();
      } catch (_) {
        if (mounted && _video == c) _next();
        return;
      }
      if (!mounted || _video != c) return;
      _timer.duration = c.value.duration > Duration.zero
          ? c.value.duration
          : const Duration(seconds: 15);
      if (s.sound != null) {
        _music = SoundSync(use: s.sound!, video: c, muted: () => false)
          ..start();
      }
      await c.play();
      _timer.forward(from: 0);
    } else {
      // Photo stories with music stay up a little longer.
      _timer.duration = Duration(seconds: s.sound != null ? 10 : 5);
      if (s.sound != null) {
        _music = SoundSync(use: s.sound!, muted: () => false);
        _music!.start().then((_) => _music?.play());
      }
      _timer.forward(from: 0);
    }
    if (mounted) setState(() {});
  }

  void _pause() {
    _timer.stop();
    _video?.pause();
    if (_video == null) _music?.pause();
  }

  void _resume() {
    if (_replyFocus.hasFocus) return;
    _timer.forward();
    _video?.play();
    if (_video == null) _music?.play();
  }

  void _next() {
    if (_index < g.stories.length - 1) {
      setState(() => _index++);
      _show();
    } else if (_group < widget.groups.length - 1) {
      _pages.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
      _show();
    } else if (_group > 0) {
      _pages.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      _show();
    }
  }

  void _onGroupChanged(int i) {
    setState(() {
      _group = i;
      final firstUnseen = g.stories.indexWhere((s) => !s.seen);
      _index = firstUnseen < 0 ? 0 : firstUnseen;
    });
    _show();
  }

  Future<void> _viewers() async {
    _pause();
    final api = ref.read(apiProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => FutureBuilder<List<AppUser>>(
        future: api.storyViewers(story.id),
        builder: (context, snap) => SafeArea(
          child: snap.hasData
              ? ListView(
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 20, bottom: 8),
                      child: Text(
                        tr('{0} viewers', [snap.data!.length]),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (snap.data!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(tr('No views yet.')),
                      ),
                    for (final u in snap.data!)
                      ListTile(
                        leading: Avatar(url: u.avatarUrl, name: u.displayName),
                        title: Text(u.displayName),
                        subtitle: Text('@${u.username}'),
                      ),
                  ],
                )
              : const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
        ),
      ),
    );
    _resume();
  }

  Future<void> _delete() async {
    _pause();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete this story?')),
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
    if (ok != true) return _resume();
    try {
      await ref.read(apiProvider).deleteStory(story.id);
      ref.read(storiesVersionProvider.notifier).bump();
      if (!mounted) return;
      setState(() => g.stories.removeAt(_index));
      if (g.stories.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      if (_index >= g.stories.length) _index = g.stories.length - 1;
      _show();
    } catch (e) {
      if (mounted) showError(context, e);
      _resume();
    }
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    _reply.clear();
    _replyFocus.unfocus();
    final api = ref.read(apiProvider);
    try {
      final c = await api.openConversation(g.user.username);
      await api.sendMessage(c.id, tr('Replied to your story: {0}', [text]));
      if (mounted) showToast(context, tr('Sent'));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.groups.length,
        onPageChanged: _onGroupChanged,
        itemBuilder: (context, gi) =>
            gi != _group ? const ColoredBox(color: Colors.black) : _page(),
      ),
    );
  }

  Widget _page() {
    final s = story;
    final v = _video;
    final top = MediaQuery.paddingOf(context).top;
    return GestureDetector(
      onTapUp: (d) => d.globalPosition.dx < MediaQuery.sizeOf(context).width / 3
          ? _prev()
          : _next(),
      onLongPressStart: (_) => _pause(),
      onLongPressEnd: (_) => _resume(),
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).maybePop();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: s.isVideo
                ? (v != null && v.value.isInitialized
                      ? AspectRatio(
                          aspectRatio: v.value.aspectRatio,
                          child: VideoPlayer(v),
                        )
                      : const CircularProgressIndicator(color: Colors.white))
                : CachedNetworkImage(
                    imageUrl: s.url,
                    fit: BoxFit.contain,
                    placeholder: (_, _) =>
                        const CircularProgressIndicator(color: Colors.white),
                  ),
          ),
          // Progress bars + author
          Positioned(
            left: 8,
            right: 8,
            top: top + 8,
            child: Column(
              children: [
                Row(
                  children: [
                    for (var i = 0; i < g.stories.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: i == _index
                                ? AnimatedBuilder(
                                    animation: _timer,
                                    builder: (_, _) => LinearProgressIndicator(
                                      value: _timer.value,
                                      minHeight: 2.5,
                                      backgroundColor: Colors.white30,
                                      color: Colors.white,
                                    ),
                                  )
                                : LinearProgressIndicator(
                                    value: i < _index ? 1 : 0,
                                    minHeight: 2.5,
                                    backgroundColor: Colors.white30,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        _pause();
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ProfileScreen(username: g.user.username),
                              ),
                            )
                            .then((_) => _resume());
                      },
                      child: Row(
                        children: [
                          Avatar(
                            url: g.user.avatarUrl,
                            name: g.user.displayName,
                            radius: 17,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            g.user.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeAgo(s.createdAt),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (s.caption.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 110,
              child: Text(
                s.caption,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                ),
              ),
            ),
          // Bottom: viewers & delete for the owner, reply for everyone else.
          Positioned(
            left: 12,
            right: 12,
            bottom:
                12 +
                MediaQuery.paddingOf(context).bottom +
                MediaQuery.viewInsetsOf(context).bottom,
            child: _mine
                ? Row(
                    children: [
                      TextButton.icon(
                        onPressed: _viewers,
                        icon: const Icon(
                          Icons.visibility_outlined,
                          color: Colors.white,
                        ),
                        label: Text(
                          tr('{0} viewers', [s.views ?? 0]),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _delete,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  )
                : TextField(
                    controller: _reply,
                    focusNode: _replyFocus,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendReply(),
                    decoration: InputDecoration(
                      hintText: tr('Reply to {0}…', [g.user.displayName]),
                      hintStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white12,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: const BorderSide(color: Colors.white38),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                        ),
                        onPressed: _sendReply,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
