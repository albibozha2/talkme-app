import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../api.dart';
import '../models.dart';
import '../screens/live_room_screen.dart';
import '../screens/profile_screen.dart';
import '../theme.dart';
import 'common.dart';
import '../i18n.dart';

const _pkRed = LinearGradient(colors: [Color(0xFFFF2E63), Color(0xFFFF5F6D)]);
const _pkBlue = LinearGradient(colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)]);
const _red = Color(0xFFFF2E63);
const _blue = Color(0xFF3B82F6);

/// PK battle overlay for a live room, laid out like TikTok's:
/// both hosts side by side, the red/blue score bar under them with the timer,
/// each side's top 3 gifters, win streaks, a 10-second countdown and WIN / LOSE stamps.
///
/// Polls the battle state, lets the host challenge another live (or a random one),
/// and shows the invitation to the challenged host. The opponent's video and voice
/// come from a second, receive-only connection to their room.
class BattleLayer extends ConsumerStatefulWidget {
  /// Where this live's own video sits during a battle (the left half). The live room
  /// moves its one video renderer there, because a second renderer of the same
  /// camera stays black in browsers.
  static Rect myPane(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final h = (size.width / 2 * 4 / 3).clamp(160.0, size.height * .46);
    return Rect.fromLTWH(
      0,
      MediaQuery.paddingOf(context).top + 92,
      size.width / 2 - 1,
      h,
    );
  }

  const BattleLayer({
    super.key,
    required this.liveId,
    required this.isHost,
    required this.myTrack,
    required this.onActive,
    this.onLike,
    this.onState,
  });

  final int liveId;
  final bool isHost;
  final VideoTrack? myTrack;

  /// Called with true while the split-screen battle view is showing.
  final ValueChanged<bool> onActive;

  /// Tapping this live's side sends likes, like tapping the video outside a battle.
  final VoidCallback? onLike;

  /// Host only: each battle update (or null), to pass on to the viewers over the live
  /// connection, so viewers don't each ask the server every 2 seconds.
  final ValueChanged<Map<String, dynamic>?>? onState;

  @override
  ConsumerState<BattleLayer> createState() => BattleLayerState();
}

class _ScorePop {
  _ScorePop(this.id, this.mine, this.points);
  final int id;
  final bool mine;
  final int points;
}

class BattleLayerState extends ConsumerState<BattleLayer> {
  Battle? _battle;
  DateTime _fetchedAt = DateTime.now();
  Timer? _poll, _tick;
  Room? _oppRoom;
  EventsListener<RoomEvent>? _oppEvents;
  int? _askedFor; // battle id we already showed the invite dialog for
  int? _closedId; // battle whose result the host closed early
  int? _ticketAskedFor; // viewers: battle we already fetched our own stream ticket for
  bool _active = false;
  bool _oppMuted = false;
  final _followed = <int>{};
  final _pops = <_ScorePop>[];
  int _popId = 0;

  Api get _api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    refresh();
    // The host checks often and passes updates on; viewers only check now and then as a fallback.
    _poll = Timer.periodic(
      Duration(seconds: widget.isHost ? 2 : 15),
      (_) => refresh(),
    );
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = _battle?.status;
      if ((s == 'active' || s == 'ended') && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _closeOpponent();
    super.dispose();
  }

  /// Fetches the battle now (also called right after a gift, so the bar moves at once).
  Future<void> refresh() async {
    try {
      final b = await _api.battle(widget.liveId);
      if (!mounted) return;
      _apply(b);
      if (widget.isHost) {
        // Viewers get their own stream ticket from the server, not from the host.
        widget.onState?.call(
          b == null ? null : (Map.of(b.raw)..remove('opponent_stream')),
        );
      }
    } catch (_) {}
  }

  /// A battle update the host passed on (viewers). A new battle, or one we have no
  /// stream ticket for yet, is fetched from the server once.
  void applyRemote(Map<String, dynamic>? j) {
    if (widget.isHost) return;
    if (j == null) {
      if (_battle != null) _apply(null);
      return;
    }
    final old = _battle;
    final status = j['status'];
    final needsTicket =
        (status == 'active' || status == 'ended') &&
        (old == null || old.id != j['id'] || old.streamToken == null) &&
        _ticketAskedFor != j['id'];
    if (needsTicket) {
      _ticketAskedFor = j['id'] as int?;
      refresh();
      return;
    }
    try {
      _apply(
        Battle.fromJson({
          ...j,
          if (old?.raw['opponent_stream'] != null)
            'opponent_stream': old!.raw['opponent_stream'],
        }),
      );
    } catch (_) {}
  }

