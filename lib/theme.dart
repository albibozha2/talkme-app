import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'i18n.dart';

/// Brand palette. Emerald primary with an amber accent; deep green-black for dark surfaces.
abstract final class AppColors {
  static const emerald = Color(0xFF14A37F);
  static const emeraldLight = Color(0xFF1FBF8F);
  static const emeraldDeep = Color(0xFF0D6E54);
  static const amber = Color(0xFFFFB020);
  static const amberDeep = Color(0xFFFF8A00);
  static const like = Color(0xFFFF3B5C);
  static const live = Color(0xFFFF2E63);
  static const ink = Color(0xFF0B0F0E);
  static const inkSurface = Color(0xFF141A18);
  static const inkHigh = Color(0xFF1C2421);
  static const mist = Color(0xFFF4F8F7);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [emeraldLight, emeraldDeep],
  );
  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFD45E), amberDeep],
  );
  static const liveGradient = LinearGradient(colors: [Color(0xFFFF5F6D), live]);
}

/// Status/navigation bar style for dark full-screen pages (feed, live, camera).
const darkSystemUi = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.black,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarDividerColor: Colors.transparent,
);

/// Status/navigation bar style that matches a normal themed page.
SystemUiOverlayStyle systemUiFor(ThemeData theme) {
  final dark = theme.brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: theme.brightness,
    systemNavigationBarColor: theme.colorScheme.surface,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: AppColors.emerald,
    brightness: brightness,
  );
  final scheme = base.copyWith(
    primary: dark ? AppColors.emeraldLight : AppColors.emerald,
    onPrimary: Colors.white,
    secondary: AppColors.amber,
    onSecondary: AppColors.ink,
    surface: dark ? AppColors.ink : Colors.white,
    surfaceContainerLowest: dark ? AppColors.ink : Colors.white,
    surfaceContainerLow: dark ? AppColors.inkSurface : AppColors.mist,
    surfaceContainer: dark ? AppColors.inkSurface : const Color(0xFFEFF4F2),
    surfaceContainerHigh: dark ? AppColors.inkHigh : const Color(0xFFE8EFEC),
    surfaceContainerHighest: dark
        ? const Color(0xFF26302C)
        : const Color(0xFFE1E9E6),
    error: AppColors.like,
  );
  final text = ThemeData(brightness: brightness, fontFamily: 'Poppins')
      .textTheme
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  final radius = BorderRadius.circular(16);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Poppins',
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.5,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.3,
      ),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: brightness,
      ),
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 17,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: .35),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: .7),
      ),
      // Keep icons neutral (Material turns them red on validation errors).
      prefixIconColor: WidgetStateColor.resolveWith(
        (s) => s.contains(WidgetState.focused) && !s.contains(WidgetState.error)
            ? scheme.primary
            : scheme.onSurfaceVariant,
      ),
      suffixIconColor: scheme.onSurfaceVariant,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainer,
      labelStyle: TextStyle(
        fontFamily: 'Poppins',
        color: scheme.onSurface,
        fontWeight: FontWeight.w500,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .4),
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: const TextStyle(
        fontFamily: 'Poppins',
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: 'Poppins',
        fontWeight: FontWeight.w500,
        fontSize: 15,
      ),
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
    ),
  );
}

/// "1 follower", "12 followers", "1.2K followers".
String plural(int n, String word) {
  final sq = currentLanguage == 'sq' ? _sqPlurals[word] : null;
  final w = sq != null
      ? (n == 1 ? sq.$1 : sq.$2)
      : (n == 1 ? word : '${word}s');
  return '${compactCount(n)} $w';
}

const _sqPlurals = {
  'comment': ('koment', 'komente'),
  'follower': ('ndjekës', 'ndjekës'),
  'post': ('postim', 'postime'),
  'like': ('pëlqim', 'pëlqime'),
  'view': ('shikim', 'shikime'),
  'video': ('video', 'video'),
  'viewer': ('shikues', 'shikues'),
};

String compactCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)}K';
  return '${(n / 1000000).toStringAsFixed(1)}M';
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return tr('now');
  if (d.inHours < 1) return tr('{0}m ago', [d.inMinutes]);
  if (d.inDays < 1) return tr('{0}h ago', [d.inHours]);
  if (d.inDays < 7) return tr('{0}d ago', [d.inDays]);
  final months = [
    tr('Jan'),
    tr('Feb'),
    tr('Mar'),
    tr('Apr'),
    tr('May'),
    tr('Jun'),
    tr('Jul'),
    tr('Aug'),
    tr('Sep'),
    tr('Oct'),
    tr('Nov'),
    tr('Dec'),
  ];
  final local = t.toLocal();
  return '${local.day} ${months[local.month - 1]}${local.year != DateTime.now().year ? ' ${local.year}' : ''}';
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
