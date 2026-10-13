import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// (percent 0–100, charging) or null when the browser doesn't tell (Safari, Firefox).
Future<({int level, bool charging})?> readBattery() async {
  try {
    final nav = web.window.navigator as JSObject;
    if (!nav.has('getBattery')) return null;
    final b = await (nav.callMethod<JSPromise<JSObject>>('getBattery'.toJS))
        .toDart;
    final level = (b.getProperty<JSNumber>('level'.toJS)).toDartDouble;
    final charging = (b.getProperty<JSBoolean>('charging'.toJS)).toDart;
    return (level: (level * 100).round(), charging: charging);
  } catch (_) {
    return null;
  }
}
