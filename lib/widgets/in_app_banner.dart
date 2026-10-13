import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../push.dart';
import '../theme.dart';

/// The notification card that slides in at the top while the app is open (TikTok style).
/// One at a time: a new one replaces the old. The same alert is never shown twice in a row.
class InAppBanner {
  InAppBanner._();

  static OverlayEntry? _entry;
  static final _recent = <String, DateTime>{};

  /// [dedupeKey]: alerts with the same key within 10 seconds show only once.
  static void show({
    required String title,
    String body = '',
    IconData icon = Icons.notifications_rounded,
    Color color = AppColors.emerald,
    VoidCallback? onTap,
    String? dedupeKey,
  }) {
    final key = dedupeKey ?? '$title|$body';
    final now = DateTime.now();
    _recent.removeWhere(
      (_, t) => now.difference(t) > const Duration(seconds: 10),
    );
    if (_recent.containsKey(key)) return;
    _recent[key] = now;

    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _entry?.remove();
    late final OverlayEntry entry;
    void close() {
      if (_entry == entry) {
        entry.remove();
        _entry = null;
      }
    }

    entry = OverlayEntry(
      builder: (_) => _BannerCard(
        title: title,
        body: body,
        icon: icon,
        color: color,
        onTap: () {
          close();
          onTap?.call();
        },
        onClose: close,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    HapticFeedback.lightImpact();
  }
}

class _BannerCard extends StatefulWidget {
  const _BannerCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.onClose,
  });
  final String title, body;
  final IconData icon;
  final Color color;
  final VoidCallback onTap, onClose;

  @override
  State<_BannerCard> createState() => _BannerCardState();
}

class _BannerCardState extends State<_BannerCard>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (!mounted) return;
    await _anim.reverse();
    widget.onClose();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      top: top,
      left: 10,
      right: 10,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -1.4),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic)),
        child: GestureDetector(
          onTap: widget.onTap,
          // Swipe up to dismiss.
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -100) _dismiss();
          },
          child: Material(
            color: const Color(0xF21C1F1E),
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: widget.color,
                    child: Icon(widget.icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                        if (widget.body.isNotEmpty)
                          Text(
                            widget.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon and colour for a notification type.
(IconData, Color) bannerStyle(String? type) => switch (type) {
  'message' => (Icons.chat_bubble_rounded, const Color(0xFF3B82F6)),
  'like' => (Icons.favorite_rounded, AppColors.like),
  'comment' ||
  'mention' => (Icons.mode_comment_rounded, const Color(0xFF3B82F6)),
  'follow' ||
  'follow_request' => (Icons.person_add_alt_1_rounded, AppColors.emerald),
  'gift' || 'subscribe' => (Icons.card_giftcard_rounded, AppColors.amber),
  'live' => (Icons.podcasts_rounded, AppColors.live),
  _ => (Icons.notifications_rounded, AppColors.emerald),
};
