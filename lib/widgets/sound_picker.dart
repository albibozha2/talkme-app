import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../audio_track.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';

String _mmss(double seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Square cover of a sound (or a music note).
class SoundCover extends StatelessWidget {
  const SoundCover({super.key, required this.sound, this.size = 52});
  final Sound sound;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size / 6),
    child: SizedBox(
      width: size,
      height: size,
      child: sound.coverUrl == null
          ? const DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.brandGradient),
              child: Icon(Icons.music_note_rounded, color: Colors.white),
            )
          : CachedNetworkImage(
              imageUrl: sound.coverUrl!,
              fit: BoxFit.cover,
              memCacheWidth: 160,
              errorWidget: (_, _, _) => const DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.brandGradient),
                child: Icon(Icons.music_note_rounded, color: Colors.white),
              ),
            ),
    ),
  );
}

/// TikTok's "Add sound" sheet. Returns the chosen sound (ready to use), or null.
Future<Sound?> pickSound(BuildContext context) => showModalBottomSheet<Sound>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) =>
      FractionallySizedBox(heightFactor: .9, child: const _SoundPicker()),
);

class _SoundPicker extends ConsumerStatefulWidget {
  const _SoundPicker();

  @override
  ConsumerState<_SoundPicker> createState() => _SoundPickerState();
}

class _SoundPickerState extends ConsumerState<_SoundPicker>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging) _load();
    });
  final _search = TextEditingController();
  Timer? _debounce;
  List<Sound>? _items;
  Object? _error;
  bool _library = true;
  int _run = 0;

  // Preview: one song at a time.
  AudioTrack? _preview;
  Sound? _playing;
  bool _choosing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _preview?.dispose();
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final run = ++_run;
    setState(() {
      _items = null;
      _error = null;
    });
    try {
      final r = await ref
          .read(apiProvider)
          .sounds(
            tab: _tabs.index == 0 ? 'talkme' : 'library',
            q: _search.text.trim(),
          );
      if (!mounted || run != _run) return;
      setState(() {
        _items = r.items;
        _library = r.library;
      });
    } catch (e) {
      if (mounted && run == _run) setState(() => _error = e);
    }
  }

  Future<void> _toggle(Sound s) async {
    final same = _playing == s;
    await _preview?.dispose();
    _preview = null;
    setState(() => _playing = same ? null : s);
    if (same || s.audioUrl == null) return;
    final c = AudioTrack(s.audioUrl!);
    _preview = c;
    try {
      await c.initialize();
      if (_preview != c) return;
      await c.play();
    } catch (_) {
      if (mounted && _preview == c) {
        setState(() => _playing = null);
        showToast(context, tr("This sound can't be played right now."));
      }
    }
  }

  Future<void> _use(Sound s) async {
    setState(() => _choosing = true);
    try {
      final picked = await ref.read(apiProvider).selectSound(s);
      if (mounted) Navigator.pop(context, picked);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _items;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: tr('Search songs or artists'),
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 450), _load);
            },
            onSubmitted: (_) => _load(),
          ),
        ),
        TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: tr('For you')),
            Tab(text: tr('Music library')),
          ],
        ),
        Expanded(
          child: items == null
              ? Center(
                  child: _error != null
                      ? Text('$_error')
                      : const CircularProgressIndicator(),
                )
              : items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      _tabs.index == 1 && !_library
                          ? tr('The music library is not connected yet.')
                          : tr('No sounds found.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final s = items[i];
                    final playing = _playing == s;
                    return ListTile(
                      onTap: () => _toggle(s),
                      leading: Stack(
                        alignment: Alignment.center,
                        children: [
                          SoundCover(sound: s),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Color(0x88000000),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      title: Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        [
                          if (s.artist.isNotEmpty) s.artist,
                          if (s.duration > 0) _mmss(s.duration),
                          if (s.uses > 0) tr('{0} videos', [s.uses]),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: playing
                          ? SizedBox(
                              width: 84,
                              height: 38,
                              child: FilledButton(
                                onPressed: _choosing ? null : () => _use(s),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.like,
                                  minimumSize: const Size(84, 38),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(tr('Use')),
                              ),
                            )
                          : null,
                    );
                  },
                ),
        ),
        if (_tabs.index == 1 && _library)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              tr(
                'Music library by Jamendo · Creative Commons, artists credited',
              ),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// The chosen sound on the posting screen: change/remove, start point and volumes.
class SoundSettingsCard extends StatelessWidget {
  const SoundSettingsCard({
    super.key,
    required this.use,
    required this.videoSeconds,
    required this.onChanged,
    required this.onChange,
    required this.onRemove,
    this.photo = false,
  });
  final SoundUse use;

  /// Length of the video (0 for a photo story).
  final double videoSeconds;
  final ValueChanged<SoundUse> onChanged;
  final VoidCallback onChange, onRemove;

  /// A photo story: there is no original sound to mix.
  final bool photo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final song = use.sound.duration;
    final maxStart = song > 0
        ? (song - (videoSeconds > 0 ? videoSeconds : 5)).clamp(0.0, song)
        : 0.0;
    SoundUse copy({double? start, int? volume, int? original}) => SoundUse(
      sound: use.sound,
      start: start ?? use.start,
      volume: volume ?? use.volume,
      originalVolume: original ?? use.originalVolume,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SoundCover(sound: use.sound, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      use.sound.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (use.sound.artist.isNotEmpty)
                      Text(
                        use.sound.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(onPressed: onChange, child: Text(tr('Change'))),
              IconButton(
                tooltip: tr('Remove'),
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (maxStart > 1) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr('Start the song at {0}', [_mmss(use.start)]),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Slider(
              value: use.start.clamp(0.0, maxStart).toDouble(),
              max: maxStart.toDouble(),
              onChanged: (v) => onChanged(copy(start: v)),
            ),
          ],
          _VolumeRow(
            icon: Icons.music_note_rounded,
            label: tr('Music'),
            value: use.volume,
            onChanged: (v) => onChanged(copy(volume: v)),
          ),
          if (!photo)
            _VolumeRow(
              icon: Icons.mic_none_rounded,
              label: tr('Original sound'),
              value: use.originalVolume,
              onChanged: (v) => onChanged(copy(original: v)),
            ),
        ],
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 6),
      SizedBox(
        width: 96,
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
      Expanded(
        child: Slider(
          value: value.toDouble(),
          max: 100,
          divisions: 20,
          label: '$value%',
          onChanged: (v) => onChanged(v.round()),
        ),
      ),
    ],
  );
}
