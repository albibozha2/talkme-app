import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../models.dart';
import '../push.dart';
import '../theme.dart';
import '../compress.dart';
import '../thumbs.dart';
import '../widgets/common.dart';
import '../widgets/video_pager.dart';
import '../widgets/voice.dart';
import 'group_screens.dart';
import 'profile_screen.dart';
import '../i18n.dart';

const chatReactions = ['❤️', '😂', '😮', '😢', '😡', '👍', '🔥', '👏'];

/// A chat (one-to-one or group). New messages are fetched every few seconds while open.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversation});
  final Conversation conversation;

  /// Opens (or creates) the chat with [username].
  static Future<void> openWith(
    BuildContext context,
    WidgetRef ref,
    String username,
  ) async {
    try {
      final c = await ref.read(apiProvider).openConversation(username);
      if (context.mounted) {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)));
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _items = <ChatMessage>[]; // newest first
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late Conversation _conv = widget.conversation;
  String? _cursor;
  bool _loading = true,
      _loadingOlder = false,
      _sending = false,
      _foreground = true,
      _recording = false;
  int _otherLastRead = 0;
  ChatMessage? _replyTo;

  /// Upload progress of a photo, video or voice message (0..1); null when nothing uploads.
  double? _progress;

  /// Names of people writing right now, and when I last told the server I'm typing.
  List<String> _typing = const [];
  DateTime _typingSent = DateTime(2000);
  Timer? _poll;
  Object? _error;

  Api get _api => ref.read(apiProvider);
  int get _id => _conv.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    openChatId = widget.conversation.id;
    _input.addListener(() {
      setState(() {});
      // Let the others see "typing…" (one ping every 3 seconds at most).
      if (_input.text.trim().isNotEmpty &&
          DateTime.now().difference(_typingSent) > const Duration(seconds: 3)) {
        _typingSent = DateTime.now();
        _activity();
        _api.sendTyping(_id).catchError((Object _) {});
      }
    });
    _loadInitial();
    _schedulePoll();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300) _loadOlder();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _foreground = state == AppLifecycleState.resumed;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (openChatId == widget.conversation.id) openChatId = null;
    _poll?.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final r = await _api.messages(_id);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(r.items);
        _cursor = r.nextCursor;
        _otherLastRead = r.otherLastRead;
        _loading = false;
      });
      _markRead();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || _cursor == null) return;
    _loadingOlder = true;
    try {
      final r = await _api.messages(_id, cursor: _cursor);
      if (mounted) {
        setState(() {
          _items.addAll(r.items);
          _cursor = r.nextCursor;
        });
      }
    } catch (_) {
    } finally {
      _loadingOlder = false;
    }
  }

  /// Last time something happened in this chat (a message, someone typing, me writing).
  DateTime _activeAt = DateTime.now();

  /// Checks for new messages every 3 s while the chat is active, then slows to 6 s
  /// and 10 s when it goes quiet (much less work for the server with many open chats).
  void _schedulePoll() {
    final idle = DateTime.now().difference(_activeAt);
    final every = idle < const Duration(seconds: 30)
        ? 3
        : idle < const Duration(minutes: 2)
        ? 6
        : 10;
    _poll?.cancel();
    _poll = Timer(Duration(seconds: every), () async {
      if (_foreground) await _pollNew();
      if (mounted) _schedulePoll();
    });
  }

  void _activity() {
    final wasIdle =
        DateTime.now().difference(_activeAt) > const Duration(seconds: 30);
    _activeAt = DateTime.now();
    if (wasIdle) _schedulePoll();
  }

  Future<void> _pollNew() async {
    if (_loading) return;
    try {
      final r = await _api.messages(
        _id,
        after: _items.isEmpty ? 0 : _items.first.id,
      );
      if (!mounted) return;
      final known = _items.map((m) => m.id).toSet();
      final fresh = r.items.where((m) => !known.contains(m.id)).toList();
      setState(() {
        _items.insertAll(0, fresh);
        _otherLastRead = r.otherLastRead;
        _typing = r.typing;
      });
      if (fresh.any((m) => !m.mine)) _markRead();
      if (fresh.isNotEmpty || r.typing.isNotEmpty) _activity();
    } catch (_) {}
  }

  void _markRead() {
    _api
        .readConversation(_id)
        .then((_) => ref.read(unreadProvider.notifier).refresh())
        .catchError((Object _) {});
  }

  void _added(ChatMessage m) {
    _activity();
    setState(() {
      _items.insert(0, m);
      _replyTo = null;
      if (_conv.status == 'request') _conv.status = 'active';
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final m = await _api.sendMessage(_id, text, replyTo: _replyTo?.id);
      _input.clear();
      if (mounted) _added(m);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendPhoto() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(tr('Take a photo')),
              onTap: () => Navigator.pop(context, 'photo_camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('Choose a photo')),
              onTap: () => Navigator.pop(context, 'photo_gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(tr('Record a video')),
              onTap: () => Navigator.pop(context, 'video_camera'),
            ),
            ListTile(
              leading: const Icon(Icons.movie_outlined),
              title: Text(tr('Choose a video')),
              onTap: () => Navigator.pop(context, 'video_gallery'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final source = choice.endsWith('camera')
        ? ImageSource.camera
        : ImageSource.gallery;
    final XFile? f;
    try {
      f = choice.startsWith('video')
          ? await ImagePicker().pickVideo(
              source: source,
              maxDuration: const Duration(minutes: 3),
            )
          : await ImagePicker().pickImage(
              source: source,
              maxWidth: 1600,
              imageQuality: 85,
            );
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (f == null || !mounted) return;
    if (choice.startsWith('video')) {
      if (await f.length() > 80 * 1024 * 1024) {
        if (mounted) {
          showError(
            context,
            tr('That video is too long. Send one under 80 MB.'),
          );
        }
        return;
      }
      setState(() {
        _sending = true;
        _progress = 0;
      });
      final thumb = await makeThumbnail(f.path);
      // Smaller (720p) before sending; the bar shows the preparing progress first.
      final small = await compressForUpload(
        f.path,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p * .3);
        },
      );
      await _upload(
        () => _api.sendMedia(
          _id,
          small,
          clip: true,
          thumbPath: thumb,
          replyTo: _replyTo?.id,
          // Preparing was the first 30%.
          onProgress: (v) => _onProgress(.3 + v * .7),
        ),
      );
    } else {
      setState(() {
        _sending = true;
        _progress = 0;
      });
      await _upload(
        () => _api.sendMedia(
          _id,
          f!.path,
          replyTo: _replyTo?.id,
          onProgress: _onProgress,
        ),
      );
    }
  }

  void _onProgress(double v) {
    if (mounted) setState(() => _progress = v);
  }

  /// Runs one media upload with the progress bar showing.
  Future<void> _upload(Future<ChatMessage> Function() send) async {
    setState(() {
      _sending = true;
      _progress ??= 0;
    });
    try {
      final m = await send();
      if (mounted) _added(m);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _sendVoice(String path, double seconds) async {
    setState(() {
      _recording = false;
      _progress = 0;
    });
    await _upload(
      () => _api.sendMedia(
        _id,
        path,
        voice: true,
        duration: seconds,
        replyTo: _replyTo?.id,
        onProgress: _onProgress,
      ),
    );
  }

  Future<void> _openVideo(int id) async {
    try {
      final v = await _api.video(id);
      if (!mounted) return;
      await openVideoPager(
        context,
        items: [v],
        index: 0,
        loader: (_) async => PageResult([v], null),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _react(ChatMessage m, String emoji) async {
    HapticFeedback.selectionClick();
    try {
      final r = await _api.react(m.id, emoji);
      if (mounted) setState(() => m.reactions = r);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _messageMenu(ChatMessage m) async {
    if (m.type == 'system' || m.deleted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in chatReactions)
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.pop(context, 'react:$e'),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text(tr('Reply')),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            if (m.body.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(tr('Copy')),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
            if (m.mine)
              ListTile(
                leading: const Icon(Icons.undo_rounded, color: AppColors.like),
                title: Text(tr('Unsend')),
                onTap: () => Navigator.pop(context, 'unsend'),
              )
            else
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(tr('Report message')),
                onTap: () => Navigator.pop(context, 'report'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.startsWith('react:')) {
      await _react(m, choice.substring(6));
    } else if (choice == 'reply') {
      setState(() => _replyTo = m);
      _focus.requestFocus();
    } else if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.body));
      if (mounted) showToast(context, tr('Copied'));
    } else if (choice == 'unsend') {
      try {
        await _api.unsendMessage(m.id);
        if (mounted) {
          setState(() {
            m.deleted = true;
            m.body = '';
          });
        }
      } catch (e) {
        if (mounted) showError(context, e);
      }
    } else if (choice == 'report') {
      await showReportDialog(context, ref, 'message', m.id);
    }
  }

  Future<void> _accept() async {
    try {
      await _api.acceptRequest(_id);
      if (mounted) setState(() => _conv.status = 'active');
      ref.read(unreadProvider.notifier).refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _decline() async {
    try {
      await _api.declineRequest(_id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _openInfo() async {
    if (_conv.isGroup) {
      final left = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => GroupInfoScreen(conversationId: _id)),
      );
      if (left == true && mounted) {
        Navigator.pop(context);
      } else {
        try {
          final c = await _api.conversationDetails(_id);
          if (mounted) setState(() => _conv = c);
        } catch (_) {}
        _pollNew();
      }
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(username: _conv.user.username),
        ),
      );
    }
  }

  Widget _header(ColorScheme scheme) {
    final c = _conv;
    return InkWell(
      onTap: _openInfo,
      child: Row(
        children: [
          ChatAvatar(conversation: c, radius: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        c.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    if (!c.isGroup && c.user.verified)
                      const VerifiedBadge(size: 14),
                  ],
                ),
                Text(
                  _typing.isNotEmpty
                      ? (c.isGroup
                            ? tr('{0} is typing…', [_typing.first])
                            : tr('typing…'))
                      : c.isGroup
                      ? tr('{0} members', [c.memberCount])
                      : '@${c.user.username}',
                  style: TextStyle(
                    fontSize: 12,
                    color: _typing.isNotEmpty
                        ? AppColors.emerald
                        : scheme.onSurfaceVariant,
                    fontWeight: _typing.isNotEmpty
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lastMine = _items
        .where((m) => m.mine && m.type != 'system')
        .firstOrNull;
    final request = _conv.status == 'request';
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: _header(scheme),
        actions: [
          if (_conv.isGroup)
            IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: _openInfo,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ChatAvatar(conversation: _conv, radius: 40),
                          const SizedBox(height: 14),
                          Text(
                            _error != null
                                ? '$_error'
                                : tr('Say hi to {0} 👋', [_conv.name]),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final m = _items[i];
                      final older = i + 1 < _items.length
                          ? _items[i + 1]
                          : null;
                      final showTime =
                          older == null ||
                          m.createdAt.difference(older.createdAt).inMinutes >
                              15;
                      final seen =
                          !_conv.isGroup &&
                          lastMine != null &&
                          m.id == lastMine.id &&
                          _otherLastRead >= m.id;
                      // In groups, show the name above the first of a run of messages from someone else.
                      final showName =
                          _conv.isGroup &&
                          !m.mine &&
                          m.type != 'system' &&
                          (older == null ||
                              older.sender?.id != m.sender?.id ||
                              older.type == 'system' ||
                              showTime);
                      return Column(
                        children: [
                          if (showTime)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                timeAgo(m.createdAt),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.outline,
                                ),
                              ),
                            ),
                          if (m.type == 'system')
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 24,
                              ),
                              child: Text(
                                m.body,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          else
                            _SwipeToReply(
                              onReply: m.deleted
                                  ? null
                                  : () {
                                      setState(() => _replyTo = m);
                                      _focus.requestFocus();
                                    },
                              child: _Bubble(
                                message: m,
                                group: _conv.isGroup,
                                showName: showName,
                                onVideo: _openVideo,
                                onLongPress: () => _messageMenu(m),
                                onReact: (e) => _react(m, e),
                              ),
                            ),
                          if (seen)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  right: 6,
                                  bottom: 4,
                                ),
                                child: Text(
                                  tr('Seen'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.outline,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          if (request)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              color: scheme.surfaceContainerHigh,
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Text(
                      tr(
                        '{0} wants to send you a message. Accept to reply; they won’t know you saw it until you do.',
                        [_conv.name],
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _decline,
                            child: Text(tr('Delete')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _accept,
                            child: Text(tr('Accept')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyTo != null)
                      Container(
                        margin: const EdgeInsets.only(left: 8, bottom: 6),
                        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: const Border(
                            left: BorderSide(
                              color: AppColors.emerald,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${tr('Replying to {0}', [_replyTo!.mine ? tr('yourself') : (_replyTo!.sender?.displayName ?? _conv.name)])}\n${_previewOf(_replyTo!)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => setState(() => _replyTo = null),
                            ),
                          ],
                        ),
                      ),
                    if (_progress != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: _progress! > 0 && _progress! < 1
                                      ? _progress
                                      : null,
                                  minHeight: 4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _progress! >= 1
                                  ? tr('Finishing…')
                                  : tr('Sending… {0}%', [
                                      (_progress! * 100).round(),
                                    ]),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    if (_recording)
                      VoiceRecorderBar(
                        onDone: _sendVoice,
                        onCancel: () => setState(() => _recording = false),
                      )
                    else
                      Row(
                        children: [
                          IconButton(
                            tooltip: tr('Photo or video'),
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            onPressed: _sending ? null : _sendPhoto,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _input,
                              focusNode: _focus,
                              maxLength: 2000,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: tr('Message…'),
                                counterText: '',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: BorderSide(color: scheme.primary),
                                ),
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: AppColors.brandGradient,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              tooltip: _input.text.trim().isEmpty
                                  ? tr('Voice message')
                                  : tr('Send'),
                              onPressed: _sending
                                  ? null
                                  : (_input.text.trim().isEmpty
                                        ? () =>
                                              setState(() => _recording = true)
                                        : _send),
                              icon: _sending
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      _input.text.trim().isEmpty
                                          ? Icons.mic_rounded
                                          : Icons.send_rounded,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ],
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

String _previewOf(ChatMessage m) => switch (m.type) {
  'image' => tr('📷 Photo'),
  'voice' => tr('🎤 Voice message'),
  'clip' => tr('🎬 Video'),
  'video' => m.body.isNotEmpty ? m.body : tr('Shared a video'),
  _ => m.body,
};

/// Group avatar (up to two overlapping photos) or the other person's photo.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.conversation, this.radius = 26});
  final Conversation conversation;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    if (!c.isGroup) {
      return Avatar(
        url: c.user.avatarUrl,
        name: c.user.displayName,
        radius: radius,
        live: c.user.liveId != null,
      );
    }
    final p = c.preview;
    if (p.length < 2) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.emerald.withValues(alpha: .2),
        child: Icon(
          Icons.groups_rounded,
          color: AppColors.emerald,
          size: radius,
        ),
      );
    }
    final small = radius * .72;
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: Avatar(
              url: p[0].avatarUrl,
              name: p[0].displayName,
              radius: small,
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                shape: BoxShape.circle,
              ),
              child: Avatar(
                url: p[1].avatarUrl,
                name: p[1].displayName,
                radius: small,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.group,
    required this.showName,
    required this.onVideo,
    required this.onLongPress,
    required this.onReact,
  });
  final ChatMessage message;
  final bool group, showName;
  final void Function(int id) onVideo;
  final VoidCallback onLongPress;
  final void Function(String emoji) onReact;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final scheme = Theme.of(context).colorScheme;
    final fg = m.mine ? Colors.white : scheme.onSurface;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(m.mine ? 20 : 6),
      bottomRight: Radius.circular(m.mine ? 6 : 20),
    );
    Widget content;
    if (m.deleted) {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Text(
          tr('Message deleted'),
          style: TextStyle(
            color: fg.withValues(alpha: .7),
            fontStyle: FontStyle.italic,
            fontSize: 14,
          ),
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.replyId != null)
            Container(
              margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              decoration: BoxDecoration(
                color: (m.mine ? Colors.white : scheme.onSurface).withValues(
                  alpha: .12,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${m.replyName ?? ''}\n${m.replyBody ?? ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg.withValues(alpha: .85),
                  fontSize: 12.5,
                ),
              ),
            ),
          if (m.type == 'image' && m.mediaUrl != null)
            Padding(
              padding: const EdgeInsets.all(4),
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _PhotoView(url: m.mediaUrl!),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 280,
                      minWidth: 120,
                    ),
                    child: CachedNetworkImage(
                      imageUrl: m.mediaUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 600,
                    ),
                  ),
                ),
              ),
            ),
          if (m.type == 'clip' && m.mediaUrl != null)
            Padding(
              padding: const EdgeInsets.all(4),
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _ClipView(url: m.mediaUrl!),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 180,
                    height: 240,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (m.thumbUrl != null)
                          CachedNetworkImage(
                            imageUrl: m.thumbUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 360,
                          )
                        else
                          const ColoredBox(color: Colors.black87),
                        const Center(
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.black45,
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                        ),
                        if ((m.duration ?? 0) > 0)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Text(
                              '${m.duration! ~/ 60}:${(m.duration!.round() % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                shadows: [Shadow(blurRadius: 6)],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (m.type == 'voice' && m.mediaUrl != null)
            VoicePlayer(
              url: m.mediaUrl!,
              seconds: m.duration ?? 0,
              light: m.mine,
            ),
          if (m.videoId != null)
            Padding(
              padding: const EdgeInsets.all(5),
              child: GestureDetector(
                onTap: () => onVideo(m.videoId!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 150,
                    height: 230,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (m.videoThumb != null)
                          CachedNetworkImage(
                            imageUrl: m.videoThumb!,
                            fit: BoxFit.cover,
                            memCacheWidth: 300,
                          )
                        else
                          ColoredBox(color: scheme.surfaceContainerHighest),
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 44,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (m.body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Text(
                m.body,
                style: TextStyle(color: fg, fontSize: 15, height: 1.35),
              ),
            ),
        ],
      );
    }
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (group && !m.mine)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 4),
              child: showName && m.sender != null
                  ? Avatar(
                      url: m.sender!.avatarUrl,
                      name: m.sender!.displayName,
                      radius: 13,
                    )
                  : const SizedBox(width: 26),
            ),
          Column(
            crossAxisAlignment: m.mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showName && m.sender != null)
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 6, bottom: 2),
                  child: Text(
                    m.sender!.displayName,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              GestureDetector(
                onLongPress: onLongPress,
                onDoubleTap: m.deleted ? null : () => onReact('❤️'),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .72,
                  ),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      gradient: m.mine && !m.deleted
                          ? AppColors.brandGradient
                          : null,
                      color: m.mine && !m.deleted
                          ? null
                          : scheme.surfaceContainerHigh,
                      borderRadius: radius,
                    ),
                    child: content,
                  ),
                ),
              ),
              if (m.reactions.isNotEmpty)
                Transform.translate(
                  offset: const Offset(0, -6),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      for (final r in m.reactions)
                        GestureDetector(
                          onTap: () => onReact(r.emoji),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: r.mine
                                  ? AppColors.emerald.withValues(alpha: .2)
                                  : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: scheme.surface,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              r.count > 1 ? '${r.emoji} ${r.count}' : r.emoji,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoView extends StatelessWidget {
  const _PhotoView({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: InteractiveViewer(
        maxScale: 5,
        child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
      ),
    ),
  );
}

/// Plays a video clip from a chat, full screen. Tap to pause, drag the bar to seek.
class _ClipView extends StatefulWidget {
  const _ClipView({required this.url});
  final String url;

  @override
  State<_ClipView> createState() => _ClipViewState();
}

class _ClipViewState extends State<_ClipView> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(
    Uri.parse(widget.url),
  );
  Object? _error;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _c.initialize().then((_) => _c.play()).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _error != null
          ? Center(
              child: Text(
                tr("Couldn't play this video."),
                style: const TextStyle(color: Colors.white70),
              ),
            )
          : !v.isInitialized
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : GestureDetector(
              onTap: () => v.isPlaying ? _c.pause() : _c.play(),
              child: Stack(
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: v.aspectRatio,
                      child: VideoPlayer(_c),
                    ),
                  ),
                  if (!v.isPlaying)
                    const Center(
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white70,
                        size: 72,
                      ),
                    ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 24,
                    child: SafeArea(
                      child: VideoProgressIndicator(
                        _c,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Picks a recent chat and sends [video] to it. Used from the video ⋯ menu.
Future<void> showSendVideoSheet(
  BuildContext context,
  WidgetRef ref,
  Video video,
) async {
  final api = ref.read(apiProvider);
  final convos = await api.conversations().catchError(
    (Object _) => <Conversation>[],
  );
  if (!context.mounted) return;
  if (convos.isEmpty) {
    showToast(
      context,
      tr('Start a chat from someone\'s profile first (Message button).'),
    );
    return;
  }
  final target = await showModalBottomSheet<Conversation>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('Send to'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in convos)
                  ListTile(
                    leading: ChatAvatar(conversation: c, radius: 20),
                    title: Text(c.name),
                    subtitle: Text(
                      c.isGroup
                          ? tr('{0} members', [c.memberCount])
                          : '@${c.user.username}',
                    ),
                    trailing: const Icon(Icons.send_rounded),
                    onTap: () => Navigator.pop(context, c),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  if (target == null) return;
  try {
    await api.sendMessage(target.id, '', videoId: video.id);
    if (context.mounted) showToast(context, tr('Sent to {0}', [target.name]));
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Drag a message to the right to reply to it (like TikTok, WhatsApp, Instagram).
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, required this.onReply});
  final Widget child;
  final VoidCallback? onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  double _dx = 0;
  bool _fired = false;
  static const _trigger = 64.0;

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        final next = (_dx + d.delta.dx).clamp(0.0, 90.0);
        if (!_fired && next >= _trigger) {
          _fired = true;
          HapticFeedback.selectionClick();
        }
        setState(() => _dx = next);
      },
      onHorizontalDragEnd: (_) {
        if (_fired) widget.onReply!();
        setState(() {
          _dx = 0;
          _fired = false;
        });
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Opacity(
            opacity: (_dx / _trigger).clamp(0.0, 1.0),
            child: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Icon(Icons.reply_rounded, size: 22),
            ),
          ),
          AnimatedContainer(
            duration: Duration(milliseconds: _dx == 0 ? 180 : 0),
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
