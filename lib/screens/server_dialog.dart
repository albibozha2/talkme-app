import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../state.dart';
import '../i18n.dart';

/// Lets the user point the app at a different server (PC on Wi-Fi, Cloudflare tunnel, …).
/// The address is checked before it is saved.
Future<void> showServerDialog(BuildContext context, WidgetRef ref) async {
  final api = ref.read(apiProvider);
  final saved = await showDialog<String>(
    context: context,
    builder: (context) =>
        _ServerDialog(initial: api.server.replaceAll(RegExp(r'/api$'), '')),
  );
  if (saved == null) return;
  await api.setServer(saved);
  ref.invalidate(remoteConfigProvider);
  ref.invalidate(sessionProvider);
}

class _ServerDialog extends StatefulWidget {
  const _ServerDialog({required this.initial});
  final String initial;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final _input = TextEditingController(text: widget.initial);
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final base = Api.normalizeServer(_input.text);
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final res = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      ).get<dynamic>('$base/config');
      if (res.data is! Map || (res.data as Map)['ok'] != true) {
        throw Exception(tr('not a TalkMe server'));
      }
      if (mounted) Navigator.pop(context, base);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr("Couldn't reach a TalkMe server at\n{0}", [base]),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Server address')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _input,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onSubmitted: (_) => _check(),
          decoration: const InputDecoration(
            hintText: 'https://xyz.trycloudflare.com',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            'Wi-Fi example: 192.168.100.12:8088\nChanging server signs you out.',
          ),
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 13,
            ),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Cancel')),
      ),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
        onPressed: _checking ? null : _check,
        child: Text(_checking ? tr('Checking…') : tr('Connect')),
      ),
    ],
  );
}
