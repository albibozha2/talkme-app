import 'dart:io';

import 'package:video_compress/video_compress.dart';

/// Re-encodes [path] to 720p before upload: phone videos are often 50–100 MB at 1080p/4K,
/// which plays slowly for everyone. Returns the smaller file, or the original when
/// it is already small, compressing fails, or the result isn't smaller.
/// [onProgress] gets 0..1.
Future<String> compressForUpload(
  String path, {
  void Function(double progress)? onProgress,
}) async {
  final original = File(path);
  final size = await original.length();
  if (size < 6 * 1024 * 1024) return path; // already light enough
  final sub = VideoCompress.compressProgress$.subscribe(
    (p) => onProgress?.call((p / 100).clamp(0, 1).toDouble()),
  );
  try {
    final info = await VideoCompress.compressVideo(
      path,
      quality: VideoQuality.Res1280x720Quality,
      includeAudio: true,
      deleteOrigin: false,
    );
    final out = info?.path;
    if (out == null || !await File(out).exists()) return path;
    return await File(out).length() < size ? out : path;
  } catch (_) {
    return path;
  } finally {
    sub.unsubscribe();
  }
}

Future<void> cancelCompression() => VideoCompress.cancelCompression();
