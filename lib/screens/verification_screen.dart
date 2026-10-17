import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Identity verification: ID card (front + back) or passport, plus a selfie holding the document while making a
/// gesture. Reviewed by TalkMe staff; photos are encrypted and deleted 30 days after the decision.
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  KycStatus? _st;
  bool _retry = false;
  bool _busy = false;
  String _doc = 'id_card';
  final _name = TextEditingController();
  DateTime? _birth;
  final Map<String, XFile> _photos = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final st = await ref.read(apiProvider).kycStatus();
      if (mounted) setState(() => _st = st);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _pick(String which) async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: which == 'selfie'
          ? CameraDevice.front
          : CameraDevice.rear,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (f != null && mounted) setState(() => _photos[which] = f);
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 20),
      firstDate: DateTime(now.year - 110),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (d != null) setState(() => _birth = d);
  }

  bool get _ready =>
      _name.text.trim().contains(' ') &&
      _birth != null &&
      _photos['front'] != null &&
      _photos['selfie'] != null &&
      (_doc == 'passport' || _photos['back'] != null);

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final b = _birth!;
      final st = await ref
          .read(apiProvider)
          .submitKyc(
            docType: _doc,
            fullName: _name.text.trim(),
            birthDate:
                '${b.year}-${b.month.toString().padLeft(2, '0')}-${b.day.toString().padLeft(2, '0')}',
            front: _photos['front']!.path,
            back: _doc == 'id_card' ? _photos['back']!.path : null,
            selfie: _photos['selfie']!.path,
          );
      if (!mounted) return;
      setState(() {
        _st = st;
        _retry = false;
        _photos.clear();
      });
      showToast(context, tr('Sent! We will review it soon.'));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Verify identity'))),
      body: st == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
              children: [
                if (st.verified)
                  _StatusCard(
                    icon: Icons.verified_rounded,
                    color: AppColors.emerald,
                    title: tr('Your identity is verified'),
                    text: tr('You can withdraw your earnings.'),
                  )
                else if (st.status == 'pending')
                  _StatusCard(
                    icon: Icons.hourglass_top_rounded,
                    color: Colors.orange,
                    title: tr('Under review'),
                    text: tr(
                      'We are checking your documents. This usually takes less than a day. You will get a notification.',
                    ),
                  )
                else if (st.status == 'rejected' && !_retry) ...[
                  _StatusCard(
                    icon: Icons.error_outline_rounded,
                    color: Colors.redAccent,
                    title: tr('Not approved'),
                    text: tr(st.reason ?? ''),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: GradientButton(
                      label: tr('Try again'),
                      icon: Icons.refresh_rounded,
                      onPressed: () => setState(() => _retry = true),
                    ),
                  ),
                ] else
                  ..._form(st),
              ],
            ),
    );
  }

  List<Widget> _form(KycStatus st) {
    final scheme = Theme.of(context).colorScheme;
    return [
      Text(
        tr(
          'To withdraw money we need to know it is really you. You must be {0} or older.',
          [st.minAge],
        ),
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 16),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(
            value: 'id_card',
            label: Text(tr('ID card')),
            icon: const Icon(Icons.badge_outlined),
          ),
          ButtonSegment(
            value: 'passport',
            label: Text(tr('Passport')),
            icon: const Icon(Icons.menu_book_rounded),
          ),
        ],
        selected: {_doc},
        onSelectionChanged: (s) => setState(() => _doc = s.first),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: tr('Full name (as on the document)'),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _pickBirth,
        icon: const Icon(Icons.cake_outlined),
        label: Text(
          _birth == null
              ? tr('Date of birth')
              : '${_birth!.day}.${_birth!.month}.${_birth!.year}',
        ),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: _PhotoTile(
              label: _doc == 'passport' ? tr('Photo page') : tr('Front'),
              file: _photos['front'],
              onTap: () => _pick('front'),
            ),
          ),
          if (_doc == 'id_card') ...[
            const SizedBox(width: 10),
            Expanded(
              child: _PhotoTile(
                label: tr('Back'),
                file: _photos['back'],
                onTap: () => _pick('back'),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Text(st.gestureIcon, style: const TextStyle(fontSize: 40)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${tr('Selfie: hold your document next to your face and:')}\n${tr(st.gestureText)}',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      _PhotoTile(
        label: tr('Selfie'),
        file: _photos['selfie'],
        onTap: () => _pick('selfie'),
        tall: true,
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(
                'Your photos are encrypted, seen only by TalkMe staff, and deleted 30 days after the review.',
              ),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      SizedBox(
        height: 50,
        child: GradientButton(
          label: _busy ? tr('Sending…') : tr('Send for review'),
          icon: Icons.send_rounded,
          onPressed: _ready && !_busy ? _submit : null,
        ),
      ),
    ];
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        Icon(icon, color: color, size: 56),
        const SizedBox(height: 10),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.label,
    required this.file,
    required this.onTap,
    this.tall = false,
  });
  final String label;
  final XFile? file;
  final VoidCallback onTap;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = file;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: tall ? 200 : 120,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (f != null)
              FutureBuilder<Uint8List>(
                future: f.readAsBytes(),
                builder: (_, s) => s.hasData
                    ? Image.memory(s.data!, fit: BoxFit.cover)
                    : const SizedBox(),
              )
            else
              Icon(Icons.photo_camera_outlined, size: 34, color: scheme.outline),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  f != null ? '✓ $label' : label,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
