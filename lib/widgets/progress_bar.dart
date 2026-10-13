import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Thin progress line under a video. Drag (or tap) to jump; it grows and shows the time while dragging.
class VideoProgressBar extends StatefulWidget {
  const VideoProgressBar({super.key, required this.controller});
  final VideoPlayerController controller;

  @override
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar> {
  double? _drag;

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  void _seekTo(double dx, double width) {
    final f = (dx / width).clamp(0.0, 1.0);
    setState(() => _drag = f);
  }

  void _finish() {
    final f = _drag;
    if (f != null) {
      final d = widget.controller.value.duration;
      widget.controller.seekTo(d * f);
    }
    setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (d) => _seekTo(d.localPosition.dx, box.maxWidth),
      onHorizontalDragUpdate: (d) => _seekTo(d.localPosition.dx, box.maxWidth),
      onHorizontalDragEnd: (_) => _finish(),
      onTapUp: (d) {
        _seekTo(d.localPosition.dx, box.maxWidth);
        _finish();
      },
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: widget.controller,
        builder: (context, v, _) {
          final len = v.duration.inMilliseconds;
          final f = _drag ?? (len > 0 ? v.position.inMilliseconds / len : 0.0);
          final dragging = _drag != null;
          return SizedBox(
            height: 22,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                if (dragging)
                  Positioned(
                    bottom: 14,
                    child: Text(
                      '${_fmt(v.duration * f)} / ${_fmt(v.duration)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(blurRadius: 10)],
                      ),
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: dragging ? 6 : 2,
                  color: Colors.white24,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: f.clamp(0.0, 1.0),
                    child: Container(
                      color: Colors.white.withValues(alpha: dragging ? 1 : .8),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
