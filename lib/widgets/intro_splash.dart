import 'dart:math';

import 'package:flutter/material.dart';

import '../config.dart';
import '../i18n.dart';
import '../theme.dart';
import 'common.dart';

/// The animated TalkMe welcome shown while the app starts: glowing background,
/// floating hearts and notes, the logo popping in with a halo, and the name.
/// It follows the phone's own launch screen (same dark colour), so the change is seamless.
class IntroSplash extends StatefulWidget {
  const IntroSplash({super.key});

  @override
  State<IntroSplash> createState() => _IntroSplashState();
}

class _IntroSplashState extends State<IntroSplash>
    with TickerProviderStateMixin {
  // Logo, name and tagline come in once; the background keeps moving.
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();
  late final _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  Animation<double> _part(double from, double to, [Curve c = Curves.easeOut]) =>
      CurvedAnimation(
        parent: _intro,
        curve: Interval(from, to, curve: c),
      );

  @override
  Widget build(BuildContext context) {
    final logo = _part(0, .55, Curves.elasticOut);
    final halo = _part(.1, .6);
    final name = _part(.35, .75, Curves.easeOutCubic);
    final tagline = _part(.55, .95);
    return Material(
      color: AppColors.ink,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Slowly drifting colour glows.
          AnimatedBuilder(
            animation: _loop,
            builder: (context, _) {
              final t = _loop.value * 2 * pi;
              return Stack(
                fit: StackFit.expand,
                children: [
                  _Glow(
                    alignment: Alignment(-.9 + .2 * sin(t), -.75 + .1 * cos(t)),
                    color: AppColors.emerald,
                    size: 520,
                    opacity: .45,
                  ),
                  _Glow(
                    alignment: Alignment(.95 + .1 * cos(t), .8 + .15 * sin(t)),
                    color: const Color(0xFF3B82F6),
                    size: 460,
                    opacity: .32,
                  ),
                  _Glow(
                    alignment: Alignment(.7 * sin(t * .5), .15),
                    color: AppColors.amber,
                    size: 260,
                    opacity: .14,
                  ),
                ],
              );
            },
          ),
          // Hearts, notes and sparkles rising gently.
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _loop,
              builder: (context, _) =>
                  CustomPaint(painter: _FloatersPainter(_loop.value)),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 190,
                  height: 190,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Turning halo ring behind the logo.
                      FadeTransition(
                        opacity: halo,
                        child: RotationTransition(
                          turns: _loop,
                          child: Container(
                            width: 178,
                            height: 178,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SweepGradient(
                                colors: [
                                  Color(0x0014A37F),
                                  AppColors.emeraldLight,
                                  Color(0xFF3B82F6),
                                  AppColors.amber,
                                  Color(0x0014A37F),
                                ],
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Soft pulse
                      AnimatedBuilder(
                        animation: _loop,
                        builder: (context, child) {
                          final p = (sin(_loop.value * 2 * pi * 2) + 1) / 2;
                          return Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.emerald.withValues(
                                    alpha: .25 + .2 * p,
                                  ),
                                  blurRadius: 50 + 20 * p,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      ScaleTransition(
                        scale: Tween(begin: .4, end: 1.0).animate(logo),
                        child: FadeTransition(
                          opacity: _part(0, .25),
                          child: const BrandMark(size: 112),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                SlideTransition(
                  position: Tween(
                    begin: const Offset(0, .5),
                    end: Offset.zero,
                  ).animate(name),
                  child: FadeTransition(
                    opacity: name,
                    child: ShaderMask(
                      shaderCallback: (r) => const LinearGradient(
                        colors: [
                          Colors.white,
                          Color(0xFFB8F5DF),
                          AppColors.emeraldLight,
                        ],
                      ).createShader(r),
                      child: const Text(
                        'TalkMe',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w800,
                          fontSize: 46,
                          letterSpacing: .5,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FadeTransition(
                  opacity: tagline,
                  child: Text(
                    tr('Watch. Go live. Connect.'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15.5,
                      letterSpacing: .4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Small loading bar and version at the bottom.
          Positioned(
            left: 0,
            right: 0,
            bottom: 44 + MediaQuery.paddingOf(context).bottom,
            child: FadeTransition(
              opacity: tagline,
              child: Column(
                children: [
                  SizedBox(
                    width: 110,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        color: AppColors.emeraldLight,
                        backgroundColor: Colors.white.withValues(alpha: .12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'v${AppConfig.appVersion}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({
    required this.alignment,
    required this.color,
    required this.size,
    required this.opacity,
  });
  final Alignment alignment;
  final Color color;
  final double size, opacity;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    ),
  );
}

/// Little hearts, music notes and sparkles floating up across the screen.
class _FloatersPainter extends CustomPainter {
  _FloatersPainter(this.t);
  final double t;

  static const _glyphs = ['♥', '♪', '✦', '♫', '•'];
  static const _colors = [
    Color(0xFFFF5F7E),
    AppColors.emeraldLight,
    AppColors.amber,
    Color(0xFF7DB4FF),
    Colors.white,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    for (var i = 0; i < 22; i++) {
      final x0 = rnd.nextDouble();
      final speed = .5 + rnd.nextDouble();
      final phase = rnd.nextDouble();
      final fontSize = 10 + rnd.nextDouble() * 16;
      final glyph = _glyphs[i % _glyphs.length];
      final color = _colors[rnd.nextInt(_colors.length)];
      final p = (phase + t * speed) % 1.0; // 0 = bottom, 1 = top
      final y = size.height * (1.05 - p * 1.15);
      final x = size.width * x0 + sin((p + phase) * 2 * pi) * 18;
      // Fade in at the bottom and out near the top.
      final alpha = (sin(p * pi) * .55).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: glyph,
          style: TextStyle(
            fontSize: fontSize,
            color: color.withValues(alpha: alpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(_FloatersPainter old) => old.t != t;
}
