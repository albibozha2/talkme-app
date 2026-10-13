import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kv.dart';

/// Viewer preferences for the video feed, remembered on the phone.
class PlaybackPrefs {
  const PlaybackPrefs({
    this.speed = 1,
    this.autoScroll = false,
    this.clear = false,
  });
  final double speed;

  /// Move to the next video when one finishes.
  final bool autoScroll;

  /// Hide buttons and text while watching (not remembered).
  final bool clear;

  PlaybackPrefs copyWith({double? speed, bool? autoScroll, bool? clear}) =>
      PlaybackPrefs(
        speed: speed ?? this.speed,
        autoScroll: autoScroll ?? this.autoScroll,
        clear: clear ?? this.clear,
      );
}

final playbackProvider = NotifierProvider<PlaybackNotifier, PlaybackPrefs>(
  PlaybackNotifier.new,
);

class PlaybackNotifier extends Notifier<PlaybackPrefs> {
  @override
  PlaybackPrefs build() {
    _load();
    return const PlaybackPrefs();
  }

  Future<void> _load() async {
    try {
      final raw = await Kv.read('playback');
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      state = state.copyWith(
        speed: (j['speed'] as num?)?.toDouble(),
        autoScroll: j['auto_scroll'] as bool?,
      );
    } catch (_) {}
  }

  Future<void> _save() => Kv.write(
    'playback',
    jsonEncode({'speed': state.speed, 'auto_scroll': state.autoScroll}),
  );

  void setSpeed(double v) {
    state = state.copyWith(speed: v);
    _save();
  }

  void setAutoScroll(bool v) {
    state = state.copyWith(autoScroll: v);
    _save();
  }

  void setClear(bool v) => state = state.copyWith(clear: v);
}

/// Recent searches (newest first), remembered on the phone.
class SearchHistory {
  static Future<List<String>> load() async {
    try {
      final raw = await Kv.read('search_history');
      return raw == null ? [] : (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> add(String term) async {
    final list = (await load())
      ..remove(term)
      ..insert(0, term);
    final kept = list.take(12).toList();
    await _write(kept);
    return kept;
  }

  static Future<List<String>> remove(String term) async {
    final list = (await load())..remove(term);
    await _write(list);
    return list;
  }

  static Future<void> clear() => _write([]);

  static Future<void> _write(List<String> list) =>
      Kv.write('search_history', jsonEncode(list));
}
