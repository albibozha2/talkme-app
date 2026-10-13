import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../i18n.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final _me = ref.read(sessionProvider).value!;
  late final _name = TextEditingController(text: _me.displayName);
  late final _bio = TextEditingController(text: _me.bio);
  late final _website = TextEditingController(text: _me.website);
  late final _instagram = TextEditingController(text: _me.instagram);
  late bool _private = _me.isPrivate;
  late bool _tips = _me.marketingOptIn;
  bool _saving = false;
  bool _uploadingPhoto = false;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _website.dispose();
    _instagram.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    // Resize on the device so we never upload a 12 MP photo for a 92 px circle.
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final user = await ref.read(apiProvider).uploadAvatar(file.path);
      ref.read(sessionProvider.notifier).setUser(user);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final user = await ref
          .read(apiProvider)
          .updateMe(
            displayName: _name.text.trim(),
            bio: _bio.text.trim(),
            website: _website.text.trim(),
            instagram: _instagram.text.trim(),
            isPrivate: _private,
            marketingOptIn: _tips,
          );
      ref.read(sessionProvider.notifier).setUser(user);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteAccount() async {
    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete your account?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(
                'Your profile, videos, comments and likes will be removed permanently.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pw,
              obscureText: true,
              decoration: InputDecoration(labelText: tr('Password')),
            ),
          ],
        ),
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
      await ref.read(apiProvider).deleteAccount(pw.text);
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      ref.invalidate(sessionProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      pw.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(sessionProvider).value ?? _me;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Edit profile'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Stack(
              children: [
                Avatar(url: me.avatarUrl, name: me.displayName, radius: 52),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IconButton.filled(
                    onPressed: _uploadingPhoto ? null : _pickPhoto,
                    icon: _uploadingPhoto
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            maxLength: 60,
            decoration: InputDecoration(labelText: tr('Name')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bio,
            maxLength: 300,
            maxLines: 4,
            minLines: 2,
            decoration: InputDecoration(labelText: tr('Bio')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _website,
            maxLength: 200,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: tr('Website'),
              hintText: 'talkme.space/u/you',
              prefixIcon: const Icon(Icons.link_rounded),
            ),
          ),
          TextField(
            controller: _instagram,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: 'Instagram',
              prefixText: '@',
              prefixIcon: const Icon(Icons.camera_alt_outlined),
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.lock_outline_rounded),
            title: Text(tr('Private account')),
            subtitle: Text(
              tr('Only people you approve can see your videos and lives.'),
            ),
            value: _private,
            onChanged: (v) => setState(() => _private = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.tips_and_updates_outlined),
            title: Text(tr('Tips & suggestions')),
            subtitle: Text(
              tr(
                'Occasional notifications about new videos, lives and features.',
              ),
            ),
            value: _tips,
            onChanged: (v) => setState(() => _tips = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? tr('Saving…') : tr('Save')),
          ),
          const SizedBox(height: 40),
          TextButton(
            onPressed: _deleteAccount,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(tr('Delete account')),
          ),
        ],
      ),
    );
  }
}
