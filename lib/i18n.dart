import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kv.dart';

import 'translations_sq.dart';

/// App languages: English (the texts in the code) and Albanian.
const languages = {'en': 'English', 'sq': 'Shqip'};

String _lang = 'en';

String get currentLanguage => _lang;

/// Translates an English text; {0}, {1}… are replaced by [args].
String tr(String en, [List<Object?> args = const []]) {
  var s = _lang == 'sq' ? (sqTexts[en] ?? en) : en;
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}

/// Translates an error message from the server (fixed texts, plus a few with details in them).
String trServer(String message) {
  if (_lang != 'sq') return message;
  final fixed = sqServer[message];
  if (fixed != null) return fixed;
  final suspended = RegExp(
    r'^Your account has been suspended(?: until (.+?))?\.(?: Reason: (.*))?$',
  ).firstMatch(message);
  if (suspended != null) {
    return 'Llogaria jote është pezulluar'
        '${suspended[1] != null ? ' deri më ${suspended[1]}' : ''}.'
        '${suspended[2] != null ? ' Arsyeja: ${suspended[2]}' : ''}';
  }
  final muted = RegExp(r"^You can't post comments or messages until (.+)\.$")
      .firstMatch(message);
  if (muted != null) {
    return 'Nuk mund të komentosh ose të dërgosh mesazhe deri më ${muted[1]}.';
  }
  final coins = RegExp(r'^Not enough coins\. You have (\d+)\.$')
      .firstMatch(message);
  if (coins != null) return 'Nuk ke mjaftueshëm monedha. Ke ${coins[1]}.';
  return message;
}

/// Loads the saved language, or picks Albanian when the phone is set to Albanian.
Future<void> loadLanguage() async {
  String? saved;
  try {
    saved = await Kv.read('language');
  } catch (_) {}
  _lang = languages.containsKey(saved)
      ? saved!
      : (PlatformDispatcher.instance.locale.languageCode == 'sq' ? 'sq' : 'en');
}

final languageProvider = NotifierProvider<LanguageNotifier, String>(
  LanguageNotifier.new,
);

class LanguageNotifier extends Notifier<String> {
  @override
  String build() => _lang;

  Future<void> set(String lang) async {
    if (!languages.containsKey(lang) || lang == _lang) return;
    _lang = lang;
    state = lang;
    try {
      await Kv.write('language', lang);
    } catch (_) {}
  }
}
