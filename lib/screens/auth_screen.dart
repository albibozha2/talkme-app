import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../push.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'server_dialog.dart';
import 'forgot_password_screen.dart';
import '../i18n.dart';
import '../widgets/language_picker.dart';
import 'safety_screens.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../google_auth.dart';
import '../web/google_button.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, required this.config});
  final RemoteConfig config;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _email = TextEditingController();
  final _invite = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;

  /// Sign-up only: "I'm 13 or older and agree to the Terms and Privacy policy".
  bool _agree = false;
  bool _showPassword = false;
  StreamSubscription<String>? _googleWeb;

  @override
  void initState() {
    super.initState();
    // Lets "finish signing up" reminders reach this phone before it has an account.
    PushService.instance.start(
      ProviderScope.containerOf(context, listen: false),
      guest: true,
    );
    // Google sign-in is on when the server announces a client ID.
    GoogleAuth.configure(widget.config.googleClientId);
    // In the browser, Google's own button sends the token here.
    if (kIsWeb && googleSignInEnabled) {
      _googleWeb = GoogleAuth.webTokens().listen(_withGoogleToken);
    }
    final reason = ref.read(sessionProvider.notifier).signedOutReason;
    if (reason != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showError(context, reason);
      });
    }
  }

  /// Phones: Google's account picker, then the server signs in or creates the account.
  Future<void> _google() async {
    if (!_agreed()) return;
    setState(() => _busy = true);
    try {
      final token = await GoogleAuth.pickAccount();
      if (token != null) await _withGoogleToken(token);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// New accounts must confirm their age and accept the terms first.
  bool _agreed() {
    if (!_register || _agree) return true;
    showError(
      context,
      tr('Please confirm you are 13 or older and agree to the Terms.'),
    );
    return false;
  }

  Future<void> _withGoogleToken(String token) async {
    if (!_agreed()) return;
    try {
      await ref
          .read(sessionProvider.notifier)
          .loginWithGoogle(token, invite: _invite.text.trim());
    } on TwoFactorRequired catch (e) {
      if (mounted) await finishTwoFactorSignIn(context, ref, e.ticket);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  void dispose() {
    _googleWeb?.cancel();
    _login.dispose();
    _email.dispose();
    _invite.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || !_agreed()) return;
    setState(() => _busy = true);
    final session = ref.read(sessionProvider.notifier);
    try {
      if (_register) {
        await session.register(
          _login.text.trim().toLowerCase(),
          _email.text.trim(),
          _password.text,
          invite: _invite.text.trim(),
          acceptTerms: true,
        );
      } else {
        await session.login(_login.text.trim(), _password.text);
      }
    } on TwoFactorRequired catch (e) {
      if (mounted) await finishTwoFactorSignIn(context, ref, e.ticket);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showText(String title, String text) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: .85,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(text.isEmpty ? tr('Not available yet.') : text),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    final scheme = Theme.of(context).colorScheme;
    final small = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);
    return Scaffold(
      body: Stack(
        children: [
          // Soft brand glow behind the form.
          Positioned(
            top: -160,
            left: -120,
            right: -120,
            child: Container(
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.emerald.withValues(alpha: .35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -140,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.amber.withValues(alpha: .18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _form,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(child: BrandMark(size: 76)),
                          const SizedBox(height: 22),
                          Text(
                            _register
                                ? tr('Create your account')
                                : tr('Welcome back'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _register
                                ? tr('Join {0} and start sharing', [
                                    cfg.appName,
                                  ])
                                : tr('Sign in to keep watching'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 32),
                          TextFormField(
                            controller: _login,
                            autofillHints: [
                              _register
                                  ? AutofillHints.newUsername
                                  : AutofillHints.username,
                            ],
                            decoration: InputDecoration(
                              hintText: _register
                                  ? tr('Username')
                                  : tr('Username or email'),
                              prefixIcon: const Icon(
                                Icons.person_outline_rounded,
                              ),
                            ),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return tr('Required');
                              if (_register &&
                                  !RegExp(r'^[a-zA-Z0-9_.]{3,30}$')
                                      .hasMatch(s)) {
                                return tr('3–30 letters, numbers, _ or .');
                              }
                              return null;
                            },
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            child: _register
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: TextFormField(
                                      controller: _email,
                                      keyboardType: TextInputType.emailAddress,
                                      autofillHints: const [
                                        AutofillHints.email,
                                      ],
                                      decoration: InputDecoration(
                                        hintText: tr('Email'),
                                        prefixIcon: Icon(
                                          Icons.alternate_email_rounded,
                                        ),
                                      ),
                                      validator: (v) => (v ?? '').contains('@')
                                          ? null
                                          : tr('Enter a valid email'),
                                    ),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: !_showPassword,
                            autofillHints: [
                              _register
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              hintText: tr('Password'),
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                ),
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                              ),
                            ),
                            validator: (v) => _register && (v ?? '').length < 8
                                ? tr('At least 8 characters')
                                : ((v ?? '').isEmpty ? tr('Required') : null),
                          ),
                          if (!_register)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ForgotPasswordScreen(
                                      login: _login.text.trim(),
                                    ),
                                  ),
                                ),
                                child: Text(tr('Forgot password?')),
                              ),
                            ),
                          if (_register) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _invite,
                              decoration: InputDecoration(
                                hintText: tr('Invited by (optional username)'),
                                prefixIcon: const Icon(
                                  Icons.card_giftcard_rounded,
                                ),
                              ),
                            ),
                          ],
                          if (_register) ...[
                            const SizedBox(height: 10),
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() => _agree = !_agree),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Checkbox(
                                    value: _agree,
                                    onChanged: (v) =>
                                        setState(() => _agree = v ?? false),
                                  ),
                                  Expanded(
                                    child: Wrap(
                                      children: [
                                        Text(
                                          tr(
                                            "I'm 13 or older and agree to the ",
                                          ),
                                          style: small,
                                        ),
                                        GestureDetector(
                                          onTap: () => _showText(
                                            tr('Terms of service'),
                                            cfg.termsText,
                                          ),
                                          child: Text(
                                            tr('Terms'),
                                            style: small.copyWith(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text(tr(' and '), style: small),
                                        GestureDetector(
                                          onTap: () => _showText(
                                            tr('Privacy policy'),
                                            cfg.privacyText,
                                          ),
                                          child: Text(
                                            tr('Privacy policy'),
                                            style: small.copyWith(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          SizedBox(height: _register ? 12 : 8),
                          GradientButton(
                            label: _register
                                ? tr('Create account')
                                : tr('Sign in'),
                            busy: _busy,
                            onPressed: _submit,
                          ),
                          if (googleSignInEnabled &&
                              (cfg.registrationOpen || !_register)) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    tr('or'),
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (kIsWeb)
                              Center(child: googleWebButton(currentLanguage))
                            else
                              SizedBox(
                                height: 50,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    shape: const StadiumBorder(),
                                    side: BorderSide(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                  onPressed: _busy ? null : _google,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const _GoogleG(),
                                      const SizedBox(width: 12),
                                      Text(
                                        tr('Continue with Google'),
                                        style: TextStyle(
                                          color: scheme.onSurface,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                          const SizedBox(height: 14),
                          if (cfg.registrationOpen || _register)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _register
                                      ? tr('Already have an account?')
                                      : tr('New here?'),
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _register = !_register),
                                  child: Text(
                                    _register
                                        ? tr('Sign in')
                                        : tr('Create an account'),
                                  ),
                                ),
                              ],
                            ),
                          if (!_register && googleSignInEnabled)
                            Wrap(
                              alignment: WrapAlignment.center,
                              children: [
                                Text(
                                  tr('By continuing you agree to the '),
                                  style: small,
                                ),
                                GestureDetector(
                                  onTap: () => _showText(
                                    tr('Terms of service'),
                                    cfg.termsText,
                                  ),
                                  child: Text(
                                    tr('Terms'),
                                    style: small.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(tr(' and '), style: small),
                                GestureDetector(
                                  onTap: () => _showText(
                                    tr('Privacy policy'),
                                    cfg.privacyText,
                                  ),
                                  child: Text(
                                    tr('Privacy policy'),
                                    style: small.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 12),
                          Center(
                            child: TextButton.icon(
                              onPressed: () => showLanguagePicker(context, ref),
                              icon: const Icon(
                                Icons.language_rounded,
                                size: 16,
                              ),
                              label: Text(languages[currentLanguage]!),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 330),
                              child: TextButton.icon(
                                onPressed: () => showServerDialog(context, ref),
                                icon: Icon(
                                  Icons.dns_outlined,
                                  size: 15,
                                  color: scheme.onSurfaceVariant,
                                ),
                                label: Text(
                                  tr('Server: {0}', [
                                    Uri.parse(ref.read(apiProvider).server)
                                        .authority,
                                  ]),
                                  style: small,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Google's coloured "G" (drawn, so no image file is needed).
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 22,
    child: CustomPaint(painter: _GooglePainter()),
  );
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * .2;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s - stroke, s - stroke);
    Paint arc(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const deg = 3.14159265 / 180;
    canvas.drawArc(
      rect,
      -40 * deg,
      -100 * deg,
      false,
      arc(const Color(0xFFEA4335)),
    ); // red, top
    canvas.drawArc(
      rect,
      -140 * deg,
      -90 * deg,
      false,
      arc(const Color(0xFFFBBC05)),
    ); // yellow, left
    canvas.drawArc(
      rect,
      130 * deg,
      -100 * deg,
      false,
      arc(const Color(0xFF34A853)),
    ); // green, bottom
    canvas.drawArc(
      rect,
      30 * deg,
      -70 * deg,
      false,
      arc(const Color(0xFF4285F4)),
    ); // blue, right
    canvas.drawRect(
      Rect.fromLTWH(s / 2, s / 2 - stroke / 2, s / 2 - stroke / 4, stroke),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
