import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool get tabVisible => web.document.visibilityState == 'visible';

/// iPhone Safari only has notifications once TalkMe is added to the home screen, and every
/// browser only on https.
bool get _supported =>
    web.window.isSecureContext && globalContext.has('Notification');

/// 'granted', 'denied', 'default', or 'unsupported'.
String get popUpPermission =>
    _supported ? web.Notification.permission : 'unsupported';

/// Browsers only allow pop-ups on https, after the person said yes.
bool get canPopUp => popUpPermission == 'granted';

/// On https and the person hasn't said yes or no yet.
bool get canAskPopUp => popUpPermission == 'default';

Future<bool> askPopUpPermission() async {
  if (!_supported) return false;
  if (web.Notification.permission == 'default') {
    try {
      await web.Notification.requestPermission().toDart;
    } catch (_) {}
  }
  return web.Notification.permission == 'granted';
}

void setTabTitle(String title) => web.document.title = title;

void popUp(String title, String body, void Function() onClick) {
  if (!canPopUp) return;
  try {
    final n = web.Notification(
      title,
      web.NotificationOptions(body: body, icon: 'icons/Icon-192.png'),
    );
    n.onclick = ((web.Event _) {
      web.window.focus();
      n.close();
      onClick();
    }).toJS;
  } catch (_) {}
}

void onTabVisible(void Function() callback) {
  web.document.addEventListener(
    'visibilitychange',
    ((web.Event _) {
      if (tabVisible) callback();
    }).toJS,
  );
}

/// iPhone/iPad in the browser (not opened from the home screen), where installing must be done by hand.
bool get showInstallHint {
  final ua = web.window.navigator.userAgent;
  final ios =
      RegExp(r'iPhone|iPad|iPod').hasMatch(ua) ||
      (ua.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1);
  return ios && !web.window.matchMedia('(display-mode: standalone)').matches;
}
