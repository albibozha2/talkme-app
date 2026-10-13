import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'i18n.dart';
import 'payments.dart';
import 'theme.dart';

/// A coin payment through POK (card / POK app) or PayPal.
class PokPayment {
  PokPayment(Map<String, dynamic> j)
    : id = j['id'] as int,
      provider = (j['provider'] as String?) ?? 'pok',
      coins = j['coins'] as int,
      amount = (j['amount'] as num).toDouble(),
      currency = j['currency'] as String,
      status = j['status'] as String,
      confirmUrl = j['confirm_url'] as String?,
      confirmDeeplink = j['confirm_deeplink'] as String?,
      bonusCoins = (j['bonus_coins'] as int?) ?? 0,
      balance = j['balance'] as int?;
  final int id, coins;
  final String provider;
  final double amount;
  final String currency, status;
  final String? confirmUrl;

  /// Opens the payment straight in the POK app (when installed).
  final String? confirmDeeplink;
  final int bonusCoins;

  /// My coins after the check (only from the status call).
  final int? balance;

  String get price => formatMoney(amount, currency);
  String get via => provider == 'paypal' ? 'PayPal' : tr('Card / POK');
}

/// The payment's current state (for PayPal this also completes an approved payment).
Future<PokPayment> paymentStatus(Api api, int id) async =>
    PokPayment(await api.get('/pay/pok/$id') as Map<String, dynamic>);

/// Opens the POK app on the payment, if the phone has it. True when it opened.
Future<bool> tryOpenPokApp(PokPayment p) async {
  final link = p.confirmDeeplink;
  if (kIsWeb || p.provider != 'pok' || link == null || link.isEmpty) {
    return false;
  }
  try {
    return await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalNonBrowserApplication,
    );
  } catch (_) {
    return false;
  }
}

Future<void> _openPage(PokPayment p) async {
  if (await tryOpenPokApp(p)) return;
  final url = p.confirmUrl;
  if (url == null) return;
  await launchUrl(
    Uri.parse(url),
    mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
    webOnlyWindowName: '_blank',
  );
}

/// Opens the payment page (again, e.g. a new browser tab) and waits for the result.
Future<bool> resumePokPayment(
  BuildContext context,
  WidgetRef ref,
  PokPayment p,
) async {
  await _openPage(p);
  if (!context.mounted) return false;
  return waitForPayment(context, p);
}

/// "Complete the payment" dialog that updates by itself. True when the coins were added.
Future<bool> waitForPayment(BuildContext context, PokPayment p) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PokWaiting(payment: p),
    ) ??
    false;

class _PokWaiting extends ConsumerStatefulWidget {
  const _PokWaiting({required this.payment});
  final PokPayment payment;

  @override
  ConsumerState<_PokWaiting> createState() => _PokWaitingState();
}

class _PokWaitingState extends ConsumerState<_PokWaiting>
    with WidgetsBindingObserver {
  Timer? _poll;
  String _status = 'pending';
  bool _checking = false;
  final _started = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the browser / POK app: check straight away.
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || _status != 'pending') return;
    if (DateTime.now().difference(_started) > const Duration(minutes: 20)) {
      _poll?.cancel();
      return;
    }
    _checking = true;
    try {
      final p = await paymentStatus(ref.read(apiProvider), widget.payment.id);
      if (!mounted) return;
      setState(() => _status = p.status);
      if (p.status != 'pending') _poll?.cancel();
    } catch (_) {
      // Offline for a moment: try again on the next tick.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    final (icon, title, text) = switch (_status) {
      'paid' => (
        const Icon(
          Icons.check_circle_rounded,
          color: AppColors.emerald,
          size: 56,
        ),
        tr('Payment received'),
        p.bonusCoins > 0
            ? tr(
                '{0} coins were added to your wallet, including a {1} coin first-purchase bonus.',
                [p.coins, p.bonusCoins],
              )
            : tr('{0} coins were added to your wallet.', [p.coins]),
      ),
      'pending' => (
        const SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(),
        ),
        tr('Complete the payment'),
        p.provider == 'paypal'
            ? tr(
                'Pay {0} on the PayPal page. This screen updates by itself when it is done.',
                [p.price],
              )
            : tr(
                'Pay {0} on the POK page with your card or the POK app. This screen updates by itself when it is done.',
                [p.price],
              ),
      ),
      _ => (
        const Icon(
          Icons.error_outline_rounded,
          color: AppColors.like,
          size: 56,
        ),
        tr('Payment not completed'),
        tr('No coins were added and no money was taken. You can try again.'),
      ),
    };
    return AlertDialog(
      icon: icon,
      title: Text(title, textAlign: TextAlign.center),
      content: Text(text, textAlign: TextAlign.center),
      actions: _status == 'pending'
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('Close')),
              ),
              TextButton(
                onPressed: p.confirmUrl == null ? null : () => _openPage(p),
                child: Text(tr('Open payment page')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
                onPressed: _check,
                child: Text(tr('Check')),
              ),
            ]
          : [
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
                onPressed: () => Navigator.pop(context, _status == 'paid'),
                child: Text(tr('OK')),
              ),
            ],
    );
  }
}
