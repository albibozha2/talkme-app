/// Build-time settings. Override with --dart-define, e.g.
/// flutter build apk --dart-define=API_BASE=https://api.yourdomain.com/api
class AppConfig {
  /// The live server. The app switches to https:// automatically once the site supports it.
  /// For local testing: --dart-define=API_BASE=http://10.0.2.2/reelll/api (emulator + XAMPP).
  static const apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://talkme.space/api',
  );

  /// Must match `version:` in pubspec.yaml; compared with min_app_version from the server.
  static const appVersion = '1.9.6';
}
