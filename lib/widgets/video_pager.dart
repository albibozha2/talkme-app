import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../video_cache.dart';
import '../web/web_media.dart';
import 'video_item.dart';
import '../i18n.dart';
import '../playback.dart';

import 'package:flutter/foundation.dart';

import '../sound_sync.dart';

/// Full-screen vertical video list. Keeps at most three players alive
/// (previous, current, next) so memory stays flat and the next video is ready
/// before the user swipes to it.
class VideoPager extends ConsumerStatefulWidget {
  const VideoPager({
    super.key,
    required this.loader,
    this.initialItems,
    this.initialCursor,
    this.initialIndex = 0,
    this.active = true,
    this.empty,
  });

  final PageLoader<Video> loader;
  final List<Video>? initialItems;
  final String? initialCursor;
  final int initialIndex;

  /// False while the pager is off-screen (another tab or route), which pauses playback.
  final bool active;
  final Widget? empty;

  @override
  ConsumerState<VideoPager> createState() => VideoPagerState();
}

class VideoPagerState extends ConsumerState<VideoPager>
    with WidgetsBindingObserver {
  late final PageController _page = PageController(
    initialPage: widget.initialIndex,
  );
  late List<Video> _items = [...?widget.initialItems];
  late String? _cursor = widget.initialCursor;
  late bool _done = widget.initialItems != null && widget.initialCursor == null;
  late int _current = widget.initialIndex;
  final _players = <int, VideoPlayerController>{};
  final _viewed = <int>{};

  /// Watch time of the video on screen, reported when the person moves on.
  Timer? _watchTick;
  int? _watchId;
  int _watchMs = 0, _watchLength = 0;
  Api? _api;
  bool _loading = false;
  bool _foreground = true;
  Object? _error;

  bool get _shouldPlay => widget.active && _foreground && mounted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchTick = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _tickWatch(),
    );
    if (_items.isEmpty) {
      _loadMore();
    } else {
      _sync();
    }
  }

  @override
  void didUpdateWidget(VideoPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _applyPlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _flushWatch();
    _applyPlayback();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchTick?.cancel();
    _flushWatch();
    _soundSync?.dispose();
    for (final c in _players.values) {
      c.dispose();
    }
    _page.dispose();
    super.dispose();
  }

  void _tickWatch() {
    if (_items.isEmpty || _current >= _items.length) return;
    final id = _items[_current].id;
    final c = _players[id];
    if (c == null || !c.value.isPlaying || !_shouldPlay) return;
    if (_watchId != id) {
      _flushWatch();
      _watchId = id;
    }
    _watchMs += 250;
    _watchLength = c.value.duration.inMilliseconds;
    _api = ref.read(apiProvider);
  }

  void _flushWatch() {
    final id = _watchId, api = _api;
    if (id != null && api != null && _watchMs >= 250) {
      api.reportWatch(id, _watchMs, _watchLength).catchError((Object _) {});
    }
    _watchId = null;
    _watchMs = 0;
  }

  /// Reload from the top (pull to refresh, or tapping the Home tab again).
  Future<void> refresh() async {
    _flushWatch();
    _soundSync?.dispose();
    _soundSync = null;
    _soundFor = null;
    for (final c in _players.values) {
      c.dispose();
    }
    _players.clear();
    setState(() {
      _items = [];
      _cursor = null;
      _done = false;
      _current = 0;
    });
    if (_page.hasClients) _page.jumpToPage(0);
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.loader(_cursor);
      if (!mounted) return;
      final known = _items.map((v) => v.id).toSet();
      setState(() {
        _items.addAll(page.items.where((v) => known.add(v.id)));
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
      });
      _sync();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A player for [v]: from the phone's saved copy when there is one, else streamed.
  VideoPlayerController _create(Video v) {
    final hls = v.hlsUrl;
    // A video already saved on the phone plays from there (instant, no download).
    final saved = !kIsWeb && hls == null
        ? VideoCache.instance.cachedFile(v.videoUrl)
        : null;
    final options = VideoPlayerOptions(mixWithOthers: false);
    final c = saved != null
        ? VideoPlayerController.file(saved, videoPlayerOptions: options)
        : VideoPlayerController.networkUrl(
            Uri.parse(
              hls != null && !kIsWeb
                  ? VideoCache.instance.playable(hls)
                  : v.videoUrl,
            ),
            formatHint: hls != null && !kIsWeb ? VideoFormat.hls : null,
            videoPlayerOptions: options,
          );
    c.setLooping(true);
    var last = 0;
    c.addListener(() {
      final pos = c.value.position.inMilliseconds;
      final len = c.value.duration.inMilliseconds;
      final looped = len > 1500 && last > len - 900 && pos < 600;
      last = pos;
      if (!looped || !mounted || !ref.read(playbackProvider).autoScroll) {
        return;
      }
      if (_current < _items.length &&
          _items[_current].id == v.id &&
          _page.hasClients &&
          _current < _items.length - 1) {
        _page.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
    c
        .initialize()
        .then((_) {
          if (mounted) {
            setState(() {});
            _applyPlayback();
          }
        })
        .catchError((Object _) {});
    return c;
  }

  int _prefetchRun = 0;

  /// Browser: download the next videos into its cache, one after another.
  Future<void> _warmNext(int run) async {
    for (var i = _current + 1; i <= _current + 3 && i < _items.length; i++) {
      if (run != _prefetchRun || !mounted) return;
      if (_items[i].hlsUrl == null) await warmVideo(_items[i].videoUrl);
    }
  }

  /// Downloads the next videos in full, one after another (one request each, which the
  /// hosting server handles far better than many small streaming requests), then the
  /// current one for rewatching. A waiting player switches to the saved copy.
  Future<void> _prefetchFiles(int run) async {
    final order = [
      for (var i = _current + 1; i <= _current + 3 && i < _items.length; i++) i,
      _current,
    ];
    for (final i in order) {
      if (run != _prefetchRun || !mounted || i >= _items.length) return;
      final v = _items[i];
      if (v.hlsUrl != null ||
          VideoCache.instance.cachedFile(v.videoUrl) != null) {
        continue;
      }
      final file = await VideoCache.instance.download(v.videoUrl);
      if (file == null || !mounted) continue;
      final old = _players[v.id];
      final isCurrent = _items[_current].id == v.id;
      // Swap only players that aren't showing yet; the current one keeps streaming.
      if (old != null && !isCurrent && !old.value.isPlaying) {
        _players[v.id] = _create(v);
        setState(() {});
        // After the tile has switched to the new player.
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    }
  }

  /// Create players for current ±1, dispose the rest, then play/pause.
  void _sync() {
    final keep = <int>{};
    for (var i = _current - 1; i <= _current + 1; i++) {
      if (i < 0 || i >= _items.length) continue;
      final v = _items[i];
      keep.add(v.id);
      _players.putIfAbsent(v.id, () => _create(v));
    }
    for (final id in _players.keys.where((id) => !keep.contains(id)).toList()) {
      _players.remove(id)!.dispose();
    }
    _applyPlayback();
    if (!kIsWeb) {
      _prefetchFiles(++_prefetchRun);
    } else {
      _warmNext(++_prefetchRun);
    }
    // Download the first seconds of the two videos after the preloaded one.
    // Only network + disk, no extra video decoders (low-end phones have few).
    for (var i = _current + 2; i <= _current + 3 && i < _items.length; i++) {
      final hls = _items[i].hlsUrl;
      if (hls != null && !kIsWeb) VideoCache.instance.prefetch(hls);
    }
  }

  /// Music of the video on screen (only one plays at a time).
  SoundSync? _soundSync;
  VideoPlayerController? _soundFor;

  void _syncSound() {
    final v = _items.isEmpty ? null : _items[_current];
    final c = v == null ? null : _players[v.id];
    final use = v?.sound;
    if (use == null || c == null) {
      _soundSync?.dispose();
      _soundSync = null;
      _soundFor = null;
      return;
    }
    if (_soundFor == c) return;
    _soundSync?.dispose();
    _soundFor = c;
    _soundSync = SoundSync(
      use: use,
      video: c,
      muted: () => ref.read(mutedProvider),
    )..start();
  }

  void _applyPlayback() {
    if (_items.isEmpty) return;
    _syncSound();
    final currentId = _items[_current].id;
    _players.forEach((id, c) {
      if (!c.value.isInitialized) return;
      if (id == currentId && _shouldPlay) {
        if (!c.value.isPlaying) c.play();
        if (_viewed.add(id)) {
          ref.read(apiProvider).addView(id).catchError((Object _) {});
        }
      } else if (c.value.isPlaying) {
        c.pause();
        if (id != currentId) c.seekTo(Duration.zero);
      }
    });
  }

  void _onPageChanged(int index) {
    _current = index;
    _sync();
    if (index >= _items.length - 3) _loadMore();
  }

  void _removeVideo(Video v) {
    final i = _items.indexOf(v);
    if (i < 0) return;
    _players.remove(v.id)?.dispose();
    setState(() {
      _items.removeAt(i);
      if (_current >= _items.length) {
        _current = (_items.length - 1).clamp(0, 1 << 30);
      }
    });
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : _error != null
              ? _Retry(error: _error!, onRetry: _loadMore)
              : RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView(
                    children: [
                      SizedBox(height: MediaQuery.sizeOf(context).height * .35),
                      widget.empty ??
                          Center(
                            child: Text(
                              tr('No videos yet'),
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                    ],
                  ),
                ),
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: RefreshIndicator(
        onRefresh: refresh,
        child: PageView.builder(
          controller: _page,
          scrollDirection: Axis.vertical,
          itemCount: _items.length + (_done ? 0 : 1),
          onPageChanged: _onPageChanged,
          itemBuilder: (context, i) {
            if (i >= _items.length) {
              return Center(
                child: _error != null
                    ? _Retry(error: _error!, onRetry: _loadMore)
                    : const CircularProgressIndicator(),
              );
            }
            final v = _items[i];
            return VideoItem(
              key: ValueKey(v.id),
              video: v,
              controller: _players[v.id],
              onDeleted: () => _removeVideo(v),
              onPausedForNavigation: (paused) {
                if (paused) {
                  _players[v.id]?.pause();
                } else {
                  _applyPlayback();
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: Text(tr('Try again'))),
      ],
    ),
  );
}

/// Opens a full-screen pager starting at [index], e.g. from a profile grid.
Future<void> openVideoPager(
  BuildContext context, {
  required List<Video> items,
  required int index,
  required PageLoader<Video> loader,
  String? cursor,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          systemOverlayStyle: darkSystemUi,
        ),
        body: VideoPager(
          loader: loader,
          initialItems: items,
          initialCursor: cursor,
          initialIndex: index,
        ),
      ),
    ),
  );
}
