import 'package:flutter/services.dart';

/// (percent 0–100, charging) or null when unknown.
Future<({int level, bool charging})?> readBattery() async {
  try {
    final r = await const MethodChannel('reelll/battery')
        .invokeMapMethod<String, Object?>('read');
    final level = (r?['level'] as num?)?.toInt();
    if (level == null || level < 0) return null;
    return (level: level, charging: r?['charging'] == true);
  } catch (_) {
    return null; // iOS / desktop: not available
  }
}
