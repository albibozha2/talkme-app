import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import '../features.dart';

/// Pick people (from those you follow and who follow you). Returns usernames.
class PeoplePicker extends ConsumerStatefulWidget {
  const PeoplePicker({
    super.key,
    required this.title,
    required this.action,
    this.exclude = const {},
    this.withTitleField = false,
  });
  final String title, action;
  final Set<String> exclude;

  /// Show a group-name field (new group).
  final bool withTitleField;

  @override
  ConsumerState<PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends ConsumerState<PeoplePicker> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _chosen = <String, AppUser>{};
  List<AppUser> _people = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = ref.read(sessionProvider).value;
    if (me == null) return;
    final api = ref.read(apiProvider);
    try {
      final r = await Future.wait([
        api.followList(me.username, 'following', null),
        api.followList(me.username, 'followers', null),
      ]);
      final seen = <int>{};
      final all =
          [...r[0].items, ...r[1].items]
              .where(
                (u) => seen.add(u.id) && !widget.exclude.contains(u.username),
              )
              .toList()
            ..sort(
              (a, b) => a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              ),
            );
      if (mounted) setState(() => _people = all);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty
        ? _people
        : _people
              .where(
                (u) =>
                    u.username.contains(q) ||
                    u.displayName.toLowerCase().contains(q),
              )
              .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _chosen.isEmpty
                ? null
                : () => Navigator.pop(context, (
                    title: _name.text.trim(),
                    usernames: _chosen.keys.toList(),
                  )),
            child: Text(
              '${widget.action}${_chosen.isEmpty ? '' : ' (${_chosen.length})'}',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.withTitleField)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _name,
                maxLength: 80,
                decoration: InputDecoration(
                  hintText: tr('Group name (optional)'),
                  prefixIcon: const Icon(Icons.groups_rounded),
                  counterText: '',
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: tr('Search'),
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          if (_chosen.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final u in _chosen.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        avatar: Avatar(
                          url: u.avatarUrl,
                          name: u.displayName,
                          radius: 10,
                        ),
                        label: Text(u.displayName),
                        onDeleted: () =>
                            setState(() => _chosen.remove(u.username)),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        tr(
                          'Only people you follow or who follow you can be added.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final u = list[i];
                      final on = _chosen.containsKey(u.username);
                      return CheckboxListTile(
                        value: on,
                        onChanged: (_) => setState(
                          () => on
                              ? _chosen.remove(u.username)
                              : _chosen[u.username] = u,
                        ),
                        secondary: Avatar(
                          url: u.avatarUrl,
                          name: u.displayName,
                        ),
                        title: Text(u.displayName),
                        subtitle: Text('@${u.username}'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Start a group chat: pick at least two people, then the chat opens.
Future<void> startGroupChat(BuildContext context, WidgetRef ref) async {
  if (!Features.on('groups')) {
    showToast(context, tr('Group chats are turned off right now.'));
    return;
  }
  final r = await Navigator.of(context)
      .push<({String title, List<String> usernames})>(
        MaterialPageRoute(
          builder: (_) => PeoplePicker(
            title: tr('New group'),
            action: tr('Create'),
            withTitleField: true,
          ),
        ),
      );
  if (r == null || !context.mounted) return;
  if (r.usernames.length < 2) {
    showToast(context, tr('Choose at least 2 people for a group.'));
    return;
  }
  try {
    final c = await ref.read(apiProvider).createGroup(r.title, r.usernames);
    if (!context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)));
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Group name, members and admin tools. Pops with true when you leave the group.
class GroupInfoScreen extends ConsumerStatefulWidget {
  const GroupInfoScreen({super.key, required this.conversationId});
  final int conversationId;

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  Conversation? _c;

  Api get _api => ref.read(apiProvider);
  int get _id => widget.conversationId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _api.conversationDetails(_id);
      if (mounted) setState(() => _c = c);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _run(Future<Object?> Function() action) async {
    try {
      final r = await action();
      if (!mounted) return;
      if (r is Conversation) {
        setState(() => _c = r);
      } else {
        await _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _rename() async {
    final name = TextEditingController(text: _c?.title ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Group name')),
        content: TextField(controller: name, autofocus: true, maxLength: 80),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Save')),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await _run(() => _api.renameGroup(_id, name.text.trim()));
    }
  }

  Future<void> _add() async {
    final c = _c;
    if (c == null) return;
    final r = await Navigator.of(context)
        .push<({String title, List<String> usernames})>(
          MaterialPageRoute(
            builder: (_) => PeoplePicker(
              title: tr('Add people'),
              action: tr('Add'),
              exclude: c.members.map((m) => m.user.username).toSet(),
            ),
          ),
        );
    if (r != null) await _run(() => _api.addToGroup(_id, r.usernames));
  }

  Future<void> _memberMenu(ChatMember m) async {
    final c = _c!;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(tr('View profile')),
              onTap: () => Navigator.pop(context, 'profile'),
            ),
            if (c.isAdmin && !m.admin)
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(tr('Make admin')),
                onTap: () => Navigator.pop(context, 'admin'),
              ),
            if (c.isAdmin)
              ListTile(
                leading: const Icon(
                  Icons.person_remove_outlined,
                  color: AppColors.like,
                ),
                title: Text(tr('Remove from group')),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'profile':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProfileScreen(username: m.user.username),
          ),
        );
      case 'admin':
        await _run(() => _api.makeGroupAdmin(_id, m.user.username));
      case 'remove':
        await _run(() => _api.removeFromGroup(_id, m.user.username));
    }
  }

  Future<void> _leave() async {
    final me = ref.read(sessionProvider).value;
    if (me == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Leave this group?')),
        content: Text(tr('You won’t get new messages from it.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Leave')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.removeFromGroup(_id, me.username);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final me = ref.watch(sessionProvider).value?.id;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Group info'))),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 16),
                Center(child: ChatAvatar(conversation: c, radius: 40)),
                const SizedBox(height: 10),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          c.name,
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (c.isAdmin)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: _rename,
                        ),
                    ],
                  ),
                ),
                Center(child: Text(tr('{0} members', [c.members.length]))),
                const SizedBox(height: 12),
                if (c.isAdmin)
                  ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_add_alt_1_rounded),
                    ),
                    title: Text(tr('Add people')),
                    onTap: _add,
                  ),
                for (final m in c.members)
                  ListTile(
                    onTap: m.user.id == me ? null : () => _memberMenu(m),
                    leading: Avatar(
                      url: m.user.avatarUrl,
                      name: m.user.displayName,
                    ),
                    title: Text(
                      m.user.id == me
                          ? tr('{0} (you)', [m.user.displayName])
                          : m.user.displayName,
                    ),
                    subtitle: Text('@${m.user.username}'),
                    trailing: m.admin
                        ? Chip(
                            label: Text(tr('Admin')),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: AppColors.emerald.withValues(
                              alpha: .15,
                            ),
                          )
                        : null,
                  ),
                const Divider(height: 32),
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: AppColors.like,
                  ),
                  title: Text(
                    tr('Leave group'),
                    style: const TextStyle(color: AppColors.like),
                  ),
                  onTap: _leave,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
