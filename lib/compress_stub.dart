/// Browsers can't re-encode video: the original file is uploaded.
Future<String> compressForUpload(
  String path, {
  void Function(double progress)? onProgress,
}) async => path;

Future<void> cancelCompression() async {}
