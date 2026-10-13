import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio_track.dart';
import '../i18n.dart';
import '../models.dart';
import '../vip.dart';
import 'common.dart';

/// Gifts on screen, TikTok-style:
/// * every gift: a banner on the left that counts up while the same person keeps sending (x2, x3 … x99);
/// * mid-price gifts (≥ 49 coins): a big pop in the middle;
/// * premium gifts (≥ 199 coins): a full-screen animation (rocket, diamond, castle, lion, universe…),
///   played one after another when several arrive.
class GiftOverlay extends StatefulWidget {
  const GiftOverlay({super.key});

  @override
  State<GiftOverlay> createState() => GiftOverlayState();
}

class _Combo {
  _Combo(this.id, this.event, this.count);
  final int id;
  final GiftEvent event;
  int count;
  int bump = 0;
  Timer? timer;
}

class GiftOverlayState extends State<GiftOverlay> {
  final _combos = <String, _Combo>{};
  final _bigQueue = <GiftEvent>[];
  GiftEvent? _big;
  (int, GiftEvent)? _burst;
  (int, String, String?, int)? _entrance;
  int _seq = 0;

  @override
  void dispose() {
    for (final c in _combos.values) {
      c.timer?.cancel();
    }
    super.dispose();
  }

  void show(GiftEvent e) {
    // Gifts announced by others carry no animation: take it from the gift list.
    final known = knownGifts[e.gift.name];
    if (e.gift.animUrl == null && e.gift.soundUrl == null && known != null && (known.animUrl != null || known.soundUrl != null)) {
      e = GiftEvent(
        gift: known,
        senderName: e.senderName,
        senderAvatar: e.senderAvatar,
        quantity: e.quantity,
        senderLevel: e.senderLevel,
      );
    }
    final premium = e.gift.coins >= 199 || e.gift.animUrl != null;
    final key = '${e.senderName}|${e.gift.name}';
    final id = ++_seq;
    setState(() {
      final c = _combos[key];
      if (c != null) {
        c.count += e.quantity;
        c.bump++;
        c.timer?.cancel();
        c.timer = _expire(key);
      } else {
        if (_combos.length >= 3) {
          final oldest = _combos.keys.first;
          _combos.remove(oldest)?.timer?.cancel();
        }
        _combos[key] = _Combo(id, e, e.quantity)..timer = _expire(key);
      }
      if (premium) {
        _bigQueue.add(e);
        _big ??= _bigQueue.removeAt(0);
        _burst = null;
      } else if (e.gift.coins >= 49 || e.total >= 490) {
        _burst = (id, e);
      }
    });
    if (premium) HapticFeedback.heavyImpact();
    Timer(const Duration(milliseconds: 2600), () {
      if (mounted && _burst?.$1 == id) setState(() => _burst = null);
    });
  }

  /// VIP entrance (Gold and up) when someone joins the live; King gets a bigger one.
  void entrance(String name, String? avatar, int level) {
    if (vipOf(level) == null) return;
    final id = ++_seq;
    setState(() => _entrance = (id, name, avatar, level));
    if (level >= 45) HapticFeedback.mediumImpact();
    Timer(const Duration(milliseconds: 3600), () {
      if (mounted && _entrance?.$1 == id) setState(() => _entrance = null);
    });
  }

  Timer _expire(String key) => Timer(const Duration(milliseconds: 3500), () {
    if (mounted) setState(() => _combos.remove(key));
  });

