import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../audio_track.dart';
import '../i18n.dart';
import '../theme.dart';

String _mmss(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Records a voice message. Shows a timer with Cancel and Send.
/// Calls [onDone] with the file path (a blob URL on the web) and the length in seconds.
class VoiceRecorderBar extends StatefulWidget {
  const VoiceRecorderBar({
    super.key,
    required this.onDone,
    required this.onCancel,
  });
  final void Function(String path, double seconds) onDone;
  final VoidCallback onCancel;

  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar> {
  final _rec = AudioRecorder();
  final _watch = Stopwatch();
  Timer? _tick;
  String? _error;

  static const _max = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        setState(
          () =>
              _error = tr('Allow microphone access to record voice messages.'),
        );
        return;
      }
      final path = kIsWeb
          ? ''
          : '${(await getTemporaryDirectory()).path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      // Browsers differ: Chrome/Android record Opus, iPhone Safari only AAC (MP4).
      var encoder = AudioEncoder.aacLc;
      if (kIsWeb && !await _rec.isEncoderSupported(AudioEncoder.aacLc)) {
        encoder = AudioEncoder.opus;
      }
      await _rec.start(
        RecordConfig(encoder: encoder, bitRate: 64000, numChannels: 1),
        path: path,
      );
      _watch.start();
      _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() {});
        if (_watch.elapsed >= _max) _finish(true);
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = kIsWeb && Uri.base.scheme != 'https'
              ? tr(
                  'Browsers only allow the microphone on secure (https) websites.',
                )
              : '$e',
        );
      }
    }
  }

  Future<void> _finish(bool send) async {
    _tick?.cancel();
    _watch.stop();
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    final seconds = _watch.elapsed.inMilliseconds / 1000;
    if (send && path != null && seconds >= 0.6) {
      widget.onDone(path, seconds);
    } else {
      widget.onCancel();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: tr('Cancel'),
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.like),
        onPressed: () => _finish(false),
      ),
      Expanded(
        child: _error != null
            ? Text(_error!, style: const TextStyle(fontSize: 13))
            : Row(
                children: [
                  const Icon(
                    Icons.fiber_manual_record_rounded,
                    color: AppColors.like,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _mmss(_watch.elapsed),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('Recording… tap send when done'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
      ),
      Container(
        decoration: const BoxDecoration(
          gradient: AppColors.brandGradient,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          onPressed: _error != null ? null : () => _finish(true),
          icon: const Icon(Icons.send_rounded, color: Colors.white),
        ),
      ),
    ],
  );
}

/// Play button + progress for a voice message.
class VoicePlayer extends StatefulWidget {
  const VoicePlayer({
    super.key,
    required this.url,
    required this.seconds,
    required this.light,
  });
  final String url;
  final double seconds;

  /// White text (on the coloured "mine" bubble).
  final bool light;

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  // One voice message plays at a time, like in other chat apps.
  static _VoicePlayerState? _current;

  AudioTrack? _t;
  Timer? _tick;
  bool _loading = false;
  bool _failed = false;

  Future<void> _toggle() async {
    var t = _t;
    if (t == null) {
      setState(() {
        _loading = true;
        _failed = false;
      });
      // The browser's own audio element on the web: Flutter's video player never loads a hidden one there.
      t = AudioTrack(widget.url, loop: false);
      try {
        await t.initialize();
      } catch (_) {
        t.dispose();
        if (mounted) {
          setState(() {
            _loading = false;
            _failed = true;
          });
        }
        return;
      }
      if (!mounted) {
        t.dispose();
        return;
      }
      setState(() {
        _t = t;
        _loading = false;
      });
    }
    if (t.isPlaying) {
      await t.pause();
      _tick?.cancel();
    } else {
      if (_current != this) _current?._stop();
      _current = this;
      if (t.isCompleted ||
          (t.duration > Duration.zero && t.position >= t.duration)) {
        await t.seek(Duration.zero);
      }
      await t.play();
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (!mounted) return;
        final tr = _t;
        if (tr != null && !tr.isPlaying) {
          _tick?.cancel();
          if (tr.isCompleted) tr.seek(Duration.zero);
        }
        setState(() {});
      });
    }
    if (mounted) setState(() {});
  }

  void _stop() {
    _t?.pause();
    _tick?.cancel();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_current == this) _current = null;
    _tick?.cancel();
    _t?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final color = widget.light
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final total = t != null && t.duration > Duration.zero
        ? t.duration
        : Duration(milliseconds: (widget.seconds * 1000).round());
    final pos = t?.position ?? Duration.zero;
    final playing = t?.isPlaying ?? false;
    final progress = total.inMilliseconds > 0
        ? (pos.inMilliseconds / total.inMilliseconds).clamp(0, 1).toDouble()
        : 0.0;
    return SizedBox(
      width: 230,
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            tooltip: _failed ? tr("Couldn't play. Tap to try again.") : null,
            icon: _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(
                    _failed
                        ? Icons.refresh_rounded
                        : playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: color,
                    size: 30,
                  ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Tap the wave to jump there.
                onTapDown: (d) {
                  final tr = _t;
                  if (tr == null || total == Duration.zero) return;
                  tr.seek(
                    total * (d.localPosition.dx / c.maxWidth).clamp(0, 1),
                  );
                  setState(() {});
                },
                child: SizedBox(
                  height: 28,
                  child: CustomPaint(
                    size: Size(c.maxWidth, 28),
                    painter: _WavePainter(
                      seed: widget.url.hashCode,
                      progress: progress,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _mmss(playing || pos > Duration.zero ? pos : total),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// Voice-note bars (a fixed pattern per message), filled up to [progress].
class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.seed,
    required this.progress,
    required this.color,
  });
  final int seed;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const bar = 3.0, gap = 2.0;
    final n = (size.width / (bar + gap)).floor();
    final rnd = Random(seed);
    final played = Paint()..color = color;
    final rest = Paint()..color = color.withValues(alpha: .35);
    for (var i = 0; i < n; i++) {
      final h = size.height * (.25 + .75 * rnd.nextDouble());
      final x = i * (bar + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, bar, h),
          const Radius.circular(2),
        ),
        (i + .5) / n <= progress ? played : rest,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.color != color || old.seed != seed;
}
