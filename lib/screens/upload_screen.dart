import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../i18n.dart';
import '../widgets/common.dart';
import '../widgets/overlays.dart';

import 'package:flutter/foundation.dart';

import '../compress.dart';
import '../filters.dart';
import '../thumbs.dart';
import '../sound_sync.dart';
import '../widgets/sound_picker.dart';

/// A video saved on the phone to finish later.
class Draft {
  Draft(this.dir, this.data);
  final Directory dir;
  final Map<String, dynamic> data;

  String get videoPath => '${dir.path}/video.mp4';
  DateTime get savedAt => DateTime.parse(data['saved_at'] as String);

  static Future<Directory> _root() async =>
      Directory('${(await getApplicationDocumentsDirectory()).path}/drafts');

  static Future<List<Draft>> all() async {
    final root = await _root();
    if (!await root.exists()) return [];
    final out = <Draft>[];
    await for (final d in root.list()) {
      final meta = File('${d.path}/draft.json');
      if (d is Directory && await meta.exists()) {
        try {
          out.add(
            Draft(
              d,
              jsonDecode(await meta.readAsString()) as Map<String, dynamic>,
            ),
          );
        } catch (_) {}
      }
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  /// Saves (or updates) a draft. The video is copied so it survives the gallery file being deleted.
  static Future<Draft> save({
    Draft? existing,
    required String videoPath,
    required Map<String, dynamic> data,
  }) async {
    final dir =
        existing?.dir ??
        Directory(
          '${(await _root()).path}/${DateTime.now().millisecondsSinceEpoch}',
        );
    await dir.create(recursive: true);
    final target = '${dir.path}/video.mp4';
    if (videoPath != target) await File(videoPath).copy(target);
    final all = {...data, 'saved_at': DateTime.now().toIso8601String()};
    await File('${dir.path}/draft.json').writeAsString(jsonEncode(all));
    return Draft(dir, all);
  }

  Future<void> delete() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

const _stickers = [
  '😂',
  '😍',
  '🔥',
  '❤️',
  '👏',
  '😎',
  '🥳',
  '😮',
  '😭',
  '🤔',
  '💯',
  '✨',
  '🎉',
  '👀',
  '🙌',
  '💪',
  '🌹',
  '⭐',
  '🇦🇱',
  '⚽',
  '🎵',
  '🍕',
  '☕',
  '😴',
  '🤣',
  '😇',
  '🥰',
  '😡',
  '👍',
  '👎',
  '🙏',
  '💔',
  '💸',
  '🎁',
  '🏆',
  '📍',
];

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key, this.sound, this.videoPath, this.duetOf});

  /// Start with this sound already added ("Use this sound").
  final Sound? sound;

  /// Start with this video (e.g. a duet just recorded).
  final String? videoPath;

  /// The original video, when posting a duet.
  final Video? duetOf;

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  final _caption = TextEditingController();
  VideoPlayerController? _preview;
  String? _path;
  Draft? _draft;
  bool _allowComments = true;
  bool _allowDuet = true;
  String _visibility = 'public';

  /// Colour filter id (filters.dart) and speed, saved with the video and applied when it plays.
  String _filter = 'none';
  double _speed = 1;
  final _overlays = <VideoOverlay>[];
  double? _progress;

  /// True while the video is being made smaller before the upload starts.
  bool _preparing = false;
  CancelToken? _cancel;
  int _draftCount = 0;

  /// Added music, and its player following the preview.
  SoundUse? _sound;
  SoundSync? _sync;