  void _apply(Battle? b) {
    final old = _battle;
    {
      final wasActive = old?.status == 'active';
      if (old != null && b != null && old.id == b.id) {
        if (b.me.score > old.me.score) _pop(true, b.me.score - old.me.score);
        if (b.them.score > old.them.score) {
          _pop(false, b.them.score - old.them.score);
        }
      }
      setState(() {
        _battle = b;
        _fetchedAt = DateTime.now();
      });
      if (b != null && b.status == 'active' && !wasActive) {
        HapticFeedback.heavyImpact();
      }
      if (b != null && b.status == 'ended' && wasActive) {
        HapticFeedback.heavyImpact();
      }
      _syncOpponent();
      _report();
      if (b != null &&
          b.status == 'invited' &&
          !b.invitedByMe &&
          widget.isHost &&
          _askedFor != b.id) {
        _askedFor = b.id;
        _showInvite(b);
      }
    }
  }

  bool get _showing {
    final b = _battle;
    return b != null &&
        (b.status == 'active' || b.status == 'ended') &&
        b.id != _closedId;
  }

  void _report() {
    final active = _showing;
    if (active != _active) {
      _active = active;
      widget.onActive(active);
    }
  }

  void _pop(bool mine, int points) {
    final p = _ScorePop(++_popId, mine, points);
    _pops.add(p);
    Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _pops.remove(p));
    });
  }

  // ---------- opponent stream ----------

  Future<void> _syncOpponent() async {
    final b = _battle;
    final want =
        b != null &&
        b.streamToken != null &&
        (b.status == 'active' || b.status == 'ended') &&
        b.id != _closedId;
    if (!want) {
      await _closeOpponent();
      return;
    }
    if (_oppRoom != null) return;
    final room = Room(roomOptions: const RoomOptions(adaptiveStream: true));
    _oppRoom = room;
    _oppEvents = room.createListener()
      ..on<TrackSubscribedEvent>((_) {
        _applyOppAudio();
        if (mounted) setState(() {});
      })
      ..on<TrackUnsubscribedEvent>((_) => mounted ? setState(() {}) : null)
      ..on<ParticipantDisconnectedEvent>(
        (_) => mounted ? setState(() {}) : null,
      );
    try {
      await room.connect(b.streamUrl!, b.streamToken!);
      _applyOppAudio();
      if (mounted) setState(() {});
    } catch (_) {
      await _closeOpponent();
    }
  }

  /// Both hosts are heard during a PK (like TikTok); the speaker button mutes the other side.
  void _applyOppAudio() {
    final room = _oppRoom;
    if (room == null) return;
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        final t = pub.track;
        if (t == null) continue;
        _oppMuted ? t.disable() : t.enable();
      }
    }
  }

  Future<void> _closeOpponent() async {
    final r = _oppRoom;
    _oppRoom = null;
    await _oppEvents?.dispose();
    _oppEvents = null;
    if (r != null) {
      await r.disconnect();
      await r.dispose();
    }
  }

  VideoTrack? get _opponentTrack {
    final room = _oppRoom, host = _battle?.streamHost;
    if (room == null || host == null) return null;
    for (final p in room.remoteParticipants.values) {
      if (p.identity != host) continue;
      for (final pub in p.videoTrackPublications) {
        if (pub.subscribed && pub.track != null) return pub.track;
      }
    }
    return null;
  }

  // ---------- host actions ----------

  /// Host: quick match with a random live, or pick one to challenge.
  Future<void> openInvite() async {
    final cur = _battle;
    if (cur != null && (cur.status == 'invited' || cur.status == 'active')) {
      showToast(
        context,
        cur.status == 'invited'
            ? tr('Waiting for an answer…')
            : tr('A battle is already running'),
      );
      return;
    }
    List<LiveInfo> lives;
    try {
      lives = (await _api.lives()).items
          .where((l) => l.id != widget.liveId)
          .toList();
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    final target = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.inkSurface,
      builder: (context) => Theme(
        data: buildTheme(Brightness.dark),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .7,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Row(
                    children: [
                      const _PkMark(size: 28),
                      const SizedBox(width: 8),
                      Text(
                        tr('Start a PK battle'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    tr(
                      'Challenge another live. Gifts during the battle count as points.',
                    ),
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(context, 'random'),
                    child: Ink(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [_red, _blue]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.shuffle_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('Quick match'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  tr('Battle a random live that is free now'),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                  child: Text(
                    tr('Live now'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (lives.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('Nobody else is live right now.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                for (final l in lives)
                  ListTile(
                    enabled: !l.inBattle,
                    leading: Avatar(
                      url: l.host.avatarUrl,
                      name: l.host.displayName,
                      radius: 22,
                      live: true,
                    ),
                    title: Text(
                      l.host.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      l.inBattle
                          ? tr('In a battle')
                          : tr('{0} watching', [compactCount(l.viewers)]),
                      style: const TextStyle(color: Colors.white60),
                    ),
                    trailing: l.inBattle
                        ? null
                        : Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              gradient: _pkRed,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              tr('Challenge'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                    onTap: () => Navigator.pop(context, l),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (target == null) return;
    await _challenge(target is LiveInfo ? target : null);
  }

  /// Sends the challenge; null = quick match with a random free live.
  Future<void> _challenge(LiveInfo? target) async {
    try {
      final b = await _api.inviteBattle(widget.liveId, target?.id);
      if (!mounted) return;
      setState(() {
        _battle = b;
        _fetchedAt = DateTime.now();
      });
      _report();
      if (b != null) {
        showToast(
          context,
          tr('Challenge sent to {0}', [b.them.live.host.displayName]),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _showInvite(Battle b) async {
    HapticFeedback.mediumImpact();
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: buildTheme(Brightness.dark),
        child: AlertDialog(
          backgroundColor: AppColors.inkSurface,
          icon: const _PkMark(size: 44),
          title: Text(tr('PK challenge!')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(
                url: b.them.live.host.avatarUrl,
                name: b.them.live.host.displayName,
                radius: 30,
                live: true,
              ),
              const SizedBox(height: 10),
              Text(
                tr('{0} challenges you to a {1}-minute battle.', [
                  b.them.live.host.displayName,
                  b.duration ~/ 60,
                ]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                tr('Gifts from your viewers count as your points.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Decline')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.live,
                minimumSize: const Size(110, 42),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Accept')),
            ),
          ],
        ),
      ),
    );
    if (accept == null || !mounted) return;
    try {
      await _api.answerBattle(b.id, accept ? 'accept' : 'decline');
      refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _cancelInvite() async {
    final b = _battle;
    if (b == null) return;
    try {
      await _api.answerBattle(b.id, 'cancel');
      if (mounted) setState(() => _battle = null);
    } catch (_) {}
  }

  /// Host closes the result screen before it times out.
  void _closeResult() {
    setState(() => _closedId = _battle?.id);
    _report();
    _closeOpponent();
  }

  // ---------- the other host ----------

  Future<void> _follow(AppUser host) async {
    setState(() => _followed.add(host.id));
    try {
      await _api.setFollow(host.username, true);
      if (mounted) showToast(context, tr('Following {0}', [host.displayName]));
    } catch (e) {
      if (mounted) {
        setState(() => _followed.remove(host.id));
        showError(context, e);
      }
    }
  }

  Future<void> _opponentSheet(Battle b) async {
    final host = b.them.live.host;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.inkSurface,
      builder: (context) => Theme(
        data: buildTheme(Brightness.dark),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Avatar(
                  url: host.avatarUrl,
                  name: host.displayName,
                  radius: 36,
                  live: true,
                ),
                const SizedBox(height: 8),
                Text(
                  host.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '@${host.username}',
                  style: const TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (!_followed.contains(host.id))
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: _red),
                          onPressed: () => Navigator.pop(context, 'follow'),
                          child: Text(tr('Follow')),
                        ),
                      ),
                    if (!_followed.contains(host.id) && !widget.isHost)
                      const SizedBox(width: 10),
                    if (!widget.isHost)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, 'watch'),
                          child: Text(tr('Watch their live')),
                        ),
                      ),
                  ],
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'profile'),
                  child: Text(tr('View profile')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'follow':
        await _follow(host);
      case 'watch':
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => LiveRoomScreen.viewer(liveId: b.them.live.id),
          ),
        );
      case 'profile':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProfileScreen(username: host.username),
          ),
        );
    }
  }

  // ---------- UI ----------

  int get _remaining {
    final b = _battle;
    if (b == null) return 0;
    return (b.remaining - DateTime.now().difference(_fetchedAt).inSeconds)
        .clamp(0, b.duration);
  }

  int get _resultLeft {
    final b = _battle;
    if (b == null) return 0;
    return (b.resultLeft - DateTime.now().difference(_fetchedAt).inSeconds)
        .clamp(0, 999);
  }

  @override
  Widget build(BuildContext context) {
    final b = _battle;
    final pad = MediaQuery.paddingOf(context);
    if (b == null) return const SizedBox.shrink();

    if (b.status == 'invited') {
      // Small banner while the challenge waits for an answer.
      return Positioned(
        top: pad.top + 92,
        left: 12,
        right: 12,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            children: [
              const _PkMark(size: 24),
              const SizedBox(width: 8),
              if (b.invitedByMe) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  b.invitedByMe
                      ? tr('Waiting for {0}…', [b.them.live.host.displayName])
                      : tr('{0} challenged this live', [
                          b.them.live.host.displayName,
                        ]),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (b.invitedByMe && widget.isHost)
                TextButton(
                  onPressed: _cancelInvite,
                  child: Text(
                    tr('Cancel'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    if (!_showing) return const SizedBox.shrink();

    // Two portrait halves (3:4), like TikTok's PK screen.
    final mine = BattleLayer.myPane(context);
    final videoH = mine.height;
    final top = mine.top;
    final ended = b.status == 'ended';
    final secs = _remaining;
    final total = b.me.score + b.them.score;
    final mePart = total == 0 ? .5 : (b.me.score / total).clamp(.1, .9);
    final (meStamp, themStamp) = switch (b.result) {
      'win' => ('WIN', 'LOSE'),
      'lose' => ('LOSE', 'WIN'),
      'draw' => ('DRAW', 'DRAW'),
      _ => (null, null),
    };
    final mvp = switch (b.result) {
      'win' => b.me.tops.firstOrNull,
      'lose' => b.them.tops.firstOrNull,
      _ => null,
    };
    final oppHost = b.them.live.host;

    return Positioned.fill(
      child: Stack(
        children: [
          // Background everywhere except the left pane, where the room's own video shows through.
          Positioned.fill(
            child: IgnorePointer(
              child: Column(
                children: [
                  SizedBox(
                    height: top,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0xFF2A0E1E)),
                    ),
                  ),
                  SizedBox(
                    height: videoH,
                    child: Row(
                      children: [
                        SizedBox(width: mine.width),
                        const Expanded(child: ColoredBox(color: Colors.black)),
                      ],
                    ),
                  ),
                  const Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF0B1230), AppColors.ink],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: top,
            left: 0,
            right: 0,
            child: Column(
              children: [
                SizedBox(
                  height: videoH,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: widget.onLike,
                          child: _Pane(
                            // Drawn underneath by the live room (see myPane).
                            track: null,
                            behind: widget.myTrack != null,
                            host: b.me.live.host,
                            color: _red,
                            streak: b.me.streak,
                            stamp: meStamp,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _opponentSheet(b),
                          child: _Pane(
                            track: _opponentTrack,
                            host: oppHost,
                            color: _blue,
                            streak: b.them.streak,
                            stamp: themStamp,
                            onFollow: _followed.contains(oppHost.id)
                                ? null
                                : () => _follow(oppHost),
                            muted: _oppMuted,
                            onMute: () {
                              setState(() => _oppMuted = !_oppMuted);
                              _applyOppAudio();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Score bar
                SizedBox(
                  height: 22,
                  child: LayoutBuilder(
                    builder: (context, c) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 600),
                              curve: Curves.easeOutCubic,
                              width: c.maxWidth * mePart,
                              decoration: const BoxDecoration(gradient: _pkRed),
                            ),
                            const Expanded(
                              child: DecoratedBox(
                                decoration: BoxDecoration(gradient: _pkBlue),
                              ),
                            ),
                          ],
                        ),
                        // The spark where red meets blue.
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          left: c.maxWidth * mePart - 9,
                          top: -3,
                          child: IgnorePointer(
                            child: Container(
                              width: 18,
                              height: 28,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9),
                                gradient: const RadialGradient(
                                  colors: [Colors.white, Color(0x00FFFFFF)],
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0xAAFFE08A),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.bolt_rounded,
                                size: 16,
                                color: Color(0xFFFFC83D),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              children: [
                                Text(
                                  '${tr('Me')} ${compactCount(b.me.score)}',
                                  style: _barText,
                                ),
                                const Spacer(),
                                Text(
                                  '${compactCount(b.them.score)} ${tr('Opponent')}',
                                  style: _barText,
                                ),
                              ],
                            ),
                          ),
                        ),
                        for (final p in _pops)
                          Positioned(
                            key: ValueKey(p.id),
                            left: p.mine ? 14 : null,
                            right: p.mine ? null : 14,
                            top: -6,
                            child: IgnorePointer(
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: 1),
                                duration: const Duration(milliseconds: 1300),
                                curve: Curves.easeOut,
                                builder: (context, t, child) => Opacity(
                                  opacity: (1 - t).clamp(0, 1),
                                  child: Transform.translate(
                                    offset: Offset(0, -34 * t),
                                    child: child,
                                  ),
                                ),
                                child: Text(
                                  '+${p.points}',
                                  style: TextStyle(
                                    color: p.mine
                                        ? const Color(0xFFFFB3C1)
                                        : const Color(0xFFB3E5FF),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    shadows: const [Shadow(blurRadius: 6)],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Top 3 gifters each side
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        _GifterSeat(
                          rank: i + 1,
                          top: i < b.me.tops.length ? b.me.tops[i] : null,
                          color: _red,
                        ),
                      const Spacer(),
                      for (var i = 2; i >= 0; i--)
                        _GifterSeat(
                          rank: i + 1,
                          top: i < b.them.tops.length ? b.them.tops[i] : null,
                          color: _blue,
                        ),
                    ],
                  ),
                ),
                if (ended) ...[
                  const SizedBox(height: 10),
                  if (mvp != null)
                    Container(
                      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.amber),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Avatar(url: mvp.avatar, name: mvp.name, radius: 14),
                          const SizedBox(width: 6),
                          const Text(
                            'MVP',
                            style: TextStyle(
                              color: AppColors.amber,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            mvp.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.isHost) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (b.them.live.status == 'live')
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _red,
                              // The app theme makes buttons full width; not in this row.
                              minimumSize: const Size(130, 42),
                            ),
                            onPressed: () => _challenge(b.them.live),
                            icon: const Icon(Icons.replay_rounded, size: 18),
                            label: Text(tr('Rematch')),
                          ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            minimumSize: const Size(100, 42),
                          ),
                          onPressed: _closeResult,
                          child: Text(tr('Close')),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
          // Timer pill on top of where the two streams meet
          Positioned(
            top: top - 13,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 3, 12, 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _PkMark(size: 20),
                      const SizedBox(width: 6),
                      Text(
                        ended
                            ? tr('Result {0}', [_mmss(_resultLeft)])
                            : _mmss(secs),
                        style: TextStyle(
                          color: !ended && secs <= 10
                              ? AppColors.live
                              : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Final countdown
          if (!ended && secs > 0 && secs <= 10)
            Positioned(
              top: top,
              height: videoH,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(secs),
                    tween: Tween(begin: 1.8, end: 1),
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutBack,
                    builder: (context, s, child) =>
                        Transform.scale(scale: s, child: child),
                    child: Text(
                      '$secs',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        shadows: [
                          Shadow(blurRadius: 24, color: _red),
                          Shadow(blurRadius: 8, color: Colors.black),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const _barText = TextStyle(
  color: Colors.white,
  fontWeight: FontWeight.w800,
  fontSize: 12.5,
  shadows: [Shadow(blurRadius: 4, color: Colors.black38)],
);

String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// The little red/blue "PK" badge.
class _PkMark extends StatelessWidget {
  const _PkMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(colors: [_red, _blue]),
    ),
    alignment: Alignment.center,
    child: Text(
      'PK',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        fontSize: size * .42,
      ),
    ),
  );
}

class _Pane extends StatelessWidget {
  const _Pane({
    required this.track,
    required this.host,
    required this.color,
    this.streak = 0,
    this.stamp,
    this.onFollow,
    this.onMute,
    this.muted = false,
    this.behind = false,
  });
  final VideoTrack? track;

  /// The video is drawn under this pane by someone else: keep it see-through.
  final bool behind;
  final AppUser host;
  final Color color;
  final int streak;

  /// WIN / LOSE / DRAW once the battle is over.
  final String? stamp;
  final VoidCallback? onFollow, onMute;
  final bool muted;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (!behind)
        ColoredBox(
          color: Colors.black,
          child: track != null
              ? VideoTrackRenderer(track!, fit: VideoViewFit.cover)
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Avatar(
                        url: host.avatarUrl,
                        name: host.displayName,
                        radius: 28,
                      ),
                      const SizedBox(height: 10),
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      if (stamp != null)
        Positioned.fill(
          child: ColoredBox(
            color: stamp == 'LOSE'
                ? Colors.black.withValues(alpha: .45)
                : Colors.transparent,
          ),
        ),
      if (streak > 0)
        Positioned(
          left: 6,
          top: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFB020), Color(0xFFFF5F2E)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              tr('🔥 {0} wins in a row', [streak]),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      if (onMute != null)
        Positioned(
          right: 4,
          top: 12,
          child: IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: muted ? tr('Unmute') : tr('Mute'),
            onPressed: onMute,
            icon: Icon(
              muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: Colors.white,
              size: 20,
              shadows: const [Shadow(blurRadius: 6)],
            ),
          ),
        ),
      Positioned(
        left: 6,
        bottom: 6,
        right: 6,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.fromLTRB(2, 2, 4, 2),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: .8)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Avatar(url: host.avatarUrl, name: host.displayName, radius: 10),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    host.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                if (onFollow != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onFollow,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: _red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
      if (stamp != null)
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 2.2, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            builder: (context, s, child) => Transform.scale(
              scale: s,
              child: Transform.rotate(angle: -.12, child: child),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: switch (stamp) {
                    'WIN' => AppColors.amber,
                    'LOSE' => Colors.white54,
                    _ => AppColors.emeraldLight,
                  },
                  width: 3,
                ),
              ),
              child: Text(
                switch (stamp) {
                  'WIN' => tr('WIN'),
                  'LOSE' => tr('LOSE'),
                  _ => tr('DRAW'),
                },
                style: TextStyle(
                  color: switch (stamp) {
                    'WIN' => AppColors.amber,
                    'LOSE' => Colors.white70,
                    _ => AppColors.emeraldLight,
                  },
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 2,
                  shadows: const [Shadow(blurRadius: 12)],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// One of the three gifter seats under the score bar (empty seats show the rank).
class _GifterSeat extends StatelessWidget {
  const _GifterSeat({
    required this.rank,
    required this.top,
    required this.color,
  });
  final int rank;
  final ({String name, String? avatar, int coins})? top;
  final Color color;

  static const _medal = [
    Color(0xFFFFC83D),
    Color(0xFFCBD5E1),
    Color(0xFFD08A4E),
  ];

  @override
  Widget build(BuildContext context) {
    final t = top;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: t == null ? '' : '${t.name} · ${t.coins}',
        child: SizedBox(
          width: 32,
          height: 36,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _medal[rank - 1],
                ),
                child: t == null
                    ? CircleAvatar(
                        radius: 14,
                        backgroundColor: color.withValues(alpha: .3),
                        child: const Icon(
                          Icons.person_rounded,
                          size: 16,
                          color: Colors.white54,
                        ),
                      )
                    : Avatar(url: t.avatar, name: t.name, radius: 14),
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _medal[rank - 1],
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
