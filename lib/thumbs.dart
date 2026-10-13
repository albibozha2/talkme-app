import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'web/web_media.dart';

/// A JPEG thumbnail (first frame) of a video, or null: a file path on phones,
/// a blob: address in the browser (the upload code accepts both).
/// The hosting server can't make thumbnails itself, so the app makes them.
Future<String?> makeThumbnail(String videoPath) async {
  if (kIsWeb) return videoCover(videoPath);
  try {
    final dir = await getTemporaryDirectory();
    final dest =
        '${dir.path}/thumb_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final ok = await FcNativeVideoThumbnail().saveThumbnailToFile(
      srcFile: videoPath,
      destFile: dest,
      width: 540,
      height: 960,
      format: 'jpeg',
      quality: 80,
    );
    return ok ? dest : null;
  } catch (_) {
    return null;
  }
}
