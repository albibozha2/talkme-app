import 'package:flutter_test/flutter_test.dart';
import 'package:reelll/models.dart';
import 'package:reelll/state.dart';

void main() {
  test('version check', () {
    expect(isVersionTooOld('1.0.0', '1.0.0'), isFalse);
    expect(isVersionTooOld('1.0.0', '1.0.1'), isTrue);
    expect(isVersionTooOld('1.10.0', '1.9.9'), isFalse);
    expect(isVersionTooOld('2.0', '1.9.9'), isFalse);
  });

  test('parses a video from the API', () {
    final v = Video.fromJson({
      'id': 1, 'caption': 'Hi #fun', 'video_url': 'http://x/v.mp4', 'thumb_url': null, 'duration': 12,
      'width': 720, 'height': 1280, 'status': 'published', 'allow_comments': true, 'views': 3, 'likes': 1,
      'comments': 0, 'liked': true, 'created_at': '2026-10-09T01:42:39Z',
      'user': {'id': 2, 'username': 'alice', 'display_name': 'Alice', 'avatar_url': null, 'verified': false},
    });
    expect(v.user.username, 'alice');
    expect(v.duration, 12.0);
    expect(v.createdAt.isUtc, isTrue);
  });
}
