import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features.dart';

import 'api.dart';
import 'models.dart';
import 'push.dart';
import 'google_auth.dart';

/// Server-side app settings (maintenance mode, minimum version, limits).
final remoteConfigProvider = FutureProvider<RemoteConfig>((ref) async {
  final cfg = await ref.watch(apiProvider).config();
  Features.update(cfg.features);
  return cfg;
});

/// Bumped when the feature switches were re-read (rebuilds what depends on them).
class FeaturesVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final featuresVersionProvider = NotifierProvider<FeaturesVersion, int>(
  FeaturesVersion.new,
);

/// Re-reads Admin → Features (when the app comes back to the front).
Future<void> refreshFeatures(WidgetRef ref) async {
  try {
    final cfg = await ref.read(apiProvider).config();
    Features.update(cfg.features);
    ref.read(featuresVersionProvider.notifier).bump();
  } catch (_) {}
}

/// The signed-in user, or null when signed out.
final sessionProvider = AsyncNotifierProvider<SessionNotifier, AppUser?>(
  SessionNotifier.new,
);

class SessionNotifier extends AsyncNotifier<AppUser?> {
  /// Set when the server ended the session (ban, expired token); shown on the sign-in screen.
  String? signedOutReason;

  Api get _api => ref.read(apiProvider);

  @override
  Future<AppUser?> build() async {
    _api.onSignedOut = (message) {
      signedOutReason = message;
      state = const AsyncData(null);
    };
    if (!await _api.hasToken()) return null;
    try {
      return await _api.me();
    } on ApiException catch (e) {
      // Keep the token on network errors so the user stays signed in offline.
      if (e.status == 401 || e.status == 403) return null;
      rethrow;
    }
  }

  Future<void> login(String login, String password) async {
    signedOutReason = null;
    state = AsyncData(await _api.login(login, password));
  }

  Future<void> loginWithGoogle(String idToken, {String invite = ''}) async {
    signedOutReason = null;
    state = AsyncData(await _api.loginWithGoogle(idToken, invite: invite));
  }

  /// Second step for accounts with two-step sign-in.
  Future<void> loginWithCode(String ticket, String code) async {
    signedOutReason = null;
    state = AsyncData(await _api.loginWithCode(ticket, code));
  }

  Future<void> resetPassword(String login, String code, String password) async {
    signedOutReason = null;
    state = AsyncData(await _api.resetPassword(login, code, password));
  }

  Future<void> register(
    String username,
    String email,
    String password, {
    String invite = '',
    bool acceptTerms = false,
  }) async {
    signedOutReason = null;
    state = AsyncData(
      await _api.register(
        username,
        email,
        password,
        invite: invite,
        acceptTerms: acceptTerms,
      ),
    );
  }

  Future<void> logout() async {
    await PushService.instance.unregister(_api);
    await _api.logout();
    await GoogleAuth.signOut();
    state = const AsyncData(null);
  }

  void setUser(AppUser user) => state = AsyncData(user);
}

/// Bumped after the signed-in user posts or deletes a video so profile grids reload.
final myVideosVersionProvider = NotifierProvider<VersionNotifier, int>(
  VersionNotifier.new,
);

class VersionNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

/// True when [current] is lower than [minimum] (both like "1.2.3").
bool isVersionTooOld(String current, String minimum) {
  List<int> parts(String v) =>
      v.split('.').map((p) => int.tryParse(p) ?? 0).toList()..addAll([0, 0, 0]);
  final a = parts(current), b = parts(minimum);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return false;
}
