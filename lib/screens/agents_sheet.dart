import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import '../i18n.dart';

/// An official coin seller (Admin → Coin agents).
class CoinAgent {
  CoinAgent(Map<String, dynamic> j)
    : username = j['username'] as String,
      displayName = j['display_name'] as String,
      avatarUrl = j['avatar_url'] as String?,
      verified = j['verified'] == true,
      contact = (j['contact'] as String?) ?? '',
      country = (j['country'] as String?) ?? '';
  final String username, displayName, contact, country;
  final String? avatarUrl;
  final bool verified;

  /// WhatsApp link when the contact looks like a phone number.
  String? get whatsapp {
    final digits = contact.replaceAll(RegExp(r'[^\d+]'), '');
    return RegExp(r'^\+?\d{8,15}$').hasMatch(digits)
        ? digits.replaceAll('+', '')
        : null;
  }
}

Future<void> showAgentsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AgentsSheet(),
    );

class _AgentsSheet extends ConsumerStatefulWidget {
  const _AgentsSheet();

  @override
  ConsumerState<_AgentsSheet> createState() => _AgentsSheetState();
}

class _AgentsSheetState extends ConsumerState<_AgentsSheet> {
  List<CoinAgent>? _agents;
  Object? _error;

  @override
  void initState() {
    super.initState();
    ref
        .read(apiProvider)
        .get('/agents')
        .then((d) {
          if (!mounted) return;
          setState(
            () => _agents = (d['items'] as List)
                .map((e) => CoinAgent(e as Map<String, dynamic>))
                .toList(),
          );
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = e);
        });
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(sessionProvider).value;
    final theme = Theme.of(context);
    final agents = _agents;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              tr('Buy from an official agent'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                'Pay the agent in cash, by bank transfer or mobile payment. '
                'Give them your username and the coins arrive in your wallet within minutes.',
              ),
            ),
            if (me != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: tr('Your username: ')),
                            TextSpan(
                              text: '@${me.username}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(text: '  ·  ID ${me.id}'),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Copy'),
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: me.username));
                        showToast(context, tr('Username copied'));
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (_error != null)
              Text('$_error')
            else if (agents == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (agents.isEmpty)
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  tr(
                    'No agents are available right now. Please check again later.',
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final a in agents) _AgentTile(agent: a, me: me?.username),
            const SizedBox(height: 10),
            Text(
              tr(
                'Only buy from agents listed here. Never share your password with anyone.',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentTile extends ConsumerWidget {
  const _AgentTile({required this.agent, required this.me});
  final CoinAgent agent;
  final String? me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wa = agent.whatsapp;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(url: agent.avatarUrl, name: agent.displayName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agent.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                          '@${agent.username}',
                          if (agent.country.isNotEmpty) agent.country,
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.verified_user_rounded,
                  color: AppColors.emerald,
                  size: 20,
                ),
              ],
            ),
            if (agent.contact.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(agent.contact),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (wa != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: const Text('WhatsApp'),
                    onPressed: () => launchUrl(
                      Uri.parse(
                        'https://wa.me/$wa?text=${Uri.encodeComponent('Hi, I want to buy coins. My username is @${me ?? ''}')}',
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.mail_outline_rounded, size: 18),
                  label: Text(tr('Message in app')),
                  onPressed: () =>
                      ChatScreen.openWith(context, ref, agent.username),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
