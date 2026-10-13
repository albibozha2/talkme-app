/// Build-time settings. Override with --dart-define, e.g.
/// flutter build apk --dart-define=API_BASE=https://api.yourdomain.com/api
class AppConfig {
  /// The live server (https; the app falls back to http by itself if https is ever unreachable).
  /// For local testing: --dart-define=API_BASE=http://10.0.2.2/reelll/api (emulator + XAMPP).
  static const apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://talkme.space/api',
  );

  /// Must match `version:` in pubspec.yaml; compared with min_app_version from the server.
  static const appVersion = '2.0.0';
}
