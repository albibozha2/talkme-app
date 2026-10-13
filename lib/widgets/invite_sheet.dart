import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// Web address of someone's public profile page (also used as the invite link).
String profileLink(WidgetRef ref, String username) =>
    '${ref.read(apiProvider).server.replaceAll(RegExp(r'/api$'), '')}/u/$username';

/// QR code + link for a profile. For your own profile it doubles as an invite.
Future<void> showProfileQr(
  BuildContext context,
  WidgetRef ref,
  AppUser u, {
  bool mine = false,
}) {
  final link = profileLink(ref, u.username);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(url: u.avatarUrl, name: u.displayName, radius: 30),
            const SizedBox(height: 8),
            Text(u.displayName, style: Theme.of(context).textTheme.titleLarge),
            Text('@${u.username}'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: QrImageView(
                data: link,
                size: 210,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.circle,
                  color: AppColors.emeraldDeep,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              mine
                  ? tr(
                      'Friends can scan this to find you. People who sign up with @{0} as “Invited by” count as your invites.',
                      [u.username],
                    )
                  : tr('Scan to open this profile.'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(tr('Copy link')),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      showToast(context, tr('Copied'));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.share_rounded),
                    label: Text(tr('Share')),
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(
                        text: mine
                            ? tr(
                                'Join me on TalkMe! Sign up with invite @{0}: {1}',
                                [u.username, link],
                              )
                            : '${u.displayName} (@${u.username}): $link',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
