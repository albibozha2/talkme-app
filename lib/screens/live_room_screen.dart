import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/battle_layer.dart';
import '../widgets/gifts.dart';
import '../vip.dart';
import 'profile_screen.dart';
import '../i18n.dart';
import 'leaderboard_screen.dart';
import '../battery.dart';

/// One live room, for the host (camera + mic) or a viewer.
///
/// Chat, hearts and gift announcements travel over LiveKit data messages; coins
/// are always charged through the API first, then announced to the room.
class LiveRoomScreen extends ConsumerStatefulWidget {
  const LiveRoomScreen.host({super.key, required LiveSession this.session})
    : liveId = null;
  const LiveRoomScreen.viewer({super.key, required int this.liveId})
    : session = null;

  final LiveSession? session;
  final int? liveId;

  bool get isHost => session != null;

  @override
  ConsumerState<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _ChatLine {
  _ChatLine(
    this.name,
    this.text, {
    this.system = false,
    this.gift,
    this.userId,
    this.username,
    this.level = 0,
    this.mod = false,
  });
  final String name, text;
  final bool system;
  final String? gift;

  /// Who wrote it (lets the host / moderators act on them).
  final int? userId;
  final String? username;
  final int level;
  final bool mod;
}

class _LiveRoomScreenState extends ConsumerState<LiveRoomScreen> {
  final _room = Room(
    roomOptions: const RoomOptions(
      adaptiveStream: true,
      dynacast: true,
      defaultCameraCaptureOptions: CameraCaptureOptions(
        params: VideoParametersPresets.h720_169,
      ),
      defaultVideoPublishOptions: VideoPublishOptions(simulcast: true),
    ),
  );
  EventsListener<RoomEvent>? _events;
  LiveSession? _session;
  Object? _error;
  bool _ended = false;
  bool _micOn = true;
  CameraPosition _camera = CameraPosition.front;
  Timer? _ping;

  /// Streamer only: this phone's battery, checked every minute (never sent anywhere).
  Timer? _batteryTimer;
  ({int level, bool charging})? _battery;
  bool _batteryDismissed = false;

  Future<void> _checkBattery() async {
    final b = await readBattery();
    if (!mounted) return;
    setState(() {
      // Warn again if it dropped further after a dismiss.
      if (b != null &&
          _battery != null &&
          b.level <= 10 &&
          _battery!.level > 10) {
        _batteryDismissed = false;
      }
      _battery = b;
    });
  }

  final _chat = <_ChatLine>[];
  final _input = TextEditingController();
  final _gifts = GlobalKey<GiftOverlayState>();
  final _hearts = GlobalKey<_FloatingHeartsState>();
  int _giftCoins = 0;
  final _battleKey = GlobalKey<BattleLayerState>();
  bool _inBattle = false;
  int? _goalCoins;
  String _goalText = '';
  int _goalProgress = 0;
  String? _pinned;
  Set<int> _mods = {};
  int _myLevel = 0;

  /// TikTok-style extras: follow button, top gifters by the viewer count,
  /// "X joined" strip, tap-to-like counter and a one-tap gift.
  bool _following = true;
  List<RankEntry> _topGifters = const [];
  Timer? _topTimer, _joinedTimer, _likeTimer;
  String? _joined;
  int _joinedLevel = 0;
  int _likes = 0, _pendingLikes = 0;
  Gift? _quickGift;

  /// Multi-guest live. Viewer: my request status (none / requested / active) and
  /// whether my camera is on stage. Host: people asking to join and the guests on camera.
  String _guestStatus = 'none';
  bool _onStage = false;
  bool _reconnecting = false;
  List<LiveGuest> _guestList = const [];
  Timer? _guestPoll;

  bool get _canModerate => widget.isHost || _session?.role == 'mod';
  int? get _hostId => _live?.host.id;

