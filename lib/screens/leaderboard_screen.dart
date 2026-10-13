import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';

/// Top gifters and top creators by day / week / month / all time.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  String _type = 'gifters', _period = 'week';
  List<RankEntry>? _items;
  RankEntry? _me;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _items = null;
      _error = null;
    });
    try {
      final (items, me) = await ref
          .read(apiProvider)
          .leaderboard(_type, _period);
      if (mounted) {
        setState(() {
          _items = items;
          _me = me;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Leaderboards'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'gifters',
                  icon: const Icon(Icons.card_giftcard_rounded),
                  label: Text(tr('Top gifters')),
                ),
                ButtonSegment(
                  value: 'creators',
                  icon: const Icon(Icons.star_rounded),
                  label: Text(tr('Top creators')),
                ),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                _type = s.first;
                _load();
              },
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final (v, l) in [
                  ('day', tr('Today')),
                  ('week', tr('This week')),
                  ('month', tr('This month')),
                  ('all', tr('All time')),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(l),
                      selected: _period == v,
                      onSelected: (_) {
                        _period = v;
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_me != null && _type == 'gifters')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                tr('You are #{0} with {1} coins', [
                  _me!.rank,
                  compactCount(_me!.coins),
                ]),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.amber,
                ),
              ),
            ),
          Expanded(
            child: items == null
                ? Center(
                    child: _error != null
                        ? Text('$_error')
                        : const CircularProgressIndicator(),
                  )
                : items.isEmpty
                ? Center(child: Text(tr('No gifts yet in this period.')))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) => RankTile(entry: items[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One leaderboard row: rank (medal for the top 3), person, level, coins.
class RankTile extends StatelessWidget {
  const RankTile({super.key, required this.entry, this.dense = false});
  final RankEntry entry;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final r = entry.rank;
    return ListTile(
      dense: dense,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(username: entry.user.username),
        ),
      ),
      leading: SizedBox(
        width: 74,
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
            Avatar(
              url: entry.user.avatarUrl,
              name: entry.user.displayName,
              radius: 19,
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
            ),
          ),
          if (entry.user.level > 0) ...[
            const SizedBox(width: 6),
            LevelBadge(level: entry.user.level),
          ],
        ],
      ),
      subtitle: Text('@${entry.user.username}'),
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
    );
  }
}
