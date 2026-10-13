import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';

/// A short description of this device sent with every request, e.g.
/// "Samsung SM-A037F, Android 13, TalkMe 1.7.1" or "Chrome, Windows, TalkMe web 1.7.1".
/// Shown in "Where you're signed in" and to admins. Only the model and system — nothing else.
class DeviceLabel {
  DeviceLabel._();

  static Future<String>? _label;

  static Future<String> get() => _label ??= _read();

  static String _clean(String s) => s
      .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static Future<String> _read() async {
    const app = 'TalkMe ${AppConfig.appVersion}';
    try {
      final info = DeviceInfoPlugin();
      if (kIsWeb) {
        final w = await info.webBrowserInfo;
        final browser = switch (w.browserName) {
          BrowserName.chrome => 'Chrome',
          BrowserName.firefox => 'Firefox',
          BrowserName.safari => 'Safari',
          BrowserName.edge => 'Edge',
          BrowserName.opera => 'Opera',
          BrowserName.samsungInternet => 'Samsung Internet',
          _ => 'Browser',
        };
        final ua = w.userAgent ?? '';
        final system = RegExp(r'iPhone|iPad').hasMatch(ua)
            ? 'iOS'
            : ua.contains('Android')
            ? 'Android'
            : ua.contains('Windows')
            ? 'Windows'
            : ua.contains('Mac OS')
            ? 'macOS'
            : (w.platform ?? '');
        return _clean('$browser, $system, TalkMe web ${AppConfig.appVersion}');
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final a = await info.androidInfo;
          final model =
              a.model.toLowerCase().startsWith(a.manufacturer.toLowerCase())
              ? a.model
              : '${_cap(a.manufacturer)} ${a.model}';
          return _clean('$model, Android ${a.version.release}, $app');
        case TargetPlatform.iOS:
          final i = await info.iosInfo;
          return _clean('${i.utsname.machine}, iOS ${i.systemVersion}, $app');
        default:
          return app;
      }
    } catch (_) {
      return app;
    }
  }
}