  void _bigDone() {
    if (!mounted) return;
    setState(() => _big = _bigQueue.isEmpty ? null : _bigQueue.removeAt(0));
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (_big != null)
          _BigGiftEffect(key: ValueKey(_big), event: _big!, onDone: _bigDone),
        if (_entrance != null && _big == null)
          _VipEntrance(
            key: ValueKey(_entrance!.$1),
            name: _entrance!.$2,
            avatar: _entrance!.$3,
            level: _entrance!.$4,
          ),
        Positioned(
          left: 10,
          top: MediaQuery.sizeOf(context).height * .3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in _combos.values)
                _ComboBanner(key: ValueKey(c.id), combo: c),
            ],
          ),
        ),
        if (_burst != null && _big == null)
          Center(
            child: TweenAnimationBuilder<double>(
              key: ValueKey(_burst!.$1),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 2400),
              builder: (context, t, _) {
                final scale = t < .25 ? Curves.easeOutBack.transform(t / .25) * 1.15 : 1.15 - (t - .25) * .2;
                final opacity = t < .8 ? 1.0 : (1 - t) / .2;
                return Opacity(
                  opacity: opacity.clamp(0, 1),
                  child: Transform.translate(
                    offset: Offset(0, -40 * t),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 210 * scale,
                          height: 210 * scale,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [const Color(0x88FFD45E), const Color(0x00FFD45E)],
                            ),
                          ),
                        ),
                        Transform.scale(
                          scale: scale,
                          child: Text(
                            _burst!.$2.gift.icon,
                            style: const TextStyle(fontSize: 130, shadows: [Shadow(blurRadius: 40, color: Colors.black54)]),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    ),
  );
}

/// "Name sent Rose  🌹 x12": slides in, and the counter bounces on every new gift.
class _ComboBanner extends StatelessWidget {
  const _ComboBanner({super.key, required this.combo});
  final _Combo combo;

