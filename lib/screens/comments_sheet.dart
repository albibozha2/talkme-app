import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../i18n.dart';
import 'profile_screen.dart';
import '../features.dart';

Future<void> showCommentsSheet(BuildContext context, Video video) async {
  if (!Features.on('comments')) {
    showToast(context, tr('Comments are turned off right now.'));
    return;
  }
  await _showCommentsSheet(context, video);
}

Future<void> _showCommentsSheet(BuildContext context, Video video) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .72,
        child: _CommentsSheet(video: video),
      ),
    );

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.video});
  final Video video;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

/// Replies loaded under one comment.
class _Thread {
  final items = <Comment>[];
  String? cursor;
  bool open = false, loading = false, done = false;
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final _items = <Comment>[];
  final _threads = <int, _Thread>{};
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  String? _cursor;
  bool _done = false, _loading = false, _sending = false;
  Object? _error;

  /// The comment being replied to (top-level), and who is being answered.
  Comment? _replyTo;
  String? _replyName;

  Video get v => widget.video;
  bool get _iAmCreator => ref.read(sessionProvider).value?.id == v.user.id;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300) _load();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    try {
      final page = await ref.read(apiProvider).comments(v.id, _cursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadReplies(Comment c) async {
    final t = _threads.putIfAbsent(c.id, _Thread.new);
    if (t.loading || t.done) {
      setState(() => t.open = true);
      return;
    }
    setState(() {
      t.open = true;
      t.loading = true;
    });
    try {
      final page = await ref.read(apiProvider).replies(c.id, t.cursor);
      if (!mounted) return;
      setState(() {
        // Replies I just wrote may already be shown.
        t.items.addAll(
          page.items.where((r) => t.items.every((x) => x.id != r.id)),
        );
        t.cursor = page.nextCursor;
        t.done = page.nextCursor == null;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => t.loading = false);
    }
  }

  void _startReply(Comment c) {
    setState(() {
      _replyTo = c.parentId == null
          ? c
          : _items.firstWhere((x) => x.id == c.parentId, orElse: () => c);
      _replyName = c.user.username;
    });
    _input.text = c.parentId == null ? '' : '@${c.user.username} ';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _focus.requestFocus();
  }

  void _cancelReply() => setState(() {
    _replyTo = null;
    _replyName = null;
  });

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final api = ref.read(apiProvider);
    try {
      final parent = _replyTo;
      if (parent != null) {
        final r = await api.reply(v.id, parent.id, text);
        final t = _threads.putIfAbsent(parent.id, _Thread.new);
        setState(() {
          t.items.add(r);
          t.open = true;
          parent.replies++;
          v.comments++;
        });
        _cancelReply();
      } else {
        final c = await api.addComment(v.id, text);
        setState(() {
          // Below a pinned comment, if there is one.
          final at = _items.isNotEmpty && _items.first.pinned ? 1 : 0;
          _items.insert(at, c);
          v.comments++;
        });
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
      _input.clear();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleLike(Comment c) async {
    HapticFeedback.selectionClick();
    final on = !c.liked;
    setState(() {
      c.liked = on;
      c.likes += on ? 1 : -1;
    });
    try {
      final n = await ref.read(apiProvider).setCommentLike(c.id, on);
      if (mounted) setState(() => c.likes = n);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        c.liked = !on;
        c.likes += on ? -1 : 1;
      });
      showError(context, e);
    }
  }

  Future<void> _longPress(Comment c) async {
    final me = ref.read(sessionProvider).value;
    final canDelete = me != null && (me.id == c.user.id || _iAmCreator);
    final canPin = _iAmCreator && c.parentId == null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text(tr('Reply')),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(tr('Copy')),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            if (canPin)
              ListTile(
                leading: Icon(
                  c.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                ),
                title: Text(c.pinned ? tr('Unpin') : tr('Pin comment')),
                onTap: () => Navigator.pop(context, 'pin'),
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(tr('Delete comment')),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            if (me?.id != c.user.id)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(tr('Report comment')),
                onTap: () => Navigator.pop(context, 'report'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'reply':
        _startReply(c);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: c.body));
        if (mounted) showToast(context, tr('Copied'));
      case 'pin':
        await _togglePin(c);
      case 'delete':
        await _delete(c);
      case 'report':
        await showReportDialog(context, ref, 'comment', c.id);
    }
  }

  Future<void> _togglePin(Comment c) async {
    final on = !c.pinned;
    try {
      await ref.read(apiProvider).setCommentPinned(c.id, on);
      if (!mounted) return;
      setState(() {
        for (final x in _items) {
          x.pinned = false;
        }
        c.pinned = on;
        v.pinnedCommentId = on ? c.id : null;
        if (on) {
          _items
            ..remove(c)
            ..insert(0, c);
        }
      });
      showToast(context, on ? tr('Comment pinned') : tr('Comment unpinned'));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Comment c) async {
    try {
      await ref.read(apiProvider).deleteComment(c.id);
      if (!mounted) return;
      setState(() {
        if (c.parentId == null) {
          _items.remove(c);
          v.comments -= 1 + c.replies;
          _threads.remove(c.id);
        } else {
          _threads[c.parentId]?.items.remove(c);
          for (final p in _items) {
            if (p.id == c.parentId) p.replies--;
          }
          v.comments--;
        }
        if (v.comments < 0) v.comments = 0;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _openProfile(String username) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => ProfileScreen(username: username)));

  Widget _comment(Comment c, {bool reply = false}) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onLongPress: () => _longPress(c),
      child: Padding(
        padding: EdgeInsets.fromLTRB(reply ? 60 : 16, 8, 8, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _openProfile(c.user.username),
              child: Avatar(
                url: c.user.avatarUrl,
                name: c.user.displayName,
                radius: reply ? 13 : 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c.pinned)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.push_pin_rounded,
                            size: 12,
                            color: scheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            tr('Pinned by creator'),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.user.username,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (c.user.verified) const VerifiedBadge(size: 12),
                      if (c.subscriber && !c.byCreator) ...[
                        const SizedBox(width: 5),
                        Tooltip(
                          message: tr('Subscriber'),
                          child: const Icon(
                            Icons.workspace_premium_rounded,
                            size: 14,
                            color: AppColors.amber,
                          ),
                        ),
                      ],
                      if (c.byCreator) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.like.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tr('Creator'),
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.like,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  MentionText(
                    text: c.body,
                    style: TextStyle(fontSize: 15, color: scheme.onSurface),
                    onMention: _openProfile,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        timeAgo(c.createdAt),
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => _startReply(c),
                        child: Text(
                          tr('Reply'),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Like
            InkResponse(
              onTap: () => _toggleLike(c),
              radius: 22,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  children: [
                    Icon(
                      c.liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 18,
                      color: c.liked ? AppColors.like : scheme.outline,
                    ),
                    if (c.likes > 0)
                      Text(
                        compactCount(c.likes),
                        style: TextStyle(fontSize: 11, color: scheme.outline),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "View 3 replies" / "Hide" under a top-level comment.
  Widget _repliesToggle(Comment c, _Thread? t) {
    final scheme = Theme.of(context).colorScheme;
    final shown = t?.items.length ?? 0;
    final open = t?.open ?? false;
    final more = c.replies - (open ? shown : 0);
    if (c.replies == 0 && shown == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 60, bottom: 4),
      child: Row(
        children: [
          Container(width: 22, height: 1, color: scheme.outlineVariant),
          const SizedBox(width: 8),
          if (t?.loading ?? false)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (!open || (more > 0 && !(t?.done ?? false)))
            GestureDetector(
              onTap: () => _loadReplies(c),
              child: Text(
                open
                    ? tr('View more replies')
                    : (c.replies == 1
                          ? tr('View 1 reply')
                          : tr('View {0} replies', [c.replies])),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            GestureDetector(
              onTap: () => setState(() => t!.open = false),
              child: Text(
                tr('Hide'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          plural(v.comments, 'comment'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : Text(
                          _error?.toString() ??
                              (v.allowComments
                                  ? tr('Be the first to comment.')
                                  : tr(
                                      'Comments are turned off for this video.',
                                    )),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                )
              : ListView.builder(
                  controller: _scroll,
                  itemCount: _items.length + (_done ? 0 : 1),
                  itemBuilder: (context, i) {
                    if (i == _items.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final c = _items[i];
                    final t = _threads[c.id];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _comment(c),
                        if (t != null && t.open)
                          for (final r in t.items) _comment(r, reply: true),
                        _repliesToggle(c, t),
                      ],
                    );
                  },
                ),
        ),
        if (v.allowComments)
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                4,
                12,
                8 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyName != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('Replying to {0}', ['@$_replyName']),
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: _cancelReply,
                        ),
                      ],
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          focusNode: _focus,
                          maxLength: 1000,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: _replyName != null
                                ? tr('Add a reply…')
                                : tr('Add a comment… use @ to mention'),
                            counterText: '',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.arrow_upward),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
