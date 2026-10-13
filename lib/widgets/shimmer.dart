import 'package:flutter/material.dart';

/// A soft light sweeping across a placeholder while content loads.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, this.radius = 0});
  final double radius;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final light = Color.lerp(base, scheme.surface, .55)!;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * 3 - 1; // sweep from left (-1) to right (2)
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + t, -0.3),
              end: Alignment(t, 0.3),
              colors: [base, light, base],
              stops: const [0.1, 0.5, 0.9],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
