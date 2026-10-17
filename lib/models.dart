class AppUser {
  AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    this.bio = '',
    this.avatarUrl,
    this.verified = false,
    this.idVerified = false,
    this.followers = 0,
    this.following = 0,
    this.videos = 0,
    this.isFollowing,
    this.email,
    this.role = 'user',
    this.coins = 0,
    this.earnedCoins = 0,
    this.liveId,
    this.isPrivate = false,
    this.requested = false,
    this.blocked = false,
    this.canView = true,
    this.marketingOptIn = true,
    this.website = '',
    this.instagram = '',
    this.likesTotal = 0,
    this.hasStory = false,
    this.storySeen = false,
    this.level = 0,
    this.giftsSent,
    this.championType,
    this.championRank = 0,
    this.bonusCoins = 0,
    this.twoFactor = false,
    this.backupCodesLeft = 0,
    this.dmPolicy = 'everyone',
    this.mentionPolicy = 'everyone',
    this.commentFilter = '',
    this.subPrice,
    this.subPerks = '',
    this.subscribedUntil,
    this.restricted = false,
  });

  /// Two-step sign-in is on (own account only).
  final bool twoFactor;
  final int backupCodesLeft;

  /// Who can message / mention me: see the server's dm_policy and mention_policy.
  final String dmPolicy, mentionPolicy;

  /// Comma-separated words; comments containing them wait for approval.
  final String commentFilter;

  /// Coins per 30 days when this creator offers subscriptions.
  final int? subPrice;
  final String subPerks;

  /// The viewer's subscription to this person runs until then.
  final DateTime? subscribedUntil;

  /// The viewer restricted this person.
  final bool restricted;

  bool get subscribed =>
      subscribedUntil != null && subscribedUntil!.isAfter(DateTime.now());

  /// Gifter level 0–50.
  final int level;

  /// Coins I have gifted in total (only on my own profile): VIP progress.
  final int? giftsSent;

  /// Top 3 of last week's LIVE ranking ('streamers' or 'gifters', place 1–3): 🏆 badge this week.
  final String? championType;
  final int championRank;

  /// Free reward coins (part of [coins]); they can be gifted but never paid out.
  final int bonusCoins;

  /// Bio links.
  final String website, instagram;

  /// Likes on all of this person's videos.
  final int likesTotal;

  /// Has a story from the last 24 hours the viewer can see, and whether all of it was seen.
  final bool hasStory, storySeen;

  /// Allows automatic tips & suggestions notifications.
  final bool marketingOptIn;

  final int id;
  final String username;
  final String displayName;
  final String bio;
  final String? avatarUrl;
  final bool verified;

  /// Own account only: identity (ID card / passport + selfie) approved.
  final bool idVerified;
  final int followers;
  final int following;
  final int videos;
  final bool? isFollowing;
  final String? email;
  final String role;
  final int coins;
  final int earnedCoins;

  /// Set when this person is live right now.
  final int? liveId;

  /// Private account: only approved followers see the videos.
  final bool isPrivate;

  /// The viewer asked to follow this private account and is waiting.
  final bool requested;

  /// The viewer blocked this person.
  final bool blocked;

  /// The viewer may see this person's videos.
  final bool canView;

  bool get isStaff => role == 'admin' || role == 'moderator';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
    id: j['id'] as int,
    username: j['username'] as String,
    displayName: (j['display_name'] as String?) ?? j['username'] as String,
    bio: (j['bio'] as String?) ?? '',
    avatarUrl: j['avatar_url'] as String?,
    verified: (j['verified'] as bool?) ?? false,
    idVerified: (j['id_verified'] as bool?) ?? false,
    followers: (j['followers'] as int?) ?? 0,
    following: (j['following'] as int?) ?? 0,
    videos: (j['videos'] as int?) ?? 0,
    isFollowing: j['is_following'] as bool?,
    email: j['email'] as String?,
    role: (j['role'] as String?) ?? 'user',
    coins: ((j['coins'] as int?) ?? 0) + ((j['bonus_coins'] as int?) ?? 0),
    earnedCoins: (j['earned_coins'] as int?) ?? 0,
    liveId: j['live_id'] as int?,
    isPrivate: (j['is_private'] as bool?) ?? false,
    requested: (j['requested'] as bool?) ?? false,
    blocked: (j['blocked'] as bool?) ?? false,
    canView: (j['can_view'] as bool?) ?? true,
    marketingOptIn: (j['marketing_opt_in'] as bool?) ?? true,
    website: (j['website'] as String?) ?? '',
    instagram: (j['instagram'] as String?) ?? '',
    likesTotal: (j['likes_total'] as int?) ?? 0,
    hasStory: (j['has_story'] as bool?) ?? false,
    storySeen: (j['story_seen'] as bool?) ?? false,
    level: (j['level'] as int?) ?? 0,
    giftsSent: j['gifts_sent'] as int?,
    championType: (j['champion'] as Map?)?['type'] as String?,
    championRank: ((j['champion'] as Map?)?['rank'] as int?) ?? 0,
    bonusCoins: (j['bonus_coins'] as int?) ?? 0,
    twoFactor: (j['two_factor'] as bool?) ?? false,
    backupCodesLeft: (j['backup_codes_left'] as int?) ?? 0,
    dmPolicy: (j['dm_policy'] as String?) ?? 'everyone',
    mentionPolicy: (j['mention_policy'] as String?) ?? 'everyone',
    commentFilter: (j['comment_filter'] as String?) ?? '',
    subPrice: j['sub_price'] as int?,
    subPerks: (j['sub_perks'] as String?) ?? '',
    subscribedUntil: j['subscribed_until'] == null
        ? null
        : DateTime.parse(j['subscribed_until'] as String).toLocal(),
    restricted: (j['restricted'] as bool?) ?? false,
  );
}

