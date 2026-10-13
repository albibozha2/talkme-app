import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n.dart';

/// Choose English or Albanian. The whole app redraws in the new language.
Future<void> showLanguagePicker(BuildContext context, WidgetRef ref) async {
  final chosen = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('Language'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final e in languages.entries)
            ListTile(
              leading: Text(
                e.key == 'sq' ? '🇦🇱' : '🇬🇧',
                style: const TextStyle(fontSize: 24),
              ),
              title: Text(e.value),
              trailing: e.key == currentLanguage
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(context, e.key),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (chosen != null) await ref.read(languageProvider.notifier).set(chosen);
}
