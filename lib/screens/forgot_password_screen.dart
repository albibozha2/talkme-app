import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../i18n.dart';
import 'safety_screens.dart';

/// Reset a forgotten password with a 6-digit code sent by email.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.login = ''});
  final String login;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final _login = TextEditingController(text: widget.login);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false, _busy = false, _show = false;
  String? _info, _error;

  @override
  void dispose() {
    _login.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_login.text.trim().isEmpty) {
      setState(() => _error = tr('Enter your username or email.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await ref
          .read(apiProvider)
          .forgotPassword(_login.text.trim().toLowerCase());
      if (mounted) {
        setState(() {
          _codeSent = true;
          _info = message;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = tr('Enter the 6-digit code from the email.'));
      return;
    }
    if (_password.text.length < 8) {
      setState(
        () => _error = tr('Use at least 8 characters for your new password.'),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .resetPassword(
            _login.text.trim().toLowerCase(),
            _code.text.trim(),
            _password.text,
          );
      if (!mounted) return;
      showToast(context, tr('Password changed. You are signed in.'));
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on TwoFactorRequired catch (e) {
      if (!mounted) return;
      if (await finishTwoFactorSignIn(context, ref, e.ticket) && mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Reset password'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(
              _codeSent ? tr('Check your email') : tr('Forgot your password?'),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _codeSent
                  ? (_info ?? '')
                  : tr(
                      'Enter your username or the email you signed up with. '
                      'We’ll email you a 6-digit code.',
                    ),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _login,
              enabled: !_codeSent,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: tr('Username or email'),
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              onSubmitted: (_) => _codeSent ? null : _sendCode(),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofillHints: const [AutofillHints.oneTimeCode],
                style: const TextStyle(
                  fontSize: 22,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  hintText: tr('6-digit code'),
                  counterText: '',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: !_show,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  hintText: tr('New password (at least 8 characters)'),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _show
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
                onSubmitted: (_) => _reset(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 22),
            GradientButton(
              label: _codeSent ? tr('Change password') : tr('Send code'),
              busy: _busy,
              onPressed: _codeSent ? _reset : _sendCode,
            ),
            if (_codeSent) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _sendCode,
                child: Text(tr('Didn’t get it? Send a new code')),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _codeSent = false;
                        _code.clear();
                        _error = null;
                      }),
                child: Text(tr('Use a different account')),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              tr(
                'The code works for 15 minutes. Check your spam folder if it doesn’t arrive.',
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
