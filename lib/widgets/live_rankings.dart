import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../screens/leaderboard_screen.dart';
import '../screens/live_room_screen.dart';
import '../screens/profile_screen.dart';
import '../theme.dart';
import '../vip.dart';
import 'common.dart';
import '../features.dart';

/// TikTok-style LIVE rankings: streamers this hour / this week, top gifters this week.
/// [tab]: 0 hourly, 1 weekly, 2 gifters. [highlight]: someone to mark in the list (the host of the open live).
Future<void> showLiveRankings(
  BuildContext context, {
  int tab = 0,
  int? highlight,
}) async {
  if (!Features.on('live_rankings')) {
    showToast(context, tr('LIVE rankings are turned off right now.'));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.inkSurface,
    builder: (_) => Theme(
      data: buildTheme(Brightness.dark),
      child: _RankingsSheet(tab: tab, highlight: highlight),
    ),
  );
}

const _tabs = [
  ('streamers', 'hour'),
  ('streamers', 'week'),
  ('gifters', 'week'),
];

class _RankingsSheet extends StatefulWidget {
  const _RankingsSheet({required this.tab, this.highlight});
  final int tab;
  final int? highlight;

  @override
  State<_RankingsSheet> createState() => _RankingsSheetState();
}

class _RankingsSheetState extends State<_RankingsSheet> {
  late int _tab = widget.tab;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 6),
            child: Row(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('LIVE rankings'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LeaderboardScreen(),
                    ),
                  ),
                  child: Text(tr('All leaderboards')),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(tr('Hourly'))),
                ButtonSegment(value: 1, label: Text(tr('Weekly'))),
                ButtonSegment(value: 2, label: Text(tr('Top gifters'))),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          Expanded(
            child: _RankingList(
              key: ValueKey(_tab),
              type: _tabs[_tab].$1,
              period: _tabs[_tab].$2,
              highlight: widget.highlight,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RankingList extends ConsumerStatefulWidget {
  const _RankingList({
    super.key,
    required this.type,
    required this.period,
    this.highlight,
  });
  final String type, period;
  final int? highlight;

  @override
  ConsumerState<_RankingList> createState() => _RankingListState();
}

class _RankingListState extends ConsumerState<_RankingList> {
  LiveRanking? _data;
  Object? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // Countdown; reload when the period ends.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final d = _data;
      if (d != null && DateTime.now().isAfter(d.endsAt)) {
        _data = null;
        _load();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await ref
          .read(apiProvider)
          .liveRanking(widget.type, widget.period);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _left(DateTime end) {
    final s = end.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30);
    final d = s ~/ 86400, h = s % 86400 ~/ 3600, m = s % 3600 ~/ 60;
    final sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return d > 0
        ? '${d}d ${two(h)}:${two(m)}:${two(sec)}'
        : '${two(h)}:${two(m)}:${two(sec)}';
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return Center(
        child: _error != null
            ? Text('$_error')
            : const CircularProgressIndicator(),
      );
    }
    final weekly = d.period == 'week';
    final prizes = d.rewards.any((r) => r > 0);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: Colors.white60,
                ),
                const SizedBox(width: 6),
                Text(
                  tr('Ends in {0}', [_left(d.endsAt)]),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Text(
                  d.type == 'gifters'
                      ? tr('Coins sent in lives')
                      : tr('Coins received in lives'),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          if (weekly && prizes)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: AppColors.goldGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Text('🎁', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr(
                        'Top 3 this week win {0} / {1} / {2} bonus coins and a 🏆 badge',
                        [
                          compactCount(d.rewards[0]),
                          compactCount(d.rewards[1]),
                          compactCount(d.rewards[2]),
                        ],
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (d.me != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                d.me!.rank == 1
                    ? tr('You are #1 with {0} coins 👑', [
                        compactCount(d.me!.coins),
                      ])
                    : tr('You are #{0} · {1} coins to pass #{2}', [
                        d.me!.rank,
                        compactCount(d.me!.gap),
                        d.me!.rank - 1,
                      ]),
                style: const TextStyle(
                  color: AppColors.amber,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 6),
          if (d.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                d.period == 'hour'
                    ? tr('No gifts in lives this hour yet. Be the first!')
                    : tr('No gifts in lives this week yet. Be the first!'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60),
              ),
            ),
          for (final e in d.items)
            _LiveRankTile(entry: e, highlight: e.user.id == widget.highlight),
          if (d.lastWinners.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Text(
                tr("Last week's winners"),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white70,
                ),
              ),
            ),
            for (final e in d.lastWinners) _LiveRankTile(entry: e, prize: true),
          ],
        ],
      ),
    );
  }
}

class _LiveRankTile extends StatelessWidget {
  const _LiveRankTile({
    required this.entry,
    this.highlight = false,
    this.prize = false,
  });
  final RankEntry entry;
  final bool highlight, prize;

  @override
  Widget build(BuildContext context) {
    final r = entry.rank;
    final live = entry.liveId;
    return Container(
      color: highlight ? AppColors.amber.withValues(alpha: .12) : null,
      child: ListTile(
        onTap: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => live != null
                  ? LiveRoomScreen.viewer(liveId: live)
                  : ProfileScreen(username: entry.user.username),
            ),
          );
        },
        leading: SizedBox(
          width: 78,
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  r <= 3 ? ['🥇', '🥈', '🥉'][r - 1] : '$r',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: r <= 3 ? 22 : 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: live != null
                            ? AppColors.live
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Avatar(
                      url: entry.user.avatarUrl,
                      name: entry.user.displayName,
                      radius: 18,
                    ),
                  ),
                  if (live != null)
                    const Positioned(
                      bottom: -6,
                      left: 0,
                      right: 0,
                      child: Center(child: LiveBadge(small: true)),
                    ),
                ],
              ),
            ],
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                entry.user.displayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (entry.user.level > 0) ...[
              const SizedBox(width: 6),
              VipBadge(level: entry.user.level, small: true),
            ],
            if (entry.user.championType != null) ...[
              const SizedBox(width: 4),
              ChampionBadge(rank: entry.user.championRank, small: true),
            ],
          ],
        ),
        subtitle: Text(
          prize && entry.reward > 0
              ? tr('Won {0} bonus coins', [compactCount(entry.reward)])
              : '@${entry.user.username}',
          style: const TextStyle(color: Colors.white54),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CoinIcon(size: 16),
            const SizedBox(width: 4),
            Text(
              compactCount(entry.coins),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