/// One photo or video story (visible for 24 hours).
class Story {
  Story({
    required this.id,
    required this.type,
    required this.url,
    required this.duration,
    required this.caption,
    this.views,
    this.seen = false,
    required this.createdAt,
    this.sound,
  });
  final int id;
  final String type, url, caption;
  final double duration;

  /// Music added to the story, or null.
  final SoundUse? sound;

  /// Only filled in for the owner.
  final int? views;
  bool seen;
  final DateTime createdAt;

  bool get isVideo => type == 'video';

  factory Story.fromJson(Map<String, dynamic> j) => Story(
    id: j['id'] as int,
    type: j['type'] as String,
    url: j['url'] as String,
    duration: (j['duration'] as num).toDouble(),
    caption: (j['caption'] as String?) ?? '',
    views: j['views'] as int?,
    seen: (j['seen'] as bool?) ?? false,
    createdAt: DateTime.parse(j['created_at'] as String),
    sound: SoundUse.fromJson(j),
  );
}

/// A piece of music people can add to videos and stories (uploaded by TalkMe or from Jamendo).
class Sound {
  Sound({
    this.id,
    required this.source,
    this.externalId,
    required this.title,
    this.artist = '',
    this.audioUrl,
    this.coverUrl,
    this.duration = 0,
    this.uses = 0,
    this.license = '',
  });

  /// Null for a library track nobody on TalkMe has used yet (it gets an id when picked).
  final int? id;
  final String source; // upload or jamendo
  final String? externalId;
  final String title, artist, license;
  final String? audioUrl, coverUrl;
  final double duration;
  final int uses;

  String get label => artist.isEmpty ? title : '$title · $artist';

  factory Sound.fromJson(Map<String, dynamic> j) => Sound(
    id: j['id'] as int?,
    source: (j['source'] as String?) ?? 'upload',
    externalId: j['external_id'] as String?,
    title: j['title'] as String,
    artist: (j['artist'] as String?) ?? '',
    audioUrl: j['audio_url'] as String?,
    coverUrl: j['cover_url'] as String?,
    duration: ((j['duration'] as num?) ?? 0).toDouble(),
    uses: (j['uses'] as int?) ?? 0,
    license: (j['license'] as String?) ?? '',
  );
}

/// A sound on one video/story: which part of the song, and how loud the song and the original are.
class SoundUse {
  SoundUse({
    required this.sound,
    this.start = 0,
    this.volume = 100,
    this.originalVolume = 100,
  });
  final Sound sound;

  /// Seconds into the song where the video starts.
  final double start;

  /// 0–100.
  final int volume, originalVolume;

  static SoundUse? fromJson(Map<String, dynamic> j) {
    final s = j['sound'];
    if (s is! Map<String, dynamic>) return null;
    return SoundUse(
      sound: Sound.fromJson(s),
      start: ((j['sound_start'] as num?) ?? 0).toDouble(),
      volume: (j['sound_volume'] as int?) ?? 100,
      originalVolume: (j['original_volume'] as int?) ?? 100,
    );
  }

  Map<String, String> toForm() => {
    if (sound.id != null) 'sound_id': '${sound.id}',
    'sound_start': start.toStringAsFixed(2),
    'sound_volume': '$volume',
    'original_volume': '$originalVolume',
  };
}

/// Someone's active stories, as shown in the story bar.
class StoryGroup {
  StoryGroup(this.user, this.stories);
  final AppUser user;
  final List<Story> stories;

  bool get allSeen => stories.every((s) => s.seen);

