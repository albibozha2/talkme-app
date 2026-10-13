import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'config.dart';
import 'models.dart';
import 'push.dart';
import 'screens/auth_screen.dart';
import 'screens/server_dialog.dart';
import 'screens/home_shell.dart';
import 'state.dart';
import 'theme.dart';
import 'updater.dart';
import 'widgets/common.dart';
import 'widgets/intro_splash.dart';
import 'video_cache.dart';
import 'i18n.dart';

import 'package:flutter/foundation.dart';

import 'diagnostics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    if (!kIsWeb) VideoCache.instance.start(),
    Api.loadServer(),
    loadLanguage(),
  ]);
  await Diagnostics.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // No automatic retries: show the error screen with a "Try again" button instead of loading forever.
  runApp(ProviderScope(retry: (_, _) => null, child: const App()));
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(remoteConfigProvider).value?.appName ?? 'TalkMe';
    final lang = ref.watch(languageProvider);
    return MaterialApp(
      // A new key rebuilds every screen in the new language.
      key: ValueKey(lang),
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('sq')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      title: name,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      navigatorKey: navigatorKey,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      // Transparent status bar and a navigation bar that matches each page.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemUiFor(Theme.of(context)),
        child: kIsWeb ? _WebFrame(child: child!) : child!,
      ),
      home: const _StartUp(),
    );
  }
}

/// The app behind the animated welcome splash, which fades away once the app has loaded
/// (shown for at least ~2 seconds so it never just flashes, at most 6).
class _StartUp extends ConsumerStatefulWidget {
  const _StartUp();

  @override
  ConsumerState<_StartUp> createState() => _StartUpState();
}

class _StartUpState extends ConsumerState<_StartUp> {
  bool _minShown = false, _gone = false, _hide = false;
  Timer? _min, _max;

  @override
  void initState() {
    super.initState();
    _min = Timer(const Duration(milliseconds: 2100), () {
      if (mounted) setState(() => _minShown = true);
    });
    _max = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _hide = true);
    });
  }

  @override
  void dispose() {
    _min?.cancel();
    _max?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading =
        ref.watch(remoteConfigProvider).isLoading ||
        ref.watch(sessionProvider).isLoading;
    final hide = _hide || (_minShown && !loading);
    return Stack(
      children: [
        const _Gate(),
        if (!_gone)
          IgnorePointer(
            ignoring: hide,
            child: AnimatedOpacity(
              opacity: hide ? 0 : 1,
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeOut,
              onEnd: () {
                if (hide && mounted) setState(() => _gone = true);
              },
              child: const IntroSplash(),
            ),
          ),
      ],
    );
  }
}

/// Decides what to show: maintenance / update-required / sign-in / the app.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(remoteConfigProvider);
    final session = ref.watch(sessionProvider);

    return config.when(
      loading: () => const _Splash(),
      error: (e, _) => _Message(
        icon: Icons.wifi_off_rounded,
        title: tr("Can't connect"),
        body: tr('{0}\n\nServer: {1}', [e, ref.read(apiProvider).server]),
        action: (tr('Try again'), () => ref.invalidate(remoteConfigProvider)),
        secondary: (tr('Change server'), () => showServerDialog(context, ref)),
      ),
      data: (cfg) {
        if (isVersionTooOld(AppConfig.appVersion, cfg.minAppVersion)) {
          return _Message(
            icon: Icons.system_update_rounded,
            title: tr('Update required'),
            body: tr(
              'This version is no longer supported. Update to keep using the app.',
            ),
            action: (tr('Update now'), () => checkForUpdates(context, ref)),
          );
        }
        return session.when(
          loading: () => const _Splash(),
          error: (e, _) => _Message(
            icon: Icons.wifi_off_rounded,
            title: tr("Can't connect"),
            body: '$e',
            action: (tr('Try again'), () => ref.invalidate(sessionProvider)),
          ),
          data: (user) {
            if (user == null) return AuthScreen(config: cfg);
            // Staff can keep using the app during maintenance to check things.
            if (cfg.maintenance && !user.isStaff) return _maintenance(ref, cfg);
            return const HomeShell();
          },
        );
      },
    );
  }

  Widget _maintenance(WidgetRef ref, RemoteConfig cfg) => _Message(
    icon: Icons.construction_rounded,
    title: tr('Back soon'),
    body: cfg.maintenanceMessage,
    action: (tr('Check again'), () => ref.invalidate(remoteConfigProvider)),
  );
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: const Center(child: BrandMark(size: 84)));
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.secondary,
  });
  final IconData icon;
  final String title, body;
  final (String, VoidCallback)? action, secondary;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .12),
              child: Icon(
                icon,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 24),
              GradientButton(label: action!.$1, onPressed: action!.$2),
            ],
            if (secondary != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: secondary!.$2, child: Text(secondary!.$1)),
            ],
          ],
        ),
      ),
    ),
  );
}

/// On wide screens (computers) the web app shows as a phone-sized column in the middle.
class _WebFrame extends StatelessWidget {
  const _WebFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width < 600) return child;
    const width = 440.0;
    return ColoredBox(
      color: const Color(0xFF05080C),
      child: Center(
        child: Container(
          width: width,
          height: (size.height - 32).clamp(500, 940).toDouble(),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white12),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 40)],
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: Size(width, (size.height - 32).clamp(500, 940).toDouble()),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
