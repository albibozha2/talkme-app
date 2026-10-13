import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'config.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'i18n.dart';

import 'package:flutter/foundation.dart';

/// A version uploaded in Admin → App release.
class AppRelease {
  AppRelease(Map<String, dynamic> j)
    : version = j['version'] as String,
      notes = (j['notes'] as String?) ?? '',
      size = (j['size'] as num?)?.toInt() ?? 0,
      sha256 = (j['sha256'] as String?) ?? '',
      url = j['url'] as String,
      minVersion = (j['min_version'] as String?) ?? '1.0.0';
  final String version, notes, sha256, url, minVersion;
  final int size;

  bool get isNewer => isVersionTooOld(AppConfig.appVersion, version);
  bool get isRequired => isVersionTooOld(AppConfig.appVersion, minVersion);
  String get sizeText => '${(size / 1048576).toStringAsFixed(1)} MB';
}

/// The newest release on the server, or null when there is none / it isn't newer than this app.
final updateProvider = FutureProvider<AppRelease?>((ref) async {
  if (kIsWeb || !Platform.isAndroid) return null;
  final data = await ref.watch(apiProvider).get('/app/version');
  final latest = data['latest'];
  if (latest is! Map<String, dynamic>) return null;
  final release = AppRelease(latest);
  return release.isNewer ? release : null;
});

const _channel = MethodChannel('reelll/update');

/// Shows the update sheet once per version, a few seconds after the app opens.
Future<void> offerUpdateOnce(BuildContext context, WidgetRef ref) async {
  await Future<void>.delayed(const Duration(seconds: 3));
  final AppRelease? release;
  try {
    release = await ref.read(updateProvider.future);
  } catch (_) {
    return;
  }
  if (release == null || !context.mounted) return;
  final marker = File(
    '${(await getApplicationSupportDirectory()).path}/update_offered',
  );
  final seen = await marker.exists() ? await marker.readAsString() : '';
  if (seen == release.version || !context.mounted) return;
  await marker.writeAsString(release.version);
  if (context.mounted) await showUpdateSheet(context, release);
}

/// Checks now and tells the user the result (menu → Check for updates).
Future<void> checkForUpdates(BuildContext context, WidgetRef ref) async {
  ref.invalidate(updateProvider);
  try {
    final release = await ref.read(updateProvider.future);
    if (!context.mounted) return;
    if (release == null) {
      showToast(
        context,
        tr("You're up to date (version {0}).", [AppConfig.appVersion]),
      );
    } else {
      await showUpdateSheet(context, release);
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

Future<void> showUpdateSheet(BuildContext context, AppRelease release) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: !release.isRequired,
      enableDrag: !release.isRequired,
      builder: (_) => _UpdateSheet(release: release),
    );

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet({required this.release});
  final AppRelease release;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet>
    with WidgetsBindingObserver {
  double? _progress;
  String? _status;
  File? _file;
  bool _waitingForPermission = false;
  final _cancel = CancelToken();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel.cancel();
    super.dispose();
  }

  // Back from "Install unknown apps" settings: carry on with the install.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForPermission) {
      _waitingForPermission = false;
      _install(back: true);
    }
  }

  Future<void> _update() async {
    final r = widget.release;
    setState(() {
      _progress = 0;
      _status = tr('Downloading…');
    });
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final file = File('${dir.path}/reelll-${r.version}.apk');
      await Dio().download(
        r.url,
        file.path,
        cancelToken: _cancel,
        onReceiveProgress: (got, total) {
          final all = total > 0 ? total : r.size;
          if (mounted && all > 0) setState(() => _progress = got / all);
        },
      );
      if (!mounted) return;
      setState(() => _status = tr('Checking the download…'));
      if (r.sha256.isNotEmpty) {
        final digest = await sha256.bind(file.openRead()).first;
        if (digest.toString() != r.sha256) {
          await file.delete();
          throw Exception(tr('The download was damaged. Please try again.'));
        }
      }
      _file = file;
      await _install();
    } catch (e) {
      if (!mounted || _cancel.isCancelled) return;
      setState(() {
        _progress = null;
        _status = e is DioException
            ? tr('Download failed. Check your connection and try again.')
            : '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  /// [back]: called on return from the permission screen. If the switch is still off, stop there
  /// (opening the screen again straight away kept the user in an endless loop).
  Future<void> _install({bool back = false}) async {
    final file = _file;
    if (file == null) return;
    final String? result;
    try {
      result = await _channel.invokeMethod<String>('install', {
        'path': file.path,
      });
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _file = null;
          _progress = null;
          _status =
              e.message ??
              tr('Download failed. Check your connection and try again.');
        });
      }
      return;
    }
    if (!mounted) return;
    if (result == 'need_permission' && back) {
      setState(
        () => _status = tr(
          'Turn on "Allow from this source" for TalkMe, then tap Install. Or install it from talkme.space in your browser.',
        ),
      );
    } else if (result == 'need_permission') {
      setState(() {
        _waitingForPermission = true;
        _status = tr('Allow this app to install updates, then come back.');
      });
      await _channel.invokeMethod<void>('openInstallSettings');
    } else {
      setState(() {
        _progress = 1;
        _status = tr('Tap Install on the next screen to finish.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.release;
    final theme = Theme.of(context);
    final busy = _progress != null && _progress! < 1 && _file == null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.isRequired
                            ? tr('Update required')
                            : tr('Update available'),
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        tr('Version {0} · {1} · you have {2}', [
                          r.version,
                          r.sizeText,
                          AppConfig.appVersion,
                        ]),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (r.notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(tr("What's new"), style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(r.notes),
            ],
            const SizedBox(height: 20),
            if (_progress != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: _progress, minHeight: 8),
              ),
              const SizedBox(height: 8),
            ],
            if (_status != null) ...[
              Text(
                busy && _progress! > 0
                    ? '$_status ${(_progress! * 100).round()}%'
                    : _status!,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                label: _file != null ? tr('Install') : tr('Update now'),
                icon: Icons.download_rounded,
                busy: busy,
                onPressed: busy ? null : (_file != null ? _install : _update),
              ),
            ),
            if (!r.isRequired)
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('Later')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
