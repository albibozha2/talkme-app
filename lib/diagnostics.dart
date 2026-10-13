import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'battery.dart';
import 'config.dart';
import 'kv.dart';

/// Diagnostics ("Share diagnostics" in Privacy & safety).
/// On by default for error reports only: when something goes wrong, the app version, device model
/// and battery level at that moment are sent, so problems on specific phones can be fixed.
/// People are told once on first start and can turn it off at any time (then nothing is sent).
/// The short daily check runs only for people who turned the switch on themselves.
class Diagnostics {
  Diagnostics._();

  static const _key = 'diagnostics_on';
  static bool enabled = true;

  /// The person turned the switch on themselves (not just the default).
  static bool chosen = false;
  static final _api = Api();
  static final _recent = <String, DateTime>{};
  static bool _sending = false;

  /// Call once at start-up: reads the choice and catches errors.
  static Future<void> init() async {
    final saved = await Kv.read(_key);
    enabled = saved != '0';
    chosen = saved == '1';
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(details.exceptionAsString(), details.stack?.toString());
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report('$error', '$stack');
      return false; // keep the normal handling
    };
    if (chosen) unawaited(_dailyCheck());
  }

  static Future<void> setEnabled(bool on) async {
    enabled = on;
    chosen = on;
    await Kv.write(_key, on ? '1' : '0');
    if (on) unawaited(_send('report', 'Diagnostics turned on'));
  }

  /// An error, sent only when diagnostics are on (the same one at most every 10 minutes).
  static void report(String message, [String? stack]) {
    if (!enabled) return;
    final key = message.length > 200 ? message.substring(0, 200) : message;
    final now = DateTime.now();
    _recent.removeWhere(
      (_, t) => now.difference(t) > const Duration(minutes: 10),
    );
    if (_recent.containsKey(key)) return;
    _recent[key] = now;
    unawaited(_send('error', message, stack));
  }

  static Future<void> _dailyCheck() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (await Kv.read('diagnostics_day') == today) return;
    await Kv.write('diagnostics_day', today);
    await _send('report', 'Daily check');
  }

  static Future<void> _send(
    String kind,
    String message, [
    String? stack,
  ]) async {
    if (_sending || !await _api.hasToken()) return;
    _sending = true;
    try {
      final b = await readBattery();
      await _api.post('/diagnostics', {
        'kind': kind,
        'message': message.length > 500 ? message.substring(0, 500) : message,
        'stack': ?(stack == null
            ? null
            : (stack.length > 8000 ? stack.substring(0, 8000) : stack)),
        'app_version': AppConfig.appVersion,
        'battery': ?b?.level,
        'charging': ?b?.charging,
      });
    } catch (_) {
      // Never let reporting cause more trouble.
    } finally {
      _sending = false;
    }
  }
}

/// One-time notice on first start that error reports are on, with a way to turn them off.
Future<bool> diagnosticsNoticeDue() async =>
    await Kv.read('diagnostics_notice') == null &&
    !Diagnostics.chosen &&
    Diagnostics.enabled;

Future<void> diagnosticsNoticeShown() => Kv.write('diagnostics_notice', '1');
