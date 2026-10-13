import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// On-phone cache for video: whole MP4 files (see [download]) and HLS streams.
///
/// MP4: upcoming videos are downloaded in one request each and played from the phone,
/// so swiping is instant and the server (which rate-limits many small requests) is asked once.
///
/// HLS:
/// The player loads streams through a tiny HTTP server on 127.0.0.1. Each
/// playlist and 2-second segment is fetched once, saved to disk, and served
/// from disk afterwards, so scrolling back and rewatching are instant and free.
/// It also lets us download the first seconds of upcoming videos ahead of time.
///
/// URL scheme: `http://127.0.0.1:PORT/SCHEME/HOST[:PORT]/PATH`
/// Relative segment paths inside playlists resolve through the proxy unchanged.
class VideoCache {
  VideoCache._();
  static final instance = VideoCache._();

  static const _maxBytes = 400 * 1024 * 1024;

  HttpServer? _server;
  late Directory _dir;
  final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..maxConnectionsPerHost = 6;
  final _inflight = <String, Future<File?>>{};

  Future<void> start({Directory? directory}) async {
    if (_server != null) return;
    try {
      _dir =
          directory ??
          Directory('${(await getApplicationCacheDirectory()).path}/hls');
      await _dir.create(recursive: true);
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen(_handle);
      unawaited(_trim());
    } catch (_) {
      _server = null; // Fall back to streaming straight from the server.
    }
  }

  /// The address the player should open for [url].
  String playable(String url) {
    final server = _server;
    if (server == null) return url;
    final u = Uri.parse(url);
    return 'http://127.0.0.1:${server.port}/${u.scheme}/${u.authority}${u.path}${u.hasQuery ? '?${u.query}' : ''}';
  }

  /// The saved copy of [url] if it is already on the phone (instant check).
  File? cachedFile(String url) {
    if (_server == null) return null;
    final f = File('${_dir.path}/${_key(Uri.parse(url))}');
    return f.existsSync() ? f : null;
  }

  /// Downloads the whole file of [url] once (later calls return the saved copy).
  Future<File?> download(String url) async {
    if (_server == null) return null;
    try {
      return await _fetch(Uri.parse(url));
    } catch (_) {
      return null;
    }
  }

  static String _key(Uri url) =>
      sha1.convert(utf8.encode(url.toString())).toString();

  /// Download the playlists and first [segments] segments of the two lowest
  /// qualities, so the video starts instantly when the user reaches it.
  Future<void> prefetch(String masterUrl, {int segments = 2}) async {
    if (_server == null) return;
    try {
      final master = Uri.parse(masterUrl);
      final variants = _variants(await _text(master), master);
      for (final v in variants.take(2)) {
        final playlist = await _text(v);
        final segs = playlist
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('#'))
            .take(segments)
            .map(v.resolve);
        await Future.wait(segs.map(_fetch));
      }
    } catch (_) {
      // Prefetch is best effort.
    }
  }

  /// Variant playlists from a master playlist, lowest bandwidth first.
  List<Uri> _variants(String master, Uri base) {
    final out = <(int, Uri)>[];
    int? bw;
    for (final raw in master.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        bw = int.tryParse(
          RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ?? '',
        );
      } else if (line.isNotEmpty && !line.startsWith('#') && bw != null) {
        out.add((bw, base.resolve(line)));
        bw = null;
      }
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out.map((e) => e.$2).toList();
  }

  Future<String> _text(Uri url) async {
    final f = await _fetch(url);
    if (f == null) throw const HttpException('fetch failed');
    return f.readAsString();
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final origin = _originOf(req.uri);
      final file = origin == null ? null : await _fetch(origin);
      if (file == null) {
        res.statusCode = HttpStatus.badGateway;
      } else {
        final path = origin!.path;
        res.headers.contentType = path.endsWith('.m3u8')
            ? ContentType('application', 'vnd.apple.mpegurl')
            : path.endsWith('.ts')
            ? ContentType('video', 'mp2t')
            : ContentType.binary;
        res.contentLength = await file.length();
        await res.addStream(file.openRead());
      }
    } catch (_) {
      res.statusCode = HttpStatus.badGateway;
    } finally {
      await res.close().catchError((Object _) {});
    }
  }

  Uri? _originOf(Uri proxied) {
    final parts = proxied.path.substring(1).split('/');
    if (parts.length < 3 || (parts[0] != 'http' && parts[0] != 'https')) {
      return null;
    }
    final rest = parts.skip(2).join('/');
    return Uri.parse(
      '${parts[0]}://${parts[1]}/$rest${proxied.hasQuery ? '?${proxied.query}' : ''}',
    );
  }

  /// Returns the cached file for [url], downloading it once if needed.
  Future<File?> _fetch(Uri url) {
    final key = _key(url);
    // Block body on purpose: returning the removed future would make whenComplete wait on itself.
    return _inflight[key] ??= _download(url, key).whenComplete(() {
      _inflight.remove(key);
    });
  }

  Future<File?> _download(Uri url, String key) async {
    final file = File('${_dir.path}/$key');
    if (await file.exists()) {
      unawaited(file.setLastModified(DateTime.now()).catchError((Object _) {}));
      return file;
    }
    final part = File('${file.path}.part');
    // A busy hosting server may answer with a short "please wait" web page instead of the
    // file. That page must never be saved as a video: wait a moment and try again.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await (await _client.getUrl(url)).close();
        final isPage = res.headers.contentType?.mimeType == 'text/html';
        if (res.statusCode != HttpStatus.ok || isPage) {
          await res.drain<void>();
          if (!isPage || attempt == 2) return null;
          await Future<void>.delayed(
            Duration(milliseconds: 1500 * (attempt + 1)),
          );
          continue;
        }
        await res.pipe(part.openWrite());
        return await part.rename(file.path);
      } catch (_) {
        if (await part.exists()) {
          await part.delete().catchError((Object _) => part);
        }
        return null;
      }
    }
    return null;
  }

  /// Keep the cache under [_maxBytes] by deleting least recently used files.
  Future<void> _trim() async {
    final files = <(File, FileStat)>[];
    var total = 0;
    await for (final e in _dir.list()) {
      if (e is! File) continue;
      if (e.path.endsWith('.part')) {
        await e.delete().catchError((Object _) => e);
        continue;
      }
      final st = await e.stat();
      total += st.size;
      files.add((e, st));
    }
    if (total <= _maxBytes) return;
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (f, st) in files) {
      if (total <= _maxBytes * .8) break;
      await f.delete().catchError((Object _) => f);
      total -= st.size;
    }
  }
}
