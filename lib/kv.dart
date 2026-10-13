import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small key/value store: secure storage on phones, browser storage on the web
/// (secure storage in browsers needs HTTPS, which the site may not have).
class Kv {
  static const _secure = FlutterSecureStorage();

  static Future<String?> read(String key) async {
    if (kIsWeb) return (await SharedPreferences.getInstance()).getString(key);
    try {
      return await _secure.read(key: key);
    } catch (_) {
      return null;
    }
  }

  /// Writes [value], or deletes the key when it's null.
  static Future<void> write(String key, String? value) async {
    try {
      if (kIsWeb) {
        final p = await SharedPreferences.getInstance();
        value == null ? await p.remove(key) : await p.setString(key, value);
      } else {
        value == null
            ? await _secure.delete(key: key)
            : await _secure.write(key: key, value: value);
      }
    } catch (_) {}
  }
}

/// A picked file as an upload field. On the web the "path" is a browser blob URL, so the bytes are sent.
Future<MultipartFile> uploadFile(
  String path, {
  DioMediaType? contentType,
  String? filename,
}) async {
  if (!kIsWeb) return MultipartFile.fromFile(path, contentType: contentType);
  final bytes = await XFile(path).readAsBytes();
  return MultipartFile.fromBytes(
    bytes,
    filename: filename ?? 'upload',
    contentType: contentType,
  );
}
