import '../filters.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'shimmer.dart';
import 'video_pager.dart';
import '../i18n.dart';

/// Paginated 3-column thumbnail grid as a sliver. Tapping opens the full-screen pager.
class VideoGrid extends StatefulWidget {
  const VideoGrid({super.key, required this.loader, this.emptyText});
  final PageLoader<Video> loader;

  /// Shown when there are no videos; defaults to "No videos yet".
  final String? emptyText;

  @override
  State<VideoGrid> createState() => _VideoGridState();
}

class _VideoGridState extends State<VideoGrid> {
  final _items = <Video>[];
  String? _cursor;
  bool _done = false, _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    try {
      final page = await widget.loader(_cursor);
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // First load: placeholder tiles instead of a spinner.
    if (_items.isEmpty && _loading && _error == null) {
      return SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 9 / 16,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: 9,
        itemBuilder: (_, _) => const Shimmer(),
      );
    }
    if (_items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error?.toString() ??
                            widget.emptyText ??
                            tr('No videos yet'),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      if (_error != null)
                        TextButton(
                          onPressed: _load,
                          child: Text(tr('Try again')),
                        ),
                    ],
                  ),
          ),
        ),
      );
    }
    final cell =
        (MediaQuery.sizeOf(context).width /
                3 *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 9 / 16,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _items.length,
      itemBuilder: (context, i) {
        if (i >= _items.length - 6) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _load());
        }
        final v = _items[i];
        return GestureDetector(
          onTap: () => openVideoPager(
            context,
            items: List.of(_items),
            index: i,
            loader: widget.loader,
            cursor: _cursor,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (v.thumbUrl != null)
                withFilter(
                  v.filter,
                  CachedNetworkImage(
                    imageUrl: v.thumbUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: cell,
                    fadeInDuration: const Duration(milliseconds: 180),
                    placeholder: (_, _) => const Shimmer(),
                    errorWidget: (_, _, _) => const _NoCover(),
                  ),
                )
              else
                const _NoCover(),
              // Darker bottom so the view count is readable on any picture.
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(0, .35),
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x99000000)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 6,
                bottom: 4,
                child: Row(
                  children: [
                    const Icon(
                      Icons.play_arrow_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    Text(
                      compactCount(v.views),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                      ),
                    ),
                  ],
                ),
              ),
              if (v.pinned)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.like,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tr('Pinned'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              if (v.status != 'published')
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      v.status,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Tile for a video without a cover picture yet.
class _NoCover extends StatelessWidget {
  const _NoCover();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF16302A), Color(0xFF0B1512)],
      ),
    ),
    child: Center(
      child: Icon(Icons.play_arrow_rounded, color: Colors.white54, size: 34),
    ),
  );
}
