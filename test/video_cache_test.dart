// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelll/video_cache.dart';

void main() {
  // Integration test against a running server: MASTER=<url of a master.m3u8> flutter test
  test('proxy serves master, variant and segment', skip: Platform.environment['MASTER'] == null ? 'set MASTER to run' : null, () async {
    final dir = await Directory.systemTemp.createTemp('vc');
    await VideoCache.instance.start(directory: dir);
    final master = Platform.environment['MASTER']!;
    final client = HttpClient();
    Future<(int, String)> get(String url) async {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      return (res.statusCode, '${body.length} bytes ${res.headers.contentType}');
    }
    final m = VideoCache.instance.playable(master);
    print('master: ${await get(m)}');
    final variant = Uri.parse(m).resolve('0.m3u8').toString();
    print('variant: ${await get(variant)}');
    print('segment: ${await get(Uri.parse(m).resolve('0_000.ts').toString())}');
    await VideoCache.instance.prefetch(master);
    print('cached files: ${dir.listSync().length}');
  });
}
