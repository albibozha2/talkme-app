import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

Future<void> _event(web.EventTarget target, String name, Duration timeout) {
  final done = Completer<void>();
  late final JSFunction listener;
  listener = ((web.Event _) {
    target.removeEventListener(name, listener);
    if (!done.isCompleted) done.complete();
  }).toJS;
  target.addEventListener(name, listener);
  return done.future.timeout(timeout);
}

/// A JPEG cover picture (as a blob: address) from the first frame of a video, or null.
/// [src] is a blob: address of a picked file, or a video on this site.
Future<String?> videoCover(String src) async {
  try {
    final video = web.HTMLVideoElement()
      ..muted = true
      ..playsInline = true
      ..preload = 'auto'
      ..src = src;
    await _event(video, 'loadeddata', const Duration(seconds: 15));
    video.currentTime = math.min(
      0.1,
      video.duration.isFinite ? video.duration / 2 : 0.1,
    );
    await _event(video, 'seeked', const Duration(seconds: 10));
    final vw = video.videoWidth, vh = video.videoHeight;
    if (vw == 0 || vh == 0) return null;
    final scale = math.min(1, 540 / vw);
    final canvas = web.HTMLCanvasElement()
      ..width = (vw * scale).round()
      ..height = (vh * scale).round();
    (canvas.getContext('2d') as web.CanvasRenderingContext2D).drawImage(
      video,
      0,
      0,
      canvas.width,
      canvas.height,
    );
    final blob = Completer<web.Blob?>();
    canvas.toBlob(
      ((web.Blob? b) => blob.complete(b)).toJS,
      'image/jpeg',
      0.8.toJS,
    );
    final b = await blob.future.timeout(const Duration(seconds: 10));
    video.src = '';
    return b == null ? null : web.URL.createObjectURL(b);
  } catch (_) {
    return null;
  }
}

/// Downloads a whole video into the browser's cache, so it plays at once when reached.
Future<void> warmVideo(String url) async {
  try {
    final res = await web.window.fetch(url.toJS).toDart;
    if (res.ok &&
        !(res.headers.get('content-type') ?? '').startsWith('text/html')) {
      await res.arrayBuffer().toDart;
    }
  } catch (_) {}
}
