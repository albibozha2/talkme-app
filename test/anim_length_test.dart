import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelll/widgets/gift_effects.dart';

void main() {
  test('reads how long an uploaded gift animation lasts', () {
    const fixtures = '../backend/tests/fixtures';
    expect(animationLength(File('$fixtures/gift_anim.webp').readAsBytesSync()), const Duration(milliseconds: 300));
    expect(animationLength(File('$fixtures/photo.jpg').readAsBytesSync()), isNull);
  });
}
