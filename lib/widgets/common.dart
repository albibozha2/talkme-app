import '../vip.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../theme.dart';
import '../i18n.dart';

/// Round profile photo with initials fallback. [ring] draws a brand (or live) gradient ring.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.url,
    required this.name,
    this.radius = 20,
    this.ring = false,
    this.live = false,
  });
  final String? url;
  final String name;
  final double radius;
  final bool ring;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final px = (radius * 2 * MediaQuery.devicePixelRatioOf(context)).round();
    final circle = CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: url == null
          ? null
          : CachedNetworkImageProvider(url!, maxWidth: px, maxHeight: px),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: radius * .8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (!ring && !live) return circle;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: live ? AppColors.liveGradient : AppColors.brandGradient,
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surface,
        ),
        child: circle,
      ),
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 15});
  final double size;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Icon(
      Icons.verified_rounded,
      size: size,
      color: const Color(0xFF38BDF8),
    ),
  );
}

/// The TalkMe mark: emerald tile, white play shape, amber spark.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: AppColors.brandGradient,
      borderRadius: BorderRadius.circular(size * .28),
      boxShadow: [
        BoxShadow(
          color: AppColors.emerald.withValues(alpha: .35),
          blurRadius: size * .4,
          offset: Offset(0, size * .12),
        ),
      ],
    ),
    child: Stack(
      children: [
        Center(
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: size * .66,
          ),
        ),
        Positioned(
          right: size * .2,
          top: size * .2,
          child: Container(
            width: size * .17,
            height: size * .17,
            decoration: const BoxDecoration(
              color: AppColors.amber,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Full-width primary action with the brand gradient.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.gradient,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : .5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient ?? AppColors.brandGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.emerald.withValues(alpha: .28),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 54,
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded Follow / Following button.
class FollowPill extends StatelessWidget {
  const FollowPill({
    super.key,
    required this.following,
    required this.onTap,
    this.onDark = false,
  });
  final bool following;
  final VoidCallback? onTap;
  final bool onDark;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    decoration: BoxDecoration(
      gradient: following ? null : AppColors.brandGradient,
      color: following
          ? (onDark
                ? Colors.white24
                : Theme.of(context).colorScheme.surfaceContainerHigh)
          : null,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          child: Text(
            following ? tr('Following') : tr('Follow'),
            style: TextStyle(
              color: following && !onDark
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Gold coin balance chip.
class CoinChip extends StatelessWidget {
  const CoinChip({super.key, required this.coins, this.onTap});
  final int coins;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CoinIcon(size: 20),
          const SizedBox(width: 6),
          Text(
            compactCount(coins),
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            const Icon(Icons.add_rounded, size: 16, color: AppColors.ink),
          ],
        ],
      ),
    ),
  );
}

class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: AppColors.goldGradient,
      border: Border.all(
        color: Colors.white.withValues(alpha: .85),
        width: size * .08,
      ),
    ),
    child: Center(
      child: Text(
        'R',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * .5,
          height: 1,
        ),
      ),
    ),
  );
}

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, this.small = false});
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: small ? 6 : 8,
      vertical: small ? 1 : 3,
    ),
    decoration: BoxDecoration(
      gradient: AppColors.liveGradient,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      'LIVE',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: small ? 9 : 11,
        letterSpacing: .8,
      ),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

/// Asks for a reason and files a report. Returns true when sent.
Future<bool> showReportDialog(
  BuildContext context,
  WidgetRef ref,
  String type,
  int id,
) async {
  final reasons = [
    'Spam',
    tr('Nudity or sexual content'),
    tr('Hate or harassment'),
    tr('Violence'),
    tr('False information'),
    tr('Something else'),
  ];
  final reason = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              tr('Why are you reporting this?'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final r in reasons)
            ListTile(
              title: Text(r),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, r),
            ),
        ],
      ),
    ),
  );
  if (reason == null || !context.mounted) return false;
  try {
    await ref.read(apiProvider).report(type, id, reason);
    if (context.mounted) {
      showToast(context, tr('Thanks — our team will review it.'));
    }
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

/// Who can watch a video: value, label, icon.
/// [subscribers]: the creator offers subscriptions, so "Subscribers only" is possible.
List<(String, String, IconData)> visibilityOptions({
  bool subscribers = false,
}) => [
  ('public', tr('Everyone'), Icons.public_rounded),
  ('friends', tr('Friends (you follow each other)'), Icons.people_alt_rounded),
  if (subscribers)
    ('subscribers', tr('Subscribers only'), Icons.workspace_premium_rounded),
  ('private', tr('Only me'), Icons.lock_rounded),
];

String visibilityLabel(String v) => switch (v) {
  'friends' => tr('Friends'),
  'subscribers' => tr('Subscribers'),
  'private' => tr('Only me'),
  _ => tr('Everyone'),
};

/// Text where @username is bold and opens that profile.
class MentionText extends StatelessWidget {
  const MentionText({
    super.key,
    required this.text,
    required this.onMention,
    this.style,
  });
  final String text;
  final void Function(String username) onMention;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    text.splitMapJoin(
      RegExp(r'@[A-Za-z0-9_.]{3,30}'),
      onMatch: (m) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => onMention(m[0]!.substring(1).toLowerCase()),
              child: Text(
                m[0]!,
                style: base.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.emeraldLight,
                ),
              ),
            ),
          ),
        );
        return '';
      },
      onNonMatch: (s) {
        spans.add(TextSpan(text: s));
        return '';
      },
    );
    return Text.rich(TextSpan(children: spans, style: base));
  }
}

/// Gifter level badge, e.g. "Lv 12". Colour changes every 10 levels.
/// Gifter level badge: the VIP style (Bronze → King) from level 5, a plain "Lv n" below.
class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.level, this.small = false});
  final int level;
  final bool small;

  @override
  Widget build(BuildContext context) => VipBadge(level: level, small: small);
}
