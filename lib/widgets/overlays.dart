import 'package:flutter/material.dart';

import '../models.dart';

/// Colours offered for text overlays.
const overlayColors = [
  0xFFFFFFFF,
  0xFF000000,
  0xFFFFCC00,
  0xFFFF3B5C,
  0xFF1FBF8F,
  0xFF38BDF8,
  0xFFA855F7,
];

/// Draws a video's texts and stickers on top of it. Positions are fractions of the area.
class OverlayLayer extends StatelessWidget {
  const OverlayLayer({super.key, required this.overlays});
  final List<VideoOverlay> overlays;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Stack(
      children: [
        for (final o in overlays)
          Align(
            alignment: Alignment(o.x * 2 - 1, o.y * 2 - 1),
            child: OverlayLabel(overlay: o, areaWidth: box.maxWidth),
          ),
      ],
    ),
  );
}

/// One text or sticker. Sizes scale with the width of the area, so it looks the same on every phone.
class OverlayLabel extends StatelessWidget {
  const OverlayLabel({
    super.key,
    required this.overlay,
    required this.areaWidth,
  });
  final VideoOverlay overlay;
  final double areaWidth;

  @override
  Widget build(BuildContext context) {
    final o = overlay;
    final base = areaWidth / 16;
    if (o.style == 'sticker') {
      return Text(
        o.text,
        style: TextStyle(fontSize: base * 2.4 * o.size, height: 1),
      );
    }
    final color = Color(o.color);
    final dark = color.computeLuminance() < .4;
    final text = Text(
      o.text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: o.style == 'box' ? (dark ? Colors.white : Colors.black) : color,
        fontSize: base * o.size,
        fontWeight: FontWeight.w800,
        height: 1.15,
        shadows: o.style == 'plain'
            ? [
                Shadow(
                  color: dark ? Colors.white54 : Colors.black87,
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: areaWidth * .86),
      child: o.style == 'box'
          ? Container(
              padding: EdgeInsets.symmetric(
                horizontal: base * .5,
                vertical: base * .25,
              ),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(base * .35),
              ),
              child: text,
            )
          : text,
    );
  }
}