  factory StoryGroup.fromJson(Map<String, dynamic> j) => StoryGroup(
    AppUser.fromJson(j['user'] as Map<String, dynamic>),
    (j['stories'] as List)
        .map((e) => Story.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// The original video a duet plays beside.
class DuetSource {
  DuetSource({
    required this.id,
    required this.videoUrl,
    this.thumbUrl,
    this.width = 0,
    this.height = 0,
    this.filter,
    required this.username,
    required this.displayName,
  });
  final int id;
  final String videoUrl;
  final String? thumbUrl;
  final int width, height;
  final String? filter;
  final String username, displayName;

  factory DuetSource.fromJson(Map<String, dynamic> j) => DuetSource(
    id: j['id'] as int,
    videoUrl: j['video_url'] as String,
    thumbUrl: j['thumb_url'] as String?,
    width: (j['width'] as int?) ?? 0,
    height: (j['height'] as int?) ?? 0,
    filter: j['filter'] as String?,
    username: j['username'] as String,
    displayName: j['display_name'] as String,
  );
}

class Video {
  Video({
    required this.id,
    required this.caption,
    required this.videoUrl,
    this.hlsUrl,
    required this.thumbUrl,
    required this.duration,
    required this.width,
    required this.height,
    required this.status,
    required this.allowComments,
    this.visibility = 'public',
    this.overlays = const [],
    this.filter,
    this.speed = 1,
    this.allowDuet = true,
    this.duetOf,
    this.pinnedCommentId,
    this.reposts = 0,
    this.reposted = false,
    this.repostedBy,
    this.pinned = false,
    required this.views,
    required this.likes,
    required this.comments,
    required this.liked,
    this.saved = false,
    this.authorFollowing = false,
    required this.createdAt,
    required this.user,
    this.sound,
  });

  final int id;
  final String caption;
  final String videoUrl;

  /// Adaptive stream (360p–720p), present once the server has processed the upload.
  final String? hlsUrl;
  final String? thumbUrl;
  final double duration;
  final int width;
  final int height;
  final String status;
  bool allowComments;

  /// Colour filter (see filters.dart) and playback speed chosen by the creator.
  final String? filter;
  final double speed;

  /// Others may duet this video; and the original when this video is a duet.
  final bool allowDuet;
  final DuetSource? duetOf;

  /// public, friends (people who follow each other) or private (only the author).
  String visibility;

  /// Texts and stickers drawn on top of the video.
  final List<VideoOverlay> overlays;
  int? pinnedCommentId;
  int reposts;
  bool reposted;

  /// Someone the viewer follows who reposted this video (Following feed).
  final String? repostedBy;

  /// Pinned to the top of the author's profile.
  bool pinned;
  final int views;
  int likes;
  int comments;
  bool liked;
  bool saved;

  /// Whether the viewer follows the author (drives the Follow pill on the video).
  bool authorFollowing;
  final DateTime createdAt;
  final AppUser user;

  /// Music added when posting (plays with the video), or null.
  final SoundUse? sound;

  factory Video.fromJson(Map<String, dynamic> j) => Video(
    id: j['id'] as int,
    caption: (j['caption'] as String?) ?? '',
    videoUrl: j['video_url'] as String,
    hlsUrl: j['hls_url'] as String?,
    thumbUrl: j['thumb_url'] as String?,
    duration: (j['duration'] as num).toDouble(),
    width: j['width'] as int,
    height: j['height'] as int,
    status: j['status'] as String,
    allowComments: j['allow_comments'] as bool,
    visibility: (j['visibility'] as String?) ?? 'public',
    overlays: ((j['overlays'] as List?) ?? const [])
        .map((e) => VideoOverlay.fromJson(e as Map<String, dynamic>))
        .toList(),
    pinnedCommentId: j['pinned_comment_id'] as int?,
    filter: j['filter'] as String?,
    speed: (j['speed'] as num?)?.toDouble() ?? 1,
    allowDuet: (j['allow_duet'] as bool?) ?? true,
    duetOf: j['duet_of'] == null
        ? null
        : DuetSource.fromJson(j['duet_of'] as Map<String, dynamic>),
    reposts: (j['reposts'] as int?) ?? 0,
    reposted: (j['reposted'] as bool?) ?? false,
    repostedBy: j['reposted_by'] as String?,
    pinned: (j['pinned'] as bool?) ?? false,
    views: j['views'] as int,
    likes: j['likes'] as int,
    comments: j['comments'] as int,
    liked: j['liked'] as bool,
    saved: (j['saved'] as bool?) ?? false,
    authorFollowing: ((j['user'] as Map)['is_following'] as bool?) ?? false,
    sound: SoundUse.fromJson(j),
    createdAt: DateTime.parse(j['created_at'] as String),
    user: AppUser.fromJson(j['user'] as Map<String, dynamic>),
  );
}

/// A text or sticker placed on a video. x/y are 0–1 of the video size.
class VideoOverlay {
  VideoOverlay({
    required this.text,
    this.x = .5,
    this.y = .4,
    this.size = 1,
    this.color = 0xFFFFFFFF,
    this.style = 'plain',
  });

  String text;
  double x, y, size;
  int color;

  /// plain (outlined text), box (text on a coloured box) or sticker (emoji).
  String style;

  factory VideoOverlay.fromJson(Map<String, dynamic> j) => VideoOverlay(
    text: j['text'] as String,
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    size: (j['size'] as num).toDouble(),
    color:
        0xFF000000 | int.parse((j['color'] as String).substring(1), radix: 16),
    style: j['style'] as String,
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'x': x,
    'y': y,
    'size': size,
    'color':
        '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
    'style': style,
  };
}

class Comment {
  Comment({
    required this.id,
    this.parentId,
    required this.body,
    this.likes = 0,
    this.liked = false,
    this.replies = 0,
    this.pinned = false,
    this.byCreator = false,
    this.subscriber = false,
    this.videoId,
    this.thumbUrl,
    this.fromRestricted = false,
    required this.createdAt,
    required this.user,
  });

  final int id;

  /// The writer subscribes to the video's creator (shown with a badge).
  final bool subscriber;

  /// Only in the "Comments to review" list.
  final int? videoId;
  final String? thumbUrl;
  final bool fromRestricted;

  /// Set for replies; points at the top-level comment.
  final int? parentId;
  final String body;
  int likes;
  bool liked;
  int replies;
  bool pinned;

  /// Written by the video's author (shown with a "Creator" label).
  final bool byCreator;
  final DateTime createdAt;
  final AppUser user;

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
    id: j['id'] as int,
    parentId: j['parent_id'] as int?,
    body: j['body'] as String,
    likes: (j['likes'] as int?) ?? 0,
    liked: (j['liked'] as bool?) ?? false,
    replies: (j['replies'] as int?) ?? 0,
    pinned: (j['pinned'] as bool?) ?? false,
    byCreator: (j['by_creator'] as bool?) ?? false,
    subscriber: (j['subscriber'] as bool?) ?? false,
    videoId: j['video_id'] as int?,
    thumbUrl: j['thumb_url'] as String?,
    fromRestricted: (j['from_restricted'] as bool?) ?? false,
    createdAt: DateTime.parse(j['created_at'] as String),
    user: AppUser.fromJson(j['user'] as Map<String, dynamic>),
  );
}

class PageResult<T> {
  PageResult(this.items, this.nextCursor);
  final List<T> items;
  final String? nextCursor;
}

typedef PageLoader<T> = Future<PageResult<T>> Function(String? cursor);

class RemoteConfig {
  RemoteConfig(this.raw);
  final Map<String, dynamic> raw;

  String get appName => raw['app_name'] as String? ?? 'TalkMe';
  bool get registrationOpen => raw['registration_open'] as bool? ?? true;
  bool get maintenance => raw['maintenance_mode'] as bool? ?? false;
  String get maintenanceMessage => raw['maintenance_message'] as String? ?? '';
  String get minAppVersion => raw['min_app_version'] as String? ?? '1.0.0';
  int get maxUploadMb => raw['max_upload_mb'] as int? ?? 100;
  int get maxDurationSec => raw['max_duration_sec'] as int? ?? 180;
  String get termsText => raw['terms_text'] as String? ?? '';
  String get privacyText => raw['privacy_text'] as String? ?? '';
  String get googleClientId => raw['google_client_id'] as String? ?? '';

  /// Modules on / off (Admin → Features).
  Map<String, bool> get features => {
    for (final e in ((raw['features'] as Map?) ?? const {}).entries)
      '${e.key}': e.value == true,
  };
}

class Gift {
  Gift({
    required this.id,
    required this.name,
    required this.icon,
    required this.coins,
    this.animUrl,
    this.animMs,
    this.soundUrl,
  });
  final int id;
  final String name;
  final String icon;
  final int coins;

  /// Ready-made full-screen animation (animated WebP / GIF) uploaded in the admin, e.g. a 3D lion.
  final String? animUrl;

  /// How long [animUrl] plays.
  final int? animMs;

  /// Sound played with the animation (a roar…).
  final String? soundUrl;

  factory Gift.fromJson(Map<String, dynamic> j) => Gift(
    id: j['id'] as int,
    name: j['name'] as String,
    icon: j['icon'] as String,
    coins: j['coins'] as int,
    animUrl: j['anim'] as String?,
    animMs: j['anim_ms'] as int?,
    soundUrl: j['sound'] as String?,
  );
}

/// The gift list as last loaded, by name: gifts announced in a live only carry name, emoji and price,
/// so their animation and sound are looked up here.
final knownGifts = <String, Gift>{};

class CoinPackage {
  CoinPackage({
    required this.id,
    required this.coins,
    required this.bonus,
    required this.price,
    required this.productId,
  });
  final int id, coins, bonus;
  final String price, productId;

  factory CoinPackage.fromJson(Map<String, dynamic> j) => CoinPackage(
    id: j['id'] as int,
    coins: j['coins'] as int,
    bonus: j['bonus'] as int,
    price: j['price'] as String,
    productId: j['product_id'] as String,
  );
}

class Wallet {
  Wallet({
    required this.coins,
    required this.earned,
    required this.sharePercent,
    required this.testMode,
    required this.packages,
    this.bonus = 0,
  });

  /// Everything spendable (bought + bonus); [bonus] is the free part.
  final int coins, earned, sharePercent, bonus;
  final bool testMode;
  final List<CoinPackage> packages;

  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
    coins: (j['coins'] as int) + ((j['bonus_coins'] as int?) ?? 0),
    bonus: (j['bonus_coins'] as int?) ?? 0,
    earned: j['earned_coins'] as int,
    sharePercent: j['creator_share_percent'] as int,
    testMode: j['test_mode'] as bool,
    packages: (j['packages'] as List)
        .map((e) => CoinPackage.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class CoinTx {
  CoinTx({
    required this.id,
    required this.wallet,
    required this.amount,
    required this.type,
    required this.note,
    required this.createdAt,
  });
  final int id, amount;
  final String wallet, type, note;
  final DateTime createdAt;

  factory CoinTx.fromJson(Map<String, dynamic> j) => CoinTx(
    id: j['id'] as int,
    wallet: j['wallet'] as String,
    amount: j['amount'] as int,
    type: j['type'] as String,
    note: j['note'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

class LiveInfo {
  LiveInfo({
    required this.id,
    required this.title,
    required this.viewers,
    required this.giftsCoins,
    required this.startedAt,
    required this.host,
    this.inBattle = false,
    this.status = 'live',
    this.goalCoins,
    this.goalText = '',
    this.goalProgress = 0,
    this.pinnedMessage,
  });
  final bool inBattle;

  /// live or ended.
  final String status;
  final int id;
  final String title;
  final int viewers, giftsCoins;

  /// Gift goal set by the host ("10,000 coins → I sing"), and how far it is.
  final int? goalCoins;
  final String goalText;
  final int goalProgress;
  final String? pinnedMessage;
  final DateTime startedAt;
  final AppUser host;

  factory LiveInfo.fromJson(Map<String, dynamic> j) => LiveInfo(
    id: j['id'] as int,
    title: (j['title'] as String?) ?? '',
    viewers: (j['viewers'] as int?) ?? 0,
    giftsCoins: (j['gifts_coins'] as int?) ?? 0,
    startedAt: DateTime.parse(j['started_at'] as String),
    host: AppUser.fromJson(j['user'] as Map<String, dynamic>),
    inBattle: (j['in_battle'] as bool?) ?? false,
    status: (j['status'] as String?) ?? 'live',
    goalCoins: (j['goal'] as Map?)?['coins'] as int?,
    goalText: ((j['goal'] as Map?)?['text'] as String?) ?? '',
    goalProgress: ((j['goal'] as Map?)?['progress'] as int?) ?? 0,
    pinnedMessage: j['pinned_message'] as String?,
  );
}

/// What the app needs to connect to a live room.
class LiveSession {
  LiveSession({
    required this.live,
    required this.url,
    required this.token,
    this.role = 'host',
    this.mods = const [],
    this.level = 0,
    this.comments = const [],
    this.following = false,
    this.guestsEnabled = false,
    this.guestStatus = 'none',
    this.guestSettings,
  });
  final LiveInfo live;

  /// Panels, who may ask to join and auto-accept, as the host set them.
  final GuestSettings? guestSettings;

  /// Viewers may ask to join on camera; my request status (none, requested, active…).
  final bool guestsEnabled;
  final String guestStatus;

  /// The viewer already follows the host (hides the Follow button).
  final bool following;

  /// Latest chat messages and gifts, oldest first (so people who join late see them).
  final List<LiveComment> comments;
  final String url, token;

  /// host, mod or viewer.
  final String role;

  /// User ids of the host's moderators.
  final List<int> mods;

  /// My gifter level.
  final int level;

  factory LiveSession.fromJson(Map<String, dynamic> j) => LiveSession(
    live: LiveInfo.fromJson(j['live'] as Map<String, dynamic>),
    url: j['url'] as String,
    token: j['token'] as String,
    role: (j['role'] as String?) ?? 'host',
    mods: ((j['mods'] as List?) ?? const []).cast<int>(),
    level: (j['level'] as int?) ?? 0,
    following: (j['following'] as bool?) ?? false,
    guestsEnabled: (j['guests_enabled'] as bool?) ?? false,
    guestStatus: (j['guest_status'] as String?) ?? 'none',
    guestSettings: j['guest_settings'] == null
        ? null
        : GuestSettings.fromJson(j['guest_settings'] as Map<String, dynamic>),
    comments: [
      for (final c in (j['comments'] as List?) ?? const [])
        LiveComment.fromJson(c as Map<String, dynamic>),
    ],
  );
}

/// Someone asking to join a live on camera (requested), invited by the host (invited) or on it (active).
class LiveGuest {
  LiveGuest(
    this.user,
    this.status, {
    this.micMuted = false,
    this.camOff = false,
    this.coins = 0,
  });
  final AppUser user;
  final String status;

  /// Turned off by the host.
  final bool micMuted, camOff;

  /// Coins received in this live.
  final int coins;

  factory LiveGuest.fromJson(Map<String, dynamic> g) => LiveGuest(
    AppUser.fromJson(g['user'] as Map<String, dynamic>),
    g['status'] as String,
    micMuted: (g['mic_muted'] as bool?) ?? false,
    camOff: (g['cam_off'] as bool?) ?? false,
    coins: (g['coins'] as int?) ?? 0,
  );
}

/// The host's multi-guest settings: panels on screen (2, 4, 6 or 9, the host's included),
/// who may ask to join (everyone, followers, off) and whether requests are accepted automatically.
class GuestSettings {
  const GuestSettings({
    this.seats = 4,
    this.policy = 'everyone',
    this.autoAccept = false,
  });
  final int seats;
  final String policy;
  final bool autoAccept;

  int get maxGuests => seats - 1;

  factory GuestSettings.fromJson(Map<String, dynamic> j) => GuestSettings(
    seats: (j['seats'] as int?) ?? 4,
    policy: (j['policy'] as String?) ?? 'everyone',
    autoAccept: (j['auto_accept'] as bool?) ?? false,
  );
}

/// Host's view: requests, invitations and guests, plus the settings.
class GuestBoard {
  GuestBoard(Map<String, dynamic> j)
    : items = [
        for (final g in j['items'] as List)
          LiveGuest.fromJson(g as Map<String, dynamic>),
      ],
      settings = GuestSettings.fromJson(j);
  final List<LiveGuest> items;
  final GuestSettings settings;
}

/// Everyone's view of the stage: guests on camera with their coins this live, the host's coins, the layout.
class LiveStage {
  LiveStage(Map<String, dynamic> j)
    : guests = [
        for (final g in j['guests'] as List)
          LiveGuest.fromJson(g as Map<String, dynamic>),
      ],
      hostCoins = (j['host_coins'] as int?) ?? 0,
      settings = GuestSettings.fromJson(j);
  final List<LiveGuest> guests;
  final int hostCoins;
  final GuestSettings settings;
}

/// A saved live chat message or gift.
class LiveComment {
  LiveComment({
    required this.type,
    this.body = '',
    this.mod = false,
    this.userId,
    this.username,
    this.name,
    this.level = 0,
    this.giftName,
    this.giftIcon,
    this.giftQuantity = 1,
  });
  final String type; // chat or gift
  final String body;

  /// Message from the admin panel's moderator.
  final bool mod;
  final int? userId;
  final String? username, name;
  final int level;
  final String? giftName, giftIcon;
  final int giftQuantity;

  factory LiveComment.fromJson(Map<String, dynamic> j) {
    final u = j['user'] as Map<String, dynamic>?;
    final g = j['gift'] as Map<String, dynamic>?;
    return LiveComment(
      type: j['type'] as String,
      body: (j['body'] as String?) ?? '',
      mod: (j['mod'] as bool?) ?? false,
      userId: u?['id'] as int?,
      username: u?['username'] as String?,
      name: u?['display_name'] as String?,
      level: (u?['level'] as int?) ?? 0,
      giftName: g?['name'] as String?,
      giftIcon: g?['icon'] as String?,
      giftQuantity: (g?['quantity'] as int?) ?? 1,
    );
  }
}

/// Everything a search found.
class SearchResults {
  SearchResults(Map<String, dynamic> j)
    : users = (j['users'] as List)
          .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
          .toList(),
      hashtags = (j['hashtags'] as List)
          .map(
            (e) => (
              name: e['name'] as String,
              count: (e['videos_count'] as num).toInt(),
            ),
          )
          .toList(),
      videos = ((j['videos'] as List?) ?? const [])
          .map((e) => Video.fromJson(e as Map<String, dynamic>))
          .toList(),
      lives = ((j['lives'] as List?) ?? const [])
          .map((e) => LiveInfo.fromJson(e as Map<String, dynamic>))
          .toList();
  final List<AppUser> users;
  final List<({String name, int count})> hashtags;
  final List<Video> videos;
  final List<LiveInfo> lives;
}

/// A favourites folder for saved videos.
class Folder {
  Folder(Map<String, dynamic> j)
    : id = j['id'] as int,
      name = j['name'] as String,
      count = (j['count'] as int?) ?? 0,
      coverUrl = j['cover_url'] as String?;
  final int id;
  final String name;
  final int count;
  final String? coverUrl;
}

/// One row of a leaderboard.
class RankEntry {
  RankEntry(this.rank, this.coins, this.user, {this.liveId, this.reward = 0});
  final int rank, coins;
  final AppUser user;

  /// Live right now (LIVE rankings): tap to join.
  final int? liveId;

  /// Bonus coins won (last week's winners).
  final int reward;

  factory RankEntry.fromJson(Map<String, dynamic> j) => RankEntry(
    j['rank'] as int,
    j['coins'] as int,
    AppUser.fromJson(j['user'] as Map<String, dynamic>),
    liveId: j['live_id'] as int?,
    reward: (j['reward'] as int?) ?? 0,
  );
}

/// Someone's place in a LIVE ranking, and the coins they need to pass the one above.
class RankPlace {
  RankPlace(Map<String, dynamic> j)
    : rank = j['rank'] as int,
      coins = j['coins'] as int,
      gap = (j['gap'] as int?) ?? 0;
  final int rank, coins, gap;
}

/// LIVE ranking for an hour, day or week (streamers by coins received, gifters by coins sent).
class LiveRanking {
  LiveRanking(Map<String, dynamic> j)
    : type = j['type'] as String,
      period = j['period'] as String,
      endsAt = DateTime.parse(j['ends_at'] as String),
      items = [
        for (final e in j['items'] as List)
          RankEntry.fromJson(e as Map<String, dynamic>),
      ],
      me = j['me'] == null ? null : RankPlace(j['me'] as Map<String, dynamic>),
      focus = j['focus'] == null
          ? null
          : RankPlace(j['focus'] as Map<String, dynamic>),
      rewards = [for (final r in (j['rewards'] as List? ?? [])) r as int],
      lastWinners = [
        for (final e in (j['last_winners'] as List? ?? []))
          RankEntry.fromJson(e as Map<String, dynamic>),
      ];
  final String type, period;
  final DateTime endsAt;
  final List<RankEntry> items;
  final RankPlace? me, focus;

  /// Bonus coins for places 1–3 (weekly).
  final List<int> rewards;
  final List<RankEntry> lastWinners;
}

/// A live someone scheduled for later.
class LiveEvent {
  LiveEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.user,
    this.reminders = 0,
    this.reminded = false,
    this.mine = false,
  });
  final int id;
  final String title;
  final DateTime startsAt;
  final AppUser user;
  int reminders;
  bool reminded;
  final bool mine;

  factory LiveEvent.fromJson(Map<String, dynamic> j) => LiveEvent(
    id: j['id'] as int,
    title: j['title'] as String,
    startsAt: DateTime.parse(j['starts_at'] as String),
    user: AppUser.fromJson(j['user'] as Map<String, dynamic>),
    reminders: (j['reminders'] as int?) ?? 0,
    reminded: (j['reminded'] as bool?) ?? false,
    mine: (j['mine'] as bool?) ?? false,
  );
}

/// Daily reward status.
class RewardState {
  RewardState(Map<String, dynamic> j)
    : enabled = j['enabled'] as bool,
      streak = j['streak'] as int,
      checkedInToday = j['checked_in_today'] as bool,
      nextReward = j['next_reward'] as int,
      week = (j['week'] as List).cast<int>(),
      bonusCoins = j['bonus_coins'] as int,
      inviteReward = j['invite_reward'] as int,
      invites = j['invites'] as int,
      invitesRewarded = j['invites_rewarded'] as int,
      reward = j['reward'] as int?;
  final bool enabled, checkedInToday;
  final int streak,
      nextReward,
      bonusCoins,
      inviteReward,
      invites,
      invitesRewarded;
  final List<int> week;

  /// Set right after a check-in: how many coins were just added.
  final int? reward;
}

/// A gift that was sent (from the API response, or relayed to viewers in a live).
class GiftEvent {
  GiftEvent({
    required this.gift,
    required this.senderName,
    this.senderAvatar,
    this.quantity = 1,
    this.senderLevel = 0,
    this.toId,
    this.toName,
  });
  final Gift gift;
  final String senderName;
  final String? senderAvatar;

  /// Multi-guest live: the guest who got it (null: the host).
  final int? toId;
  final String? toName;

  /// x1 / x5 / x10 / x99 sent at once.
  final int quantity;

  /// Sender's gifter level (VIP colour on the gift banner).
  final int senderLevel;

  int get total => gift.coins * quantity;
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.videoId,
    this.liveId,
    this.thumbUrl,
    this.actor,
  });

  final int id;
  final String type, title, body;
  bool read;
  final DateTime createdAt;
  final int? videoId, liveId;
  final String? thumbUrl;
  final AppUser? actor;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as int,
    type: j['type'] as String,
    title: j['title'] as String,
    body: (j['body'] as String?) ?? '',
    read: j['read'] as bool,
    createdAt: DateTime.parse(j['created_at'] as String),
    videoId: j['video_id'] as int?,
    liveId: j['live_id'] as int?,
    thumbUrl: j['thumb_url'] as String?,
    actor: j['actor'] == null
        ? null
        : AppUser.fromJson(j['actor'] as Map<String, dynamic>),
  );
}

class BannerItem {
  BannerItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    required this.linkType,
    required this.linkValue,
  });
  final int id;
  final String title, subtitle, linkType, linkValue;
  final String? imageUrl;

