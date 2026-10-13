import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'web/web_notify.dart';

import 'package:flutter/foundation.dart';

import 'widgets/in_app_banner.dart';

/// Firebase project values, passed at build time. Push stays off when they're missing:
///   --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=...
///   --dart-define=FIREBASE_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=...
const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _appId = String.fromEnvironment('FIREBASE_APP_ID');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

/// The web app's own Firebase id and the Web Push key (Firebase > Cloud Messaging > Web Push certificates).
const _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
const _vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');

bool get webPushConfigured =>
    _apiKey.isNotEmpty &&
    _webAppId.isNotEmpty &&
    _vapidKey.isNotEmpty &&
    _senderId.isNotEmpty &&
    _projectId.isNotEmpty;

bool get pushConfigured =>
    _apiKey.isNotEmpty &&
    _appId.isNotEmpty &&
    _senderId.isNotEmpty &&
    _projectId.isNotEmpty;

/// Shown on top of every screen (set as MaterialApp.scaffoldMessengerKey).
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// The app's navigator (set as MaterialApp.navigatorKey); in-app banners use its overlay.
final navigatorKey = GlobalKey<NavigatorState>();

/// The chat that is open on screen right now (no banners for it).
int? openChatId;

/// Shows the in-app banner for a push / live update, unless it's about the open chat.
void showActivityBanner(
  String title,
  String body,
  Map<String, dynamic> data,
  void Function(Map<String, dynamic>)? open,
) {
  final type = data['type']?.toString();
  final chat = int.tryParse('${data['conversation_id'] ?? ''}');
  if (type == 'message' && chat != null && chat == openChatId) return;
  final (icon, color) = bannerStyle(type);
  InAppBanner.show(
    title: title,
    body: body,
    icon: icon,
    color: color,
    // Several messages from one chat in a row: one banner, not a pile.
    dedupeKey: type == 'message' && chat != null ? 'chat:$chat:$body' : null,
    onTap: open == null ? null : () => open(data),
  );
}

/// Unread notification count for the bell badge. Polls while the app is open.
final unreadProvider = NotifierProvider<UnreadNotifier, int>(
  UnreadNotifier.new,
);

/// Total unread (notifications + chats with new messages); the parts are kept for the inbox tabs.
class UnreadNotifier extends Notifier<int> {
  Timer? _timer;
  int notifications = 0;
  int messages = 0;

  @override
  int build() {
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => refresh());
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(refresh);
    return 0;
  }

  Future<void> refresh() async {
    try {
      final api = ref.read(apiProvider);
      final r = await Future.wait([api.unreadCount(), api.messagesUnread()]);
      notifications = r[0];
      messages = r[1];
      state = notifications + messages;
    } catch (_) {}
  }

  void clearNotifications() {
    notifications = 0;
    state = messages;
  }

  /// Counts that came with a live update (web pulse).
  void setCounts(int notifications, int messages) {
    this.notifications = notifications;
    this.messages = messages;
    state = notifications + messages;
  }
}

/// Goes up whenever something new arrives (push or web pulse), so open lists can reload.
final activityProvider = NotifierProvider<ActivityNotifier, int>(
  ActivityNotifier.new,
);

class ActivityNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Registers this phone with Firebase and the TalkMe server, and reacts to pushes.
class PushService {
  PushService._();
  static final instance = PushService._();

  bool _started = false;
  bool _guest = false;
  Future<void> Function(String token)? _register;
  String? _token;
  void Function(Map<String, dynamic> data)? onOpen;

  /// Call after sign-in. [container] is the app-wide provider container.
  /// [guest]: no account yet; the phone is registered for "finish signing up" reminders.
  Future<void> start(ProviderContainer container, {bool guest = false}) async {
    if (kIsWeb) {
      _container = container;
      _guest = guest;
      // Browsers: only once the person allowed notifications (asking needs a tap, see startWeb).
      if (popUpPermission == 'granted') await startWeb();
      return;
    }
    // iPhone: needs an Apple push certificate and a paid developer account (not there when sideloaded).
    if (!pushConfigured || Platform.isIOS) return;
    final api = container.read(apiProvider);
    final platform = Platform.isIOS ? 'ios' : 'android';
    _guest = guest;
    Future<void> register(String token) =>
        (_guest
                ? api.registerGuestDevice(token, platform)
                : api.registerDevice(token, platform))
            .catchError((Object _) {});
    _register = register;
    if (_started) {
      // Signed in (maybe as someone else): attach this phone to the account.
      if (_token != null) await register(_token!);
      return;
    }
    _started = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: _apiKey,
            appId: _appId,
            messagingSenderId: _senderId,
            projectId: _projectId,
          ),
        );
      }
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      _token = await fm.getToken();
      if (_token != null) await _register?.call(_token!);
      fm.onTokenRefresh.listen((t) {
        _token = t;
        _register?.call(t);
      });
      // In the foreground the system doesn't show the notification, so show a banner.
      FirebaseMessaging.onMessage.listen((m) {
        container.read(unreadProvider.notifier).refresh();
        container.read(activityProvider.notifier).bump();
        final n = m.notification;
        if (n == null) return;
        showActivityBanner(n.title ?? '', n.body ?? '', m.data, onOpen);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpen?.call(m.data));
      final initial = await fm.getInitialMessage();
      if (initial != null) onOpen?.call(initial.data);
    } catch (e) {
      debugPrint('Push setup failed: $e');
    }
  }

  ProviderContainer? _container;

  /// The browser is registered for real push notifications (they show by themselves).
  bool get webPushActive => kIsWeb && _token != null;

  /// Web: registers this browser for pushes that arrive while TalkMe is closed.
  /// Call after the person allowed notifications.
  Future<void> startWeb() async {
    final container = _container;
    if (!kIsWeb || container == null || !webPushConfigured) return;
    final api = container.read(apiProvider);
    Future<void> register(String token) =>
        (_guest
                ? api.registerGuestDevice(token, 'web')
                : api.registerDevice(token, 'web'))
            .catchError((Object _) {});
    _register = register;
    if (_started) {
      if (_token != null) await register(_token!);
      return;
    }
    _started = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: _apiKey,
            appId: _webAppId,
            messagingSenderId: _senderId,
            projectId: _projectId,
            authDomain: '$_projectId.firebaseapp.com',
          ),
        );
      }
      final fm = FirebaseMessaging.instance;
      _token = await fm.getToken(vapidKey: _vapidKey);
      if (_token != null) await register(_token!);
      fm.onTokenRefresh.listen((t) {
        _token = t;
        _register?.call(t);
      });
      // While the page is open the live updates already show a banner; just refresh counts.
      FirebaseMessaging.onMessage.listen((_) {
        container.read(unreadProvider.notifier).refresh();
        container.read(activityProvider.notifier).bump();
      });
    } catch (e) {
      _started = false;
      debugPrint('Web push setup failed: $e');
    }
  }

  /// Call before signing out so this phone stops receiving the old account's pushes.
  Future<void> unregister(Api api) async {
    final t = _token;
    if (t == null) return;
    try {
      await api.unregisterDevice(t);
    } catch (_) {}
  }
}