  @override
  void initState() {
    super.initState();
    _countDrafts();
    if (widget.sound != null) _sound = SoundUse(sound: widget.sound!);
    final start = widget.videoPath;
    if (start != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final maxSec =
            ref.read(remoteConfigProvider).value?.maxDurationSec ?? 180;
        _open(start, maxSec + 60);
      });
    }
  }

  @override
  void dispose() {
    _sync?.dispose();
    _cancel?.cancel();
    _preview?.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _countDrafts() async {
    if (kIsWeb) return;
    final n = (await Draft.all()).length;
    if (mounted) setState(() => _draftCount = n);
  }

  Future<void> _pick(ImageSource source) async {
    final cfg = ref.read(remoteConfigProvider).value;
    final maxSec = cfg?.maxDurationSec ?? 180;
    final file = await ImagePicker().pickVideo(
      source: source,
      maxDuration: Duration(seconds: maxSec),
    );
    if (file == null) return;
    final sizeMb = await file.length() / (1024 * 1024);
    final maxMb = cfg?.maxUploadMb ?? 100;
    if (sizeMb > maxMb) {
      if (mounted) {
        showError(
          context,
          tr('That video is {0} MB. The limit is {1} MB.', [
            sizeMb.toStringAsFixed(0),
            maxMb,
          ]),
        );
      }
      return;
    }
    if (await _open(file.path, maxSec)) _draft = null;
  }

  /// Loads a video into the preview. False if it can't be played or is too long.
  Future<bool> _open(String path, int maxSec) async {
    final c = kIsWeb
        ? VideoPlayerController.networkUrl(Uri.parse(path))
        : VideoPlayerController.file(File(path));
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      if (mounted) {
        showError(context, tr("This video can't be played. Try another one."));
      }
      return false;
    }
    if (c.value.duration.inMilliseconds > (maxSec + 1) * 1000) {
      await c.dispose();
      if (mounted) {
        showError(
          context,
          tr('Videos can be up to {0} seconds long.', [maxSec]),
        );
      }
      return false;
    }
    await c.setLooping(true);
    await c.play();
    _sync?.dispose();
    _sync = null;
    await _preview?.dispose();
    if (!mounted) return false;
    c.setPlaybackSpeed(_speed);
    setState(() {
      _path = path;
      _preview = c;
    });
    _startSound();
    return true;
  }

  /// Plays the added music with the preview.
  void _startSound() {
    _sync?.dispose();
    _sync = null;
    final use = _sound, c = _preview;
    if (c == null) return;
    if (use == null) {
      c.setVolume(1);
      return;
    }
    _sync = SoundSync(use: use, video: c, muted: () => false)..start();
  }

  Future<void> _chooseSound() async {
    final s = await pickSound(context);
    if (s == null || !mounted) return;
    setState(() => _sound = SoundUse(sound: s, originalVolume: 30));
    _startSound();
  }

  Map<String, dynamic> _draftData() => {
    'caption': _caption.text,
    'allow_comments': _allowComments,
    'allow_duet': _allowDuet,
    'filter': _filter,
    'speed': _speed,
    'visibility': _visibility,
    'overlays': _overlays.map((o) => o.toJson()).toList(),
  };

  Future<void> _saveDraft() async {
    final path = _path;
    if (path == null) return;
    await _preview?.pause();
    try {
      _draft = await Draft.save(
        existing: _draft,
        videoPath: path,
        data: _draftData(),
      );
      if (!mounted) return;
      showToast(context, tr('Saved to drafts'));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _openDrafts() async {
    final drafts = await Draft.all();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<Draft>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .7,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 8),
                  child: Text(
                    tr('Drafts'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (drafts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(tr('No drafts yet.')),
                  ),
                for (final d in drafts)
                  ListTile(
                    leading: const Icon(Icons.movie_outlined),
                    title: Text(
                      (d.data['caption'] as String?)?.trim().isNotEmpty == true
                          ? d.data['caption'] as String
                          : tr('Untitled draft'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(timeAgo(d.savedAt)),
                    onTap: () => Navigator.pop(context, d),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: tr('Delete'),
                      onPressed: () async {
                        await d.delete();
                        setSheet(() => drafts.remove(d));
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await _countDrafts();
    if (chosen == null || !mounted) return;
    final maxSec = ref.read(remoteConfigProvider).value?.maxDurationSec ?? 180;
    if (!await _open(chosen.videoPath, maxSec + 60)) return;
    setState(() {
      _draft = chosen;
      _caption.text = (chosen.data['caption'] as String?) ?? '';
      _allowComments = (chosen.data['allow_comments'] as bool?) ?? true;
      _allowDuet = (chosen.data['allow_duet'] as bool?) ?? true;
      _filter = (chosen.data['filter'] as String?) ?? 'none';
      _speed = (chosen.data['speed'] as num?)?.toDouble() ?? 1;
      _preview?.setPlaybackSpeed(_speed);
      _visibility = (chosen.data['visibility'] as String?) ?? 'public';
      _overlays
        ..clear()
        ..addAll(
          ((chosen.data['overlays'] as List?) ?? const []).map(
            (e) => VideoOverlay.fromJson(e as Map<String, dynamic>),
          ),
        );
    });
  }

  Future<void> _upload() async {
    final path = _path, c = _preview;
    if (path == null || c == null) return;
    await c.pause();
    _cancel = CancelToken();
    setState(() {
      _progress = 0;
      _preparing = true;
    });
    try {
      // A cover picture from the first frame (the server can't make one).
      final thumb = await makeThumbnail(path);
      // Smaller file (720p): uploads faster and plays smoothly for viewers.
      final upload = await compressForUpload(
        path,
        onProgress: (p) {
          if (mounted && _preparing) setState(() => _progress = p);
        },
      );
      if (_cancel?.isCancelled ?? false) {
        if (mounted) {
          setState(() {
            _progress = null;
            _preparing = false;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _preparing = false;
          _progress = 0;
        });
      }
      final v = await ref
          .read(apiProvider)
          .upload(
            path: upload,
            thumbPath: thumb,
            caption: _caption.text.trim(),
            duration: c.value.duration.inMilliseconds / 1000,
            width: c.value.size.width.round(),
            height: c.value.size.height.round(),
            allowComments: _allowComments,
            allowDuet: _allowDuet,
            filter: _filter,
            speed: _speed,
            duetOf: widget.duetOf?.id,
            visibility: _visibility,
            overlays: _overlays,
            sound: _sound,
            cancel: _cancel,
            onProgress: (sent, total) {
              if (mounted && total > 0) {
                setState(() => _progress = sent / total);
              }
            },
          );
      await _draft?.delete();
      ref.read(myVideosVersionProvider.notifier).bump();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (v.status) {
            'published' => tr('Your video is live!'),
            'pending' => tr('Uploaded — it will appear after review.'),
            _ => tr('Uploaded — processing, it will be live shortly.'),
          }),
        ),
      );
      Navigator.pop(context);
    } on DioException {
      if (mounted) setState(() => _progress = null);
    } catch (e) {
      if (mounted) {
        setState(() => _progress = null);
        showError(context, e);
      }
    }
  }

  // ---------- texts & stickers ----------

  Future<void> _editText([VideoOverlay? existing]) async {
    final o = existing ?? VideoOverlay(text: '', y: .35, size: 1.2);
    final result = await showModalBottomSheet<VideoOverlay>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TextEditor(overlay: o),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.text.trim().isEmpty) {
        _overlays.remove(o);
      } else if (existing == null) {
        if (_overlays.length < 10) _overlays.add(result);
      }
    });
  }

  Future<void> _addSticker() async {
    final s = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            for (final e in _stickers)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(context, e),
                child: Center(
                  child: Text(e, style: const TextStyle(fontSize: 32)),
                ),
              ),
          ],
        ),
      ),
    );
    if (s == null || !mounted || _overlays.length >= 10) return;
    setState(
      () => _overlays.add(VideoOverlay(text: s, style: 'sticker', y: .3)),
    );
  }

  /// 9:16-ish frame shaped like this phone's screen, so texts land where they'll appear in the feed.
  Widget _editor(VideoPlayerController c) {
    final screen = MediaQuery.sizeOf(context);
    final ratio = (screen.width / screen.height).clamp(.4, .75);
    final portrait = c.value.aspectRatio < 1;
    final fit = portrait && (ratio - c.value.aspectRatio).abs() < .25
        ? BoxFit.cover
        : BoxFit.contain;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: AspectRatio(
          aspectRatio: ratio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.black,
                    child: GestureDetector(
                      onTap: () => c.value.isPlaying ? c.pause() : c.play(),
                      child: FittedBox(
                        fit: fit,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: c.value.size.width,
                          height: c.value.size.height,
                          child: withFilter(_filter, VideoPlayer(c)),
                        ),
                      ),
                    ),
                  ),
                  if (_speed != 1)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: _Badge(text: speedLabel(_speed)),
                    ),
                  for (final o in _overlays)
                    Align(
                      alignment: Alignment(o.x * 2 - 1, o.y * 2 - 1),
                      child: GestureDetector(
                        onPanUpdate: (d) => setState(() {
                          o.x = (o.x + d.delta.dx / box.maxWidth).clamp(0, 1);
                          o.y = (o.y + d.delta.dy / box.maxHeight).clamp(0, 1);
                        }),
                        onTap: o.style == 'sticker' ? null : () => _editText(o),
                        onLongPress: () => setState(() => _overlays.remove(o)),
                        child: OverlayLabel(
                          overlay: o,
                          areaWidth: box.maxWidth,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _preview;
    final uploading = _progress != null;
    return PopScope(
      canPop: !uploading,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.duetOf != null
                ? tr('Duet with @{0}', [widget.duetOf!.user.username])
                : tr('New video'),
          ),
          actions: [
            if (c == null && _draftCount > 0)
              TextButton.icon(
                onPressed: _openDrafts,
                icon: const Icon(Icons.drafts_outlined),
                label: Text(tr('Drafts ({0})', [_draftCount])),
              ),
          ],
        ),
        body: c == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.movie_creation_outlined,
                        size: 72,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.videocam_outlined),
                        label: Text(tr('Record')),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(tr('Choose from gallery')),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _editor(c),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Tool(
                        icon: Icons.music_note_rounded,
                        label: tr('Sound'),
                        onTap: uploading ? null : _chooseSound,
                      ),
                      _Tool(
                        icon: Icons.text_fields_rounded,
                        label: tr('Text'),
                        onTap: uploading ? null : () => _editText(),
                      ),
                      _Tool(
                        icon: Icons.emoji_emotions_outlined,
                        label: tr('Sticker'),
                        onTap: uploading ? null : _addSticker,
                      ),
                      _Tool(
                        icon: Icons.swap_horiz,
                        label: tr('Change'),
                        onTap: uploading
                            ? null
                            : () => _pick(ImageSource.gallery),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Filters: each chip previews its look on a sample, the video shows it live.
                  SizedBox(
                    height: 86,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final f in videoFilters)
                          _FilterChip(
                            filter: f,
                            selected: _filter == f.id,
                            onTap: uploading
                                ? null
                                : () => setState(() => _filter = f.id),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.speed_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        tr('Speed'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      for (final sp in videoSpeeds)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ChoiceChip(
                            label: Text(speedLabel(sp)),
                            selected: _speed == sp,
                            visualDensity: VisualDensity.compact,
                            onSelected: uploading
                                ? null
                                : (_) {
                                    setState(() => _speed = sp);
                                    c.setPlaybackSpeed(sp);
                                  },
                          ),
                        ),
                    ],
                  ),
                  if (_sound != null) ...[
                    const SizedBox(height: 8),
                    SoundSettingsCard(
                      use: _sound!,
                      videoSeconds: c.value.duration.inMilliseconds / 1000,
                      onChanged: (u) {
                        setState(() => _sound = u);
                        _sync?.update(u);
                      },
                      onChange: _chooseSound,
                      onRemove: () {
                        setState(() => _sound = null);
                        _startSound();
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_overlays.isNotEmpty)
                    Text(
                      tr('Drag to move · tap text to edit · hold to remove'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _caption,
                    maxLength: 500,
                    maxLines: 4,
                    minLines: 2,
                    enabled: !uploading,
                    decoration: InputDecoration(
                      hintText: tr(
                        'Describe your video… add #hashtags and @mentions',
                      ),
                    ),
                  ),
                  Text(
                    tr('Who can watch'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: [
                      for (final (value, _, icon) in visibilityOptions(
                        subscribers:
                            ref.read(sessionProvider).value?.subPrice != null,
                      ))
                        ButtonSegment(
                          value: value,
                          icon:
                              ref.read(sessionProvider).value?.subPrice != null
                              ? null
                              : Icon(icon, size: 18),
                          label: Text(visibilityLabel(value)),
                        ),
                    ],
                    selected: {_visibility},
                    showSelectedIcon: false,
                    onSelectionChanged: uploading
                        ? null
                        : (s) => setState(() => _visibility = s.first),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Allow comments')),
                    value: _allowComments,
                    onChanged: uploading
                        ? null
                        : (v) => setState(() => _allowComments = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Allow Duet')),
                    subtitle: Text(
                      tr('Others can post a video side by side with yours'),
                    ),
                    value: _allowDuet,
                    onChanged: uploading
                        ? null
                        : (v) => setState(() => _allowDuet = v),
                  ),
                  const SizedBox(height: 8),
                  if (uploading) ...[
                    LinearProgressIndicator(
                      value: _progress,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          _preparing
                              ? tr('Preparing video… {0}%', [
                                  (_progress! * 100).round(),
                                ])
                              : tr('Uploading {0}%', [
                                  (_progress! * 100).round(),
                                ]),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            _cancel?.cancel();
                            if (_preparing) cancelCompression();
                          },
                          child: Text(tr('Cancel')),
                        ),
                      ],
                    ),
                  ] else
                    Row(
                      children: [
                        if (!kIsWeb)
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                              ),
                              onPressed: _saveDraft,
                              icon: const Icon(Icons.drafts_outlined),
                              label: Text(tr('Save draft')),
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                            ),
                            onPressed: _upload,
                            child: Text(tr('Post')),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
  );
}

/// One filter in the strip: a little sample picture with the filter on it.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.filter,
    required this.selected,
    required this.onTap,
  });
  final VideoFilter filter;
  final bool selected;
  final VoidCallback? onTap;

  static const _sample = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF6EC6FF),
      Color(0xFFFFC6A8),
      Color(0xFFFF8A65),
      Color(0xFF66BB6A),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 58,
              height: 58,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? scheme.primary : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: withFilter(
                  filter.id,
                  const DecoratedBox(
                    decoration: BoxDecoration(gradient: _sample),
                    child: Center(
                      child: Icon(Icons.face_rounded, color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              filter.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: TextButton(
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}

/// Type a text, pick a colour, style and size.
class _TextEditor extends StatefulWidget {
  const _TextEditor({required this.overlay});
  final VideoOverlay overlay;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final _text = TextEditingController(text: widget.overlay.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.overlay;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 110,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(14),
            ),
            child: LayoutBuilder(
              builder: (context, box) => OverlayLabel(
                overlay: VideoOverlay(
                  text: _text.text.isEmpty ? tr('Your text') : _text.text,
                  size: o.size,
                  color: o.color,
                  style: o.style,
                ),
                areaWidth: 300,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: 120,
            decoration: InputDecoration(
              hintText: tr('Type something…'),
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in overlayColors)
                  GestureDetector(
                    onTap: () => setState(() => o.color = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: o.color == c
                              ? AppColors.emeraldLight
                              : Colors.white24,
                          width: o.color == c ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'plain', label: Text(tr('Outline'))),
                  ButtonSegment(value: 'box', label: Text(tr('Box'))),
                ],
                selected: {o.style},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => o.style = s.first),
              ),
              Expanded(
                child: Slider(
                  value: o.size,
                  min: .6,
                  max: 2.5,
                  onChanged: (x) => setState(() => o.size = x),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GradientButton(
            label: tr('Done'),
            onPressed: () {
              o.text = _text.text.trim();
              Navigator.pop(context, o);
            },
          ),
        ],
      ),
    );
  }
}
