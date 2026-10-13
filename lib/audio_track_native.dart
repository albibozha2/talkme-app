import 'package:video_player/video_player.dart';

class AudioTrack {
  AudioTrack(String url, {this.loop = true})
    : _c = VideoPlayerController.networkUrl(Uri.parse(url));
  final VideoPlayerController _c;
  final bool loop;

  Future<void> initialize() async {
    await _c.initialize();
    await _c.setLooping(loop);
  }

  Duration get duration => _c.value.duration;
  Duration get position => _c.value.position;
  bool get isPlaying => _c.value.isPlaying;

  /// Played to the end (only when not looping).
  bool get isCompleted => _c.value.isCompleted;
  Future<void> play() => _c.play();
  Future<void> pause() => _c.pause();
  Future<void> seek(Duration d) => _c.seekTo(d);
  Future<void> setVolume(double v) => _c.setVolume(v.clamp(0, 1).toDouble());
  Future<void> dispose() => _c.dispose();
}
