import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/video_grid.dart';

/// Videos you watched (last 90 days), newest first.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  int _version = 0;

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Clear watch history?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Clear')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).clearHistory();
      if (mounted) setState(() => _version++);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('Watch history')),
      actions: [TextButton(onPressed: _clear, child: Text(tr('Clear')))],
    ),
    body: CustomScrollView(
      slivers: [
        VideoGrid(
          key: ValueKey(_version),
          loader: ref.read(apiProvider).history,
          emptyText: tr('Videos you watch appear here.'),
        ),
      ],
    ),
  );
}

/// Accounts you chose "Don't show videos from" for.
class HiddenAccountsScreen extends ConsumerStatefulWidget {
  const HiddenAccountsScreen({super.key});

  @override
  ConsumerState<HiddenAccountsScreen> createState() =>
      _HiddenAccountsScreenState();
}

class _HiddenAccountsScreenState extends ConsumerState<HiddenAccountsScreen> {
  List<AppUser>? _items;

  @override
  void initState() {
    super.initState();
    ref
        .read(apiProvider)
        .hiddenAuthors()
        .then((v) {
          if (mounted) setState(() => _items = v);
        })
        .catchError((Object e) {
          if (mounted) showError(context, e);
        });
  }

  Future<void> _unhide(AppUser u) async {
    try {
      await ref.read(apiProvider).unhideAuthor(u.username);
      if (mounted) setState(() => _items!.remove(u));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Hidden accounts'))),
    body: _items == null
        ? const Center(child: CircularProgressIndicator())
        : _items!.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                tr('Accounts you hide from For You appear here.'),
                textAlign: TextAlign.center,
              ),
            ),
          )
        : ListView(
            children: [
              for (final u in _items!)
                ListTile(
                  leading: Avatar(url: u.avatarUrl, name: u.displayName),
                  title: Text(u.displayName),
                  subtitle: Text('@${u.username}'),
                  trailing: TextButton(
                    onPressed: () => _unhide(u),
                    child: Text(tr('Show again')),
                  ),
                ),
            ],
          ),
  );
}

/// Folder chips above the Saved grid: All, each folder, + New. Long-press a folder to delete it.
class FolderChips extends ConsumerStatefulWidget {
  const FolderChips({
    super.key,
    required this.selected,
    required this.onSelect,
  });
  final int? selected;
  final void Function(int? folderId) onSelect;

  @override
  ConsumerState<FolderChips> createState() => _FolderChipsState();
}

class _FolderChipsState extends ConsumerState<FolderChips> {
  List<Folder> _folders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await ref.read(apiProvider).folders();
      if (mounted) setState(() => _folders = f);
    } catch (_) {}
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('New folder')),
        content: TextField(controller: name, autofocus: true, maxLength: 60),
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
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      final f = await ref.read(apiProvider).createFolder(name.text.trim());
      if (!mounted) return;
      setState(() => _folders.add(f));
      showToast(context, tr('Save videos into it from a video’s ⋯ menu.'));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Folder f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete folder “{0}”?', [f.name])),
        content: Text(tr('The videos stay in your saved list.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).deleteFolder(f.id);
      if (!mounted) return;
      setState(() => _folders.remove(f));
      if (widget.selected == f.id) widget.onSelect(null);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(tr('All')),
            selected: widget.selected == null,
            onSelected: (_) => widget.onSelect(null),
          ),
        ),
        for (final f in _folders)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onLongPress: () => _delete(f),
              child: ChoiceChip(
                avatar: const Icon(Icons.folder_rounded, size: 16),
                label: Text('${f.name} · ${f.count}'),
                selected: widget.selected == f.id,
                onSelected: (_) => widget.onSelect(f.id),
              ),
            ),
          ),
        ActionChip(
          avatar: const Icon(
            Icons.add_rounded,
            size: 18,
            color: AppColors.emerald,
          ),
          label: Text(tr('New folder')),
          onPressed: _create,
        ),
      ],
    ),
  );
}
