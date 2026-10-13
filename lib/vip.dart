import 'package:flutter/material.dart';

import 'i18n.dart';

/// VIP tiers for gifters, from the gifter level (which grows with the coins someone has gifted).
/// Level n needs 100·n² coins in total (same formula as the server).
class VipTier {
  const VipTier(
    this.name,
    this.minLevel,
    this.icon,
    this.colors, {
    this.glow = false,
  });
  final String name; // English; shown through tr()
  final int minLevel;
  final String icon;
  final List<Color> colors;

  /// Gold and up shine a little.
  final bool glow;

  String get label => tr(name);
  Color get color => colors.first;
  LinearGradient get gradient => LinearGradient(colors: colors);
}

const vipTiers = [
  VipTier('Bronze', 5, '🥉', [Color(0xFFB87333), Color(0xFFE0A370)]),
  VipTier('Silver', 10, '🥈', [Color(0xFF94A3B8), Color(0xFFE2E8F0)]),
  VipTier('Gold', 15, '👑', [Color(0xFFF59E0B), Color(0xFFFDE68A)], glow: true),
  VipTier('Platinum', 25, '💠', [
    Color(0xFF06B6D4),
    Color(0xFFA5F3FC),
  ], glow: true),
  VipTier('Diamond', 35, '💎', [
    Color(0xFF6366F1),
    Color(0xFFC4B5FD),
  ], glow: true),
  VipTier('King', 45, '🦁', [Color(0xFFDC2626), Color(0xFFFBBF24)], glow: true),
];

VipTier? vipOf(int level) {
  VipTier? t;
  for (final v in vipTiers) {
    if (level >= v.minLevel) t = v;
  }
  return t;
}

VipTier? nextVip(int level) {
  for (final v in vipTiers) {
    if (level < v.minLevel) return v;
  }
  return null;
}

int coinsForLevel(int level) => 100 * level * level;

/// The perks of a tier (cumulative), shown on the VIP card.
List<String> vipPerks(VipTier t) {
  final i = vipTiers.indexOf(t);
  return [
    tr('VIP badge next to your name everywhere'),
    tr('Gift banners in your tier colours'),
    if (i >= 1) tr('Your name stands out in live chat'),
    if (i >= 2) tr('Shining badge and a special entrance when you join a live'),
    if (i >= 5) tr('King entrance with golden rays'),
  ];
}

/// Small VIP / level pill: "👑 Gold 17" for VIPs, "Lv 3" below Bronze.
class VipBadge extends StatelessWidget {
  const VipBadge({super.key, required this.level, this.small = false});
  final int level;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = vipOf(level);
    if (t == null) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 4 : 6, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFF64748B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Lv $level',
          style: TextStyle(
            color: Colors.white,
            fontSize: small ? 9.5 : 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return Container(
      padding: EdgeInsets.fromLTRB(small ? 3 : 4, 1, small ? 5 : 7, 1),
      decoration: BoxDecoration(
        gradient: t.gradient,
        borderRadius: BorderRadius.circular(8),
        boxShadow: t.glow
            ? [BoxShadow(color: t.color.withValues(alpha: .55), blurRadius: 8)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.icon, style: TextStyle(fontSize: small ? 9 : 11)),
          const SizedBox(width: 2),
          Text(
            '$level',
            style: TextStyle(
              color: t.name == 'Silver'
                  ? const Color(0xFF1E293B)
                  : Colors.white,
              fontSize: small ? 9.5 : 11,
              fontWeight: FontWeight.w900,
              shadows: t.name == 'Silver'
                  ? null
                  : const [Shadow(blurRadius: 2, color: Colors.black38)],
            ),
          ),
        ],
      ),
    );
  }
}

/// My VIP card: current tier, progress to the next one and the perks.
class VipCard extends StatelessWidget {
  const VipCard({super.key, required this.level, required this.giftsSent});
  final int level, giftsSent;

  @override
  Widget build(BuildContext context) {
    final t = vipOf(level);
    final next = nextVip(level);
    final from = coinsForLevel(t?.minLevel ?? 0);
    final to = next == null ? null : coinsForLevel(next.minLevel);
    final progress = to == null
        ? 1.0
        : ((giftsSent - from) / (to - from)).clamp(0.0, 1.0);
    final colors = t?.colors ?? const [Color(0xFF334155), Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F172A),
            Color.lerp(const Color(0xFF0F172A), colors.first, .55)!,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.first.withValues(alpha: .6)),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: .25),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(t?.icon ?? '⭐', style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t == null ? tr('Not VIP yet') : tr('{0} VIP', [t.label]),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      tr('Gifter level {0}', [level]),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              VipBadge(level: level),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(next?.color ?? colors.first),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            next == null
                ? tr('You reached the highest VIP tier. Thank you! 🦁')
                : tr('Gift {0} more coins to reach {1} {2}', [
                    (to! - giftsSent).clamp(0, to),
                    next.icon,
                    next.label,
                  ]),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (t != null) ...[
            const SizedBox(height: 12),
            for (final p in vipPerks(t))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: t.colors.last,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// All VIP tiers with what they need and give (opened from a VIP badge or the wallet).
Future<void> showVipTiers(
  BuildContext context, {
  int level = 0,
  int? giftsSent,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(tr('VIP levels'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            tr(
              'Every coin you gift counts. Higher tiers stand out in lives and chats.',
            ),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          if (giftsSent != null) ...[
            VipCard(level: level, giftsSent: giftsSent),
            const SizedBox(height: 14),
          ],
          for (final t in vipTiers)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: t.color.withValues(alpha: vipOf(level) == t ? 1 : .3),
                  width: vipOf(level) == t ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Text(t.icon, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: t.color,
                          ),
                        ),
                        Text(
                          tr('Level {0} · {1} coins gifted', [
                            t.minLevel,
                            coinsForLevel(t.minLevel),
                          ]),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (level >= t.minLevel)
                    Icon(Icons.check_circle_rounded, color: t.color),
                ],
              ),
            ),
        ],
      ),
    ),
  ),
);
