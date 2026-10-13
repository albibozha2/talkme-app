import 'package:flutter/widgets.dart';

/// Browsers can't show another site inside the app: the caller opens a new tab instead.
const bool inAppPaymentPages = false;

Future<void> openPaymentPage(
  BuildContext context, {
  required String url,
  required String title,
  required Future<bool> Function() isFinished,
}) async {}
