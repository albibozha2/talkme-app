import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';

String _when(DateTime t) {
  final l = t.toLocal();
  final now = DateTime.now();
  final day = DateTime(
    l.year,
    l.month,
    l.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  final hm =
      '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  return switch (day) {
    0 => tr('Today {0}', [hm]),
    1 => tr('Tomorrow {0}', [hm]),
    _ => '${l.day}.${l.month}. $hm',
  };
}

/// Upcoming scheduled lives with a "Remind me" button.
class LiveEventsList extends ConsumerStatefulWidget {
  const LiveEventsList({super.key, this.username});

  /// Only this person's lives (profile), or null for everyone you follow.
  final String? username;

  @override
  ConsumerState<LiveEventsList> createState() => LiveEventsListState();
}

class LiveEventsListState extends ConsumerState<LiveEventsList> {
  List<LiveEvent> _items = [];

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final items = await ref
          .read(apiProvider)
          .liveEvents(username: widget.username);
      if (mounted) setState(() => _items = items);
    } catch (_) {}
  }

  Future<void> _toggle(LiveEvent e) async {
    final on = !e.reminded;
    setState(() {
      e.reminded = on;
      e.reminders += on ? 1 : -1;
    });
    try {
      await ref.read(apiProvider).setLiveReminder(e.id, on);
      if (mounted && on) {
        showToast(context, tr('We’ll remind you 10 minutes before'));
      }
    } catch (err) {
      if (!mounted) return;
      setState(() {
        e.reminded = !on;
        e.reminders += on ? -1 : 1;
      });
      showError(context, err);
    }
  }

  Future<void> _delete(LiveEvent e) async {
    try {
      await ref.read(apiProvider).deleteLiveEvent(e.id);
      if (mounted) setState(() => _items.remove(e));
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(tr('Upcoming lives')),
        for (final e in _items)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              onTap: widget.username != null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ProfileScreen(username: e.user.username),
                      ),
                    ),
              leading: Avatar(url: e.user.avatarUrl, name: e.user.displayName),
              title: Text(
                e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${widget.username == null ? '${e.user.displayName} · ' : ''}${_when(e.startsAt)} · ${tr('{0} waiting', [e.reminders])}',
              ),
              trailing: e.mine
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => _delete(e),
                    )
                  : FilledButton.tonal(
                      onPressed: () => _toggle(e),
                      child: Text(
                        e.reminded ? tr('Reminded') : tr('Remind me'),
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}

/// Pick a title and time for a future live.
Future<bool> scheduleLiveDialog(BuildContext context, WidgetRef ref) async {
  final title = TextEditingController();
  var when = DateTime.now().add(const Duration(hours: 1));
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Schedule a live'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: title,
              maxLength: 120,
              decoration: InputDecoration(
                hintText: tr('What is your live about?'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text(_when(when)),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: when,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 30)),
                );
                if (date == null || !context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(when),
                );
                if (time == null) return;
                setSheet(
                  () => when = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            GradientButton(
              label: tr('Schedule'),
              icon: Icons.event_available_rounded,
              onPressed: () async {
                try {
                  await ref
                      .read(apiProvider)
                      .scheduleLive(title.text.trim(), when);
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
            ),
            const SizedBox(height: 6),
            Text(
              tr('Your followers get a notification and can set a reminder.'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
  title.dispose();
  return ok == true;
}

/// People who can remove viewers and mute the chat in all your lives.
class LiveModsScreen extends ConsumerStatefulWidget {
  const LiveModsScreen({super.key});

  @override
  ConsumerState<LiveModsScreen> createState() => _LiveModsScreenState();
}

class _LiveModsScreenState extends ConsumerState<LiveModsScreen> {
  List<AppUser>? _mods;
  final _add = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await ref.read(apiProvider).liveMods();
      if (mounted) setState(() => _mods = m);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _set(String username, bool on) async {
    try {
      await ref
          .read(apiProvider)
          .setLiveMod(username.replaceAll('@', '').trim().toLowerCase(), on);
      _add.clear();
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Live moderators'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          tr(
            'Moderators can remove people and mute the chat in all your lives. You can also make someone a moderator by tapping their name in your live chat.',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _add,
                decoration: InputDecoration(
                  hintText: tr('Username'),
                  prefixText: '@',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _set(_add.text, true),
              child: Text(tr('Add')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_mods == null)
          const Center(child: CircularProgressIndicator())
        else if (_mods!.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(tr('No moderators yet.'), textAlign: TextAlign.center),
          )
        else
          for (final m in _mods!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(url: m.avatarUrl, name: m.displayName),
              title: Text(m.displayName),
              subtitle: Text('@${m.username}'),
              trailing: IconButton(
                icon: const Icon(
                  Icons.remove_circle_outline_rounded,
                  color: AppColors.like,
                ),
                onPressed: () => _set(m.username, false),
              ),
            ),
      ],
    ),
  );
}
