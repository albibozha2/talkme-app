import '../pok_pay.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'agents_sheet.dart';
import '../payments.dart';
import '../widgets/recharge_sheet.dart';
import '../i18n.dart';
import '../vip.dart';
import 'rewards_screen.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  Wallet? _wallet;
  PayoutInfo? _payouts;
  PayOptions? _pay;

  /// Me, for the VIP card (level and coins gifted so far).
  AppUser? _me;
  List<CoinTx> _history = [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider);
    try {
      final r = await Future.wait([
        api.wallet(),
        api.transactions(null),
        api
            .payouts()
            .then<PayoutInfo?>((p) => p)
            .catchError((Object _) => null),
        PayOptions.load(api)
            .then<PayOptions?>((p) => p)
            .catchError((Object _) => null),
        api.me().then<AppUser?>((u) => u).catchError((Object _) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = r[0] as Wallet;
        _history = (r[1] as PageResult<CoinTx>).items;
        _payouts = r[2] as PayoutInfo?;
        _pay = r[3] as PayOptions?;
        _me = r[4] as AppUser? ?? _me;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Opens the TikTok-style recharge sheet (with this package picked).
  Future<void> _buy(CoinPackage p) async {
    if (await showRechargeSheet(context, ref, packageId: p.id)) {
      await _load();
      if (mounted) showToast(context, tr('Coins added'));
    } else if (mounted) {
      _load();
    }
  }

  /// The lek price of a package (card / POK), when payments are set up.
  PayPackage? _lekPackage(CoinPackage p) {
    for (final x in _pay?.packages ?? const <PayPackage>[]) {
      if (x.id == p.id) return x;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final w = _wallet;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Wallet'))),
      body: w == null
          ? Center(
              child: _error != null
                  ? Text('$_error')
                  : const CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // Balance card
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: AppColors.goldGradient,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.amber.withValues(alpha: .35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Coin balance'),
                          style: TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const CoinIcon(size: 36),
                            const SizedBox(width: 10),
                            Text(
                              '${w.coins}',
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .35),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.trending_up_rounded,
                                color: AppColors.ink,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tr('Earned from gifts: {0} · you keep {1}%', [
                                    w.earned,
                                    w.sharePercent,
                                  ]),
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (w.bonus > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        tr(
                          'Includes {0} bonus coins (for gifts only, not withdrawable).',
                          [w.bonus],
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Material(
                    color: AppColors.amber.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(20),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      leading: const Icon(
                        Icons.card_giftcard_rounded,
                        color: AppColors.amber,
                      ),
                      title: Text(
                        tr('Daily rewards'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(tr('Free bonus coins every day')),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RewardsScreen(),
                          ),
                        );
                        if (mounted) _load();
                      },
                    ),
                  ),
                  if (w.testMode)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        tr(
                          'Test mode: purchases are free and for testing only.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.secondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  if (_me?.giftsSent != null) ...[
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => showVipTiers(
                        context,
                        level: _me!.level,
                        giftsSent: _me!.giftsSent,
                      ),
                      child: VipCard(
                        level: _me!.level,
                        giftsSent: _me!.giftsSent!,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text(
                    tr('Get coins'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if ((_pay?.firstPurchaseBonus ?? 0) > 0 && !w.testMode) ...[
                    // First purchase: extra coins (set in admin).
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppColors.goldGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Text('🎁', style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tr(
                                'First purchase: +{0}% extra coins on any package',
                                [_pay!.firstPurchaseBonus],
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Material(
                    color: AppColors.emerald.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      leading: const Icon(
                        Icons.storefront_rounded,
                        color: AppColors.emerald,
                      ),
                      title: Text(
                        tr('Buy from an official agent'),
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        tr('Pay cash, bank transfer or mobile payment'),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await showAgentsSheet(context);
                        if (mounted) _load();
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.35,
                    children: [
                      for (final p in w.packages)
                        Material(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _buy(p),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const CoinIcon(size: 22),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${p.coins}',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (p.bonus > 0)
                                    Text(
                                      tr('+{0} bonus', [p.bonus]),
                                      style: const TextStyle(
                                        color: AppColors.emerald,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  const Spacer(),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: AppColors.brandGradient,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        !w.testMode && _lekPackage(p) != null
                                            ? formatLek(
                                                _lekPackage(p)!.priceAll,
                                              )
                                            : p.price,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if ((_pay?.payments ?? const []).isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Text(
                      tr('Your payments'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    // Card / POK app payments.
                    for (final p in _pay!.payments)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: p.status == 'pending'
                            ? () async {
                                await resumePokPayment(context, ref, p);
                                if (mounted) _load();
                              }
                            : null,
                        leading: CircleAvatar(
                          backgroundColor:
                              (p.status == 'paid'
                                      ? AppColors.emerald
                                      : p.status == 'pending'
                                      ? AppColors.amber
                                      : scheme.surfaceContainerHigh)
                                  .withValues(alpha: .18),
                          child: Icon(
                            p.status == 'paid'
                                ? Icons.check_rounded
                                : p.status == 'pending'
                                ? Icons.credit_card
                                : Icons.close_rounded,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          tr('{0} coins · {1}', [p.coins, p.price]),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${p.via} · ${switch (p.status) {
                            'paid' => tr('Paid'),
                            'pending' => tr('Not paid yet · tap to continue'),
                            'refunded' => tr('Refunded'),
                            _ => tr('Not completed'),
                          }}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: p.status == 'pending'
                            ? const Icon(Icons.chevron_right_rounded)
                            : null,
                      ),
                  ],
                  if (_payouts != null) ...[
                    const SizedBox(height: 26),
                    _WithdrawCard(info: _payouts!, onChanged: _load),
                  ],
                  const SizedBox(height: 26),
                  Text(
                    tr('History'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  if (_history.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        tr('No coin activity yet.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  for (final t in _history)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor:
                            (t.amount >= 0 ? AppColors.emerald : AppColors.like)
                                .withValues(alpha: .12),
                        child: Icon(
                          switch (t.type) {
                            'purchase' => Icons.add_card_rounded,
                            'agent' => Icons.storefront_rounded,
                            'gift_sent' => Icons.card_giftcard_rounded,
                            'gift_received' => Icons.volunteer_activism_rounded,
                            'payout' => Icons.account_balance_rounded,
                            'reward' => Icons.card_giftcard_rounded,
                            'subscription' => Icons.workspace_premium_rounded,
                            _ => Icons.tune_rounded,
                          },
                          color: t.amount >= 0
                              ? AppColors.emerald
                              : AppColors.like,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        switch (t.type) {
                          'purchase' => tr('Bought coins'),
                          'gift_sent' => tr('Sent {0}', [t.note]),
                          'gift_received' => tr('Received {0}', [t.note]),
                          'payout' => tr('Payout'),
                          'refund' => tr('Refund'),
                          'subscription' =>
                            t.amount < 0
                                ? tr('Subscribed to {0}', [
                                    t.note.replaceFirst('Subscription: ', ''),
                                  ])
                                : tr('New subscriber {0}', [
                                    t.note.replaceFirst('Subscriber: ', ''),
                                  ]),
                          _ => t.note.isEmpty ? tr('Adjustment') : t.note,
                        },
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '${timeAgo(t.createdAt)}${t.wallet == 'earned' ? ' · earnings' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Text(
                        '${t.amount > 0 ? '+' : ''}${t.amount}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: t.amount >= 0
                              ? AppColors.emerald
                              : AppColors.like,
                          fontSize: 15,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Earnings withdrawal: balance in money, request button, and past requests.
class _WithdrawCard extends ConsumerWidget {
  const _WithdrawCard({required this.info, required this.onChanged});
  final PayoutInfo info;
  final Future<void> Function() onChanged;

  Future<void> _request(BuildContext context) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PayoutSheet(info: info),
    );
    if (sent == true) {
      await onChanged();
      if (context.mounted) {
        showToast(
          context,
          tr('Payout requested. We will notify you when it is sent.'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final usd = info.earned * info.usdPerCoin;
    final canRequest = info.earned >= info.minCoins && !info.hasOpenRequest;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.emerald.withValues(alpha: .14),
                child: const Icon(
                  Icons.account_balance_rounded,
                  color: AppColors.emerald,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Withdraw earnings'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      tr('{0} coins ≈ \${1}', [
                        info.earned,
                        usd.toStringAsFixed(2),
                      ]),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (info.earned / info.minCoins).clamp(0, 1).toDouble(),
              minHeight: 7,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            info.hasOpenRequest
                ? tr('You have a payout in progress.')
                : info.earned >= info.minCoins
                ? tr('You can withdraw now.')
                : tr('{0} more coins to reach the {1} minimum.', [
                    info.minCoins - info.earned,
                    info.minCoins,
                  ]),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: GradientButton(
              label: tr('Request payout'),
              icon: Icons.payments_rounded,
              onPressed: canRequest ? () => _request(context) : null,
            ),
          ),
          for (final p in info.items.take(5)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p.money} · ${p.method}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        [
                          timeAgo(p.createdAt),
                          if (p.note.isNotEmpty) p.note,
                        ].join(' · '),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: p.status),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'paid' => (tr('Paid'), AppColors.emerald),
      'approved' => (tr('Approved'), const Color(0xFF3B82F6)),
      'rejected' => (tr('Rejected'), AppColors.like),
      _ => (tr('Waiting'), AppColors.amberDeep),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PayoutSheet extends ConsumerStatefulWidget {
  const _PayoutSheet({required this.info});
  final PayoutInfo info;

  @override
  ConsumerState<_PayoutSheet> createState() => _PayoutSheetState();
}

class _PayoutSheetState extends ConsumerState<_PayoutSheet> {
  late double _coins = widget.info.earned.toDouble();
  late String _method = widget.info.methods.first;
  final _details = TextEditingController();
  final _holder = TextEditingController();
  final _iban = TextEditingController();
  final _bank = TextEditingController();
  final _bic = TextEditingController();
  bool _busy = false;

  /// "Bank transfer (IBAN)": name, IBAN, bank and SWIFT/BIC fields.
  bool get _isBank {
    final m = _method.toLowerCase();
    return m.contains('iban') || m.contains('bank');
  }

  @override
  void dispose() {
    for (final c in [_details, _holder, _iban, _bank, _bic]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (_isBank
        ? _holder.text.trim().isEmpty || _iban.text.trim().isEmpty
        : _details.text.trim().isEmpty) {
      showToast(context, tr('Enter where we should send the money.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .requestPayout(
            coins: _coins.round(),
            method: _method,
            details: _isBank ? '' : _details.text.trim(),
            holder: _isBank ? _holder.text.trim() : null,
            iban: _isBank ? _iban.text.trim() : null,
            bank: _isBank ? _bank.text.trim() : null,
            bic: _isBank ? _bic.text.trim() : null,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final coins = _coins.round();
    final amount = (coins * info.usdPerCoin).toStringAsFixed(2);
    // POK and Albanian bank accounts (IBAN starting with AL) are paid in lek.
    final pok =
        (_method.toLowerCase() == 'pok' ||
            (_isBank && _iban.text.trim().toUpperCase().startsWith('AL'))) &&
        info.lekPerCoin > 0;
    final money = pok
        ? formatLek((coins * info.lekPerCoin).floor())
        : '\$$amount';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Request a payout'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                money,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: AppColors.emerald,
                ),
              ),
            ),
            Center(
              child: Text(
                tr('{0} coins', [coins]),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (info.earned > info.minCoins)
              Slider(
                value: _coins,
                min: info.minCoins.toDouble(),
                max: info.earned.toDouble(),
                divisions: ((info.earned - info.minCoins) / 10).ceil().clamp(
                  1,
                  1000,
                ),
                onChanged: (v) => setState(() => _coins = v),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: InputDecoration(labelText: tr('Payout method')),
              items: [
                for (final m in info.methods)
                  DropdownMenuItem(value: m, child: Text(tr(m))),
              ],
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
            const SizedBox(height: 12),
            if (_isBank) ...[
              TextField(
                controller: _holder,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: tr('Account holder (full name)'),
                  helperText: tr('The bank account must be in your name.'),
                ),
              ),
              TextField(
                controller: _iban,
                maxLength: 42,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'IBAN',
                  hintText: 'AL47 2121 1009 0000 0002 3569 8741',
                ),
              ),
              TextField(
                controller: _bank,
                maxLength: 60,
                decoration: InputDecoration(
                  labelText: tr('Bank name'),
                  hintText: 'BKT, Raiffeisen, Credins, OTP…',
                ),
              ),
              TextField(
                controller: _bic,
                maxLength: 11,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: tr('SWIFT / BIC (for banks outside Albania)'),
                ),
              ),
            ] else
              TextField(
                controller: _details,
                maxLength: 255,
                keyboardType: _method.toLowerCase() == 'pok'
                    ? TextInputType.phone
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: _method.toLowerCase() == 'pok'
                      ? tr('Phone number of your POK account')
                      : _method.toLowerCase().contains('paypal')
                      ? tr('PayPal email')
                      : tr('Account details'),
                  hintText: _method.toLowerCase() == 'pok'
                      ? '+355 69 123 4567'
                      : _method.toLowerCase().contains('bank')
                      ? tr('Name, IBAN / account number, bank')
                      : null,
                  helperText: _method.toLowerCase() == 'pok'
                      ? tr('The money is sent to your POK wallet.')
                      : null,
                ),
              ),
            const SizedBox(height: 8),
            GradientButton(
              label: tr('Request {0}', [money]),
              busy: _busy,
              onPressed: _send,
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                'Your coins are held until the payout is sent. If it is not approved, they come back to you.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
