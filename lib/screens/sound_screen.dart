import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../audio_track.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/sound_picker.dart';
import '../widgets/video_grid.dart';
import 'upload_screen.dart';

/// A sound's page (TikTok style): the song, how many videos use it, "Use this sound", and the videos.
class SoundScreen extends ConsumerStatefulWidget {
  const SoundScreen({super.key, required this.soundId});
  final int soundId;

  @override
  ConsumerState<SoundScreen> createState() => _SoundScreenState();
}

class _SoundScreenState extends ConsumerState<SoundScreen> {
  Sound? _sound;
  Object? _error;
  AudioTrack? _preview;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(apiProvider)
        .soundPage(widget.soundId)
        .then((r) {
          if (mounted) setState(() => _sound = r.sound);
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = e);
        });
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _togglePreview() async {
    final s = _sound;
    if (s?.audioUrl == null) return;
    if (_preview == null) {
      final c = AudioTrack(s!.audioUrl!);
      _preview = c;
      try {
        await c.initialize();
      } catch (_) {
        return;
      }
    }
    final c = _preview!;
    c.isPlaying ? await c.pause() : await c.play();
    if (mounted) setState(() => _playing = c.isPlaying);
  }

  @override
  Widget build(BuildContext context) {
    final s = _sound;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Sound'))),
      floatingActionButton: s == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.like,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.videocam_rounded),
              label: Text(tr('Use this sound')),
              onPressed: () async {
                await _preview?.pause();
                if (mounted) setState(() => _playing = false);
                if (!context.mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => UploadScreen(sound: s)),
                );
              },
            ),
      body: s == null
          ? Center(
              child: _error != null
                  ? Text('$_error')
                  : const CircularProgressIndicator(),
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _togglePreview,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SoundCover(sound: s, size: 104),
                              Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: Color(0x88000000),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.title,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              if (s.artist.isNotEmpty)
                                Text(
                                  s.artist,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 15,
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Text(
                                tr('{0} videos', [s.uses]),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (s.source == 'jamendo')
                                Text(
                                  tr('From Jamendo · Creative Commons'),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                VideoGrid(
                  loader: (cursor) async =>
                      (await ref
                              .read(apiProvider)
                              .soundPage(widget.soundId, cursor))
                          .videos,
                  emptyText: tr('Be the first to use this sound.'),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 90)),
              ],
            ),
    );
  }
}
