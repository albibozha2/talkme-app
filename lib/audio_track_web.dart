import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class AudioTrack {
  AudioTrack(String url, {bool loop = true})
    : _el = web.HTMLAudioElement()
        ..preload = 'auto'
        ..loop = loop
        ..src = url;
  final web.HTMLAudioElement _el;

  Future<void> initialize() async {
    if (_el.readyState >= 1) return; // metadata already there
    final done = Completer<void>();
    void finish([Object? error]) {
      if (done.isCompleted) return;
      error == null ? done.complete() : done.completeError(error);
    }

    _el.addEventListener('loadedmetadata', ((web.Event _) => finish()).toJS);
    _el.addEventListener(
      'error',
      ((web.Event _) => finish('load failed')).toJS,
    );
    _el.load();
    await done.future.timeout(const Duration(seconds: 20));
  }

  Duration get duration => _el.duration.isFinite
      ? Duration(milliseconds: (_el.duration * 1000).round())
      : Duration.zero;
  Duration get position =>
      Duration(milliseconds: (_el.currentTime * 1000).round());
  bool get isPlaying => !_el.paused;

  /// Played to the end (only when not looping).
  bool get isCompleted => _el.ended;

  Future<void> play() async {
    try {
      await _el.play().toDart;
    } catch (_) {
      // The browser can refuse sound before the person tapped the page; it plays after a tap.
    }
  }

  Future<void> pause() async => _el.pause();
  Future<void> seek(Duration d) async =>
      _el.currentTime = d.inMilliseconds / 1000;

  Future<void> setVolume(double v) async {
    final vol = v.clamp(0, 1).toDouble();
    _el.volume = vol;
    _el.muted = vol == 0;
  }

  Future<void> dispose() async {
    _el.pause();
    _el.removeAttribute('src');
    _el.load();
  }
}
