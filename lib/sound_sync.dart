import 'dart:async';

import 'package:video_player/video_player.dart';

import 'audio_track.dart';
import 'models.dart';

/// Plays a video's added music next to it, following the video: play, pause, seeking and
/// looping, with the chosen start point and volumes. Without a video (photo stories)
/// the music simply plays from the start point while [play] is on.
class SoundSync {
  SoundSync({required SoundUse use, this.video, required this.muted})
    // ignore: prefer_initializing_formals
    : _use = use;

  SoundUse _use;
  final VideoPlayerController? video;

  /// The app-wide mute switch (the browser starts muted).
  final bool Function() muted;

  AudioTrack? _audio;
  bool _disposed = false;
  bool _ready = false;
  bool _want = false; // photo stories: should be playing
  double? _audioVol, _videoVol;

  SoundUse get use => _use;

  Future<void> start() async {
    final url = _use.sound.audioUrl;
    if (url == null || url.isEmpty) return;
    final a = AudioTrack(url);
    _audio = a;
    try {
      await a.initialize();
    } catch (_) {
      return;
    }
    if (_disposed) {
      await a.dispose();
      return;
    }
    _ready = true;
    video?.addListener(_tick);
    _tick();
  }

  /// New start point or volumes (upload screen sliders).
  void update(SoundUse use) {
    final moved = use.start != _use.start;
    _use = use;
    if (moved && _ready) _audio!.seek(_target());
    _tick();
  }

  /// Photo stories only (videos are followed automatically).
  void play() {
    _want = true;
    if (_ready && video == null) _audio!.seek(_ms(_use.start));
    _tick();
  }

  void pause() {
    _want = false;
    _tick();
  }

  Duration _ms(double seconds) =>
      Duration(milliseconds: (seconds * 1000).round());

  /// Where the song should be now: start point + video position (wrapped around the song).
  Duration _target() {
    final pos = video?.value.position ?? Duration.zero;
    var t = _ms(_use.start) + pos;
    final len = _audio?.duration ?? Duration.zero;
    if (len > Duration.zero && t >= len) {
      t = Duration(milliseconds: t.inMilliseconds % len.inMilliseconds);
    }
    return t;
  }

  void _tick() {
    if (!_ready || _disposed) return;
    final a = _audio!;
    final mute = muted();
    final aVol = mute ? 0.0 : _use.volume / 100;
    if (aVol != _audioVol) {
      _audioVol = aVol;
      a.setVolume(aVol);
    }
    final v = video;
    if (v == null) {
      if (_want && !a.isPlaying) a.play();
      if (!_want && a.isPlaying) a.pause();
      return;
    }
    final vVol = mute ? 0.0 : _use.originalVolume / 100;
    if (vVol != _videoVol) {
      _videoVol = vVol;
      v.setVolume(vVol);
    }
    if (v.value.isPlaying) {
      final target = _target();
      if (!a.isPlaying) {
        a.seek(target);
        a.play();
      } else if ((a.position - target).inMilliseconds.abs() > 450) {
        // The video looped, was dragged, or the two drifted apart.
        a.seek(target);
      }
    } else if (a.isPlaying) {
      a.pause();
    }
  }

  void dispose() {
    _disposed = true;
    video?.removeListener(_tick);
    final a = _audio;
    _audio = null;
    unawaited(a?.dispose());
  }
}