  LiveInfo? get _live => _session?.live;
  String get _hostIdentity => 'u${_live?.host.id}';

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _start();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _ping?.cancel();
    _batteryTimer?.cancel();
    _topTimer?.cancel();
    _joinedTimer?.cancel();
    _likeTimer?.cancel();
    _guestPoll?.cancel();
    // Leaving the screen also leaves the stage / cancels a request.
    if (!widget.isHost && _guestStatus != 'none' && _live != null) {
      ref.read(apiProvider).leaveLiveStage(_live!.id).ignore();
    }
    _events?.dispose();
    _input.dispose();
    _room.disconnect().then((_) => _room.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final api = ref.read(apiProvider);
      final session = widget.session ?? await api.joinLive(widget.liveId!);
      if (!mounted) return;
      setState(() {
        _session = session;
        _giftCoins = session.live.giftsCoins;
        _goalCoins = session.live.goalCoins;
        _goalText = session.live.goalText;
        _goalProgress = session.live.goalProgress;
        _pinned = session.live.pinnedMessage;
        _mods = session.mods.toSet();
        _following = widget.isHost || session.following;
        _guestStatus =
            session.guestStatus == 'active' ||
                session.guestStatus == 'requested'
            ? session.guestStatus
            : 'none';
        _myLevel = widget.isHost
            ? (ref.read(sessionProvider).value?.level ?? 0)
            : session.level;
        // What was said before I joined.
        for (final c in session.comments.reversed.take(60).toList().reversed) {
          _chat.add(
            c.type == 'gift'
                ? _ChatLine(
                    c.name ?? tr('Someone'),
                    _sentText(c.giftName ?? '', c.giftQuantity),
                    gift: c.giftIcon,
                    userId: c.userId,
                    username: c.username,
                    level: c.level,
                  )
                : c.mod
                ? _ChatLine('🛡️ ${tr('Moderator')}', c.body, system: true)
                : _ChatLine(
                    c.name ?? tr('Someone'),
                    c.body,
                    userId: c.userId,
                    username: c.username,
                    level: c.level,
                    mod:
                        c.userId != null &&
                        (_mods.contains(c.userId) ||
                            c.userId == session.live.host.id),
                  ),
          );
        }
      });
      if (widget.isHost) {
        api.liveMods().then((m) {
          if (mounted) setState(() => _mods = m.map((u) => u.id).toSet());
        }).ignore();
      }
      _events = _room.createListener()
        ..on<ParticipantConnectedEvent>((_) => setState(() {}))
        ..on<ParticipantDisconnectedEvent>((e) {
          if (!widget.isHost && e.participant.identity == _hostIdentity) {
            setState(() => _ended = true);
          } else {
            setState(() {});
          }
        })
        ..on<TrackSubscribedEvent>((_) {
          setState(() {});
          // Someone's camera appeared: keep the host's guest list (and badge) current.
          if (widget.isHost) _loadGuests();
        })
        ..on<TrackUnsubscribedEvent>((_) => setState(() {}))
        ..on<LocalTrackPublishedEvent>((_) => setState(() {}))
        ..on<LocalTrackUnpublishedEvent>((_) => setState(() {}))
        ..on<TrackMutedEvent>((_) => setState(() {}))
        ..on<TrackUnmutedEvent>((_) => setState(() {}))
        ..on<DataReceivedEvent>(_onData)
        ..on<RoomDisconnectedEvent>((_) {
          // A guest briefly reconnects with a camera ticket: that's not the live ending.
          if (mounted && !widget.isHost && !_reconnecting) {
            setState(() => _ended = true);
          }
        });
      await _room.connect(session.url, session.token);
      if (widget.isHost) {
        await _room.localParticipant?.setCameraEnabled(true);
        await _room.localParticipant?.setMicrophoneEnabled(true);
        _ping = Timer.periodic(const Duration(seconds: 25), (_) => _sendPing());
        _sendPing();
        _checkBattery();
        _batteryTimer = Timer.periodic(
          const Duration(minutes: 1),
          (_) => _checkBattery(),
        );
        _addLine(
          _ChatLine(
            '',
            tr('You are live! Say hi to your viewers.'),
            system: true,
          ),
        );
        // Download the gift animations now so they play straight away.
        api.gifts().then(preloadGiftAnimations).ignore();
      } else {
        if (!_room.remoteParticipants.values.any(
          (p) => p.identity == _hostIdentity,
        )) {
          setState(() => _ended = true);
        }
        _broadcast({'t': 'join'});
        // VIPs (Gold and up) see their own entrance too.
        if ((vipOf(_myLevel)?.minLevel ?? 0) >= 15) {
          _gifts.currentState?.entrance(
            _myName,
            ref.read(sessionProvider).value?.avatarUrl,
            _myLevel,
          );
        }
        _addLine(
          _ChatLine('', tr('Tap the screen to send likes ❤️'), system: true),
        );
        api.gifts().then((g) {
          preloadGiftAnimations(g);
          if (g.isNotEmpty && mounted) {
            setState(
              () => _quickGift = g.reduce((a, b) => a.coins <= b.coins ? a : b),
            );
          }
        }).ignore();
      }
      if (widget.isHost) {
        _loadGuests();
      } else if (_guestStatus == 'active') {
        _goOnStage(); // came back to a live where I'm still a guest
      } else if (_guestStatus == 'requested') {
        _pollGuestStatus();
      }
      _loadTop();
      _topTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _loadTop(),
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _sendPing() async {
    final live = _live;
    if (live == null) return;
    try {
      final info = await ref
          .read(apiProvider)
          .pingLive(live.id, _room.remoteParticipants.length);
      if (mounted) setState(() => _giftCoins = info.giftsCoins);
    } on ApiException catch (e) {
      if (e.status == 410 && mounted) {
        _ping?.cancel();
        _batteryTimer?.cancel();
        setState(() => _ended = true);
      }
    } catch (_) {}
  }

  String get _myName =>
      ref.read(sessionProvider).value?.displayName ?? tr('Someone');

  void _broadcast(Map<String, dynamic> msg, {bool reliable = true}) {
    final me = ref.read(sessionProvider).value;
    final data = utf8.encode(
      jsonEncode({
        ...msg,
        'n': _myName,
        'a': me?.avatarUrl,
        'u': me?.id,
        'un': me?.username,
        'l': _myLevel,
      }),
    );
    _room.localParticipant
        ?.publishData(data, reliable: reliable, topic: msg['t'] as String)
        .catchError((Object _) {});
  }

  void _onData(DataReceivedEvent e) {
    try {
      final m = jsonDecode(utf8.decode(e.data)) as Map<String, dynamic>;
      final name = (m['n'] as String?) ?? tr('Someone');
      final uid = (m['u'] as num?)?.toInt();
      final uname = m['un'] as String?;
      final level = (m['l'] as num?)?.toInt() ?? 0;
      final isMod = uid != null && (_mods.contains(uid) || uid == _hostId);
      final me = ref.read(sessionProvider).value?.id;
      switch (m['t']) {
        case 'guestreq':
          // Someone asked to join on camera (the host reloads the list).
          if (widget.isHost) {
            _loadGuests();
            showToast(context, tr('{0} wants to join your live', [name]));
          }
        case 'guestoff':
          if (widget.isHost) _loadGuests();
        case 'guest':
          // The host accepted or removed someone; act if it's me.
          if (e.participant?.identity == _hostIdentity &&
              (m['id'] as num?)?.toInt() == me &&
              !widget.isHost) {
            if (m['on'] == true) {
              _goOnStage();
            } else {
              _leaveStage(tellServer: false, removed: true);
            }
          }
        case 'pk':
          // Battle scores from the host (only the host may send these).
          if (e.participant?.identity == _hostIdentity) {
            _battleKey.currentState?.applyRemote(
              m['b'] == null ? null : Map<String, dynamic>.from(m['b'] as Map),
            );
          }
        case 'chat':
          // Moderator messages sent from the admin panel stand out.
          _addLine(
            _ChatLine(
              name,
              (m['m'] as String?) ?? '',
              system: m['mod'] == true,
              userId: uid,
              username: uname,
              level: level,
              mod: isMod,
            ),
          );
        case 'join':
          // Shown in the strip above the chat (like TikTok), not as a chat line.
          _showJoined(name, level);
          if ((vipOf(level)?.minLevel ?? 0) >= 15) {
            _gifts.currentState?.entrance(name, m['a'] as String?, level);
          }
        case 'follow':
          _addLine(
            _ChatLine(
              name,
              tr('followed the host'),
              system: true,
              userId: uid,
              username: uname,
              level: level,
            ),
          );
        case 'share':
          _addLine(
            _ChatLine(
              name,
              tr('shared the live'),
              system: true,
              userId: uid,
              username: uname,
              level: level,
            ),
          );
        case 'goal':
          setState(() {
            final c = (m['gc'] as num?)?.toInt() ?? 0;
            _goalCoins = c > 0 ? c : null;
            _goalText = (m['gt'] as String?) ?? '';
            _goalProgress = 0;
          });
        case 'pin':
          final text = (m['m'] as String?) ?? '';
          setState(() => _pinned = text.isEmpty ? null : text);
        case 'modset':
          final id = (m['id'] as num?)?.toInt();
          if (id != null) {
            setState(() => m['on'] == true ? _mods.add(id) : _mods.remove(id));
          }
        case 'heart':
          final n = ((m['c'] as num?)?.toInt() ?? 1).clamp(1, 50);
          _hearts.currentState?.burst(n.clamp(1, 5));
          setState(() => _likes += n);
        case 'gift':
          final gift = Gift(
            id: 0,
            name: m['g'] as String,
            icon: m['i'] as String,
            coins: (m['c'] as num).toInt(),
          );
          final q = ((m['q'] as num?)?.toInt() ?? 1).clamp(1, 99);
          _gifts.currentState?.show(
            GiftEvent(
              gift: gift,
              senderName: name,
              senderAvatar: m['a'] as String?,
              quantity: q,
              senderLevel: level,
            ),
          );
          _addLine(
            _ChatLine(
              name,
              _sentText(gift.name, q),
              gift: gift.icon,
              userId: uid,
              username: uname,
              level: level,
            ),
          );
          setState(() {
            _giftCoins += gift.coins * q;
            _goalProgress += gift.coins * q;
          });
          if (_inBattle) _battleKey.currentState?.refresh();
          _loadTop();
      }
    } catch (_) {}
  }

  void _addLine(_ChatLine line) {
    if (!mounted) return;
    setState(() {
      _chat.add(line);
      if (_chat.length > 60) _chat.removeAt(0);
    });
  }

  Future<void> _sendChat() async {
    var text = _input.text.trim();
    if (text.isEmpty) return;
    if (text.length > 200) text = text.substring(0, 200);
    _input.clear();
    // Saved first (so people joining later see it, and the word filter / mutes apply),
    // then sent to everyone in the room.
    final liveId = _live?.id;
    if (liveId != null) {
      try {
        text = await ref.read(apiProvider).liveComment(liveId, text);
      } on ApiException catch (e) {
        // An older server without saved chat still lets the message through.
        if (e.status != 404) {
          if (mounted) showError(context, e);
          return;
        }
      } catch (_) {
        // Offline for a moment: still send it to the room.
      }
    }
    if (!mounted) return;
    _broadcast({'t': 'chat', 'm': text});
    _addLine(
      _ChatLine(
        _myName,
        text,
        userId: ref.read(sessionProvider).value?.id,
        username: ref.read(sessionProvider).value?.username,
        level: _myLevel,
        mod: _canModerate,
      ),
    );
  }

  /// Tap the screen to like: shown at once, sent to the room in small batches.
  void _sendHeart() {
    if (widget.isHost || _ended) return;
    HapticFeedback.selectionClick();
    _hearts.currentState?.burst(1);
    setState(() => _likes++);
    _pendingLikes++;
    _likeTimer ??= Timer(const Duration(milliseconds: 500), () {
      _likeTimer = null;
      final n = _pendingLikes;
      _pendingLikes = 0;
      if (n > 0) _broadcast({'t': 'heart', 'c': n}, reliable: false);
    });
  }

  // ---------- guests on camera ----------

  Future<void> _loadGuests() async {
    final live = _live;
    if (live == null || !widget.isHost) return;
    try {
      final list = await ref.read(apiProvider).liveGuests(live.id);
      if (mounted) setState(() => _guestList = list);
    } catch (_) {}
  }

  /// Viewer: ask to join the host on camera (or cancel / leave).
  Future<void> _stageButton() async {
    final live = _live;
    if (live == null) return;
    if (_guestStatus != 'none') {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            _onStage ? tr('Leave the stage?') : tr('Cancel your request?'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Stay')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_onStage ? tr('Leave') : tr('Cancel request')),
            ),
          ],
        ),
      );
      if (leave == true) await _leaveStage();
      return;
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.group_add_rounded, size: 44),
              const SizedBox(height: 10),
              Text(
                tr('Join {0} on camera?', [live.host.displayName]),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  'The host sees your request. If they accept, your camera and microphone turn on and everyone in the live can see and hear you.',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(tr('Request to join')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final status = await ref.read(apiProvider).requestToJoinLive(live.id);
      if (!mounted) return;
      setState(() => _guestStatus = status);
      _broadcast({'t': 'guestreq'});
      if (status == 'active') {
        _goOnStage();
      } else {
        showToast(context, tr('Request sent. Wait for the host to accept.'));
        _pollGuestStatus();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// While waiting, check now and then in case the host's message was missed.
  void _pollGuestStatus() {
    _guestPoll?.cancel();
    _guestPoll = Timer.periodic(const Duration(seconds: 6), (_) async {
      final live = _live;
      if (live == null || _guestStatus != 'requested') {
        _guestPoll?.cancel();
        return;
      }
      try {
        final s = await ref.read(apiProvider).myGuestStatus(live.id);
        if (!mounted) return;
        if (s == 'active') {
          _goOnStage();
        } else if (s != 'requested') {
          _guestPoll?.cancel();
          setState(() => _guestStatus = 'none');
          if (s == 'declined') {
            showToast(context, tr('The host can’t add you right now.'));
          }
        }
      } catch (_) {}
    });
  }

  /// Accepted: turn on my camera and microphone in this live.
  Future<void> _goOnStage() async {
    final live = _live;
    if (live == null || _onStage) return;
    _guestPoll?.cancel();
    setState(() {
      _guestStatus = 'active';
      _onStage = true;
    });
    HapticFeedback.mediumImpact();
    final lp = _room.localParticipant;
    try {
      if (lp == null || !lp.permissions.canPublish) throw StateError('ticket');
      await lp.setCameraEnabled(true);
      await lp.setMicrophoneEnabled(true);
    } catch (_) {
      // The live server didn't update my permissions: reconnect with a guest ticket.
      try {
        final t = await ref.read(apiProvider).guestTicket(live.id);
        _reconnecting = true;
        await _room.disconnect();
        await _room.connect(t.url, t.token);
        _reconnecting = false;
        await _room.localParticipant?.setCameraEnabled(true);
        await _room.localParticipant?.setMicrophoneEnabled(true);
      } catch (e) {
        _reconnecting = false;
        if (mounted) {
          setState(() {
            _onStage = false;
            _guestStatus = 'none';
          });
          showError(context, e);
        }
        return;
      }
    }
    if (mounted) {
      setState(() {});
      showToast(context, tr('You are on camera in this live'));
    }
  }

  /// Leave the stage (or cancel the request). [removed]: the host took me off.
  Future<void> _leaveStage({
    bool tellServer = true,
    bool removed = false,
  }) async {
    final live = _live;
    _guestPoll?.cancel();
    final wasOn = _onStage;
    setState(() {
      _onStage = false;
      _guestStatus = 'none';
    });
    if (wasOn) {
      try {
        await _room.localParticipant?.setCameraEnabled(false);
        await _room.localParticipant?.setMicrophoneEnabled(false);
      } catch (_) {}
    }
    if (tellServer && live != null) {
      try {
        await ref.read(apiProvider).leaveLiveStage(live.id);
      } catch (_) {}
      _broadcast({'t': 'guestoff'});
    }
    if (removed && mounted) {
      showToast(context, tr('The host ended your time on camera'));
    }
  }

  /// Host: who's asking to join, and who's on camera.
  Future<void> _guestsSheet() async {
    await _loadGuests();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          Future<void> act(LiveGuest g, String action) async {
            try {
              final list = await ref
                  .read(apiProvider)
                  .answerGuest(_live!.id, g.user.id, action);
              setState(() => _guestList = list);
              setSheet(() {});
              _broadcast({
                't': 'guest',
                'id': g.user.id,
                'on': action == 'accept',
              });
            } catch (e) {
              if (context.mounted) showError(context, e);
            }
          }

          final active = _guestList.where((g) => g.status == 'active').toList();
          final asking = _guestList
              .where((g) => g.status == 'requested')
              .toList();
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .7,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                children: [
                  ListTile(
                    title: Text(
                      tr('Guests ({0}/3)', [active.length]),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    subtitle: Text(
                      tr(
                        'Viewers can ask to join you on camera. Up to 3 at a time.',
                      ),
                    ),
                  ),
                  for (final g in active)
                    ListTile(
                      leading: Avatar(
                        url: g.user.avatarUrl,
                        name: g.user.displayName,
                        radius: 20,
                      ),
                      title: Text(g.user.displayName),
                      subtitle: Text(tr('On camera')),
                      trailing: OutlinedButton(
                        onPressed: () => act(g, 'remove'),
                        child: Text(tr('Remove')),
                      ),
                    ),
                  if (asking.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        tr('Asking to join'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  for (final g in asking)
                    ListTile(
                      leading: Avatar(
                        url: g.user.avatarUrl,
                        name: g.user.displayName,
                        radius: 20,
                      ),
                      title: Text(g.user.displayName),
                      subtitle: Text('@${g.user.username}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: tr('Decline'),
                            onPressed: () => act(g, 'decline'),
                            icon: const Icon(Icons.close_rounded),
                          ),
                          IconButton.filled(
                            tooltip: tr('Accept'),
                            onPressed: active.length >= 3
                                ? null
                                : () => act(g, 'accept'),
                            icon: const Icon(Icons.check_rounded),
                          ),
                        ],
                      ),
                    ),
                  if (asking.isEmpty && active.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        tr(
                          'Nobody has asked yet. Tell your viewers to tap the join button.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Everyone on camera besides the host (up to 3), in a stable order.
  List<_StageTile> get _stageTiles {
    final tiles = <_StageTile>[];
    final lp = _room.localParticipant;
    if (!widget.isHost && _onStage && lp != null) {
      final t = lp.videoTrackPublications.firstOrNull?.track;
      tiles.add(
        _StageTile(
          lp.identity,
          _myName,
          t is VideoTrack ? t : null,
          micOn: lp.isMicrophoneEnabled(),
          local: true,
        ),
      );
    }
    for (final p in _room.remoteParticipants.values) {
      if (p.identity == _hostIdentity) continue;
      VideoTrack? track;
      for (final pub in p.videoTrackPublications) {
        if (pub.subscribed && pub.track != null) track = pub.track;
      }
      if (track == null && !p.isCameraEnabled()) continue;
      tiles.add(
        _StageTile(
          p.identity,
          p.name.isEmpty ? tr('Guest') : p.name,
          track,
          micOn: p.isMicrophoneEnabled(),
        ),
      );
    }
    tiles.sort((a, b) => a.identity.compareTo(b.identity));
    return tiles.take(3).toList();
  }

  /// Where seat [i] of [n] sits on screen (seat 0 is the host). 2 people side by side,
  /// 3–4 in a 2x2 grid, like TikTok's multi-guest live.
  Rect _seat(int i, int n, Size size, EdgeInsets pad) {
    final top = pad.top + 92;
    final w = size.width / 2;
    if (n <= 2) {
      final h = (w * 4 / 3).clamp(160.0, size.height * .46);
      return Rect.fromLTWH(i * w + (i > 0 ? 1 : 0), top, w - 1, h);
    }
    final h = (w * 1.0).clamp(130.0, size.height * .27);
    final col = i % 2, row = i ~/ 2;
    return Rect.fromLTWH(
      col * w + (col > 0 ? 1 : 0),
      top + row * (h + 2),
      w - 1,
      h,
    );
  }

  Future<void> _loadTop() async {
    final live = _live;
    if (live == null) return;
    try {
      final top = await ref.read(apiProvider).liveTop(live.id);
      if (mounted) setState(() => _topGifters = top.take(3).toList());
    } catch (_) {}
  }

  void _showJoined(String name, [int level = 0]) {
    _joinedTimer?.cancel();
    setState(() {
      _joined = name;
      _joinedLevel = level;
    });
    _joinedTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _joined = null);
    });
  }

  Future<void> _follow() async {
    final live = _live;
    if (live == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _following = true);
    try {
      await ref.read(apiProvider).setFollow(live.host.username, true);
      _broadcast({'t': 'follow'});
      _addLine(_ChatLine(_myName, tr('followed the host'), system: true));
    } catch (e) {
      if (mounted) {
        setState(() => _following = false);
        showError(context, e);
      }
    }
  }

  Future<void> _share() async {
    final live = _live;
    if (live == null) return;
    final base = ref.read(apiProvider).server.replaceAll(RegExp(r'/api$'), '');
    await SharePlus.instance.share(
      ShareParams(
        text: tr('{0} is LIVE on TalkMe 🔴\n{1}/u/{2}', [
          live.host.displayName,
          base,
          live.host.username,
        ]),
      ),
    );
    if (!widget.isHost) _broadcast({'t': 'share'});
  }

  /// Who is watching (from the room itself, so it is always current).
  Future<void> _showViewers() async {
    final people = _room.remoteParticipants.values
        .where((p) => p.identity != _hostIdentity)
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .6,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 6),
                child: Text(
                  tr('{0} watching', [compactCount(people.length)]),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_topGifters.isNotEmpty) ...[
                for (final e in _topGifters) RankTile(entry: e, dense: true),
                const Divider(),
              ],
              for (final p in people)
                ListTile(
                  dense: true,
                  leading: Avatar(
                    url: null,
                    name: p.name.isEmpty ? p.identity : p.name,
                    radius: 16,
                  ),
                  title: Text(p.name.isEmpty ? tr('Someone') : p.name),
                ),
              if (people.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('Nobody is watching yet.')),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Host toolbar "⋯": goal, pinned message, top gifters, share.
  Future<void> _hostMore() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flip_camera_android_rounded),
              title: Text(tr('Flip camera')),
              onTap: () => Navigator.pop(context, 'flip'),
            ),
            ListTile(
              leading: const Icon(Icons.flag_rounded),
              title: Text(tr('Gift goal')),
              onTap: () => Navigator.pop(context, 'goal'),
            ),
            ListTile(
              leading: const Icon(Icons.push_pin_rounded),
              title: Text(tr('Pinned message')),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.emoji_events_rounded),
              title: Text(tr('Top gifters in this live')),
              onTap: () => Navigator.pop(context, 'top'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: Text(tr('Share')),
              onTap: () => Navigator.pop(context, 'share'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'flip':
        await _flipCamera();
      case 'goal':
        await _setGoal();
      case 'pin':
        await _pin(null);
      case 'top':
        await _showTop();
      case 'share':
        await _share();
    }
  }

  /// One tap sends the cheapest gift (TikTok's rose button).
  Future<void> _sendQuickGift() async {
    final live = _live, g = _quickGift;
    if (live == null || g == null) return;
    try {
      await ref.read(apiProvider).sendGift(g.id, liveId: live.id);
      HapticFeedback.mediumImpact();
      final me = ref.read(sessionProvider).value;
      _announceGift(
        GiftEvent(
          gift: g,
          senderName: me?.displayName ?? tr('You'),
          senderAvatar: me?.avatarUrl,
          senderLevel: _myLevel,
        ),
      );
    } on ApiException catch (e) {
      // Not enough coins: the gift sheet offers to recharge.
      if (e.status == 402) {
        await _gift();
      } else if (mounted) {
        showError(context, e);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _gift() async {
    final live = _live;
    if (live == null) return;
    await showGiftSheet(context, liveId: live.id, onSent: _announceGift);
  }

  /// "sent Rose" / "sent Rose x10".
  static String _sentText(String gift, int quantity) => quantity > 1
      ? '${tr('sent {0}', [gift])} x$quantity'
      : tr('sent {0}', [gift]);

  void _announceGift(GiftEvent sent) {
    if (!mounted) return;
    _gifts.currentState?.show(sent);
    _addLine(
      _ChatLine(
        _myName,
        _sentText(sent.gift.name, sent.quantity),
        gift: sent.gift.icon,
        level: _myLevel,
      ),
    );
    setState(() {
      _giftCoins += sent.total;
      _goalProgress += sent.total;
    });
    _broadcast({
      't': 'gift',
      'g': sent.gift.name,
      'i': sent.gift.icon,
      'c': sent.gift.coins,
      if (sent.quantity > 1) 'q': sent.quantity,
    });
    if (_inBattle) _battleKey.currentState?.refresh();
    _loadTop();
  }

  Future<void> _setGoal() async {
    final live = _live;
    if (live == null) return;
    final coins = TextEditingController(text: _goalCoins?.toString() ?? '1000');
    final text = TextEditingController(text: _goalText);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Gift goal')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: coins,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('Coins'),
                prefixText: '🪙 ',
              ),
            ),
            TextField(
              controller: text,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: tr('What happens when it’s reached?'),
              ),
            ),
          ],
        ),
        actions: [
          if (_goalCoins != null)
            TextButton(
              onPressed: () {
                coins.text = '0';
                Navigator.pop(context, true);
              },
              child: Text(tr('Remove goal')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Save')),
          ),
        ],
      ),
    );
    if (save != true) return;
    final c = int.tryParse(coins.text.trim()) ?? 0;
    try {
      final info = await ref
          .read(apiProvider)
          .setLiveGoal(live.id, c, text.text.trim());
      if (!mounted) return;
      setState(() {
        _goalCoins = info.goalCoins;
        _goalText = info.goalText;
        _goalProgress = 0;
      });
      _broadcast({'t': 'goal', 'gc': info.goalCoins ?? 0, 'gt': info.goalText});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _pin(String? message) async {
    final live = _live;
    if (live == null) return;
    var text = message;
    if (text == null) {
      final c = TextEditingController(text: _pinned ?? '');
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Pinned message')),
          content: TextField(controller: c, maxLength: 200, autofocus: true),
          actions: [
            if (_pinned != null)
              TextButton(
                onPressed: () {
                  c.text = '';
                  Navigator.pop(context, true);
                },
                child: Text(tr('Unpin')),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Pin')),
            ),
          ],
        ),
      );
      if (ok != true) return;
      text = c.text.trim();
    }
    try {
      await ref.read(apiProvider).pinLiveMessage(live.id, text);
      if (!mounted) return;
      setState(() => _pinned = text!.isEmpty ? null : text);
      _broadcast({'t': 'pin', 'm': text});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _showTop() async {
    final live = _live;
    if (live == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => FutureBuilder<List<RankEntry>>(
        future: ref.read(apiProvider).liveTop(live.id),
        builder: (context, snap) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .6,
            ),
            child: !snap.hasData
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 20, bottom: 6),
                        child: Text(
                          tr('Top gifters in this live'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (snap.data!.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(tr('No gifts yet. Be the first!')),
                        ),
                      for (final e in snap.data!)
                        RankTile(entry: e, dense: true),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Tap a name in the chat: profile for everyone; pin / mute / remove / moderator for the host and moderators.
  Future<void> _lineActions(_ChatLine line) async {
    final me = ref.read(sessionProvider).value?.id;
    final uid = line.userId;
    final username = line.username;
    if (uid == null || username == null || uid == me) return;
    final targetIsStaff = uid == _hostId || _mods.contains(uid);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                line.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(tr('View profile')),
              onTap: () => Navigator.pop(context, 'profile'),
            ),
            if (_canModerate && !line.system && line.gift == null)
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: Text(tr('Pin this message')),
                onTap: () => Navigator.pop(context, 'pin'),
              ),
            if (_canModerate && !targetIsStaff) ...[
              ListTile(
                leading: const Icon(Icons.speaker_notes_off_outlined),
                title: Text(tr('Mute in chat')),
                onTap: () => Navigator.pop(context, 'mute'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.person_remove_outlined,
                  color: AppColors.like,
                ),
                title: Text(tr('Remove from live')),
                onTap: () => Navigator.pop(context, 'kick'),
              ),
            ],
            if (widget.isHost && uid != _hostId)
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(
                  _mods.contains(uid)
                      ? tr('Remove moderator')
                      : tr('Make moderator'),
                ),
                onTap: () => Navigator.pop(context, 'mod'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final api = ref.read(apiProvider);
    final live = _live!;
    try {
      switch (choice) {
        case 'profile':
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProfileScreen(username: username),
            ),
          );
        case 'pin':
          await _pin('${line.name}: ${line.text}');
        case 'mute':
          await api.liveMute(live.id, uid, true);
          if (mounted) {
            showToast(
              context,
              tr('{0} can no longer chat in this live', [line.name]),
            );
          }
        case 'kick':
          await api.liveKick(live.id, uid);
          if (mounted) showToast(context, tr('{0} was removed', [line.name]));
        case 'mod':
          final on = !_mods.contains(uid);
          await api.setLiveMod(username, on);
          setState(() => on ? _mods.add(uid) : _mods.remove(uid));
          _broadcast({'t': 'modset', 'id': uid, 'on': on});
          if (mounted) {
            showToast(
              context,
              on
                  ? tr('{0} is now a moderator', [line.name])
                  : tr('Moderator removed'),
            );
          }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _flipCamera() async {
    final track =
        _room.localParticipant?.videoTrackPublications.firstOrNull?.track;
    if (track is! LocalVideoTrack) return;
    final next = _camera == CameraPosition.front
        ? CameraPosition.back
        : CameraPosition.front;
    try {
      await track.setCameraPosition(next);
      setState(() => _camera = next);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleMic() async {
    _micOn = !_micOn;
    await _room.localParticipant?.setMicrophoneEnabled(_micOn);
    setState(() {});
  }

  Future<void> _close() async {
    if (!widget.isHost || _ended) {
      Navigator.pop(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('End your live?')),
        content: Text(tr('Everyone watching will be disconnected.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Keep going')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('End live')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _ping?.cancel();
    _batteryTimer?.cancel();
    Map<String, dynamic>? summary;
    try {
      summary = await ref.read(apiProvider).endLive(_live!.id);
    } catch (_) {}
    // Mark ended first so leaving the screen doesn't ask "End your live?" again.
    setState(() => _ended = true);
    await _room.disconnect();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _SummaryDialog(summary: summary, giftCoins: _giftCoins),
    );
    if (mounted) Navigator.pop(context);
  }

  VideoTrack? get _videoTrack {
    if (widget.isHost) {
      final t =
          _room.localParticipant?.videoTrackPublications.firstOrNull?.track;
      return t is VideoTrack ? t : null;
    }
    for (final p in _room.remoteParticipants.values) {
      if (p.identity != _hostIdentity) continue;
      for (final pub in p.videoTrackPublications) {
        if (pub.subscribed && pub.track != null) return pub.track;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final live = _live;
    final track = _videoTrack;
    final pad = MediaQuery.paddingOf(context);
    final screen = MediaQuery.sizeOf(context);
    final guests = _inBattle ? const <_StageTile>[] : _stageTiles;
    final stage = guests.isNotEmpty;
    final seats = stage ? (guests.length + 1 <= 2 ? 2 : 4) : 1;
    final asking = _guestList.where((g) => g.status == 'requested').length;
    final viewers = widget.isHost
        ? _room.remoteParticipants.length
        : max(0, _room.remoteParticipants.length);

    return PopScope(
      canPop: _ended || !widget.isHost,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: darkSystemUi,
        child: Theme(
          data: buildTheme(Brightness.dark),
          child: Scaffold(
            backgroundColor: Colors.black,
            resizeToAvoidBottomInset: true,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Video (during a PK battle the battle layer shows both hosts instead)
                // One renderer for the whole time: during a PK it moves into the left half
                // (a second renderer of the same camera stays black in browsers).
                // Dark stage behind the guest grid (always present so the host's
                // video below keeps its place in the tree).
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: stage ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF1B1035),
                              Color(0xFF0B1230),
                              AppColors.ink,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (track != null)
                  Positioned.fromRect(
                    rect: _inBattle
                        ? BattleLayer.myPane(context)
                        : stage
                        ? _seat(0, seats, screen, pad)
                        : Offset.zero & screen,
                    child: VideoTrackRenderer(track, fit: VideoViewFit.cover),
                  )
                else if (!_inBattle)
                  _Waiting(
                    host: live?.host,
                    error: _error,
                    connecting: _error == null && !_ended,
                  ),
                // Guests on camera, each in their seat.
                for (var i = 0; i < guests.length; i++)
                  Positioned.fromRect(
                    key: ValueKey('seat-${guests[i].identity}'),
                    rect: _seat(i + 1, seats, screen, pad),
                    child: _GuestSeat(
                      tile: guests[i],
                      onRemove: widget.isHost
                          ? () {
                              final uid = int.tryParse(
                                guests[i].identity.substring(1),
                              );
                              final g = _guestList
                                  .where((x) => x.user.id == uid)
                                  .firstOrNull;
                              if (g == null) return;
                              ref
                                  .read(apiProvider)
                                  .answerGuest(_live!.id, g.user.id, 'remove')
                                  .then((l) {
                                    if (mounted) setState(() => _guestList = l);
                                  })
                                  .ignore();
                              _broadcast({
                                't': 'guest',
                                'id': g.user.id,
                                'on': false,
                              });
                            }
                          : null,
                    ),
                  ),
                // An open seat invites viewers to ask (TikTok shows "+" seats).
                if (stage &&
                    guests.length == 2 &&
                    !widget.isHost &&
                    _guestStatus == 'none')
                  Positioned.fromRect(
                    rect: _seat(3, seats, screen, pad),
                    child: _OpenSeat(onTap: _stageButton),
                  ),
                // The host's name on their seat in the grid.
                if (stage && live != null)
                  Positioned(
                    left: _seat(0, seats, screen, pad).left + 6,
                    top: _seat(0, seats, screen, pad).bottom - 28,
                    child: IgnorePointer(
                      child: _SeatName(name: live.host.displayName, host: true),
                    ),
                  ),
                // Tap anywhere to like (viewers).
                if (!widget.isHost && !_ended)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _sendHeart,
                    ),
                  ),
                if (live != null && !_ended)
                  BattleLayer(
                    key: _battleKey,
                    liveId: live.id,
                    isHost: widget.isHost,
                    myTrack: track,
                    onActive: (v) => setState(() => _inBattle = v),
                    onLike: widget.isHost ? null : _sendHeart,
                    onState: widget.isHost
                        ? (b) => _broadcast({'t': 'pk', 'b': b})
                        : null,
                  ),
                // Shade for the chat over the video (the PK screen has its own dark background).
                if (!_inBattle)
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, .2, .55, 1],
                          colors: [
                            Color(0x99000000),
                            Colors.transparent,
                            Colors.transparent,
                            Color(0xCC000000),
                          ],
                        ),
                      ),
                    ),
                  ),
                FloatingHearts(key: _hearts),
                GiftOverlay(key: _gifts),
                // Top bar: host + follow, top gifters, viewers, close
                Positioned(
                  top: pad.top + 8,
                  left: 10,
                  right: 4,
                  child: Row(
                    children: [
                      if (live != null)
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _HostPill(
                              live: live,
                              coins: _giftCoins,
                              onFollow: _following ? null : _follow,
                              onTap: widget.isHost
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ProfileScreen(
                                          username: live.host.username,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _showTop,
                        child: SizedBox(
                          width: 26.0 * _topGifters.length + 6,
                          height: 32,
                          child: Stack(
                            children: [
                              for (var i = _topGifters.length - 1; i >= 0; i--)
                                Positioned(
                                  left: 26.0 * i,
                                  child: _RankAvatar(entry: _topGifters[i]),
                                ),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _showViewers,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.person_rounded,
                                color: Colors.white,
                                size: 15,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                compactCount(viewers),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: _close,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // Second row: LIVE, rankings, likes
                Positioned(
                  top: pad.top + 56,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      const LiveBadge(),
                      const SizedBox(width: 6),
                      _TopChip(
                        icon: Icons.emoji_events_rounded,
                        color: AppColors.amber,
                        text: tr('Top gifters'),
                        onTap: _showTop,
                      ),
                      if (_likes > 0) ...[
                        const SizedBox(width: 6),
                        _TopChip(
                          icon: Icons.favorite_rounded,
                          color: AppColors.like,
                          text: compactCount(_likes),
                        ),
                      ],
                    ],
                  ),
                ),
                if (live != null && live.title.isNotEmpty && !_inBattle)
                  Positioned(
                    top: pad.top + 92,
                    left: 14,
                    right: 80,
                    child: IgnorePointer(
                      child: Text(
                        live.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(blurRadius: 8)],
                        ),
                      ),
                    ),
                  ),
                if (widget.isHost &&
                    !_batteryDismissed &&
                    _battery != null &&
                    !_battery!.charging &&
                    _battery!.level <= 20)
                  Positioned(
                    top: pad.top + 92,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                        decoration: BoxDecoration(
                          color: _battery!.level <= 10
                              ? AppColors.like
                              : const Color(0xE6B45309),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.battery_alert_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              tr(
                                'Battery {0}% · plug in to keep your live going',
                                [_battery!.level],
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              iconSize: 16,
                              color: Colors.white,
                              onPressed: () =>
                                  setState(() => _batteryDismissed = true),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!_inBattle && (_goalCoins != null || _pinned != null))
                  Positioned(
                    top: pad.top + 132,
                    left: 12,
                    right: 70,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_goalCoins != null)
                          _GoalBar(
                            coins: _goalCoins!,
                            text: _goalText,
                            progress: _goalProgress,
                          ),
                        if (_pinned != null) ...[
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: _canModerate ? () => _pin(null) : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.amber.withValues(alpha: .6),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.push_pin_rounded,
                                    size: 15,
                                    color: AppColors.amber,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _pinned!,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                // Chat, "joined" strip and the bottom toolbar
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: _inBattle || stage ? 170 : 230,
                          child: ShaderMask(
                            shaderCallback: (r) => const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.white],
                              stops: [0, .25],
                            ).createShader(r),
                            blendMode: BlendMode.dstIn,
                            child: ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.fromLTRB(12, 30, 90, 4),
                              itemCount: _chat.length,
                              itemBuilder: (context, i) {
                                final line = _chat[_chat.length - 1 - i];
                                return GestureDetector(
                                  onTap: () => _lineActions(line),
                                  child: _ChatBubble(line: line),
                                );
                              },
                            ),
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, a) => SlideTransition(
                            position: Tween(
                              begin: const Offset(-1, 0),
                              end: Offset.zero,
                            ).animate(a),
                            child: FadeTransition(opacity: a, child: child),
                          ),
                          child: _joined == null
                              ? const SizedBox(height: 0, key: ValueKey('none'))
                              : Align(
                                  key: ValueKey(_joined),
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.fromLTRB(
                                      12,
                                      2,
                                      0,
                                      2,
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      4,
                                      22,
                                      4,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      gradient: LinearGradient(
                                        colors: [
                                          (vipOf(_joinedLevel)?.color ??
                                                  const Color(0xFF7C3AED))
                                              .withValues(alpha: .8),
                                          const Color(0x007C3AED),
                                        ],
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (vipOf(_joinedLevel) != null) ...[
                                          VipBadge(
                                            level: _joinedLevel,
                                            small: true,
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Text(
                                          tr('{0} joined', [_joined!]),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _input,
                                  maxLength: 200,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _sendChat(),
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: tr('Add comment…'),
                                    counterText: '',
                                    isDense: true,
                                    fillColor: Colors.white.withValues(
                                      alpha: .14,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(30),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(30),
                                      borderSide: BorderSide.none,
                                    ),
                                    suffixIcon: IconButton(
                                      onPressed: _sendChat,
                                      icon: const Icon(
                                        Icons.send_rounded,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (widget.isHost) ...[
                                const SizedBox(width: 8),
                                Badge(
                                  isLabelVisible: asking > 0,
                                  label: Text('$asking'),
                                  child: _CircleButton(
                                    icon: Icons.group_add_rounded,
                                    onTap: _guestsSheet,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _PkButton(
                                  onTap: () =>
                                      _battleKey.currentState?.openInvite(),
                                ),
                                const SizedBox(width: 8),
                                _CircleButton(
                                  icon: _micOn
                                      ? Icons.mic_rounded
                                      : Icons.mic_off_rounded,
                                  onTap: _toggleMic,
                                  active: !_micOn,
                                ),
                                const SizedBox(width: 8),
                                _CircleButton(
                                  icon: Icons.more_horiz_rounded,
                                  onTap: _hostMore,
                                ),
                              ] else if (_onStage) ...[
                                // On camera as a guest: my own controls.
                                const SizedBox(width: 8),
                                _CircleButton(
                                  icon: Icons.flip_camera_android_rounded,
                                  onTap: _flipCamera,
                                ),
                                const SizedBox(width: 8),
                                _CircleButton(
                                  icon:
                                      _room.localParticipant
                                              ?.isMicrophoneEnabled() ??
                                          false
                                      ? Icons.mic_rounded
                                      : Icons.mic_off_rounded,
                                  onTap: () async {
                                    final lp = _room.localParticipant;
                                    await lp?.setMicrophoneEnabled(
                                      !(lp.isMicrophoneEnabled()),
                                    );
                                    setState(() {});
                                  },
                                ),
                                const SizedBox(width: 8),
                                _CircleButton(
                                  icon: Icons.logout_rounded,
                                  active: true,
                                  onTap: _stageButton,
                                ),
                              ] else ...[
                                if (_session?.guestsEnabled ?? false) ...[
                                  const SizedBox(width: 8),
                                  _CircleButton(
                                    icon: _guestStatus == 'requested'
                                        ? Icons.hourglass_top_rounded
                                        : Icons.group_add_rounded,
                                    active: _guestStatus == 'requested',
                                    onTap: _stageButton,
                                  ),
                                ],
                                if (_quickGift != null) ...[
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message:
                                        '${_quickGift!.name} · ${_quickGift!.coins}',
                                    child: Material(
                                      color: Colors.white.withValues(
                                        alpha: .16,
                                      ),
                                      shape: const CircleBorder(),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: _sendQuickGift,
                                        child: SizedBox(
                                          width: 42,
                                          height: 42,
                                          child: Center(
                                            child: Text(
                                              _quickGift!.icon,
                                              style: const TextStyle(
                                                fontSize: 22,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _gift,
                                  child: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      gradient: AppColors.goldGradient,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.amber.withValues(
                                            alpha: .5,
                                          ),
                                          blurRadius: 14,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.card_giftcard_rounded,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _CircleButton(
                                  icon: Icons.reply_rounded,
                                  flip: true,
                                  onTap: _share,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_ended)
                  _EndedOverlay(
                    isHost: widget.isHost,
                    onClose: () => Navigator.pop(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({this.host, this.error, required this.connecting});
  final AppUser? host;
  final Object? error;
  final bool connecting;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.emeraldDeep, AppColors.ink],
      ),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (host != null)
              Avatar(
                url: host!.avatarUrl,
                name: host!.displayName,
                radius: 46,
                live: true,
              ),
            const SizedBox(height: 18),
            if (error != null)
              Text(
                tr("Couldn't connect to the live.\n{0}", [error]),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              )
            else if (connecting) ...[
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(tr('Connecting…'), style: TextStyle(color: Colors.white70)),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.line});
  final _ChatLine line;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: line.gift != null
            ? AppColors.amber.withValues(alpha: .28)
            : Colors.black.withValues(alpha: .32),
        borderRadius: BorderRadius.circular(16),
      ),
      child: line.system
          ? Text(
              line.name.isEmpty ? line.text : '${line.name} ${line.text}',
              style: const TextStyle(
                color: AppColors.emeraldLight,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            )
          : Text.rich(
              TextSpan(
                children: [
                  if (line.mod)
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.shield_rounded,
                          size: 14,
                          color: AppColors.emeraldLight,
                        ),
                      ),
                    ),
                  if (line.level > 0)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: LevelBadge(level: line.level, small: true),
                      ),
                    ),
                  TextSpan(
                    text: '${line.name}  ',
                    style: TextStyle(
                      // VIPs from Silver up stand out in the chat.
                      color: (vipOf(line.level)?.minLevel ?? 0) >= 10
                          ? vipOf(line.level)!.colors.last
                          : Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: line.text),
                  if (line.gift != null)
                    TextSpan(
                      text: ' ${line.gift}',
                      style: const TextStyle(fontSize: 17),
                    ),
                ],
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
            ),
    ),
  );
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.flip = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  /// Mirror the icon (TikTok's share arrow points right).
  final bool flip;

  @override
  Widget build(BuildContext context) => Material(
    color: active
        ? AppColors.like.withValues(alpha: .7)
        : Colors.white.withValues(alpha: .16),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        width: 42,
        height: 42,
        child: Transform.flip(
          flipX: flip,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    ),
  );
}

class _StageTile {
  _StageTile(
    this.identity,
    this.name,
    this.track, {
    this.micOn = true,
    this.local = false,
  });
  final String identity, name;
  final VideoTrack? track;
  final bool micOn, local;
}

class _SeatName extends StatelessWidget {
  const _SeatName({required this.name, this.host = false, this.micOn = true});
  final String name;
  final bool host, micOn;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (host) ...[
          const Icon(Icons.star_rounded, size: 13, color: AppColors.amber),
          const SizedBox(width: 3),
        ],
        if (!micOn) ...[
          const Icon(Icons.mic_off_rounded, size: 13, color: Colors.white70),
          const SizedBox(width: 3),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One guest's video in the grid, with their name (and a remove button for the host).
class _GuestSeat extends StatelessWidget {
  const _GuestSeat({required this.tile, this.onRemove});
  final _StageTile tile;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(
        color: const Color(0xFF151A2E),
        child: tile.track != null
            ? VideoTrackRenderer(tile.track!, fit: VideoViewFit.cover)
            : Center(child: Avatar(url: null, name: tile.name, radius: 26)),
      ),
      Positioned(
        left: 6,
        bottom: 6,
        child: _SeatName(name: tile.name, micOn: tile.micOn),
      ),
      if (onRemove != null)
        Positioned(
          right: 2,
          top: 2,
          child: IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: tr('Remove'),
            onPressed: onRemove,
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 18,
              shadows: [Shadow(blurRadius: 6)],
            ),
          ),
        ),
    ],
  );
}

/// An empty seat in the grid: viewers tap it to ask to join.
class _OpenSeat extends StatelessWidget {
  const _OpenSeat({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: ColoredBox(
      color: Colors.white.withValues(alpha: .05),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white38, width: 1.5),
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              tr('Join'),
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Host name, coins and a red "+" follow button, in one dark capsule.
class _HostPill extends StatelessWidget {
  const _HostPill({
    required this.live,
    required this.coins,
    this.onFollow,
    this.onTap,
  });
  final LiveInfo live;
  final int coins;
  final VoidCallback? onFollow, onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 4, 3),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Avatar(
            url: live.host.avatarUrl,
            name: live.host.displayName,
            radius: 17,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  live.host.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CoinIcon(size: 11),
                    const SizedBox(width: 3),
                    Text(
                      compactCount(coins),
                      style: const TextStyle(
                        color: AppColors.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (onFollow != null)
            Material(
              color: AppColors.like,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onFollow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    tr('Follow'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 6),
        ],
      ),
    ),
  );
}

/// A top gifter's photo with a 1 / 2 / 3 medal.
class _RankAvatar extends StatelessWidget {
  const _RankAvatar({required this.entry});
  final RankEntry entry;

  static const _medal = [
    Color(0xFFFFC83D),
    Color(0xFFCBD5E1),
    Color(0xFFD08A4E),
  ];

  @override
  Widget build(BuildContext context) {
    final c = _medal[(entry.rank - 1).clamp(0, 2)];
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(shape: BoxShape.circle, color: c),
            child: Avatar(
              url: entry.user.avatarUrl,
              name: entry.user.displayName,
              radius: 14,
            ),
          ),
          Positioned(
            right: -1,
            bottom: -2,
            child: Container(
              width: 13,
              height: 13,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              child: Text(
                '${entry.rank}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small dark chip under the top bar ("🏆 Top gifters", "❤ 1.2K").
class _TopChip extends StatelessWidget {
  const _TopChip({
    required this.icon,
    required this.color,
    required this.text,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Host's PK button (red/blue, like TikTok's).
class _PkButton extends StatelessWidget {
  const _PkButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFF2E63), Color(0xFF3B82F6)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF2E63).withValues(alpha: .45),
            blurRadius: 12,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Text(
        'PK',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          fontSize: 15,
        ),
      ),
    ),
  );
}

class _EndedOverlay extends StatelessWidget {
  const _EndedOverlay({required this.isHost, required this.onClose});
  final bool isHost;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black.withValues(alpha: .75),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_rounded, color: Colors.white, size: 54),
          const SizedBox(height: 12),
          Text(
            isHost ? tr('This live was ended') : tr('This live has ended'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 200,
            child: GradientButton(label: tr('Close'), onPressed: onClose),
          ),
        ],
      ),
    ),
  );
}

class _SummaryDialog extends StatelessWidget {
  const _SummaryDialog({required this.summary, required this.giftCoins});
  final Map<String, dynamic>? summary;
  final int giftCoins;

  @override
  Widget build(BuildContext context) {
    final secs = (summary?['duration_sec'] as num?)?.toInt() ?? 0;
    final duration = secs >= 3600
        ? '${secs ~/ 3600}h ${(secs % 3600) ~/ 60}m'
        : '${secs ~/ 60}m ${secs % 60}s';
    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return AlertDialog(
      title: Text(tr('Live ended'), textAlign: TextAlign.center),
      content: Row(
        children: [
          stat(duration, tr('Duration')),
          stat('${summary?['viewers_peak'] ?? 0}', tr('Peak viewers')),
          stat(
            compactCount(
              (summary?['gifts_coins'] as num?)?.toInt() ?? giftCoins,
            ),
            tr('Gift coins'),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Done')),
        ),
      ],
    );
  }
}

/// Hearts that float up from the bottom right.
class FloatingHearts extends StatefulWidget {
  const FloatingHearts({super.key});

  @override
  State<FloatingHearts> createState() => _FloatingHeartsState();
}

class _FloatingHeartsState extends State<FloatingHearts> {
  final _rand = Random();
  final _hearts = <(int, double, Color)>[];
  int _seq = 0;

  void burst(int n) {
    for (var i = 0; i < n; i++) {
      final id = ++_seq;
      final colors = [
        AppColors.like,
        AppColors.amber,
        AppColors.emeraldLight,
        const Color(0xFFB388FF),
      ];
      setState(
        () => _hearts.add((
          id,
          _rand.nextDouble() * 40 - 20,
          colors[_rand.nextInt(colors.length)],
        )),
      );
      Timer(const Duration(milliseconds: 2200), () {
        if (mounted) setState(() => _hearts.removeWhere((h) => h.$1 == id));
      });
    }
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      children: [
        for (final (id, drift, color) in _hearts)
          Positioned(
            key: ValueKey(id),
            right: 40,
            bottom: 90,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 2200),
              curve: Curves.easeOut,
              builder: (context, t, child) => Transform.translate(
                offset: Offset(drift * sin(t * pi * 2), -320 * t),
                child: Opacity(
                  opacity: (1 - t).clamp(0, 1),
                  child: Transform.scale(scale: .6 + t * .6, child: child),
                ),
              ),
              child: Icon(Icons.favorite_rounded, color: color, size: 30),
            ),
          ),
      ],
    ),
  );
}

/// Progress towards the host's gift goal.
class _GoalBar extends StatelessWidget {
  const _GoalBar({
    required this.coins,
    required this.text,
    required this.progress,
  });
  final int coins, progress;
  final String text;

  @override
  Widget build(BuildContext context) {
    final done = progress >= coins;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(done ? '🎉 ' : '🎯 ', style: const TextStyle(fontSize: 13)),
              Expanded(
                child: Text(
                  text.isEmpty ? tr('Gift goal') : text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${compactCount(progress.clamp(0, coins))}/${compactCount(coins)}',
                style: const TextStyle(
                  color: AppColors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (progress / coins).clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: Colors.white24,
              color: done ? AppColors.emeraldLight : AppColors.amber,
            ),
          ),
        ],
      ),
    );
  }
}
