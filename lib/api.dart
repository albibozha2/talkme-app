import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'models.dart';
import 'i18n.dart';

import 'package:flutter/foundation.dart';

import 'kv.dart';
import 'device_label.dart';
import 'diagnostics.dart';

class ApiException implements Exception {
  ApiException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

final apiProvider = Provider<Api>((ref) => Api());

class Api {
  Api() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          _token ??= await Kv.read(_tokenKey);
          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          options.headers['Accept-Language'] = currentLanguage;
          options.headers['X-Talkme-Device'] = await DeviceLabel.get();
          handler.next(options);
        },
      ),
    );
  }

  static const _tokenKey = 'api_token';
  static const _serverKey = 'api_server';

  /// Server chosen in the app (Wi-Fi address, Cloudflare tunnel...), loaded before runApp.
  static String _server = AppConfig.apiBase;

  static Future<void> loadServer() async {
    var saved = await Kv.read(_serverKey);
    // Quick-tunnel addresses are temporary; fall back to the real server.
    if (saved != null && saved.contains('.trycloudflare.com')) {
      await Kv.write(_serverKey, null);
      saved = null;
    }
    // The web app talks to the site it's served from (same address, http or https).
    _server = saved ?? (kIsWeb ? '${Uri.base.origin}/api' : AppConfig.apiBase);
    if (kIsWeb) return;
    // Prefer HTTPS as soon as the server offers it (e.g. after enabling Cloudflare).
    if (saved == null && _server.startsWith('http://') && !_isLocal(_server)) {
      final secure = 'https://${_server.substring(7)}';
      if (await _isOurServer(secure)) _server = secure;
    }
  }

  static bool _isLocal(String url) =>
      RegExp(r'^http://(localhost|127\.|10\.|192\.168\.)').hasMatch(url);

  /// True when [base] answers like a TalkMe API (not a placeholder page).
  static Future<bool> _isOurServer(String base) async {
    try {
      final res = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      ).get<dynamic>('$base/config');
      return res.data is Map && (res.data as Map)['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Turns what a person types ("abc.trycloudflare.com", "192.168.1.5:8088")
  /// into an API base URL ("https://abc.trycloudflare.com/api").
  static String normalizeServer(String input) {
    var s = input.trim().replaceAll(RegExp(r'/+$'), '');
    if (!s.contains('://')) {
      final local = RegExp(
        r'^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)',
      ).hasMatch(s);
      s = '${local ? 'http' : 'https'}://$s';
    }
    if (!s.endsWith('/api')) s = '$s/api';
    return s;
  }

  String get server => _server;

  /// Switch servers. Signs out, because accounts belong to one server.
  Future<void> setServer(String apiBase) async {
    _server = apiBase;
    _dio.options.baseUrl = apiBase;
    await Kv.write(_serverKey, apiBase);
    await saveToken(null);
  }

  final _dio = Dio(
    BaseOptions(
      baseUrl: _server,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  String? _token;

  /// Called when the server says the session is gone (401) or the account is banned (403 on /me).
  void Function(String message)? onSignedOut;

  Future<bool> hasToken() async =>
      (_token ??= await Kv.read(_tokenKey)) != null;

  Future<void> saveToken(String? token) async {
    _token = token;
    if (token == null) {
      await Kv.write(_tokenKey, null);
    } else {
      await Kv.write(_tokenKey, token);
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    void Function(int, int)? onSendProgress,
    CancelToken? cancel,
  }) async {
    try {
      final res = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: Options(method: method),
        onSendProgress: onSendProgress,
        cancelToken: cancel,
      );
      final body = res.data;
      if (body is! Map<String, dynamic>) {
        // Not TalkMe's answer (a hosting error or "please wait" page): explain instead of crashing.
        Diagnostics.report(
          'Unexpected server answer on $method $path',
          '$body'.length > 500 ? '$body'.substring(0, 500) : '$body',
        );
        throw ApiException(
          tr('The server is busy right now. Please try again in a moment.'),
          res.statusCode ?? 0,
        );
      }
      return body['data'];
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      final body = e.response?.data;
      final status = e.response?.statusCode ?? 0;
      final message =
          body is Map && body['data'] is Map && body['data']['error'] is String
          ? body['data']['error'] as String
          : (status == 0
                ? tr('No connection. Check your internet and try again.')
                : status == 413
                ? tr('That file is too large to send.')
                : tr('Something went wrong ({0}).', [status]));
      if (status >= 500 && !path.startsWith('/diagnostics')) {
        Diagnostics.report('Server error $status on $method $path', message);
      }
      if (status == 401 && _token != null) {
        await saveToken(null);
        onSignedOut?.call(tr('Your session ended. Please sign in again.'));
      } else if (status == 403 && message.contains('suspended')) {
        await saveToken(null);
        onSignedOut?.call(trServer(message));
      }
      throw ApiException(trServer(message), status);
    }
  }

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) =>
      _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? data]) =>
      _send('POST', path, data: data);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  PageResult<T> _page<T>(
    dynamic data,
    T Function(Map<String, dynamic>) parse,
  ) => PageResult(
    (data['items'] as List)
        .map((e) => parse(e as Map<String, dynamic>))
        .toList(),
    data['next_cursor'] as String?,
  );

  // ---- endpoints ----

  Future<RemoteConfig> config() async =>
      RemoteConfig(await get('/config') as Map<String, dynamic>);

  Future<AppUser> login(String login, String password) =>
      _auth('/auth/login', {'login': login, 'password': password});

  Future<AppUser> register(
    String username,
    String email,
    String password, {
    String invite = '',
    bool acceptTerms = false,
  }) => _auth('/auth/register', {
    'username': username,
    'email': email,
    'password': password,
    if (invite.isNotEmpty) 'invite': invite,
    if (acceptTerms) 'accept_terms': '1',
  });

  /// Emails a reset code; returns the server's message (same whether or not the account exists).
  Future<String> forgotPassword(String login) async =>
      (await post('/auth/forgot', {'login': login}) as Map)['message']
          as String;

  /// Sets a new password with the emailed code and signs in.
  Future<AppUser> resetPassword(String login, String code, String password) =>
      _auth('/auth/reset', {
        'login': login,
        'code': code,
        'password': password,
      });

  Future<AppUser> _auth(String path, Map<String, String> body) async {
    final data = await post(path, body) as Map<String, dynamic>;
    if (data['two_factor'] == true) {
      throw TwoFactorRequired(data['ticket'] as String);
    }
    await saveToken(data['token'] as String);
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Sign in or sign up with a Google ID token (see GoogleAuth).
  Future<AppUser> loginWithGoogle(String idToken, {String invite = ''}) =>
      _auth('/auth/google', {
        'id_token': idToken,
        if (invite.isNotEmpty) 'invite': invite,
      });

  /// Second sign-in step: code from the authenticator app or a backup code.
  Future<AppUser> loginWithCode(String ticket, String code) =>
      _auth('/auth/2fa', {'ticket': ticket, 'code': code});

  /// Starts turning on two-step sign-in: the secret and an otpauth:// link for the QR code.
  Future<({String secret, String uri})> twoFactorSetup() async {
    final r = await post('/me/2fa/setup') as Map<String, dynamic>;
    return (secret: r['secret'] as String, uri: r['uri'] as String);
  }

  /// Finishes it with the first code; returns the one-time backup codes.
  Future<({List<String> codes, AppUser user})> twoFactorEnable(
    String code,
  ) async {
    final r =
        await post('/me/2fa/enable', {'code': code}) as Map<String, dynamic>;
    return (
      codes: (r['backup_codes'] as List).cast<String>(),
      user: AppUser.fromJson(r['user'] as Map<String, dynamic>),
    );
  }

  Future<AppUser> twoFactorDisable(String password) async => AppUser.fromJson(
    await post('/me/2fa/disable', {'password': password})
        as Map<String, dynamic>,
  );

  /// Privacy & safety settings; only the given ones change.
  Future<AppUser> updateSettings({
    String? dmPolicy,
    String? mentionPolicy,
    String? commentFilter,
  }) async => AppUser.fromJson(
    await post('/me', {
      'dm_policy': ?dmPolicy,
      'mention_policy': ?mentionPolicy,
      'comment_filter': ?commentFilter,
    }) as Map<String, dynamic>,
  );

  Future<Analytics> analytics(int days) async => Analytics(
    await get('/me/analytics', {'days': days}) as Map<String, dynamic>,
  );

  Future<List<Comment>> heldComments() async => [
    for (final c
        in (await get('/me/held-comments') as Map<String, dynamic>)['items']
            as List)
      Comment.fromJson(c as Map<String, dynamic>),
  ];

  Future<void> approveComment(int id) => post('/comments/$id/approve');

  Future<AppUser> setRestricted(String username, bool on) async =>
      AppUser.fromJson(
        await (on
                ? post('/users/$username/restrict')
                : delete('/users/$username/restrict'))
            as Map<String, dynamic>,
      );

  Future<List<AppUser>> restrictedAccounts() async => [
    for (final u
        in (await get('/me/restricted') as Map<String, dynamic>)['items']
            as List)
      AppUser.fromJson(u as Map<String, dynamic>),
  ];

  /// Creator: price in coins per 30 days (0 turns subscriptions off).
  Future<AppUser> subscriptionSettings(int price, String perks) async =>
      AppUser.fromJson(
        await post('/me/subscription', {'price': price, 'perks': perks})
            as Map<String, dynamic>,
      );

  /// Pays [price] coins for 30 more days; returns the new end date.
  Future<DateTime> subscribe(String username, int price) async {
    final r = await post('/users/$username/subscribe', {
      'price': price,
    }) as Map<String, dynamic>;
    return DateTime.parse(r['subscribed_until'] as String).toLocal();
  }

  /// My subscribers, or with [mine] the creators I subscribe to.
  Future<List<Subscription>> subscriptions({bool mine = false}) async => [
    for (final s
        in (await get('/me/subscriptions', {if (mine) 'mine': 1})
                as Map<String, dynamic>)['items']
            as List)
      Subscription.fromJson(s as Map<String, dynamic>),
  ];

  /// A download link (valid 15 minutes) for all of my data.
  Future<String> dataExportLink() async =>
      (await post('/me/export') as Map<String, dynamic>)['url'] as String;

  /// "Where you're signed in".
  Future<List<SessionInfo>> sessions() async => [
    for (final s
        in (await get('/me/sessions') as Map<String, dynamic>)['items'] as List)
      SessionInfo.fromJson(s as Map<String, dynamic>),
  ];

  /// Signs out one other device, or all other devices when [id] is null.
  Future<void> endSession([int? id]) =>
      delete(id == null ? '/me/sessions' : '/me/sessions/$id');

  Future<void> logout() async {
    try {
      await post('/auth/logout');
    } finally {
      await saveToken(null);
    }
  }

  Future<AppUser> me() async =>
      AppUser.fromJson(await get('/me') as Map<String, dynamic>);

  Future<AppUser> updateMe({
    required String displayName,
    required String bio,
    bool? isPrivate,
    bool? marketingOptIn,
    String? website,
    String? instagram,
  }) async => AppUser.fromJson(
    await post('/me', {
      'display_name': displayName,
      'bio': bio,
      'website': ?website,
      'instagram': ?instagram,
      'is_private': ?isPrivate,
      'marketing_opt_in': ?marketingOptIn,
    }) as Map<String, dynamic>,
  );

  Future<AppUser> uploadAvatar(String path) async => AppUser.fromJson(
    await post(
      '/me/avatar',
      FormData.fromMap({
        'avatar': await uploadFile(path, filename: 'avatar.jpg'),
      }),
    ) as Map<String, dynamic>,
  );

  Future<void> deleteAccount(String password) async {
    await post('/me/delete', {'password': password});
    await saveToken(null);
  }

  Future<PageResult<Video>> feed(String? cursor) async =>
      _page(await get('/feed', {'cursor': ?cursor}), Video.fromJson);

  Future<PageResult<Video>> followingFeed(String? cursor) async =>
      _page(await get('/feed/following', {'cursor': ?cursor}), Video.fromJson);

  Future<PageResult<Video>> userVideos(String username, String? cursor) async =>
      _page(
        await get('/users/$username/videos', {'cursor': ?cursor}),
        Video.fromJson,
      );

  Future<PageResult<Video>> hashtagVideos(String tag, String? cursor) async =>
      _page(
        await get('/hashtags/${Uri.encodeComponent(tag)}/videos', {
          'cursor': ?cursor,
        }),
        Video.fromJson,
      );

  Future<Video> upload({
    required String path,
    required String caption,
    required double duration,
    required int width,
    required int height,
    required bool allowComments,
    String visibility = 'public',
    List<VideoOverlay> overlays = const [],
    String? thumbPath,
    SoundUse? sound,
    String? filter,
    double speed = 1,
    int? duetOf,
    bool allowDuet = true,
    void Function(int, int)? onProgress,
    CancelToken? cancel,
  }) async {
    final form = FormData.fromMap({
      'video': await uploadFile(path, filename: 'video.mp4'),
      if (thumbPath != null)
        'thumb': await uploadFile(thumbPath, filename: 'thumb.jpg'),
      'caption': caption,
      'duration': duration.toStringAsFixed(2),
      'width': '$width',
      'height': '$height',
      'allow_comments': allowComments ? '1' : '0',
      'visibility': visibility,
      if (overlays.isNotEmpty)
        'overlays': jsonEncode(overlays.map((o) => o.toJson()).toList()),
      ...?sound?.toForm(),
      if (filter != null && filter != 'none') 'filter': filter,
      if (speed != 1)
        'speed': speed == speed.roundToDouble() ? '${speed.toInt()}' : '$speed',
      'duet_of': ?duetOf?.toString(),
      'allow_duet': allowDuet ? '1' : '0',
    });
    final data = await _send(
      'POST',
      '/videos',
      data: form,
      onSendProgress: onProgress,
      cancel: cancel,
    );
    return Video.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteVideo(int id) => delete('/videos/$id');

  /// Owner: a thumbnail made on the phone for a video that has none.
  Future<String?> setVideoThumb(int id, String path) async =>
      (await post(
            '/videos/$id/thumb',
            FormData.fromMap({
              'thumb': await uploadFile(path, filename: 'thumb.jpg'),
            }),
          ) as Map<String, dynamic>)['thumb_url']
          as String?;

  Future<int> setLike(int id, bool on) async {
    final data =
        await (on ? post('/videos/$id/like') : delete('/videos/$id/like'))
            as Map<String, dynamic>;
    return data['likes'] as int;
  }

  Future<void> addView(int id) => post('/videos/$id/view');

  /// How long a video played before moving on (loops included): the main signal of the "For you" feed.
  Future<void> reportWatch(int id, int ms, int durationMs) =>
      post('/videos/$id/watch', {'ms': ms, 'duration_ms': durationMs});

  /// Shared outside the app (helps the video reach more people).
  Future<void> reportShare(int id) => post('/videos/$id/share');

  Future<PageResult<Comment>> comments(int videoId, String? cursor) async =>
      _page(
        await get('/videos/$videoId/comments', {'cursor': ?cursor}),
        Comment.fromJson,
      );

  Future<Comment> addComment(int videoId, String body) async =>
      Comment.fromJson(
        await post('/videos/$videoId/comments', {'body': body})
            as Map<String, dynamic>,
      );

  Future<void> deleteComment(int id) => delete('/comments/$id');

  // ---------- rewards, leaderboards ----------

  Future<RewardState> rewards() async =>
      RewardState(await get('/rewards') as Map<String, dynamic>);

  Future<RewardState> checkIn() async =>
      RewardState(await post('/rewards/checkin') as Map<String, dynamic>);

  /// [type] gifters or creators; [period] day, week, month or all.
  Future<(List<RankEntry>, RankEntry?)> leaderboard(
    String type,
    String period,
  ) async {
    final d = await get('/leaderboard', {
      'type': type,
      'period': period,
    }) as Map<String, dynamic>;
    final me = d['me'] as Map<String, dynamic>?;
    return (
      (d['items'] as List)
          .map((e) => RankEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      me == null
          ? null
          : RankEntry(
              me['rank'] as int,
              me['coins'] as int,
              AppUser(id: 0, username: '', displayName: ''),
            ),
    );
  }

  // ---------- live extras ----------

  Future<List<RankEntry>> liveTop(int liveId) async =>
      ((await get('/live/$liveId/top') as Map)['items'] as List)
          .map((e) => RankEntry.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<LiveInfo> setLiveGoal(int liveId, int coins, String text) async =>
      LiveInfo.fromJson(
        (await post('/live/$liveId/goal', {'coins': coins, 'text': text})
                as Map)['live']
            as Map<String, dynamic>,
      );

  Future<LiveInfo> pinLiveMessage(int liveId, String message) async =>
      LiveInfo.fromJson(
        (await post('/live/$liveId/pin', {'message': message}) as Map)['live']
            as Map<String, dynamic>,
      );

  Future<void> liveKick(int liveId, int userId) =>
      post('/live/$liveId/kick', {'user_id': userId});

  Future<void> liveMute(int liveId, int userId, bool on) =>
      post('/live/$liveId/mute', {'user_id': userId, 'on': on});

  Future<List<AppUser>> liveMods() async =>
      ((await get('/live/mods') as Map)['items'] as List)
          .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<void> setLiveMod(String username, bool on) =>
      on ? post('/live/mods/$username') : delete('/live/mods/$username');

  Future<List<LiveEvent>> liveEvents({String? username}) async =>
      ((await get(username == null ? '/live/events' : '/users/$username/events')
                  as Map)['items']
              as List)
          .map((e) => LiveEvent.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<LiveEvent> scheduleLive(String title, DateTime startsAt) async =>
      LiveEvent.fromJson(
        (await post('/live/events', {
              'title': title,
              'starts_at': startsAt.toUtc().toIso8601String(),
            }) as Map)['event']
            as Map<String, dynamic>,
      );

  Future<void> deleteLiveEvent(int id) => delete('/live/events/$id');

  Future<void> setLiveReminder(int id, bool on) =>
      on ? post('/live/events/$id/remind') : delete('/live/events/$id/remind');

  // ---------- stories ----------

  Future<List<StoryGroup>> storyFeed() async =>
      ((await get('/stories') as Map)['items'] as List)
          .map((e) => StoryGroup.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<StoryGroup> userStories(String username) async => StoryGroup.fromJson(
    await get('/users/$username/stories') as Map<String, dynamic>,
  );

  Future<Story> createStory({
    required String path,
    required bool isVideo,
    double duration = 0,
    String caption = '',
    SoundUse? sound,
    void Function(int, int)? onProgress,
  }) async {
    final form = FormData.fromMap({
      ...?sound?.toForm(),
      'media': await uploadFile(
        path,
        filename: isVideo ? 'story.mp4' : 'story.jpg',
        contentType: isVideo ? DioMediaType('video', 'mp4') : null,
      ),
      'caption': caption,
      'duration': duration.toStringAsFixed(2),
    });
    final d = await _send(
      'POST',
      '/stories',
      data: form,
      onSendProgress: onProgress,
    );
    return Story.fromJson((d as Map)['story'] as Map<String, dynamic>);
  }

  Future<void> viewStory(int id) => post('/stories/$id/view');

  // ---------- sounds ----------

  /// [tab]: talkme (popular on TalkMe + uploaded) or library (Jamendo). [q]: search.
  Future<({List<Sound> items, bool library})> sounds({
    String tab = 'talkme',
    String q = '',
  }) async {
    final r = await get('/sounds', {
      'tab': tab,
      if (q.isNotEmpty) 'q': q,
    }) as Map<String, dynamic>;
    return (
      items: [
        for (final s in r['items'] as List)
          Sound.fromJson(s as Map<String, dynamic>),
      ],
      library: (r['library'] as bool?) ?? false,
    );
  }

  /// Makes a picked sound usable (library tracks get a TalkMe id).
  Future<Sound> selectSound(Sound s) async => Sound.fromJson(
    await post(
      '/sounds/select',
      s.source == 'jamendo' && s.id == null
          ? {'source': 'jamendo', 'external_id': s.externalId}
          : {'id': s.id},
    ) as Map<String, dynamic>,
  );

  /// A sound's page: the sound and the videos using it.
  Future<({Sound sound, PageResult<Video> videos})> soundPage(
    int id, [
    String? cursor,
  ]) async {
    final r =
        await get('/sounds/$id', {'cursor': ?cursor}) as Map<String, dynamic>;
    return (
      sound: Sound.fromJson(r['sound'] as Map<String, dynamic>),
      videos: _page(r, Video.fromJson),
    );
  }

  Future<List<AppUser>> storyViewers(int id) async =>
      ((await get('/stories/$id/viewers') as Map)['items'] as List)
          .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<void> deleteStory(int id) => delete('/stories/$id');

  // ---------- profile extras ----------

  Future<void> setVideoPinned(int id, bool on) async =>
      on ? await post('/videos/$id/pin') : await delete('/videos/$id/pin');

  /// [which] is followers or following.
  Future<PageResult<AppUser>> followList(
    String username,
    String which,
    String? cursor,
  ) async => _page(
    await get('/users/$username/$which', {'cursor': ?cursor}),
    AppUser.fromJson,
  );

  Future<PageResult<Comment>> replies(int commentId, String? cursor) async =>
      _page(
        await get('/comments/$commentId/replies', {'cursor': ?cursor}),
        Comment.fromJson,
      );

  Future<Comment> reply(int videoId, int parentId, String body) async =>
      Comment.fromJson(
        await post('/videos/$videoId/comments', {
          'body': body,
          'parent_id': parentId,
        }) as Map<String, dynamic>,
      );

  /// Returns the new like count.
  Future<int> setCommentLike(int id, bool on) async {
    final d = on
        ? await post('/comments/$id/like')
        : await delete('/comments/$id/like');
    return (d as Map)['likes'] as int;
  }

  Future<void> setCommentPinned(int id, bool on) async =>
      on ? await post('/comments/$id/pin') : await delete('/comments/$id/pin');

  /// Returns the new repost count.
  Future<int> setRepost(int videoId, bool on) async {
    final d = on
        ? await post('/videos/$videoId/repost')
        : await delete('/videos/$videoId/repost');
    return (d as Map)['reposts'] as int;
  }

  Future<PageResult<Video>> userReposts(
    String username,
    String? cursor,
  ) async => _page(
    await get('/users/$username/reposts', {'cursor': ?cursor}),
    Video.fromJson,
  );

  /// Owner: who can watch the video and whether comments are allowed.
  Future<Video> videoSettings(
    int id, {
    required String visibility,
    required bool allowComments,
  }) async => Video.fromJson(
    await post('/videos/$id/settings', {
      'visibility': visibility,
      'allow_comments': allowComments,
    }) as Map<String, dynamic>,
  );

  Future<AppUser> user(String username) async =>
      AppUser.fromJson(await get('/users/$username') as Map<String, dynamic>);

  Future<AppUser> setFollow(String username, bool on) async => AppUser.fromJson(
    await (on
            ? post('/users/$username/follow')
            : delete('/users/$username/follow'))
        as Map<String, dynamic>,
  );

  Future<({List<AppUser> users, List<({String name, int count})> hashtags})>
  search(String q) async {
    final data = await get('/search', {'q': q}) as Map<String, dynamic>;
    return (
      users: (data['users'] as List)
          .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
          .toList(),
      hashtags: (data['hashtags'] as List)
          .map(
            (e) => (
              name: e['name'] as String,
              count: (e['videos_count'] as num).toInt(),
            ),
          )
          .toList(),
    );
  }

  Future<bool> setSaved(int id, bool on) async {
    final data =
        await (on ? post('/videos/$id/save') : delete('/videos/$id/save'))
            as Map<String, dynamic>;
    return data['saved'] as bool;
  }

  Future<PageResult<Video>> savedVideos(String? cursor, {int? folder}) async =>
      _page(
        await get('/me/saved', {'cursor': ?cursor, 'collection': ?folder}),
        Video.fromJson,
      );

  Future<SearchResults> searchAll(String q) async =>
      SearchResults(await get('/search', {'q': q}) as Map<String, dynamic>);

  Future<PageResult<Video>> friendsFeed(String? cursor) async =>
      _page(await get('/feed/friends', {'cursor': ?cursor}), Video.fromJson);

  Future<PageResult<Video>> history(String? cursor) async =>
      _page(await get('/me/history', {'cursor': ?cursor}), Video.fromJson);

  Future<void> clearHistory() => delete('/me/history');

  /// Hide a video from For You; with [author] also everything from its author.
  Future<void> notInterested(int videoId, {bool author = false}) =>
      post('/videos/$videoId/not-interested', {'author': author});

  Future<List<AppUser>> hiddenAuthors() async =>
      ((await get('/me/hidden-authors') as Map)['items'] as List)
          .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<void> unhideAuthor(String username) =>
      delete('/me/hidden-authors/$username');

  Future<List<Folder>> folders() async =>
      ((await get('/me/collections') as Map)['items'] as List)
          .map((e) => Folder(e as Map<String, dynamic>))
          .toList();

  Future<Folder> createFolder(String name) async => Folder(
    await post('/me/collections', {'name': name}) as Map<String, dynamic>,
  );

  Future<void> deleteFolder(int id) => delete('/me/collections/$id');

  /// Save a video into a folder (also saves it if it wasn't saved yet).
  Future<void> saveToFolder(int videoId, int folderId) =>
      post('/videos/$videoId/save', {'collection_id': folderId});

  Future<List<AppUser>> suggestedUsers() async =>
      (await get('/users/suggested') as List)
          .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
          .toList();

  // ---- coins & gifts ----

  Future<Wallet> wallet() async =>
      Wallet.fromJson(await get('/wallet') as Map<String, dynamic>);

  Future<PageResult<CoinTx>> transactions(String? cursor) async => _page(
    await get('/wallet/transactions', {'cursor': ?cursor}),
    CoinTx.fromJson,
  );

  /// Returns the new coin balance.
  Future<int> buyCoins(int packageId) async =>
      (await post('/wallet/buy', {'package_id': packageId})
              as Map<String, dynamic>)['coins']
          as int;

  Future<List<Gift>> gifts() async {
    final list = (await get('/gifts') as List)
        .map((e) => Gift.fromJson(e as Map<String, dynamic>))
        .toList();
    for (final g in list) {
      knownGifts[g.name] = g;
    }
    return list;
  }

  /// Sends a gift to a live or a video. Returns the sender's new balance.
  Future<int> sendGift(
    int giftId, {
    int? liveId,
    int? videoId,
    int quantity = 1,
  }) async {
    final data = await post('/gifts/send', {
      'gift_id': giftId,
      if (quantity > 1) 'quantity': quantity,
      'live_id': ?liveId,
      'video_id': ?videoId,
    }) as Map<String, dynamic>;
    return data['balance'] as int;
  }

  // ---- live ----

  Future<({bool enabled, List<LiveInfo> items})> lives() async {
    final data = await get('/live') as Map<String, dynamic>;
    return (
      enabled: data['enabled'] as bool,
      items: (data['items'] as List)
          .map((e) => LiveInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<LiveSession> startLive(String title) async => LiveSession.fromJson(
    await post('/live/start', {'title': title}) as Map<String, dynamic>,
  );

  Future<LiveSession> joinLive(int id) async => LiveSession.fromJson(
    await post('/live/$id/join') as Map<String, dynamic>,
  );

  /// Saves a live chat message; returns the text to send to the room (bad words filtered).
  Future<String> liveComment(int liveId, String body) async =>
      (await post('/live/$liveId/comments', {'body': body})
              as Map<String, dynamic>)['body']
          as String;

  Future<LiveInfo> pingLive(int id, int viewers) async => LiveInfo.fromJson(
    await post('/live/$id/ping', {'viewers': viewers}) as Map<String, dynamic>,
  );

  Future<Map<String, dynamic>> endLive(int id) async =>
      await post('/live/$id/end') as Map<String, dynamic>;

  // ---- notifications ----

  /// [group]: followers, activity or system (null = all).
  Future<PageResult<AppNotification>> notifications(
    String? cursor, {
    String? group,
  }) async => _page(
    await get('/notifications', {'cursor': ?cursor, 'group': ?group}),
    AppNotification.fromJson,
  );

  /// Unread count and latest title per inbox group.
  Future<({Map<String, int> counts, Map<String, String?> latest})>
  notificationGroups() async {
    final r = await get('/notifications/unread') as Map<String, dynamic>;
    return (
      counts: ((r['groups'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(k as String, (v as num).toInt()),
      ),
      latest: ((r['latest'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(k as String, v as String?),
      ),
    );
  }

  Future<int> unreadCount() async =>
      (await get('/notifications/unread') as Map<String, dynamic>)['unread']
          as int;

  Future<void> markAllRead({String? group}) =>
      post('/notifications/read', {'group': ?group});

  Future<void> registerDevice(String token, String platform) =>
      post('/devices', {'token': token, 'platform': platform});

  Future<void> registerGuestDevice(String token, String platform) =>
      post('/devices/guest', {'token': token, 'platform': platform});

  Future<void> unregisterDevice(String token) =>
      post('/devices/remove', {'token': token});

  Future<Video> video(int id) async =>
      Video.fromJson(await get('/videos/$id') as Map<String, dynamic>);

  Future<List<BannerItem>> banners() async => (await get('/banners') as List)
      .map((e) => BannerItem.fromJson(e as Map<String, dynamic>))
      .toList();

  Future<void> bannerClick(int id) => post('/banners/$id/click');

  Future<PayoutInfo> payouts() async =>
      PayoutInfo.fromJson(await get('/wallet/payouts') as Map<String, dynamic>);

  Future<void> requestPayout({
    required int coins,
    required String method,
    required String details,
  }) => post('/wallet/payouts', {
    'coins': coins,
    'method': method,
    'details': details,
  });

  // ---- direct messages ----

  /// Inbox, or message requests with [requests].
  Future<List<Conversation>> conversations({bool requests = false}) async =>
      (await get('/conversations', {if (requests) 'folder': 'requests'})
              as List)
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<Conversation> openConversation(String username) async =>
      Conversation.fromJson(
        await post('/conversations', {'username': username})
            as Map<String, dynamic>,
      );

  /// Newest first. [after]: only messages newer than this id (polling). [cursor]: older page.
  Future<
    ({
      List<ChatMessage> items,
      String? nextCursor,
      int otherLastRead,
      List<String> typing,
    })
  >
  messages(int conversationId, {int? after, String? cursor}) async {
    final data = await get('/conversations/$conversationId/messages', {
      'after': ?after,
      'cursor': ?cursor,
    }) as Map<String, dynamic>;
    return (
      items: (data['items'] as List)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: data['next_cursor'] as String?,
      otherLastRead: (data['other_last_read'] as int?) ?? 0,
      typing: ((data['typing'] as List?) ?? const []).cast<String>(),
    );
  }

  /// "I'm typing" (the chat sends it at most every few seconds).
  Future<void> sendTyping(int conversationId) =>
      post('/conversations/$conversationId/typing');

  Future<ChatMessage> sendMessage(
    int conversationId,
    String body, {
    int? videoId,
    int? replyTo,
  }) async => ChatMessage.fromJson(
    await post('/conversations/$conversationId/messages', {
      'body': body,
      'video_id': ?videoId,
      'reply_to': ?replyTo,
    }) as Map<String, dynamic>,
  );

  /// Send a photo, a voice message ([voice]) or a video clip ([clip], with an optional
  /// first-frame [thumbPath]) from a file path. [onProgress] gets 0..1 while it uploads.
  Future<ChatMessage> sendMedia(
    int conversationId,
    String path, {
    bool voice = false,
    bool clip = false,
    String? thumbPath,
    double duration = 0,
    int? replyTo,
    void Function(double)? onProgress,
  }) async {
    final field = clip ? 'clip' : (voice ? 'voice' : 'image');
    final form = FormData.fromMap({
      field: await uploadFile(
        path,
        filename: clip
            ? 'clip.mp4'
            : voice
            ? (kIsWeb ? 'voice.webm' : 'voice.m4a')
            : 'photo.jpg',
      ),
      if (thumbPath != null)
        'thumb': await uploadFile(thumbPath, filename: 'thumb.jpg'),
      if (voice || clip) 'duration': duration.toStringAsFixed(1),
      'reply_to': ?replyTo,
    });
    final data = await _send(
      'POST',
      '/conversations/$conversationId/messages',
      data: form,
      onSendProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total > 0) onProgress(sent / total);
            },
    );
    return ChatMessage.fromJson(data as Map<String, dynamic>);
  }

  Future<List<Reaction>> react(int messageId, String emoji) async =>
      ((await post('/messages/$messageId/react', {'emoji': emoji})
                  as Map)['reactions']
              as List)
          .map((e) => Reaction.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<void> unsendMessage(int messageId) => delete('/messages/$messageId');

  Future<Conversation> conversationDetails(int id) async =>
      Conversation.fromJson(
        await get('/conversations/$id') as Map<String, dynamic>,
      );

  Future<Conversation> createGroup(
    String title,
    List<String> usernames,
  ) async => Conversation.fromJson(
    await post('/conversations/group', {'title': title, 'usernames': usernames})
        as Map<String, dynamic>,
  );

  Future<Conversation> addToGroup(int id, List<String> usernames) async =>
      Conversation.fromJson(
        await post('/conversations/$id/members', {'usernames': usernames})
            as Map<String, dynamic>,
      );

  /// Leave (your own username) or remove someone (admins).
  Future<void> removeFromGroup(int id, String username) =>
      delete('/conversations/$id/members/$username');

  Future<Conversation> makeGroupAdmin(int id, String username) async =>
      Conversation.fromJson(
        await post('/conversations/$id/admins/$username')
            as Map<String, dynamic>,
      );

  Future<Conversation> renameGroup(int id, String title) async =>
      Conversation.fromJson(
        await post('/conversations/$id/title', {'title': title})
            as Map<String, dynamic>,
      );

  Future<void> acceptRequest(int id) => post('/conversations/$id/accept');

  Future<void> declineRequest(int id) => post('/conversations/$id/decline');

  Future<int> messageRequests() async =>
      ((await get('/messages/unread') as Map<String, dynamic>)['requests']
          as int?) ??
      0;

  Future<void> readConversation(int conversationId) =>
      post('/conversations/$conversationId/read');

  Future<int> messagesUnread() async =>
      (await get('/messages/unread') as Map<String, dynamic>)['unread'] as int;

  // ---- blocking & follow requests ----

  Future<AppUser> setBlocked(String username, bool on) async =>
      AppUser.fromJson(
        await (on
                ? post('/users/$username/block')
                : delete('/users/$username/block'))
            as Map<String, dynamic>,
      );

  Future<List<AppUser>> blockedUsers() async =>
      (await get('/me/blocked') as List)
          .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<List<AppUser>> followRequests() async =>
      (await get('/me/follow-requests') as List)
          .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<void> answerFollowRequest(String username, bool approve) =>
      post('/follow-requests/$username/${approve ? 'approve' : 'decline'}');

  // ---- live guests (viewers on camera with the host) ----

  /// Ask the host to join on camera. Returns my status (requested / active).
  Future<String> requestToJoinLive(int liveId) async =>
      (await post('/live/$liveId/guests/request') as Map)['status'] as String;

  /// Cancel my request or leave the stage.
  Future<void> leaveLiveStage(int liveId) => post('/live/$liveId/guests/leave');

  Future<String> myGuestStatus(int liveId) async =>
      (await get('/live/$liveId/guests/me') as Map)['status'] as String;

  /// Host: requests and guests.
  Future<List<LiveGuest>> liveGuests(int liveId) async =>
      _guests(await get('/live/$liveId/guests') as Map<String, dynamic>);

  /// Host: accept, decline or remove someone.
  Future<List<LiveGuest>> answerGuest(
    int liveId,
    int userId,
    String action,
  ) async => _guests(
    await post('/live/$liveId/guests/$userId/$action') as Map<String, dynamic>,
  );

  List<LiveGuest> _guests(Map<String, dynamic> j) => [
    for (final g in j['items'] as List)
      LiveGuest(
        AppUser.fromJson((g as Map)['user'] as Map<String, dynamic>),
        g['status'] as String,
      ),
  ];

  /// Accepted guest: a connection that may send camera and microphone.
  Future<({String url, String token})> guestTicket(int liveId) async {
    final j = await post('/live/$liveId/guests/ticket') as Map;
    return (url: j['url'] as String, token: j['token'] as String);
  }

  // ---- PK battles ----

  Future<Battle?> battle(int liveId) async {
    final b =
        (await get('/live/$liveId/battle') as Map<String, dynamic>)['battle'];
    return b == null ? null : Battle.fromJson(b as Map<String, dynamic>);
  }

  /// Challenge one live, or a random free one when [opponentLiveId] is null (quick match).
  Future<Battle?> inviteBattle(int myLiveId, int? opponentLiveId) async {
    final b = (await post('/live/$myLiveId/battle', {
      if (opponentLiveId != null) 'live_id': opponentLiveId else 'random': 1,
    }) as Map<String, dynamic>)['battle'];
    return b == null ? null : Battle.fromJson(b as Map<String, dynamic>);
  }

  Future<void> answerBattle(int battleId, String action) =>
      post('/battles/$battleId/$action');

  Future<void> report(String type, int id, String reason) => post('/reports', {
    'target_type': type,
    'target_id': id,
    'reason': reason,
  });
}

/// The password was right; the account wants a code from the authenticator app.
class TwoFactorRequired implements Exception {
  TwoFactorRequired(this.ticket);
  final String ticket;
}
