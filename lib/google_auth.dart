import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The OAuth "Web client ID" from Google Cloud. Comes from the server (config.php
/// 'google_client_ids'), so it can be set without rebuilding the app; a build-time
/// --dart-define=GOOGLE_WEB_CLIENT_ID=... is the fallback. Empty = no Google button.
const _builtInClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
String _clientId = _builtInClientId;

String get googleWebClientId => _clientId;

/// Not on iPhone: Google sign-in there needs its own iOS client ID in Info.plist, or tapping it crashes.
bool get googleSignInEnabled =>
    _clientId.isNotEmpty &&
    (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS);

/// Sign in with Google: hands back Google's ID token, which the server checks.
class GoogleAuth {
  GoogleAuth._();

  static Future<void>? _ready;

  /// Uses the client ID the server announces (call before showing the button).
  static void configure(String serverClientId) {
    if (_ready == null && serverClientId.isNotEmpty) _clientId = serverClientId;
  }

  static Future<void> ready() => _ready ??= GoogleSignIn.instance.initialize(
    // Browser: this site's client; phones: tokens are made for the server (same Web client ID).
    clientId: kIsWeb ? googleWebClientId : null,
    serverClientId: kIsWeb ? null : googleWebClientId,
  );

  /// Phones: shows Google's account picker. Null when the person cancels.
  static Future<String?> pickAccount() async {
    await ready();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// Browser: ID tokens from Google's own button (see GoogleWebButton).
  static Stream<String> webTokens() async* {
    await ready();
    await for (final e in GoogleSignIn.instance.authenticationEvents) {
      if (e is GoogleSignInAuthenticationEventSignIn) {
        final token = e.user.authentication.idToken;
        if (token != null) yield token;
      }
    }
  }

  /// Forget the Google account on this device (on sign-out), so the picker shows next time.
  static Future<void> signOut() async {
    if (!googleSignInEnabled || _ready == null) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
