import 'package:flutter/widgets.dart';

import 'i18n.dart';

/// Colour filters a creator can put on a video. The file is not changed: the filter is
/// saved with the video and applied when it is shown (feed, profile grid, preview).
class VideoFilter {
  const VideoFilter(this.id, this.name, this.matrix);
  final String id;
  final String name; // English; shown through tr()
  final List<double>? matrix; // 4x5 colour matrix, null = original

  String get label => tr(name);
}

/// Brightness/contrast/saturation helpers to build the matrices.
List<double> _saturate(double s) {
  const r = .2126, g = .7152, b = .0722;
  return [
    r * (1 - s) + s,
    g * (1 - s),
    b * (1 - s),
    0,
    0,
    r * (1 - s),
    g * (1 - s) + s,
    b * (1 - s),
    0,
    0,
    r * (1 - s),
    g * (1 - s),
    b * (1 - s) + s,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _mul(List<double> a, List<double> b) {
  // a ∘ b for 4x5 colour matrices (b applied first).
  final out = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var v = col == 4 ? a[row * 5 + 4] : 0.0;
      for (var k = 0; k < 4; k++) {
        v += a[row * 5 + k] * b[k * 5 + col];
      }
      out[row * 5 + col] = v;
    }
  }
  return out;
}

List<double> _contrast(double c) {
  final t = 128 * (1 - c);
  return [c, 0, 0, 0, t, 0, c, 0, 0, t, 0, 0, c, 0, t, 0, 0, 0, 1, 0];
}

List<double> _tint(double r, double g, double b, [double add = 0]) => [
  r,
  0,
  0,
  0,
  add,
  0,
  g,
  0,
  0,
  add,
  0,
  0,
  b,
  0,
  add,
  0,
  0,
  0,
  1,
  0,
];

final videoFilters = <VideoFilter>[
  const VideoFilter('none', 'Original', null),
  VideoFilter('vivid', 'Vivid', _mul(_contrast(1.12), _saturate(1.45))),
  VideoFilter('warm', 'Warm', _mul(_tint(1.12, 1.02, .86), _saturate(1.1))),
  VideoFilter('cool', 'Cool', _mul(_tint(.9, 1.0, 1.15), _saturate(1.05))),
  VideoFilter('rose', 'Rose', _mul(_tint(1.12, .95, 1.03, 6), _saturate(1.1))),
  VideoFilter('vintage', 'Vintage', [
    .393 * .85 + .15,
    .769 * .85,
    .189 * .85,
    0,
    12,
    .349 * .85,
    .686 * .85 + .15,
    .168 * .85,
    0,
    8,
    .272 * .85,
    .534 * .85,
    .131 * .85 + .15,
    0,
    -6,
    0,
    0,
    0,
    1,
    0,
  ]),
  VideoFilter('fade', 'Fade', _mul(_contrast(.82), _saturate(.75))),
  VideoFilter('mono', 'B&W', _saturate(0)),
  VideoFilter('noir', 'Noir', _mul(_contrast(1.35), _saturate(0))),
];

VideoFilter? filterById(String? id) {
  if (id == null || id == 'none') return null;
  for (final f in videoFilters) {
    if (f.id == id) return f;
  }
  return null;
}

/// [child] with the filter [id] applied (or unchanged for none / unknown).
Widget withFilter(String? id, Widget child) {
  final m = filterById(id)?.matrix;
  return m == null
      ? child
      : ColorFiltered(colorFilter: ColorFilter.matrix(m), child: child);
}

/// Speeds a creator can pick (TikTok-style), applied when the video plays.
const videoSpeeds = [0.5, 1.0, 1.5, 2.0];

String speedLabel(double s) => '${s == s.roundToDouble() ? s.toInt() : s}x';
