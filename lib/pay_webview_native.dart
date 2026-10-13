import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'i18n.dart';

/// Phones show the payment page inside the app.
const bool inAppPaymentPages = true;

/// Shows the provider's payment page (POK / PayPal) in a sheet inside the app. It closes by itself
/// when the provider sends the person back to our site (payment finished or cancelled), or when
/// [isFinished] says the payment went through; the caller then checks the result.
Future<void> openPaymentPage(
  BuildContext context, {
  required String url,
  required String title,
  required Future<bool> Function() isFinished,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) =>
        _PaymentPage(url: url, title: title, isFinished: isFinished),
  ),
);

class _PaymentPage extends StatefulWidget {
  const _PaymentPage({
    required this.url,
    required this.title,
    required this.isFinished,
  });
  final String url, title;
  final Future<bool> Function() isFinished;

  @override
  State<_PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<_PaymentPage> {
  late final WebViewController _web;
  int _progress = 0;
  bool _closed = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onNavigationRequest: (r) {
            final u = Uri.tryParse(r.url);
            // Back on our site: the provider is done; the app checks the result.
            if (u != null && u.path.endsWith('/pay.php')) {
              _close();
              return NavigationDecision.prevent;
            }
            // Bank / POK app links (pok://, intent://…) open outside the web page.
            if (u != null && u.scheme != 'http' && u.scheme != 'https') {
              launchUrl(
                u,
                mode: LaunchMode.externalApplication,
              ).catchError((Object _) => false);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
    // The payment can also be confirmed by the provider in the background.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (await widget.isFinished()) _close();
    });
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    _poll?.cancel();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: _close,
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_rounded, size: 16, color: Color(0xFF16A34A)),
          const SizedBox(width: 6),
          Flexible(child: Text(widget.title, overflow: TextOverflow.ellipsis)),
        ],
      ),
      bottom: _progress < 100
          ? PreferredSize(
              preferredSize: const Size.fromHeight(2),
              child: LinearProgressIndicator(
                value: _progress / 100,
                minHeight: 2,
              ),
            )
          : null,
    ),
    body: SafeArea(top: false, child: WebViewWidget(controller: _web)),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Text(
          tr(
            'Secure payment. Your card details go only to the payment provider.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ),
  );
}
