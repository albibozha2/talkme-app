import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/video_pager.dart';
import 'profile_screen.dart';
import 'safety_screens.dart';
import 'wallet_screen.dart';

String shortDate(DateTime d) => '${d.day}.${d.month}.${d.year}';

/// Creator tools: analytics, subscriptions, comments to review.
class CreatorToolsScreen extends ConsumerWidget {
  const CreatorToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(sessionProvider).value;
    void open(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Creator tools'))),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.insights_rounded),
            title: Text(tr('Analytics')),
            subtitle: Text(tr('Views, followers, likes and earnings')),
            onTap: () => open(const AnalyticsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.workspace_premium_rounded),
            title: Text(tr('Subscriptions')),
            subtitle: Text(
              me?.subPrice == null
                  ? tr('Off')
                  : tr('{0} coins per month', [me!.subPrice!]),
            ),
            onTap: () => open(const SubscriptionSettingsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.rate_review_outlined),
            title: Text(tr('Comments to review')),
            onTap: () => open(const HeldCommentsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.loyalty_outlined),
            title: Text(tr('Creators you subscribe to')),
            onTap: () => open(const MySubscriptionsScreen()),
          ),
        ],
      ),
    );
  }
}

// ---------- analytics ----------

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _days = 7;
  Analytics? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final d = await ref.read(apiProvider).analytics(_days);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Analytics'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final n in [7, 28, 60])
                  ButtonSegment(value: n, label: Text(tr('{0} days', [n]))),
              ],
              selected: {_days},
              onSelectionChanged: (s) {
                _days = s.first;
                _load();
              },
            ),
            const SizedBox(height: 16),
            if (d == null)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Center(
                  child: _error != null
                      ? Text('$_error')
                      : const CircularProgressIndicator(),
                ),
              )
            else ...[
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.7,
                children: [
                  _Stat(
                    tr('Video views'),
                    d,
                    'views',
                    Icons.play_arrow_rounded,
                  ),
                  _Stat(
                    tr('New followers'),
                    d,
                    'followers',
                    Icons.person_add_alt_1_rounded,
                  ),
                  _Stat(tr('Likes'), d, 'likes', Icons.favorite_rounded),
                  _Stat(
                    tr('Comments'),
                    d,
                    'comments',
                    Icons.mode_comment_rounded,
                  ),
                  _Stat(
                    tr('Coins earned'),
                    d,
                    'coins',
                    Icons.monetization_on_rounded,
                  ),
                  _Box(
                    title: tr('Followers'),
                    value: compactCount(d.followersTotal),
                    icon: Icons.groups_rounded,
                    note: tr('{0} subscribers', [d.subscribers]),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Chart(
                title: tr('Video views'),
                values: [for (final s in d.series) s.views],
                days: [for (final s in d.series) s.day],
              ),
              const SizedBox(height: 16),
              _Chart(
                title: tr('New followers'),
                values: [for (final s in d.series) s.followers],
                days: [for (final s in d.series) s.day],
              ),
              const SizedBox(height: 20),
              Text(
                tr('Top videos'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (d.topVideos.isEmpty)
                Text(tr('Post a video to see how it does.')),
              for (final (i, v) in d.topVideos.indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 42,
                      height: 56,
                      child: v.thumbUrl == null
                          ? ColoredBox(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                            )
                          : Image.network(
                              v.thumbUrl!,
                              fit: BoxFit.cover,
                              cacheWidth: 240,
                              errorBuilder: (_, _, _) => const SizedBox(),
                            ),
                    ),
                  ),
                  title: Text(
                    v.caption.isEmpty ? tr('No caption') : v.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    tr('{0} views in this period · {1} total', [
                      compactCount(d.topVideoViews[i]),
                      compactCount(v.views),
                    ]),
                  ),
                  onTap: () => openVideoPager(
                    context,
                    items: d.topVideos,
                    index: i,
                    loader: (_) async => PageResult<Video>([], null),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                tr(
                  '{0} lives in this period. Views are counted from version 1.6.0 on.',
                  [d.lives],
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.title,
    required this.value,
    required this.icon,
    this.note,
    this.noteColor,
  });
  final String title, value;
  final IconData icon;
  final String? note;
  final Color? noteColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.emerald),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          if (note != null)
            Text(
              note!,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: noteColor ?? scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

/// A total with the change against the period before.
class _Stat extends StatelessWidget {
  const _Stat(this.title, this.d, this.field, this.icon);
  final String title, field;
  final Analytics d;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final now = d.total(field), before = d.previous(field);
    final String note;
    Color? color;
    if (before == 0) {
      note = now == 0 ? tr('No change') : tr('New this period');
    } else {
      final pct = ((now - before) * 100 / before).round();
      note = tr('{0}% vs previous {1} days', [
        pct > 0 ? '+$pct' : '$pct',
        d.days,
      ]);
      color = pct >= 0 ? AppColors.emerald : AppColors.like;
    }
    return _Box(
      title: title,
      value: compactCount(now),
      icon: icon,
      note: note,
      noteColor: color,
    );
  }
}

/// Simple bar chart, one bar per day.
class _Chart extends StatelessWidget {
  const _Chart({required this.title, required this.values, required this.days});
  final String title;
  final List<int> values;
  final List<DateTime> days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = values.fold<int>(1, (a, b) => b > a ? b : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            Text(
              tr('Most: {0}', [
                compactCount(top == 1 && !values.contains(1) ? 0 : top),
              ]),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 90,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final v in values)
                Expanded(
                  child: Container(
                    margin: EdgeInsets.symmetric(
                      horizontal: values.length > 30 ? .5 : 2,
                    ),
                    height: 2 + 86 * v / top,
                    decoration: BoxDecoration(
                      gradient: v > 0 ? AppColors.brandGradient : null,
                      color: v > 0 ? null : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              shortDate(days.first),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            Text(
              tr('Today'),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------- subscriptions ----------

class SubscriptionSettingsScreen extends ConsumerStatefulWidget {
  const SubscriptionSettingsScreen({super.key});

  @override
  ConsumerState<SubscriptionSettingsScreen> createState() =>
      _SubscriptionSettingsScreenState();
}

class _SubscriptionSettingsScreenState
    extends ConsumerState<SubscriptionSettingsScreen> {
  late bool _on;
  late final TextEditingController _price, _perks;
  bool _busy = false;
  List<Subscription>? _subs;

  @override
  void initState() {
    super.initState();
    final me = ref.read(sessionProvider).value;
    _on = me?.subPrice != null;
    _price = TextEditingController(text: '${me?.subPrice ?? 100}');
    _perks = TextEditingController(text: me?.subPerks ?? '');
    _loadSubs();
  }

  @override
  void dispose() {
    _price.dispose();
    _perks.dispose();
    super.dispose();
  }

  Future<void> _loadSubs() async {
    try {
      final s = await ref.read(apiProvider).subscriptions();
      if (mounted) setState(() => _subs = s);
    } catch (_) {
      if (mounted) setState(() => _subs = []);
    }
  }

  Future<void> _save() async {
    final price = _on ? int.tryParse(_price.text.trim()) ?? 0 : 0;
    if (_on && price <= 0) {
      showToast(context, tr('Enter a price in coins.'));
      return;
    }
    setState(() => _busy = true);
    try {
      final u = await ref
          .read(apiProvider)
          .subscriptionSettings(price, _perks.text.trim());
      ref.read(sessionProvider.notifier).setUser(u);
      if (mounted) showToast(context, tr('Saved'));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final subs = _subs;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Subscriptions'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr(
              'Fans pay you coins every month. They get a subscriber badge in your comments and can watch your “Subscribers only” videos. You earn the same share as with gifts.',
            ),
            style: muted,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Offer subscriptions')),
            value: _on,
            onChanged: (v) => setState(() => _on = v),
          ),
          if (_on) ...[
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('Price (coins per 30 days)'),
                prefixIcon: const Icon(Icons.monetization_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _perks,
              maxLength: 200,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: tr('What subscribers get (optional)'),
                hintText: tr('e.g. Behind-the-scenes videos every week'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          GradientButton(
            label: tr('Save'),
            icon: Icons.check_rounded,
            busy: _busy,
            onPressed: _save,
          ),
          const SizedBox(height: 24),
          Text(
            subs == null
                ? tr('Subscribers')
                : tr('Subscribers ({0})', [subs.length]),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          if (subs == null)
            const Center(child: CircularProgressIndicator())
          else if (subs.isEmpty)
            Text(tr('No subscribers yet.'), style: muted)
          else
            for (final s in subs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Avatar(
                  url: s.user.avatarUrl,
                  name: s.user.displayName,
                ),
                title: Text(s.user.displayName),
                subtitle: Text(
                  tr('Since {0} · until {1}', [
                    shortDate(s.since),
                    shortDate(s.until),
                  ]),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(username: s.user.username),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class MySubscriptionsScreen extends ConsumerStatefulWidget {
  const MySubscriptionsScreen({super.key});

  @override
  ConsumerState<MySubscriptionsScreen> createState() =>
      _MySubscriptionsScreenState();
}

class _MySubscriptionsScreenState extends ConsumerState<MySubscriptionsScreen> {
  List<Subscription>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(apiProvider).subscriptions(mine: true);
      if (mounted) setState(() => _items = s);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Creators you subscribe to'))),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? Center(child: Text(tr('You don’t subscribe to anyone yet.')))
          : ListView(
              children: [
                for (final s in items)
                  ListTile(
                    leading: Avatar(
                      url: s.user.avatarUrl,
                      name: s.user.displayName,
                    ),
                    title: Text(s.user.displayName),
                    subtitle: Text(tr('Until {0}', [shortDate(s.until)])),
                    trailing: TextButton(
                      onPressed: () async {
                        if (await showSubscribeSheet(context, ref, s.user) !=
                            null) {
                          _load();
                        }
                      },
                      child: Text(tr('Renew')),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ProfileScreen(username: s.user.username),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Explains the subscription and pays for 30 days. Returns the new end date.
Future<DateTime?> showSubscribeSheet(
  BuildContext context,
  WidgetRef ref,
  AppUser creator,
) async {
  final price = creator.subPrice;
  if (price == null) return null;
  final me = ref.read(sessionProvider).value;
  final paid = (me?.coins ?? 0) - (me?.bonusCoins ?? 0);
  final go = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.workspace_premium_rounded,
              size: 48,
              color: AppColors.amber,
            ),
            const SizedBox(height: 8),
            Text(
              creator.subscribed
                  ? tr('Renew your subscription to {0}', [creator.displayName])
                  : tr('Subscribe to {0}', [creator.displayName]),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (creator.subPerks.isNotEmpty) ...[
              Text(creator.subPerks, textAlign: TextAlign.center),
              const SizedBox(height: 8),
            ],
            Text(
              tr(
                'Subscriber badge, subscriber-only videos, and you support the creator directly.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                '{0} coins for 30 days. It doesn’t renew by itself. Free bonus coins can’t be used.',
                [price],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (creator.subscribed) ...[
              const SizedBox(height: 6),
              Text(
                tr('Your subscription runs until {0}; 30 days are added.', [
                  shortDate(creator.subscribedUntil!),
                ]),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            GradientButton(
              label: paid >= price
                  ? tr('Pay {0} coins', [price])
                  : tr('Get coins (you have {0})', [paid]),
              icon: paid >= price
                  ? Icons.workspace_premium_rounded
                  : Icons.add_card_rounded,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    ),
  );
  if (go != true || !context.mounted) return null;
  if (paid < price) {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const WalletScreen()));
    return null;
  }
  try {
    final until = await ref
        .read(apiProvider)
        .subscribe(creator.username, price);
    final fresh = await ref.read(apiProvider).me();
    ref.read(sessionProvider.notifier).setUser(fresh);
    if (context.mounted) {
      showToast(context, tr('Subscribed until {0}', [shortDate(until)]));
    }
    return until;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}
