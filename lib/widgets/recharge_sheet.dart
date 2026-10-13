import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../pay_webview.dart';
import '../payments.dart';
import '../pok_pay.dart';
import '../screens/agents_sheet.dart';
import '../theme.dart';
import 'common.dart';

/// TikTok-style "Recharge" sheet: pick a coin package, pick Card / POK or PayPal, tap Recharge.
/// The payment page opens inside the app and the sheet closes by itself once the coins are in.
/// Returns true when coins were added.
Future<bool> showRechargeSheet(
  BuildContext context,
  WidgetRef ref, {
  int? packageId,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _RechargeSheet(packageId: packageId),
    ) ??
    false;

class _RechargeSheet extends ConsumerStatefulWidget {
  const _RechargeSheet({this.packageId});
  final int? packageId;

  @override
  ConsumerState<_RechargeSheet> createState() => _RechargeSheetState();
}

class _RechargeSheetState extends ConsumerState<_RechargeSheet> {
  Wallet? _wallet;
  PayOptions? _opts;
  Object? _error;
  int? _selected;
  String _method = 'pok';
  bool _busy = false;
  int? _added; // coins just added (success view)

  Api get _api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        _api.wallet(),
        PayOptions.load(_api)
            .then<PayOptions?>((o) => o)
            .catchError((Object _) => null),
      ]);
      if (!mounted) return;
      final w = r[0] as Wallet;
      final o = r[1] as PayOptions?;
      setState(() {
        _wallet = w;
        _opts = o;
        _method = (o?.pok ?? false) ? 'pok' : 'paypal';
        final ids = _packages.map((p) => p.$1).toList();
        _selected = ids.contains(widget.packageId)
            ? widget.packageId
            : (ids.isEmpty ? null : ids[ids.length > 2 ? 1 : 0]);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  bool get _test => _wallet?.testMode ?? false;

  /// (id, coins, bonus) of what can be bought right now.
  List<(int, int, int)> get _packages {
    if (_test) {
      return [for (final p in _wallet!.packages) (p.id, p.coins, p.bonus)];
    }
    return [
      for (final p in _opts?.packages ?? const <PayPackage>[])
        (p.id, p.coins, p.bonus),
    ];
  }

  PayPackage? get _pack {
    for (final p in _opts?.packages ?? const <PayPackage>[]) {
      if (p.id == _selected) return p;
    }
    return null;
  }

  String _priceOf(int id) {
    if (_test) {
      return _wallet!.packages.firstWhere((p) => p.id == id).price;
    }
    final p = _opts!.packages.firstWhere((x) => x.id == id);
    return _method == 'paypal' && p.pricePaypal != null
        ? formatMoney(p.pricePaypal!, _opts!.paypalCurrency)
        : formatLek(p.priceAll);
  }

  Future<void> _recharge() async {
    final id = _selected;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (_test) {
        await _api.buyCoins(id);
        final p = _wallet!.packages.firstWhere((x) => x.id == id);
        _success(p.coins + p.bonus);
        return;
      }
      final paypal = _method == 'paypal';
      final p = PokPayment(
        await _api.post(paypal ? '/pay/paypal' : '/pay/pok', {'package_id': id})
            as Map<String, dynamic>,
      );
      if (!mounted) return;
      bool paid;
      final openedApp = await tryOpenPokApp(p);
      if (!mounted) return;
      if (openedApp) {
        // The POK app handles it; wait here for the confirmation.
        paid = await waitForPayment(context, p);
      } else if (inAppPaymentPages && p.confirmUrl != null) {
        await openPaymentPage(
          context,
          url: p.confirmUrl!,
          title: paypal ? 'PayPal' : 'POK',
          isFinished: () async {
            try {
              return (await paymentStatus(_api, p.id)).status == 'paid';
            } catch (_) {
              return false;
            }
          },
        );
        if (!mounted) return;
        // Back from the page: confirm the result (this also completes an approved PayPal payment).
        var st = await paymentStatus(_api, p.id);
        if (st.status == 'pending') {
          await Future<void>.delayed(const Duration(seconds: 2));
          st = await paymentStatus(_api, p.id);
        }
        paid = st.status == 'paid';
        if (!paid && mounted) {
          showToast(
            context,
            st.status == 'pending'
                ? tr(
                    'Payment not finished. You can continue it from your wallet.',
                  )
                : tr(
                    'No coins were added and no money was taken. You can try again.',
                  ),
          );
        }
      } else {
        // Browser: new tab + the waiting dialog.
        paid = await resumePokPayment(context, ref, p);
      }
      if (paid) _success(p.coins);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _success(int coins) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _added = coins;
      _wallet = _wallet == null
          ? null
          : Wallet(
              coins: _wallet!.coins + coins,
              earned: _wallet!.earned,
              sharePercent: _wallet!.sharePercent,
              testMode: _wallet!.testMode,
              packages: _wallet!.packages,
              bonus: _wallet!.bonus,
            );
    });
    Timer(const Duration(milliseconds: 1700), () {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = _wallet;
    if (_added != null) return _SuccessView(coins: _added!, balance: w?.coins);
    if (w == null) {
      return SizedBox(
        height: 260,
        child: Center(
          child: _error != null
              ? Text('$_error')
              : const CircularProgressIndicator(),
        ),
      );
    }
    final opts = _opts;
    final canPay = _test || (opts?.available ?? false);
    final packs = _packages;
    final bonusPct = _test ? 0 : (opts?.firstPurchaseBonus ?? 0);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  tr('Recharge'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const CoinIcon(size: 18),
                      const SizedBox(width: 6),
                      Text(
                        '${w.coins}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (bonusPct > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: AppColors.goldGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tr('🎁 First purchase: +{0}% extra coins', [bonusPct]),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (!canPay) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  tr('Buying coins in the app is not available right now.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => showAgentsSheet(context),
                icon: const Icon(Icons.storefront_rounded),
                label: Text(tr('Buy from an official agent')),
              ),
            ] else ...[
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: .92,
                children: [
                  for (var i = 0; i < packs.length; i++)
                    _PackTile(
                      coins: packs[i].$2,
                      bonus:
                          packs[i].$3 +
                          (packs[i].$2 + packs[i].$3) * bonusPct ~/ 100,
                      price: _priceOf(packs[i].$1),
                      popular: packs.length > 2 && i == 1,
                      selected: _selected == packs[i].$1,
                      onTap: _busy
                          ? null
                          : () => setState(() => _selected = packs[i].$1),
                    ),
                ],
              ),
              if (!_test && (opts!.pok || opts.paypal)) ...[
                const SizedBox(height: 16),
                Text(
                  tr('Payment method'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (opts.pok)
                  _MethodTile(
                    selected: _method == 'pok',
                    icon: Icons.credit_card,
                    title: tr('Card or POK app'),
                    subtitle: 'Visa · Mastercard · POK',
                    onTap: _busy ? null : () => setState(() => _method = 'pok'),
                  ),
                if (opts.paypal) ...[
                  const SizedBox(height: 8),
                  _MethodTile(
                    selected: _method == 'paypal',
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'PayPal',
                    subtitle: _pack?.pricePaypal != null
                        ? tr('Pay in {0}', [opts.paypalCurrency])
                        : 'PayPal',
                    onTap: _busy
                        ? null
                        : () => setState(() => _method = 'paypal'),
                    paypal: true,
                  ),
                ],
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.like,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _selected == null || _busy ? null : _recharge,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _selected == null
                              ? tr('Recharge')
                              : tr('Recharge {0}', [_priceOf(_selected!)]),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _test
                          ? tr(
                              'Test mode: purchases are free and for testing only.',
                            )
                          : tr(
                              'Secure payment by {0}. Coins are added instantly.',
                              [_method == 'paypal' ? 'PayPal' : 'POK'],
                            ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({
    required this.coins,
    required this.bonus,
    required this.price,
    required this.popular,
    required this.selected,
    required this.onTap,
  });
  final int coins, bonus;
  final String price;
  final bool popular, selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.like.withValues(alpha: .08)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.like
                : scheme.outlineVariant.withValues(alpha: .4),
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CoinIcon(size: 18),
                        const SizedBox(width: 4),
                        Text(
                          '$coins',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    if (bonus > 0)
                      Text(
                        tr('+{0} bonus', [bonus]),
                        style: const TextStyle(
                          color: AppColors.emerald,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      price,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (popular)
              Positioned(
                top: -1,
                left: -1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.like,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomRight: Radius.circular(10),
                    ),
                  ),
                  child: Text(
                    tr('Popular'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.paypal = false,
  });
  final bool selected, paypal;
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.like
                  : scheme.outlineVariant.withValues(alpha: .4),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: paypal
                      ? const Color(0xFF003087)
                      : const Color(0xFF4F46E5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: paypal
                    ? const Center(
                        child: Text(
                          'P',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            fontSize: 20,
                          ),
                        ),
                      )
                    : Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.like : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Coins added: a big check and the new balance, then the sheet closes.
class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.coins, this.balance});
  final int coins;
  final int? balance;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 300,
    child: Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: .5, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.elasticOut,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.emerald,
              size: 72,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CoinIcon(size: 26),
                const SizedBox(width: 8),
                Text(
                  '+$coins',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(tr('Payment received')),
            if (balance != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr('Balance: {0}', [balance!]),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
