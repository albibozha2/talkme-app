import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../filters.dart';
import '../i18n.dart';
import '../models.dart';

/// A duet as TikTok shows it: the new video on the left, the original on the right,
/// playing together. The original follows the main video (play, pause, seek, loop).
class DuetView extends StatefulWidget {
  const DuetView({
    super.key,
    required this.main,
    required this.source,
    this.filter,
    this.muted = false,
  });

  /// The duet's own video (already playing in the feed).
  final VideoPlayerController main;
  final DuetSource source;
  final String? filter;
  final bool muted;

  @override
  State<DuetView> createState() => _DuetViewState();
}

class _DuetViewState extends State<DuetView> {
  late final VideoPlayerController _orig = VideoPlayerController.networkUrl(
    Uri.parse(widget.source.videoUrl),
    videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
  );
  bool _ready = false;
  Duration _lastMain = Duration.zero;

  @override
  void initState() {
    super.initState();
    _orig
        .initialize()
        .then((_) {
          if (!mounted) return;
          _orig.setVolume(widget.muted ? 0 : 1);
          setState(() => _ready = true);
          _follow();
        })
        .catchError((Object _) {});
    widget.main.addListener(_follow);
  }

  @override
  void didUpdateWidget(DuetView old) {
    super.didUpdateWidget(old);
    if (old.main != widget.main) {
      old.main.removeListener(_follow);
      widget.main.addListener(_follow);
    }
    if (_ready) _orig.setVolume(widget.muted ? 0 : 1);
  }

  /// Keeps the original in step with the main video.
  void _follow() {
    if (!_ready) return;
    final m = widget.main.value;
    final o = _orig.value;
    if (o.playbackSpeed != m.playbackSpeed) {
      _orig.setPlaybackSpeed(m.playbackSpeed);
    }
    // The main video looped back to the start: restart the original too.
    if (m.position < _lastMain - const Duration(milliseconds: 800)) {
      _orig.seekTo(Duration.zero);
    }
    _lastMain = m.position;
    if (m.isPlaying && !o.isPlaying && m.position < o.duration) {
      _orig.play();
    } else if (!m.isPlaying && o.isPlaying) {
      _orig.pause();
    }
    final drift = (m.position - o.position).inMilliseconds.abs();
    if (drift > 450 && m.position < o.duration) _orig.seekTo(m.position);
  }

  @override
  void dispose() {
    widget.main.removeListener(_follow);
    _orig.dispose();
    super.dispose();
  }

  Widget _half(VideoPlayerController c, String? filter) {
    final v = c.value;
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: v.size.width == 0 ? 9 : v.size.width,
            height: v.size.height == 0 ? 16 : v.size.height,
            child: withFilter(filter, VideoPlayer(c)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(height: MediaQuery.paddingOf(context).top + 60),
      Expanded(
        child: Row(
          children: [
            Expanded(child: _half(widget.main, widget.filter)),
            const SizedBox(width: 2),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_ready)
                    _half(_orig, widget.source.filter)
                  else if (widget.source.thumbUrl != null)
                    Image.network(widget.source.thumbUrl!, fit: BoxFit.cover)
                  else
                    const ColoredBox(color: Colors.black),
                  Positioned(
                    left: 6,
                    top: 6,
                    right: 6,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          tr('Duet with @{0}', [widget.source.username]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: MediaQuery.paddingOf(context).bottom + 150),
    ],
  );
}
