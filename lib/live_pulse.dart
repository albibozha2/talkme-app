import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'i18n.dart';
import 'push.dart';
import 'web/web_notify.dart';

/// Real-time notifications for the web app (phones get Firebase pushes instead).
/// While the app is open it asks the server "anything new?" every few seconds and shows
/// the same banner as the phone app, a count in the tab title, and, on https with
/// permission, a desktop pop-up when the tab is in the background.
class LivePulse {
  LivePulse(this._container, this._open);

  final ProviderContainer _container;
  final void Function(Map<String, dynamic> data) _open;
  Timer? _timer;
  bool _stopped = false;
  bool _busy = false;
  int _n = 0;
  int _m = 0;
  bool _started = false;

  static const _visibleEvery = Duration(seconds: 5);
  static const _hiddenEvery = Duration(seconds: 20);

  void start() {
    onTabVisible(() {
      if (!_stopped) _tick();
    });
    _tick();
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    setTabTitle('TalkMe');
  }

  void _schedule() {
    _timer?.cancel();
    if (_stopped) return;
    _timer = Timer(tabVisible ? _visibleEvery : _hiddenEvery, _tick);
  }

  Future<void> _tick() async {
    if (_stopped || _busy) return;
    _busy = true;
    try {
      final r = await _container.read(apiProvider).get('/me/pulse', {
        'n': _n,
        'm': _m,
        if (!_started) 'start': 1,
      }) as Map<String, dynamic>;
      if (_stopped) return;
      final notes = (r['notifications'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final msgs = (r['messages'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final unreadN = r['unread_notifications'] as int? ?? 0;
      final unreadM = r['unread_messages'] as int? ?? 0;
      final requests = r['message_requests'] as int? ?? 0;
      _container
          .read(unreadProvider.notifier)
          .setCounts(unreadN, unreadM + requests);
      final total = unreadN + unreadM + requests;
      setTabTitle(total > 0 ? '($total) TalkMe' : 'TalkMe');
      // The first answer only tells us where "now" is; nothing older is announced.
      if (_started && (notes.isNotEmpty || msgs.isNotEmpty)) {
        _container.read(activityProvider.notifier).bump();
        _announce(notes, msgs);
      }
      _n = r['n'] as int? ?? _n;
      _m = r['m'] as int? ?? _m;
      _started = true;
    } catch (e) {
      // Offline or signed out: try again later.
      debugPrint('live updates: $e');
    } finally {
      _busy = false;
      _schedule();
    }
  }

  void _announce(
    List<Map<String, dynamic>> notes,
    List<Map<String, dynamic>> msgs,
  ) {
    // Newest first; messages win because they're usually what people wait for.
    final items = <({String title, String body, Map<String, dynamic> data})>[
      for (final m in msgs)
        (
          title: '${m['title'] ?? ''}',
          body: trServer('${m['body'] ?? ''}'),
          data: {'type': 'message', 'conversation_id': m['conversation_id']},
        ),
      for (final n in notes)
        (
          title: trServer('${n['title'] ?? ''}'),
          body: trServer('${n['body'] ?? ''}'),
          data: {
            'type': n['type'],
            'live_id': n['live_id'],
            'video_id': n['video_id'],
            'username': n['username'],
          },
        ),
    ];
    if (items.isEmpty) return;
    if (!tabVisible) {
      // In the background the browser's own push notification already appears;
      // only without it does the app show a pop-up (never both).
      if (canPopUp && !PushService.instance.webPushActive) {
        for (final i in items.take(3)) {
          popUp(i.title, i.body, () => _open(i.data));
        }
      }
      return;
    }
    final first = items.first;
    final more = items.length - 1;
    showActivityBanner(
      first.title,
      [
        first.body,
        if (more > 0) tr('+{0} more', [more]),
      ].where((s) => s.isNotEmpty).join(' · '),
      first.data,
      _open,
    );
  }
}
