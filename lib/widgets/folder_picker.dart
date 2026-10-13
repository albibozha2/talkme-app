import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';

/// Ask for a new folder name. Returns the created folder, or null.
Future<Folder?> createFolderDialog(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('New folder')),
      content: TextField(
        controller: name,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(hintText: tr('e.g. Recipes, Funny, Music')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(tr('Create')),
        ),
      ],
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return null;
  try {
    return await ref.read(apiProvider).createFolder(name.text.trim());
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}

/// Pick (or create) a folder and save the video into it. True if it was saved.
Future<bool> showFolderPicker(
  BuildContext context,
  WidgetRef ref,
  int videoId,
) async {
  List<Folder> folders;
  try {
    folders = await ref.read(apiProvider).folders();
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
  if (!context.mounted) return false;
  final chosen = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 6),
            child: Text(
              tr('Add to folder'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.create_new_folder_rounded,
              color: AppColors.emerald,
            ),
            title: Text(tr('New folder')),
            onTap: () => Navigator.pop(context, 'new'),
          ),
          for (final f in folders)
            ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: Text(f.name),
              subtitle: Text(tr('{0} videos', [f.count])),
              onTap: () => Navigator.pop(context, f),
            ),
        ],
      ),
    ),
  );
  if (chosen == null || !context.mounted) return false;
  final folder = chosen is Folder
      ? chosen
      : await createFolderDialog(context, ref);
  if (folder == null) return false;
  try {
    await ref.read(apiProvider).saveToFolder(videoId, folder.id);
    if (context.mounted) showToast(context, tr('Saved to {0}', [folder.name]));
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}