  factory BannerItem.fromJson(Map<String, dynamic> j) => BannerItem(
    id: j['id'] as int,
    title: j['title'] as String,
    subtitle: (j['subtitle'] as String?) ?? '',
    imageUrl: j['image_url'] as String?,
    linkType: j['link_type'] as String,
    linkValue: (j['link_value'] as String?) ?? '',
  );
}

class PayoutRequest {
  PayoutRequest({
    required this.id,
    required this.coins,
    required this.amountUsd,
    this.amountAll,
    required this.method,
    required this.status,
    required this.note,
    required this.createdAt,
  });
  final int id, coins;
  final double amountUsd;

  /// Lek sent for POK withdrawals.
  final int? amountAll;
  final String method, status, note;
  final DateTime createdAt;

  String get money => amountAll != null
      ? '${amountAll.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')} L'
      : '\$${amountUsd.toStringAsFixed(2)}';

  factory PayoutRequest.fromJson(Map<String, dynamic> j) => PayoutRequest(
    id: j['id'] as int,
    coins: j['coins'] as int,
    amountUsd: (j['amount_usd'] as num).toDouble(),
    amountAll: j['amount_all'] as int?,
    method: j['method'] as String,
    status: j['status'] as String,
    note: (j['note'] as String?) ?? '',
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

class PayoutInfo {
  PayoutInfo({
    required this.minCoins,
    required this.usdPerCoin,
    this.lekPerCoin = 0,
    required this.methods,
    required this.earned,
    required this.items,
  });
  final int minCoins, earned;
  final double usdPerCoin;

  /// Withdrawals to POK are paid in lek at this rate.
  final double lekPerCoin;
  final List<String> methods;
  final List<PayoutRequest> items;

  bool get hasOpenRequest =>
      items.any((p) => p.status == 'pending' || p.status == 'approved');

  factory PayoutInfo.fromJson(Map<String, dynamic> j) => PayoutInfo(
    minCoins: j['min_coins'] as int,
    usdPerCoin: (j['usd_per_coin'] as num).toDouble(),
    lekPerCoin: (j['lek_per_coin'] as num?)?.toDouble() ?? 0,
    methods: (j['methods'] as List).cast<String>(),
    earned: j['earned_coins'] as int,
    items: (j['items'] as List)
        .map((e) => PayoutRequest.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// One emoji reaction on a message, with how many people chose it.
class Reaction {
  Reaction(this.emoji, this.count, this.mine);
  final String emoji;
  final int count;
  final bool mine;

  factory Reaction.fromJson(Map<String, dynamic> j) =>
      Reaction(j['emoji'] as String, j['count'] as int, j['mine'] as bool);
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.body,
    required this.mine,
    required this.createdAt,
    this.type = 'text',
    this.deleted = false,
    this.sender,
    this.videoId,
    this.videoThumb,
    this.mediaUrl,
    this.thumbUrl,
    this.duration,
    this.replyId,
    this.replyBody,
    this.replyName,
    this.reactions = const [],
  });
  final int id;
  String body;

  /// text, image, voice, clip (a video file sent in the chat), video (shared post) or system ("X joined").
  final String type;
  bool deleted;
  final bool mine;
  final DateTime createdAt;
  final AppUser? sender;
  final int? videoId;
  final String? videoThumb;
  final String? mediaUrl;

  /// First frame of a clip.
  final String? thumbUrl;
  final double? duration;
  final int? replyId;
  final String? replyBody, replyName;
  List<Reaction> reactions;

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final v = j['video'] as Map<String, dynamic>?;
    final r = j['reply_to'] as Map<String, dynamic>?;
    final s = j['sender'] as Map<String, dynamic>?;
    return ChatMessage(
      id: j['id'] as int,
      body: (j['body'] as String?) ?? '',
      type: (j['type'] as String?) ?? (v != null ? 'video' : 'text'),
      deleted: (j['deleted'] as bool?) ?? false,
      mine: j['mine'] as bool,
      createdAt: DateTime.parse(j['created_at'] as String),
      sender: s == null ? null : AppUser.fromJson(s),
      videoId: v?['id'] as int?,
      videoThumb: v?['thumb_url'] as String?,
      mediaUrl: j['media_url'] as String?,
      thumbUrl: j['thumb_url'] as String?,
      duration: (j['duration'] as num?)?.toDouble(),
      replyId: r?['id'] as int?,
      replyBody: r?['body'] as String?,
      replyName: r?['sender_name'] as String?,
      reactions: ((j['reactions'] as List?) ?? const [])
          .map((e) => Reaction.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A member of a group chat.
class ChatMember {
  ChatMember(this.user, this.admin, this.pending);
  final AppUser user;
  final bool admin, pending;
}

class Conversation {
  Conversation({
    required this.id,
    required this.user,
    this.lastBody,
    this.lastMine = false,
    this.lastAt,
    this.unread = 0,
    this.isGroup = false,
    this.title,
    this.status = 'active',
    this.role = 'member',
    this.memberCount = 2,
    this.preview = const [],
    this.members = const [],
  });
  final int id;

  /// The other person (one-to-one chats).
  final AppUser user;
  final String? lastBody;
  final bool lastMine;
  final DateTime? lastAt;
  final int unread;
  final bool isGroup;
  final String? title;

  /// active, or request (a message request you haven't accepted).
  String status;

  /// admin or member (groups).
  final String role;
  final int memberCount;

  /// A few members' photos for the group avatar.
  final List<AppUser> preview;

  /// Filled in by the details call.
  final List<ChatMember> members;

  String get name => isGroup ? (title ?? '') : user.displayName;
  bool get isAdmin => role == 'admin';

  factory Conversation.fromJson(Map<String, dynamic> j) {
    final last = j['last_message'] as Map<String, dynamic>?;
    return Conversation(
      id: j['id'] as int,
      user: AppUser.fromJson(j['user'] as Map<String, dynamic>),
      lastBody: last?['body'] as String?,
      lastMine: (last?['mine'] as bool?) ?? false,
      lastAt: last == null
          ? null
          : DateTime.parse(last['created_at'] as String),
      unread: (j['unread'] as int?) ?? 0,
      isGroup: (j['is_group'] as bool?) ?? false,
      title: j['title'] as String?,
      status: (j['status'] as String?) ?? 'active',
      role: (j['role'] as String?) ?? 'member',
      memberCount: (j['member_count'] as int?) ?? 2,
      preview: ((j['members_preview'] as List?) ?? const [])
          .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
          .toList(),
      members: ((j['members'] as List?) ?? const [])
          .map(
            (e) => ChatMember(
              AppUser.fromJson(e as Map<String, dynamic>),
              e['role'] == 'admin',
              e['pending'] == true,
            ),
          )
          .toList(),
    );
  }
}

class BattleSide {
  BattleSide({
    required this.live,
    required this.score,
    this.topName,
    this.topAvatar,
    this.topCoins = 0,
    this.tops = const [],
    this.streak = 0,
  });
  final LiveInfo live;
  final int score;
  final String? topName, topAvatar;
  final int topCoins;

  /// Best gifters of this side during the battle, up to 3.
  final List<({String name, String? avatar, int coins})> tops;

  /// Battles in a row this host has won.
  final int streak;

  factory BattleSide.fromJson(Map<String, dynamic> j) {
    final top = j['top'] as Map<String, dynamic>?;
    final tops = [
      for (final t in (j['tops'] as List?) ?? (top == null ? const [] : [top]))
        (
          name: (t as Map)['display_name'] as String,
          avatar: t['avatar_url'] as String?,
          coins: (t['coins'] as int?) ?? 0,
        ),
    ];
    return BattleSide(
      live: LiveInfo.fromJson(j['live'] as Map<String, dynamic>),
      score: j['score'] as int,
      topName: top?['display_name'] as String?,
      topAvatar: top?['avatar_url'] as String?,
      topCoins: (top?['coins'] as int?) ?? 0,
      tops: tops,
      streak: (j['streak'] as int?) ?? 0,
    );
  }
}

/// A PK battle as seen from one live ("me" = this live's side).
class Battle {
  Battle({
    required this.id,
    required this.status,
    required this.invitedByMe,
    required this.duration,
    required this.remaining,
    required this.me,
    required this.them,
    this.result,
    this.resultLeft = 0,
    this.streamUrl,
    this.streamToken,
    this.streamHost,
    this.raw = const {},
  });

  /// The server's answer as-is (the host passes it on to its viewers).
  final Map<String, dynamic> raw;
  final int id;
  final String status; // invited | active | ended
  final bool invitedByMe;
  final int duration, remaining;
  final BattleSide me, them;
  final String? result; // win | lose | draw

  /// Seconds the result stays up after the battle ended.
  final int resultLeft;
  final String? streamUrl, streamToken, streamHost;

  factory Battle.fromJson(Map<String, dynamic> j) {
    final s = j['opponent_stream'] as Map<String, dynamic>?;
    return Battle(
      id: j['id'] as int,
      status: j['status'] as String,
      invitedByMe: j['invited_by_me'] as bool,
      duration: j['duration'] as int,
      remaining: j['remaining'] as int,
      me: BattleSide.fromJson(j['me'] as Map<String, dynamic>),
      them: BattleSide.fromJson(j['them'] as Map<String, dynamic>),
      result: j['result'] as String?,
      resultLeft: (j['result_left'] as int?) ?? 0,
      streamUrl: s?['url'] as String?,
      streamToken: s?['token'] as String?,
      streamHost: s?['host_identity'] as String?,
      raw: j,
    );
  }
}

/// Creator analytics for the last [days] days.
class Analytics {
  Analytics(this.j);
  final Map<String, dynamic> j;

  int get days => j['days'] as int;
  int total(String key) => ((j['totals'] as Map)[key] as int?) ?? 0;
  int previous(String key) => ((j['previous'] as Map)[key] as int?) ?? 0;
  List<({DateTime day, int views, int followers})> get series => [
    for (final d in j['series'] as List)
      (
        day: DateTime.parse(d['day'] as String),
        views: d['views'] as int,
        followers: d['followers'] as int,
      ),
  ];
  List<Video> get topVideos => [
    for (final v in j['top_videos'] as List)
      Video.fromJson(v as Map<String, dynamic>),
  ];
  List<int> get topVideoViews => [
    for (final v in j['top_videos'] as List) (v['period_views'] as int?) ?? 0,
  ];
  int get followersTotal => j['followers_total'] as int;
  int get subscribers => j['subscribers'] as int;
  int get lives => j['lives'] as int;
}

/// A subscriber (for creators) or a creator I subscribe to.
class Subscription {
  Subscription({
    required this.user,
    required this.until,
    required this.since,
    required this.price,
  });
  final AppUser user;
  final DateTime until, since;
  final int price;

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
    user: AppUser.fromJson(j['user'] as Map<String, dynamic>),
    until: DateTime.parse(j['until'] as String).toLocal(),
    since: DateTime.parse(j['since'] as String).toLocal(),
    price: j['price'] as int,
  );
}

/// A device where this account is signed in.
class SessionInfo {
  SessionInfo({
    required this.id,
    required this.device,
    required this.place,
    required this.signedIn,
    this.lastActive,
    this.current = false,
  });
  final int id;
  final String device, place;
  final DateTime signedIn;
  final DateTime? lastActive;
  final bool current;

  factory SessionInfo.fromJson(Map<String, dynamic> j) => SessionInfo(
    id: j['id'] as int,
    device: (j['device'] as String?) ?? '',
    place: (j['place'] as String?) ?? '',
    signedIn: DateTime.parse(j['signed_in'] as String),
    lastActive: j['last_active'] == null
        ? null
        : DateTime.parse(j['last_active'] as String),
    current: (j['current'] as bool?) ?? false,
  );
}

/// Identity verification state (GET /verification).
class KycStatus {
  KycStatus.fromJson(Map<String, dynamic> j)
    : verified = j['verified'] == true,
      status = (j['status'] as String?) ?? 'none',
      reason = j['reason'] as String?,
      gestureIcon = (j['gesture']?['icon'] as String?) ?? '✌️',
      gestureText = (j['gesture']?['text'] as String?) ?? '',
      minAge = (j['min_age'] as int?) ?? 18;
  final bool verified;
  final String status;
  final String? reason;
  final String gestureIcon;
  final String gestureText;
  final int minAge;
}
