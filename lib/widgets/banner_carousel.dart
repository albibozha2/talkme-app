import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../models.dart';
import '../screens/discover_screen.dart';
import '../screens/live_screen.dart';
import '../screens/profile_screen.dart';
import '../theme.dart';

/// Promo banners managed in Admin → Banners. Slides automatically; hidden when there are none.
class BannerCarousel extends ConsumerStatefulWidget {
  const BannerCarousel({super.key, required this.items});
  final List<BannerItem> items;

  @override
  ConsumerState<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends ConsumerState<BannerCarousel> {
  final _page = PageController(viewportFraction: .92);
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.items.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_page.hasClients) return;
        final next = (_index + 1) % widget.items.length;
        _page.animateToPage(
          next,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  Future<void> _open(BannerItem b) async {
    ref.read(apiProvider).bannerClick(b.id).catchError((Object _) {});
    final nav = Navigator.of(context);
    switch (b.linkType) {
      case 'url':
        final uri = Uri.tryParse(b.linkValue);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      case 'user':
        await nav.push(
          MaterialPageRoute(
            builder: (_) => ProfileScreen(username: b.linkValue.toLowerCase()),
          ),
        );
      case 'hashtag':
        await nav.push(
          MaterialPageRoute(
            builder: (_) => HashtagScreen(tag: b.linkValue.toLowerCase()),
          ),
        );
      case 'live':
        await nav.push(
          MaterialPageRoute(builder: (_) => const LiveScreen(active: true)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final px =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return Column(
      children: [
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _page,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final b = items[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: GestureDetector(
                  onTap: () => _open(b),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (b.imageUrl != null)
                          CachedNetworkImage(
                            imageUrl: b.imageUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: px,
                          )
                        else
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.emeraldLight,
                                  AppColors.emeraldDeep,
                                  Color(0xFF2563EB),
                                ],
                              ),
                            ),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xB3000000), Colors.transparent],
                              stops: [0, .75],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                b.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                              if (b.subtitle.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  b.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < items.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: i == _index ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _index
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
