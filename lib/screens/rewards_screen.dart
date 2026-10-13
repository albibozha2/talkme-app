import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/invite_sheet.dart';
import '../kv.dart';

/// Shows the daily reward sheet once a day (if not collected yet), a few seconds after the app opens.
Future<void> offerDailyReward(BuildContext context, WidgetRef ref) async {
  await Future<void>.delayed(const Duration(seconds: 6));
  if (!context.mounted) return;
  final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  if (await Kv.read('reward_offered') == today) return;
  RewardState state;
  try {
    state = await ref.read(apiProvider).rewards();
  } catch (_) {
    return;
  }
  if (!state.enabled || state.checkedInToday || !context.mounted) return;
  // Don't cover something else the user opened (an update sheet, a live…).
  if (ModalRoute.of(context)?.isCurrent == false) return;
  await Kv.write('reward_offered', today);
  if (context.mounted) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RewardSheet(initial: state),
    );
  }
}

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  RewardState? _state;

  @override
  void initState() {
    super.initState();
    ref
        .read(apiProvider)
        .rewards()
        .then((s) {
          if (mounted) setState(() => _state = s);
        })
        .catchError((Object e) {
          if (mounted) showError(context, e);
        });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Daily rewards'))),
    body: _state == null
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _RewardBody(
              initial: _state!,
              onChanged: (s) => setState(() => _state = s),
            ),
          ),
  );
}

class _RewardSheet extends StatelessWidget {
  const _RewardSheet({required this.initial});
  final RewardState initial;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: _RewardBody(initial: initial, compact: true),
    ),
  );
}

class _RewardBody extends ConsumerStatefulWidget {
  const _RewardBody({
    required this.initial,
    this.compact = false,
    this.onChanged,
  });
  final RewardState initial;
  final bool compact;
  final void Function(RewardState)? onChanged;

  @override
  ConsumerState<_RewardBody> createState() => _RewardBodyState();
}

class _RewardBodyState extends ConsumerState<_RewardBody> {
  late RewardState s = widget.initial;
  bool _busy = false;
  int? _justGot;

  Future<void> _checkIn() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).checkIn();
      HapticFeedback.heavyImpact();
      ref.invalidate(sessionProvider);
      if (!mounted) return;
      setState(() {
        s = r;
        _justGot = r.reward;
      });
      widget.onChanged?.call(r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Which day of the 7 is today (1-based): tomorrow's slot until checked in.
    final today = s.checkedInToday ? s.streak : s.streak + 1;
    final slot = ((today - 1) % 7) + 1;
    final me = ref.watch(sessionProvider).value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.goldGradient,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              Text(
                _justGot != null
                    ? tr('+{0} bonus coins!', [_justGot])
                    : tr('Daily reward'),
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.streak > 0
                    ? tr('🔥 {0}-day streak', [s.streak])
                    : tr('Open the app every day to build a streak'),
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (var d = 1; d <= 7; d++)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: d < slot || (d == slot && s.checkedInToday)
                        ? AppColors.emerald.withValues(alpha: .18)
                        : (d == slot
                              ? AppColors.amber.withValues(alpha: .2)
                              : theme.colorScheme.surfaceContainerHigh),
                    borderRadius: BorderRadius.circular(12),
                    border: d == slot
                        ? Border.all(color: AppColors.amber, width: 2)
                        : null,
                  ),
                  child: Column(
                    children: [
                      Text(
                        tr('Day {0}', [d]),
                        style: const TextStyle(fontSize: 10.5),
                      ),
                      const SizedBox(height: 4),
                      d < slot || (d == slot && s.checkedInToday)
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.emerald,
                              size: 22,
                            )
                          : const CoinIcon(size: 20),
                      const SizedBox(height: 2),
                      Text(
                        '${s.week[d - 1]}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (!s.enabled)
          Text(
            tr('Rewards are turned off right now.'),
            textAlign: TextAlign.center,
          )
        else if (s.checkedInToday)
          Text(
            tr('Collected! Come back tomorrow for {0} more.', [s.nextReward]),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          )
        else
          GradientButton(
            label: tr('Collect {0} coins', [s.nextReward]),
            icon: Icons.card_giftcard_rounded,
            busy: _busy,
            gradient: AppColors.goldGradient,
            onPressed: _checkIn,
          ),
        const SizedBox(height: 8),
        Text(
          tr(
            'Bonus coins: {0}. You can send them as gifts; they can’t be withdrawn.',
            [s.bonusCoins],
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.group_add_rounded,
              color: AppColors.emerald,
            ),
            title: Text(tr('Invite friends: +{0} each', [s.inviteReward])),
            subtitle: Text(
              tr(
                '{0} joined with your invite · {1} rewarded. Your friend must check in on 3 days.',
                [s.invites, s.invitesRewarded],
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: me == null
                ? null
                : () => showProfileQr(context, ref, me, mine: true),
          ),
        ),
        if (widget.compact)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Close')),
          ),
      ],
    );
  }
}
