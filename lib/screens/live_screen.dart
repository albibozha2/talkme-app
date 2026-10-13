import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'live_room_screen.dart';
import '../i18n.dart';
import '../widgets/live_rankings.dart';
import 'live_extras.dart';

/// "Live" tab: who's streaming now, plus a Go Live call to action.
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key, required this.active});
  final bool active;

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  List<LiveInfo>? _items;
  bool _enabled = true;
  Object? _error;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 20), (_) {
      if (widget.active) _load();
    });
  }

  @override
  void didUpdateWidget(LiveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiProvider).lives();
      if (mounted) {
        setState(() {
          _items = r.items;
          _enabled = r.enabled;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  final _events = GlobalKey<LiveEventsListState>();

  Future<void> _open(LiveInfo l) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LiveRoomScreen.viewer(liveId: l.id)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [LiveBadge(), SizedBox(width: 8), Text(tr('Live now'))],
        ),
        actions: [
          IconButton(
            tooltip: tr('LIVE rankings'),
            icon: const Icon(
              Icons.emoji_events_rounded,
              color: AppColors.amber,
            ),
            onPressed: () => showLiveRankings(context),
          ),
          IconButton(
            tooltip: tr('Schedule a live'),
            icon: const Icon(Icons.event_rounded),
            onPressed: () async {
              if (await scheduleLiveDialog(context, ref)) {
                _events.currentState?.reload();
                if (context.mounted) showToast(context, tr('Live scheduled'));
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: _GoLiveCard(enabled: _enabled, onDone: _load),
              ),
            ),
            SliverToBoxAdapter(child: LiveEventsList(key: _events)),
            if (items == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: _error != null
                      ? Text('$_error')
                      : const CircularProgressIndicator(),
                ),
              )
            else if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.podcasts_rounded,
                        size: 56,
                        color: scheme.primary.withValues(alpha: .6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr('Nobody is live right now'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr('Be the first — tap Go Live above.'),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: .66,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) =>
                      _LiveCard(live: items[i], onTap: () => _open(items[i])),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GoLiveCard extends StatelessWidget {
  const _GoLiveCard({required this.enabled, required this.onDone});
  final bool enabled;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFFF5F6D), Color(0xFFFF2E63), Color(0xFFB0306A)],
      ),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: AppColors.live.withValues(alpha: .3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () async {
          if (!enabled) {
            showToast(
              context,
              tr('Live streaming is not available right now.'),
            );
            return;
          }
          await Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const GoLiveScreen()));
          onDone();
        },
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white24,
                child: Icon(
                  Icons.videocam_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Go Live'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      tr('Stream to your followers and receive gifts'),
                      style: TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.live, required this.onTap});
  final LiveInfo live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: Material(
      color: AppColors.inkHigh,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (live.host.avatarUrl != null)
              CachedNetworkImage(
                imageUrl: live.host.avatarUrl!,
                fit: BoxFit.cover,
                color: Colors.black38,
                colorBlendMode: BlendMode.darken,
              )
            else
              const DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.brandGradient),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                  stops: [.45, 1],
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  const LiveBadge(small: true),
                  if (live.inBattle) ...[
                    const SizedBox(width: 5),
                    // In a PK battle right now (TikTok marks these too).
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF2E63), Color(0xFF3B82F6)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'PK',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.remove_red_eye_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          compactCount(live.viewers),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (live.host.avatarUrl == null)
              Center(
                child: Avatar(
                  url: null,
                  name: live.host.displayName,
                  radius: 34,
                  live: true,
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (live.title.isNotEmpty)
                    Text(
                      live.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Avatar(
                        url: live.host.avatarUrl,
                        name: live.host.displayName,
                        radius: 11,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          live.host.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Camera preview + title, then start the live.
class GoLiveScreen extends ConsumerStatefulWidget {
  const GoLiveScreen({super.key});

  @override
  ConsumerState<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends ConsumerState<GoLiveScreen> {
  final _title = TextEditingController();
  LocalVideoTrack? _preview;
  bool _starting = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _startPreview();
  }

  Future<void> _startPreview() async {
    try {
      final t = await LocalVideoTrack.createCameraTrack(
        const CameraCaptureOptions(params: VideoParametersPresets.h720_169),
      );
      if (!mounted) {
        await t.stop();
        return;
      }
      setState(() => _preview = t);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _preview?.stop();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() => _starting = true);
    try {
      final session = await ref.read(apiProvider).startLive(_title.text.trim());
      // Release the preview camera before the room opens its own.
      await _preview?.stop();
      _preview = null;
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LiveRoomScreen.host(session: session),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _starting = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: darkSystemUi,
      child: Theme(
        data: buildTheme(Brightness.dark),
        child: Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            systemOverlayStyle: darkSystemUi,
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (preview != null)
                VideoTrackRenderer(preview, fit: VideoViewFit.cover)
              else
                Center(
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            kIsWeb && Uri.base.scheme != 'https'
                                ? tr(
                                    'Browsers only allow the camera on secure (https) websites. Go live from the Android app for now.',
                                  )
                                : tr(
                                    'Camera unavailable. Allow camera and microphone access in Settings.\n\n{0}',
                                    [_error],
                                  ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        )
                      : const CircularProgressIndicator(),
                ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xDD000000)],
                      stops: [.5, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _title,
                          maxLength: 120,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: tr('Add a title for your live…'),
                            counterText: '',
                            fillColor: Colors.white.withValues(alpha: .14),
                            prefixIcon: const Icon(
                              Icons.edit_rounded,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        GradientButton(
                          label: tr('Go Live'),
                          icon: Icons.podcasts_rounded,
                          busy: _starting,
                          gradient: AppColors.liveGradient,
                          onPressed: preview == null ? null : _go,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
