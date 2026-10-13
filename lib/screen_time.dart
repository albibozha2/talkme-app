import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'i18n.dart';
import 'kv.dart';

/// "1 h 5 min" / "12 min".
String formatMinutes(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return tr('{0} min', [m]);
  return m == 0 ? tr('{0} h', [h]) : tr('{0} h {1} min', [h, m]);
}

/// Counts how long the app is open each day (on this device), and calls [onLimit] once a day
/// when the daily limit is reached and [onBreak] after [breakMinutes] of use without a pause.
class ScreenTime with WidgetsBindingObserver {
  ScreenTime._();
  static final instance = ScreenTime._();

  static const _usageKey = 'screen_time_usage'; // {"2026-10-10": seconds}
  static const _limitKey = 'screen_time_limit'; // minutes, 0 = off
  static const _breakKey = 'screen_time_break'; // minutes, 0 = off
  static const _shownKey =
      'screen_time_limit_shown'; // day the limit reminder was shown
  static const _step = 15; // seconds per tick

  Map<String, int> _usage = {};
  int limitMinutes = 0;
  int breakMinutes = 0;
  String? _limitShownOn;
  Future<void>? _loading;
  Timer? _timer;
  bool _active = true;
  DateTime? _pausedAt;
  int _sessionSeconds = 0;

  void Function()? onLimit;
  void Function(int minutes)? onBreak;

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> load() => _loading ??= () async {
    try {
      final raw = jsonDecode(await Kv.read(_usageKey) ?? '{}') as Map;
      _usage = raw.map((k, v) => MapEntry(k as String, (v as num).toInt()));
    } catch (_) {}
    limitMinutes = int.tryParse(await Kv.read(_limitKey) ?? '') ?? 0;
    breakMinutes = int.tryParse(await Kv.read(_breakKey) ?? '') ?? 0;
    _limitShownOn = await Kv.read(_shownKey);
  }();

  void start() {
    load();
    WidgetsBinding.instance.addObserver(this);
    _timer ??= Timer.periodic(const Duration(seconds: _step), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    _save();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active == _active) return;
    _active = active;
    if (!active) {
      _pausedAt = DateTime.now();
      _save();
    } else if (_pausedAt != null &&
        DateTime.now().difference(_pausedAt!) > const Duration(minutes: 5)) {
      // A real pause: the break timer starts over.
      _sessionSeconds = 0;
    }
  }

  void _tick() {
    if (!_active || _loading == null) return;
    final today = _day(DateTime.now());
    final used = (_usage[today] ?? 0) + _step;
    _usage[today] = used;
    _sessionSeconds += _step;
    if (_sessionSeconds % 60 == 0) _save();
    if (limitMinutes > 0 &&
        used >= limitMinutes * 60 &&
        _limitShownOn != today) {
      _limitShownOn = today;
      Kv.write(_shownKey, today);
      onLimit?.call();
    }
    if (breakMinutes > 0 && _sessionSeconds >= breakMinutes * 60) {
      _sessionSeconds = 0;
      onBreak?.call(breakMinutes);
    }
  }

  void _save() {
    // Keep two weeks.
    final cutoff = _day(DateTime.now().subtract(const Duration(days: 14)));
    _usage.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    Kv.write(_usageKey, jsonEncode(_usage));
  }

  Duration get today => Duration(seconds: _usage[_day(DateTime.now())] ?? 0);

  /// Oldest first, ending today.
  List<(DateTime, Duration)> lastDays(int n) {
    final now = DateTime.now();
    return [
      for (var i = n - 1; i >= 0; i--)
        () {
          final d = DateTime(now.year, now.month, now.day - i);
          return (d, Duration(seconds: _usage[_day(d)] ?? 0));
        }(),
    ];
  }

  Future<void> setLimit(int minutes) async {
    limitMinutes = minutes;
    // A new limit may remind again today.
    _limitShownOn = null;
    await Kv.write(_shownKey, null);
    await Kv.write(_limitKey, '$minutes');
  }

  Future<void> setBreak(int minutes) async {
    breakMinutes = minutes;
    _sessionSeconds = 0;
    await Kv.write(_breakKey, '$minutes');
  }
}
