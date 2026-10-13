import 'dart:async';

import 'package:flutter/material.dart';

import 'recharge_sheet.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import 'common.dart';
import '../i18n.dart';

import 'gift_effects.dart';

export 'gift_effects.dart';

/// Gift picker, TikTok-style: pick a gift and how many (x1 … x99), send, and keep tapping the combo
/// button to send again. Stays open; [onSent] runs after every gift that went through.
Future<void> showGiftSheet(
  BuildContext context, {
  int? liveId,
  int? videoId,
  required void Function(GiftEvent sent) onSent,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.inkSurface,
  barrierColor: Colors.black26,
  builder: (_) => Theme(
    data: buildTheme(Brightness.dark),
    child: _GiftSheet(liveId: liveId, videoId: videoId, onSent: onSent),
  ),
);

const _quantities = [1, 5, 10, 99];

class _GiftSheet extends ConsumerStatefulWidget {
  const _GiftSheet({this.liveId, this.videoId, required this.onSent});
  final int? liveId;
  final int? videoId;
  final void Function(GiftEvent sent) onSent;

  @override
  ConsumerState<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends ConsumerState<_GiftSheet>
    with SingleTickerProviderStateMixin {
  List<Gift>? _gifts;
  int? _balance;
  Gift? _selected;
  int _quantity = 1;
  bool _sending = false;
  Object? _error;

  /// Combo window after a send: the button turns into a countdown ring.
  late final _combo = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  int _comboCount = 0;

  @override
  void initState() {
    super.initState();
    _combo.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _comboCount = 0);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _combo.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider);
    try {
      final r = await Future.wait([api.gifts(), api.wallet()]);
      if (!mounted) return;
      setState(() {
        _gifts = r[0] as List<Gift>;
        preloadGiftAnimations(_gifts!);
        _balance = (r[1] as Wallet).coins;
        _selected ??= _gifts!.isEmpty ? null : _gifts!.first;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _recharge() async {
    // TikTok-style: recharge right here, without leaving the gift sheet.
    _combo.reset();
    setState(() => _comboCount = 0);
    await showRechargeSheet(context, ref);
    _load();
  }

  void _pick(Gift g) {
    if (g.id != _selected?.id) {
      _combo.reset();
      _comboCount = 0;
    }
    setState(() => _selected = g);
  }

  void _pickQuantity(int q) {
    if (q != _quantity) {
      _combo.reset();
      _comboCount = 0;
    }
    setState(() => _quantity = q);
  }

  Future<void> _send() async {
    final g = _selected;
    if (g == null || _sending) return;
    final q = _quantity;
    if ((_balance ?? 0) < g.coins * q) {
      await _recharge();
      return;
    }
    setState(() => _sending = true);
    try {
      final balance = await ref
          .read(apiProvider)
          .sendGift(g.id, liveId: widget.liveId, videoId: widget.videoId, quantity: q);
      HapticFeedback.mediumImpact();
      final me = ref.read(sessionProvider).value;
      widget.onSent(
        GiftEvent(
          gift: g,
          senderName: me?.displayName ?? tr('You'),
          senderAvatar: me?.avatarUrl,
          quantity: q,
          senderLevel: me?.level ?? 0,
        ),
      );
      if (mounted) {
        setState(() {
          _balance = balance;
          _comboCount += q;
        });
        _combo.forward(from: 0);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gifts = _gifts;
    final g = _selected;
    final cost = (g?.coins ?? 0) * _quantity;
    final short = g != null && (_balance ?? 0) < cost;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  tr('Send a gift'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (_balance != null)
                  CoinChip(coins: _balance!, onTap: _recharge),
              ],
            ),
            const SizedBox(height: 14),
            if (gifts == null)
              SizedBox(
                height: 200,
                child: Center(
                  child: _error != null
                      ? Text('$_error')
                      : const CircularProgressIndicator(),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .42,
                ),
                child: GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: .82,
                  children: [
                    for (final g in gifts)
                      _GiftTile(
                        gift: g,
                        selected: g.id == _selected?.id,
                        onTap: () => _pick(g),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final q in _quantities)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _QuantityChip(
                      quantity: q,
                      selected: q == _quantity,
                      onTap: () => _pickQuantity(q),
                    ),
                  ),
                const Spacer(),
                if (_comboCount > 0 && g != null)
                  _ComboButton(
                    animation: _combo,
                    gift: g,
                    count: _comboCount,
                    busy: _sending,
                    onTap: _send,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            GradientButton(
              label: g == null
                  ? tr('Choose a gift')
                  : short
                  ? tr('Recharge to send {0}', [g.name])
                  : _quantity > 1
                  ? tr('Send {0} x{1} · {2}', [g.name, _quantity, cost])
                  : tr('Send {0} · {1}', [g.name, cost]),
              icon: Icons.card_giftcard_rounded,
              busy: _sending && _comboCount == 0,
              gradient: AppColors.goldGradient,
              onPressed: g == null ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityChip extends StatelessWidget {
  const _QuantityChip({
    required this.quantity,
    required this.selected,
    required this.onTap,
  });
  final int quantity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? AppColors.amber : Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'x$quantity',
        style: TextStyle(
          color: selected ? Colors.black : Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    ),
  );
}

/// Round "Combo" button with a countdown ring: tap again before it runs out to keep the combo going.
class _ComboButton extends StatelessWidget {
  const _ComboButton({
    required this.animation,
    required this.gift,
    required this.count,
    required this.busy,
    required this.onTap,
  });
  final Animation<double> animation;
  final Gift gift;
  final int count;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: busy ? null : onTap,
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, child) => SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: 1 - animation.value,
                strokeWidth: 4,
                color: AppColors.amber,
                backgroundColor: Colors.white12,
              ),
            ),
            child!,
          ],
        ),
      ),
      child: TweenAnimationBuilder<double>(
        key: ValueKey(count),
        tween: Tween(begin: 1.25, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
        child: Container(
          width: 54,
          height: 54,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFFFF2E63), Color(0xFFFFB020)],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(gift.icon, style: const TextStyle(fontSize: 18)),
              Text(
                'x$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _GiftTile extends StatelessWidget {
  const _GiftTile({
    required this.gift,
    required this.selected,
    required this.onTap,
  });
  final Gift gift;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.amber.withValues(alpha: .14)
            : Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppColors.amber : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: selected ? 1.18 : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Text(gift.icon, style: const TextStyle(fontSize: 34)),
          ),
          const SizedBox(height: 4),
          Text(
            gift.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CoinIcon(size: 12),
              const SizedBox(width: 3),
              Text(
                '${gift.coins}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