  @override
  Widget build(BuildContext context) {
    final e = combo.event;
    final vip = vipOf(e.senderLevel);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(-70 * (1 - t), 0), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: vip == null
                      ? const [Color(0xCC1F2937), Color(0x661F2937)]
                      : [vip.colors.first.withValues(alpha: .9), vip.colors.last.withValues(alpha: .35)],
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Avatar(url: e.senderAvatar, name: e.senderName, radius: 17),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (vip != null) ...[VipBadge(level: e.senderLevel, small: true), const SizedBox(width: 4)],
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Text(
                              e.senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        tr('sent {0}', [e.gift.name]),
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Text(e.gift.icon, style: const TextStyle(fontSize: 30)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            TweenAnimationBuilder<double>(
              key: ValueKey('${combo.id}-${combo.bump}'),
              tween: Tween(begin: 1.7, end: 1),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              builder: (context, s, child) => Transform.scale(scale: s, child: child),
              child: Text(
                'x${combo.count}',
                style: const TextStyle(
                  color: Color(0xFFFFD45E),
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  shadows: [Shadow(blurRadius: 6, color: Color(0xFFFF5F2E)), Shadow(blurRadius: 2, color: Colors.black)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Kind { rocket, diamond, castle, lion, universe, fireworks }

_Kind _kindOf(Gift g) {
  final n = g.name.toLowerCase();
  if (n.contains('rocket') || g.icon == '🚀') return _Kind.rocket;
  if (n.contains('diamond') || g.icon == '💎') return _Kind.diamond;
  if (n.contains('castle') || g.icon == '🏰') return _Kind.castle;
  if (n.contains('lion') || g.icon == '🦁') return _Kind.lion;
  if (n.contains('universe') || n.contains('galaxy') || g.icon == '🌌') return _Kind.universe;
  return _Kind.fireworks;
}

/// One full-screen animation for a premium gift (about 4 seconds), then [onDone].
class _BigGiftEffect extends StatefulWidget {
  const _BigGiftEffect({super.key, required this.event, required this.onDone});
  final GiftEvent event;
  final VoidCallback onDone;

  @override
  State<_BigGiftEffect> createState() => _BigGiftEffectState();
}

class _BigGiftEffectState extends State<_BigGiftEffect> with SingleTickerProviderStateMixin {
  late final _Kind _kind = _kindOf(widget.event.gift);
  /// The uploaded animation, once downloaded (null: none, still loading, or it failed).
  Uint8List? _bytes;
  late final AnimationController _c = AnimationController(vsync: this)
    ..addStatusListener((st) {
      if (st == AnimationStatus.completed) widget.onDone();
    });
  final _seed = Random().nextInt(1 << 30);
  AudioTrack? _sound;

  @override
  void initState() {
    super.initState();
    final url = widget.event.gift.animUrl;
    if (url == null) {
      _start(Duration(milliseconds: _kind == _Kind.universe || _kind == _Kind.lion ? 4800 : 4000));
      return;
    }
    // Wait for the file (the effect would otherwise run out before a big GIF arrives), then play all of it.
    _loadAnim(url).timeout(const Duration(seconds: 10)).then((bytes) {
      if (!mounted) return;
      final file = animationLength(bytes);
      final wanted = Duration(milliseconds: widget.event.gift.animMs ?? 0);
      final len = file == null ? (wanted > Duration.zero ? wanted : const Duration(seconds: 5)) : (wanted > file ? wanted : file);
      setState(() => _bytes = bytes);
      _start(len + const Duration(milliseconds: 400));
    }).catchError((Object _) {
      // Couldn't download it: play the built-in effect instead.
      if (mounted) _start(const Duration(milliseconds: 4800));
    });
  }

  void _start(Duration length) {
    _c.duration = Duration(milliseconds: length.inMilliseconds.clamp(2000, 20000));
    _c.forward();
    final s = widget.event.gift.soundUrl;
    if (s != null) {
      final t = _sound = AudioTrack(s, loop: false);
      t.initialize().then((_) => t.play()).catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _sound?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) {
      final t = _c.value;
      final size = MediaQuery.sizeOf(context);
      // Quick fade in / out (about 0.35 s whatever the length).
      final edge = 350 / max(1, _c.duration?.inMilliseconds ?? 4000);
      final fade = t < edge ? t / edge : (t > 1 - edge ? (1 - t) / edge : 1.0);
      return Opacity(
        opacity: fade.clamp(0.0, 1.0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Dim the stream a little so the effect stands out.
            ColoredBox(color: Colors.black.withValues(alpha: _kind == _Kind.universe ? .55 : .3)),
            CustomPaint(painter: _ParticlesPainter(_kind, t, _seed)),
            if (_bytes != null)
              // The uploaded animation (e.g. a 3D lion), full width; the built-in one if it can't load.
              Center(
                child: Transform.translate(
                  offset: Offset(0, -size.height * .04),
                  child: SizedBox(
                    width: min(size.width, 720),
                    height: size.height * .8,
                    child: GiftAnimation(
                      bytes: _bytes!,
                      fallback: Stack(fit: StackFit.expand, children: [_hero(t, size)]),
                    ),
                  ),
                ),
              )
            else
              _hero(t, size),
            Positioned(
              left: 24,
              right: 24,
              bottom: size.height * .2,
              child: _SenderBanner(event: widget.event, t: t),
            ),
          ],
        ),
      );
    },
  );

  Widget _emoji(String e, double fontSize) =>
      Text(e, style: TextStyle(fontSize: fontSize, shadows: const [Shadow(blurRadius: 30, color: Colors.black54)]));

  /// The gift itself, moving the way its theme does.
  Widget _hero(double t, Size size) {
    final icon = widget.event.gift.icon;
    switch (_kind) {
      case _Kind.rocket:
        // Shakes on the pad, then launches to the top.
        final launch = Curves.easeInCubic.transform(((t - .25) / .6).clamp(0.0, 1.0));
        final shake = t < .25 ? sin(t * 120) * 3 : 0.0;
        return Positioned(
          left: size.width / 2 - 60 + shake,
          top: size.height * .62 - launch * size.height * .95,
          child: Transform.rotate(angle: -pi / 4, child: _emoji(icon, 110)),
        );
      case _Kind.diamond:
        final fall = Curves.bounceOut.transform((t / .4).clamp(0.0, 1.0));
        final spin = t * pi * 4;
        return Positioned(
          left: size.width / 2 - 70,
          top: -150 + fall * (size.height * .35 + 150),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .002)
              ..rotateY(spin),
            child: _emoji(icon, 130),
          ),
        );
      case _Kind.castle:
        final rise = Curves.easeOutBack.transform((t / .35).clamp(0.0, 1.0));
        return Positioned(
          left: size.width / 2 - 85,
          top: size.height * .32 + (1 - rise) * size.height * .6,
          child: _emoji(icon, 160),
        );
      case _Kind.lion:
        final zoom = Curves.elasticOut.transform((t / .45).clamp(0.0, 1.0));
        final roar = t > .45 && t < .6 ? sin(t * 200) * 6 : 0.0;
        return Center(
          child: Transform.translate(
            offset: Offset(roar, -size.height * .05),
            child: Transform.scale(scale: .3 + zoom * .9, child: _emoji(icon, 170)),
          ),
        );
      case _Kind.universe:
        final appear = Curves.easeOutCubic.transform(((t - .3) / .35).clamp(0.0, 1.0));
        final orbit = t * pi * 3;
        final r = 120.0 + 30 * sin(t * pi);
        return Stack(
          children: [
            for (final (i, p) in ['🪐', '🌍', '🌙'].indexed)
              Positioned(
                left: size.width / 2 - 24 + cos(orbit + i * 2.1) * r,
                top: size.height * .42 - 24 + sin(orbit + i * 2.1) * r * .55,
                child: Opacity(opacity: appear, child: _emoji(p, 44)),
              ),
            Center(
              child: Transform.translate(
                offset: Offset(0, -size.height * .08),
                child: Transform.scale(scale: .2 + appear, child: _emoji(icon, 150)),
              ),
            ),
          ],
        );
      case _Kind.fireworks:
        final pop = Curves.easeOutBack.transform((t / .3).clamp(0.0, 1.0));
        return Center(
          child: Transform.translate(
            offset: Offset(0, -size.height * .06),
            child: Transform.scale(scale: pop, child: _emoji(icon, 150)),
          ),
        );
    }
  }
}

/// "{name} sent Castle 🏰" at the bottom of a premium gift effect.
class _SenderBanner extends StatelessWidget {
  const _SenderBanner({required this.event, required this.t});
  final GiftEvent event;
  final double t;

  @override
  Widget build(BuildContext context) {
    final vip = vipOf(event.senderLevel);
    final slide = Curves.easeOutBack.transform(((t - .15) / .25).clamp(0.0, 1.0));
    return Transform.scale(
      scale: slide,
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 18, 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: vip == null
                  ? const [Color(0xFFFF2E63), Color(0xFFFFB020)]
                  : [vip.colors.first, vip.colors.last],
            ),
            borderRadius: BorderRadius.circular(40),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(url: event.senderAvatar, name: event.senderName, radius: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  event.quantity > 1
                      ? '${event.senderName} ${tr('sent {0}', [event.gift.name])} x${event.quantity}'
                      : '${event.senderName} ${tr('sent {0}', [event.gift.name])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fireworks, sparkles, golden rays, coin rain, warp stars and rocket flames, drawn from a fixed seed
/// so every frame of one effect is consistent.
class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter(this.kind, this.t, this.seed);
  final _Kind kind;
  final double t;
  final int seed;

  static const _palette = [
    Color(0xFFFF5F6D), Color(0xFFFFD45E), Color(0xFF22D3EE), Color(0xFFA78BFA), Color(0xFF34D399), Color(0xFFFF8A00),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(seed);
    switch (kind) {
      case _Kind.rocket:
        _stars(canvas, size, rnd, 60);
        _flames(canvas, size);
        if (t > .8) _burst(canvas, Offset(size.width / 2, size.height * .15), (t - .8) / .2, rnd, 40, 160);
      case _Kind.diamond:
        _sparkles(canvas, size, rnd, Offset(size.width / 2, size.height * .45));
      case _Kind.castle:
        for (var i = 0; i < 6; i++) {
          final start = .25 + i * .1;
          final p = (t - start) / .35;
          if (p > 0 && p < 1) {
            final c = Offset(size.width * (.15 + rnd.nextDouble() * .7), size.height * (.12 + rnd.nextDouble() * .3));
            _burst(canvas, c, p, Random(seed + i), 28, 70 + rnd.nextDouble() * 60);
          } else {
            rnd.nextDouble();
            rnd.nextDouble();
            rnd.nextDouble();
          }
        }
      case _Kind.lion:
        _rays(canvas, size, Offset(size.width / 2, size.height * .45));
        _coinRain(canvas, size, rnd);
      case _Kind.universe:
        _warp(canvas, size, rnd);
      case _Kind.fireworks:
        for (var i = 0; i < 4; i++) {
          final p = (t - i * .15) / .45;
          if (p > 0 && p < 1) {
            final c = Offset(size.width * (.2 + .6 * Random(seed + i).nextDouble()), size.height * (.2 + .25 * Random(seed + 7 * i).nextDouble()));
            _burst(canvas, c, p, Random(seed + i), 30, 110);
          }
        }
    }
  }

  void _burst(Canvas canvas, Offset c, double p, Random rnd, int n, double radius) {
    final paint = Paint();
    for (var i = 0; i < n; i++) {
      final a = i / n * 2 * pi + rnd.nextDouble() * .2;
      final d = radius * Curves.easeOutCubic.transform(p) * (.7 + rnd.nextDouble() * .3);
      final pos = c + Offset(cos(a) * d, sin(a) * d + 40 * p * p);
      paint.color = _palette[i % _palette.length].withValues(alpha: (1 - p).clamp(0.0, 1.0));
      canvas.drawCircle(pos, 3.2 * (1 - p * .6), paint);
    }
  }

  void _stars(Canvas canvas, Size size, Random rnd, int n) {
    final paint = Paint()..color = Colors.white;
    for (var i = 0; i < n; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = (rnd.nextDouble() * size.height + t * size.height * (1 + rnd.nextDouble())) % size.height;
      paint.color = Colors.white.withValues(alpha: .3 + .5 * rnd.nextDouble());
      canvas.drawCircle(Offset(x, y), 1 + rnd.nextDouble() * 1.5, paint);
    }
  }

  void _flames(Canvas canvas, Size size) {
    final launch = Curves.easeInCubic.transform(((t - .25) / .6).clamp(0.0, 1.0));
    final base = Offset(size.width / 2 - 20, size.height * .62 - launch * size.height * .95 + 120);
    for (var i = 0; i < 18; i++) {
      final k = i / 18;
      final paint = Paint()
        ..shader = RadialGradient(colors: [const Color(0xFFFFF3B0), const Color(0xFFFF8A00).withValues(alpha: .7), const Color(0x00FF2E63)])
            .createShader(Rect.fromCircle(center: base + Offset(-k * 30, k * 140), radius: 26 - k * 10));
      canvas.drawCircle(base + Offset(-k * 30 + sin(t * 60 + i) * 4, k * 140), 26 - k * 10, paint);
    }
  }

  void _sparkles(Canvas canvas, Size size, Random rnd, Offset c) {
    final paint = Paint();
    for (var i = 0; i < 70; i++) {
      final a = rnd.nextDouble() * 2 * pi;
      final speed = .4 + rnd.nextDouble();
      final p = ((t - .3) * speed * 1.6).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final d = p * size.width * .55;
      final pos = c + Offset(cos(a) * d, sin(a) * d);
      paint.color = HSVColor.fromAHSV((1 - p).clamp(0.0, 1.0), (i * 37) % 360.0, .5, 1).toColor();
      final s = 2.5 + 3 * (1 - p);
      final path = Path()
        ..moveTo(pos.dx, pos.dy - s * 2)
        ..lineTo(pos.dx + s * .6, pos.dy)
        ..lineTo(pos.dx, pos.dy + s * 2)
        ..lineTo(pos.dx - s * .6, pos.dy)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _rays(Canvas canvas, Size size, Offset c) {
    final paint = Paint()..color = const Color(0x55FFD45E);
    final spin = t * pi;
    for (var i = 0; i < 16; i++) {
      final a = spin + i * pi / 8;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + cos(a - .08) * size.height, c.dy + sin(a - .08) * size.height)
        ..lineTo(c.dx + cos(a + .08) * size.height, c.dy + sin(a + .08) * size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.drawCircle(c, size.width * .35, Paint()..shader = RadialGradient(colors: const [Color(0x99FFD45E), Color(0x00FFD45E)])
        .createShader(Rect.fromCircle(center: c, radius: size.width * .35)));
  }

  void _coinRain(Canvas canvas, Size size, Random rnd) {
    for (var i = 0; i < 40; i++) {
      final x = rnd.nextDouble() * size.width;
      final delay = rnd.nextDouble() * .5;
      final p = ((t - delay) / .5).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final y = -20 + p * (size.height + 40);
      final r = 7 + rnd.nextDouble() * 5;
      final squash = cos(t * 20 + i).abs();
      final rect = Rect.fromCenter(center: Offset(x, y), width: r * 2 * (.3 + .7 * squash), height: r * 2);
      canvas.drawOval(rect, Paint()..color = const Color(0xFFF59E0B));
      canvas.drawOval(rect.deflate(2), Paint()..color = const Color(0xFFFDE68A));
    }
  }

  void _warp(Canvas canvas, Size size, Random rnd) {
    final c = Offset(size.width / 2, size.height * .42);
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 140; i++) {
      final a = rnd.nextDouble() * 2 * pi;
      final speed = .3 + rnd.nextDouble();
      final p = ((t * speed * 2 + rnd.nextDouble()) % 1.0);
      final d1 = p * p * size.height;
      final d2 = d1 * .82;
      paint
        ..color = HSVColor.fromAHSV((.3 + p * .7).clamp(0.0, 1.0), 200 + 80 * rnd.nextDouble(), .4, 1).toColor()
        ..strokeWidth = .8 + p * 2.2;
      canvas.drawLine(c + Offset(cos(a) * d2, sin(a) * d2), c + Offset(cos(a) * d1, sin(a) * d1), paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter old) => old.t != t;
}

/// A VIP walking in: a shining banner sweeps across the screen in the tier's colours.
/// King (level 45+) adds golden rays behind it.
class _VipEntrance extends StatelessWidget {
  const _VipEntrance({super.key, required this.name, required this.avatar, required this.level});
  final String name;
  final String? avatar;
  final int level;

  @override
  Widget build(BuildContext context) {
    final vip = vipOf(level)!;
    final king = level >= 45;
    final size = MediaQuery.sizeOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 3400),
      builder: (context, t, _) {
        // Slide in, hold, slide out to the left.
        final x = t < .18
            ? Curves.easeOutCubic.transform(t / .18) - 1
            : t > .82
            ? -Curves.easeInCubic.transform((t - .82) / .18)
            : 0.0;
        final shine = ((t * 2.2) % 1.0) * 2 - .5;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (king)
              Opacity(
                opacity: (t < .1 ? t / .1 : t > .85 ? (1 - t) / .15 : 1.0).clamp(0.0, 1.0) * .8,
                child: CustomPaint(painter: _ParticlesPainter(_Kind.lion, t, name.hashCode)),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: size.height * (king ? .36 : .22),
              child: Transform.translate(
                offset: Offset(x * size.width, 0),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: EdgeInsets.fromLTRB(6, 6, 20, 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      gradient: LinearGradient(
                        colors: [vip.colors.first, vip.colors.last, vip.colors.first],
                        stops: [0, shine.clamp(0.0, 1.0), 1],
                      ),
                      boxShadow: [BoxShadow(color: vip.color.withValues(alpha: .6), blurRadius: king ? 30 : 16)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Avatar(url: avatar, name: name, radius: king ? 24 : 18),
                        const SizedBox(width: 10),
                        Text(vip.icon, style: TextStyle(fontSize: king ? 26 : 20)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: king ? 17 : 14.5,
                                  shadows: const [Shadow(blurRadius: 4, color: Colors.black45)],
                                ),
                              ),
                              Text(
                                tr('{0} VIP has entered', [vip.label]),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  shadows: [Shadow(blurRadius: 3, color: Colors.black45)],
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
          ],
        );
      },
    );
  }
}

final _animBytes = <String, Future<Uint8List>>{};

Future<Uint8List> _loadAnim(String url) => _animBytes[url] ??= Dio()
    .get<List<int>>(url, options: Options(responseType: ResponseType.bytes))
    .then((r) => Uint8List.fromList(r.data!))
    .catchError((Object e) {
      _animBytes.remove(url); // try again next time
      throw e;
    });

/// Downloads the gift animations of [gifts] ahead of time, so they play at once when sent.
void preloadGiftAnimations(Iterable<Gift> gifts) {
  for (final g in gifts) {
    final a = g.animUrl;
    if (a != null) _loadAnim(a).ignore();
  }
}

/// Plays an animated WebP / GIF from its first frame (Image.network would resume a cached animation
/// wherever it stopped last time), looping if the effect runs longer than the file.
class GiftAnimation extends StatefulWidget {
  const GiftAnimation({super.key, required this.bytes, required this.fallback});
  final Uint8List bytes;
  final Widget fallback;

  @override
  State<GiftAnimation> createState() => _GiftAnimationState();
}

class _GiftAnimationState extends State<GiftAnimation> {
  ui.Image? _frame;
  bool _failed = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _play();
  }

  Future<void> _play() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      while (!_gone) {
        final f = await codec.getNextFrame();
        if (_gone) {
          f.image.dispose();
          break;
        }
        setState(() {
          _frame?.dispose();
          _frame = f.image;
        });
        if (codec.frameCount == 1) break;
        await Future<void>.delayed(_frameTime(f.duration));
      }
      codec.dispose();
    } catch (_) {
      if (!_gone) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _gone = true;
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    final f = _frame;
    if (f == null) return const SizedBox.shrink();
    return RawImage(image: f, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
  }
}

/// Browsers and Android show frames marked 0–10 ms for 100 ms.
Duration _frameTime(Duration d) => d.inMilliseconds <= 10 ? const Duration(milliseconds: 100) : d;

/// How long one pass of an animated GIF / WebP lasts, read from the file (null if it can't tell).
Duration? animationLength(Uint8List b) {
  try {
    var ms = 0, frames = 0;
    void add(int d) {
      ms += _frameTime(Duration(milliseconds: d)).inMilliseconds;
      frames++;
    }

    if (b.length > 13 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      // GIF: walk the blocks; each Graphic Control Extension holds a frame delay in 1/100 s.
      var i = 13;
      if (b[10] & 0x80 != 0) i += 3 * (2 << (b[10] & 7));
      int skipSubBlocks(int i) {
        while (b[i] != 0) {
          i += b[i] + 1;
        }
        return i + 1;
      }

      while (i < b.length) {
        final t = b[i];
        if (t == 0x21) {
          if (b[i + 1] == 0xF9) add((b[i + 4] | b[i + 5] << 8) * 10);
          i = skipSubBlocks(i + 2);
        } else if (t == 0x2C) {
          final packed = b[i + 9];
          i += 10;
          if (packed & 0x80 != 0) i += 3 * (2 << (packed & 7));
          i = skipSubBlocks(i + 1);
        } else {
          break; // 0x3B: end
        }
      }
    } else if (b.length > 16 && String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' && String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
      // Animated WebP: every ANMF chunk has a 24-bit duration in ms.
      var i = 12;
      while (i + 8 <= b.length) {
        final id = String.fromCharCodes(b.sublist(i, i + 4));
        final size = b[i + 4] | b[i + 5] << 8 | b[i + 6] << 16 | b[i + 7] << 24;
        if (id == 'ANMF') add(b[i + 20] | b[i + 21] << 8 | b[i + 22] << 16);
        i += 8 + size + (size & 1);
      }
    }
    return frames > 1 ? Duration(milliseconds: ms) : null;
  } catch (_) {
    return null;
  }
}
