import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../filters.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import 'upload_screen.dart';

/// Records a duet like TikTok: your camera on the left, the original playing on the right.
/// Recording starts after a 3-second countdown and stops when the original ends
/// (or when you tap stop); then the normal post screen opens with the duet attached.
class DuetScreen extends StatefulWidget {
  const DuetScreen({super.key, required this.original});
  final Video original;

  @override
  State<DuetScreen> createState() => _DuetScreenState();
}

class _DuetScreenState extends State<DuetScreen> {
  late final VideoPlayerController _orig = VideoPlayerController.networkUrl(
    Uri.parse(widget.original.videoUrl),
    videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
  );
  CameraController? _cam;
  List<CameraDescription> _cameras = const [];
  int _camIndex = 0;
  Object? _error;
  int? _countdown;
  bool _recording = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    try {
      await _orig.initialize();
      _orig.addListener(_onOriginal);
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception(tr('No camera found on this phone.'));
      }
      final front = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      _camIndex = front < 0 ? 0 : front;
      await _openCamera();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _openCamera() async {
    final old = _cam;
    setState(() => _cam = null);
    await old?.dispose();
    final c = CameraController(
      _cameras[_camIndex],
      ResolutionPreset.high,
      enableAudio: true,
    );
    await c.initialize();
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() => _cam = c);
  }

  void _onOriginal() {
    final v = _orig.value;
    if (_recording && v.duration > Duration.zero && v.position >= v.duration) {
      _stop();
    }
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final cam = _cam;
    if (cam == null || _recording || _countdown != null) return;
    await _orig.pause();
    await _orig.seekTo(Duration.zero);
    for (var i = 3; i > 0; i--) {
      if (!mounted) return;
      setState(() => _countdown = i);
      HapticFeedback.selectionClick();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    setState(() => _countdown = null);
    try {
      await cam.startVideoRecording();
      await _orig.play();
      setState(() => _recording = true);
      // Safety stop in case the end of the original is missed.
      _tick = Timer(_orig.value.duration + const Duration(seconds: 1), _stop);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _stop() async {
    final cam = _cam;
    if (cam == null || !_recording) return;
    _tick?.cancel();
    setState(() => _recording = false);
    await _orig.pause();
    try {
      final file = await cam.stopVideoRecording();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              UploadScreen(videoPath: file.path, duetOf: widget.original),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _orig.removeListener(_onOriginal);
    _orig.dispose();
    _cam?.dispose();
    super.dispose();
  }

  Widget _cover(Widget child, Size size) => ClipRect(
    child: SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final o = _orig.value;
    final progress = o.duration.inMilliseconds > 0
        ? o.position.inMilliseconds / o.duration.inMilliseconds
        : 0.0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: darkSystemUi,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            tr('Duet with @{0}', [
                              widget.original.user.username,
                            ]),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_cameras.length > 1 && !_recording)
                          IconButton(
                            tooltip: tr('Flip camera'),
                            onPressed: () {
                              _camIndex = (_camIndex + 1) % _cameras.length;
                              _openCamera();
                            },
                            icon: const Icon(
                              Icons.flip_camera_android_rounded,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                    // Progress of the original (how much of the duet is recorded).
                    LinearProgressIndicator(
                      value: progress.clamp(0, 1).toDouble(),
                      minHeight: 3,
                      color: AppColors.live,
                      backgroundColor: Colors.white12,
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: cam == null || !cam.value.isInitialized
                                    ? const Center(
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                        ),
                                      )
                                    : _cover(
                                        CameraPreview(cam),
                                        Size(
                                          cam.value.previewSize?.height ?? 9,
                                          cam.value.previewSize?.width ?? 16,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                child: o.isInitialized
                                    ? _cover(
                                        withFilter(
                                          widget.original.filter,
                                          VideoPlayer(_orig),
                                        ),
                                        o.size,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                          if (_countdown != null)
                            Center(
                              child: Text(
                                '$_countdown',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 96,
                                  fontWeight: FontWeight.w900,
                                  shadows: [Shadow(blurRadius: 20)],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: GestureDetector(
                        onTap: _recording ? _stop : _start,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 5),
                          ),
                          padding: EdgeInsets.all(_recording ? 22 : 5),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.live,
                              borderRadius: BorderRadius.circular(
                                _recording ? 6 : 40,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      _recording
                          ? tr('Recording… tap to finish')
                          : tr('Tap to record. It stops when the video ends.'),
                      style: const TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
        ),
      ),
    );
  }
}
