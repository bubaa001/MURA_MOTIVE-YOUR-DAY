import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<ThemeMode> muraThemeMode =
    ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> setMuraThemeMode(ThemeMode mode) async {
  muraThemeMode.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('mura.theme_mode', mode.name);
}

Future<void> loadMuraThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString('mura.theme_mode');
  if (value == null) return;
  muraThemeMode.value = ThemeMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => ThemeMode.system,
  );
}

/// Obsidian + Amber design tokens.
///
/// Hex values come from stitch_zenith_discipline_app_ui/obsidian_amber/
/// DESIGN.md: a #131313 base with the #0e0e0e..#353534 container ramp, an
/// amber-gold primary family (#f59e0b seed / #ffc174 highlight), teal for
/// calm states, indigo for goals. No font assets are bundled - the Sora-like
/// display look is approximated with heavy default-font weights and tight
/// letter spacing, per project scope.
class MuraColors {
  const MuraColors._();

  // Surfaces (DESIGN.md color ramp).
  static const Color background = Color(0xFF131313);
  static const Color surfaceLowest = Color(0xFF0E0E0E);
  static const Color surfaceLow = Color(0xFF1C1B1B);
  static const Color surfaceContainer = Color(0xFF201F1F);
  static const Color surfaceHigh = Color(0xFF2A2A2A);
  static const Color surfaceHighest = Color(0xFF353534);

  // Ink on dark surfaces.
  static const Color onSurface = Color(0xFFE5E2E1);
  static const Color onSurfaceVariant = Color(0xFFD8C3AD);
  static const Color outline = Color(0xFFA08E7A);
  static const Color outlineVariant = Color(0xFF534434);

  // Amber family - energy, streaks, primary actions.
  static const Color primarySeed = Color(0xFFF59E0B);
  static const Color primary = Color(0xFFFFC174);
  static const Color primaryDim = Color(0xFFFFB95F);
  static const Color onPrimary = Color(0xFF472A00);
  static const Color primaryContainer = Color(0xFFF59E0B);
  static const Color onPrimaryContainer = Color(0xFF613B00);

  // Teal family - calm, prayer, reflection.
  static const Color secondary = Color(0xFF6BD8CB);
  static const Color onSecondary = Color(0xFF003732);
  static const Color secondaryContainer = Color(0xFF29A195);

  // Indigo family - long-term goals and intellectual pursuits.
  static const Color tertiary = Color(0xFFC7C8FF);
  static const Color onTertiary = Color(0xFF1000A9);
  static const Color tertiaryContainer = Color(0xFFA7A9FF);

  // Error.
  static const Color error = Color(0xFFFFB4AB);
  static const Color onError = Color(0xFF690005);

  /// Glass hairline - DESIGN.md cards carry a 10% white top border.
  static const Color glassBorder = Color(0x1AFFFFFF);
}

/// Per-page palette that follows the active theme, so screens render true
/// Obsidian & Amber in dark mode and a warm paper/amber brand in light mode
/// instead of staying permanently dark.
class MuraPalette {
  const MuraPalette({
    required this.bg,
    required this.card,
    required this.cardAlt,
    required this.cardHi,
    required this.field,
    required this.amber,
    required this.amberDeep,
    required this.onAmber,
    required this.text,
    required this.textDim,
    required this.outline,
    required this.stroke,
    required this.teal,
    required this.coral,
  });

  final Color bg;
  final Color card;
  final Color cardAlt;
  final Color cardHi;
  final Color field;
  final Color amber;
  final Color amberDeep;
  final Color onAmber;
  final Color text;
  final Color textDim;
  final Color outline;
  final Color stroke;
  final Color teal;
  final Color coral;

  static const MuraPalette dark = MuraPalette(
    bg: Color(0xFF0D0B09),
    card: Color(0xFF17120D),
    cardAlt: Color(0xFF241D15),
    cardHi: Color(0xFF221A11),
    field: Color(0xFF241C12),
    amber: Color(0xFFFFC174),
    amberDeep: Color(0xFFF59E0B),
    onAmber: Color(0xFF472A00),
    text: Color(0xFFE5E2E1),
    textDim: Color(0xFFA08E7A),
    outline: Color(0xFF534434),
    stroke: Color(0x16FFFFFF),
    teal: Color(0xFF6BD8CB),
    coral: Color(0xFFFF8A80),
  );

  static const MuraPalette light = MuraPalette(
    bg: Color(0xFFFFF9F4),
    card: Color(0xFFFFFFFF),
    cardAlt: Color(0xFFF7EDE1),
    cardHi: Color(0xFFF2E7DA),
    field: Color(0xFFF2E9DF),
    amber: Color(0xFFB4730A),
    amberDeep: Color(0xFFF59E0B),
    onAmber: Color(0xFF472A00),
    text: Color(0xFF241A12),
    textDim: Color(0xFF6E5C49),
    outline: Color(0xFFD9C2AD),
    stroke: Color(0xFFE3BC83),
    teal: Color(0xFF00695C),
    coral: Color(0xFFB3261E),
  );

  static MuraPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Corner radii: cards sit in the 16-20 range, controls at 16 (DESIGN.md
/// buttons/inputs use 16).
const double kCardRadius = 18.0;
const double kControlRadius = 16.0;

/// Builds the app-wide dark Material 3 theme from the tokens above.
ThemeData buildMuraTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: MuraColors.primarySeed,
    brightness: Brightness.dark,
  ).copyWith(
    surface: MuraColors.background,
    onSurface: MuraColors.onSurface,
    onSurfaceVariant: MuraColors.onSurfaceVariant,
    surfaceContainerLowest: MuraColors.surfaceLowest,
    surfaceContainerLow: MuraColors.surfaceLow,
    surfaceContainer: MuraColors.surfaceContainer,
    surfaceContainerHigh: MuraColors.surfaceHigh,
    surfaceContainerHighest: MuraColors.surfaceHighest,
    outline: MuraColors.outline,
    outlineVariant: MuraColors.outlineVariant,
    primary: MuraColors.primary,
    onPrimary: MuraColors.onPrimary,
    primaryContainer: MuraColors.primaryContainer,
    onPrimaryContainer: MuraColors.onPrimaryContainer,
    secondary: MuraColors.secondary,
    onSecondary: MuraColors.onSecondary,
    secondaryContainer: MuraColors.secondaryContainer,
    tertiary: MuraColors.tertiary,
    onTertiary: MuraColors.onTertiary,
    tertiaryContainer: MuraColors.tertiaryContainer,
    error: MuraColors.error,
    onError: MuraColors.onError,
  );

  // Sora-flavored type scale using the default font family: extra-bold
  // display/stat weights with tightened tracking (DESIGN.md typography).
  final TextTheme base = ThemeData.dark(useMaterial3: true).textTheme;
  final TextTheme textTheme = base.copyWith(
    displayLarge: base.displayLarge
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.0),
    displayMedium: base.displayMedium
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
    displaySmall: base.displaySmall
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
    headlineLarge: base.headlineLarge
        ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
    headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: base.labelLarge
        ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.7),
    labelMedium: base.labelMedium
        ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5),
  );

  OutlineInputBorder fieldBorder(Color? side) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(kControlRadius),
        borderSide: side == null ? BorderSide.none : BorderSide(color: side),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: MuraColors.background,
    canvasColor: MuraColors.background,
    textTheme: textTheme,
    iconTheme: const IconThemeData(color: MuraColors.onSurfaceVariant),
    appBarTheme: AppBarTheme(
      backgroundColor: MuraColors.background,
      foregroundColor: MuraColors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: MuraColors.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        side: const BorderSide(color: MuraColors.glassBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MuraColors.surfaceLow,
      hintStyle: const TextStyle(color: MuraColors.outline),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: fieldBorder(null),
      enabledBorder: fieldBorder(null),
      focusedBorder: fieldBorder(MuraColors.primaryDim),
      errorBorder: fieldBorder(MuraColors.error),
      focusedErrorBorder: fieldBorder(MuraColors.error),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MuraColors.primaryContainer,
        foregroundColor: MuraColors.onPrimaryContainer,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kControlRadius),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MuraColors.primaryContainer,
        foregroundColor: MuraColors.onPrimaryContainer,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kControlRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MuraColors.primary,
        side: const BorderSide(color: MuraColors.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kControlRadius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: MuraColors.primary),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: MuraColors.surfaceHigh,
      selectedColor: MuraColors.primaryContainer,
      labelStyle: const TextStyle(color: MuraColors.onSurface),
      side: const BorderSide(color: MuraColors.outlineVariant),
      shape: const StadiumBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      elevation: 0,
      backgroundColor: MuraColors.surfaceLow.withAlpha(235),
      indicatorColor: MuraColors.primary.withAlpha(41),
      iconTheme: const WidgetStatePropertyAll(
        IconThemeData(color: MuraColors.onSurfaceVariant),
      ),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: MuraColors.onSurfaceVariant,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: MuraColors.surfaceHighest,
      contentTextStyle: const TextStyle(color: MuraColors.onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kControlRadius),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: MuraColors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: MuraColors.surfaceContainer,
      modalBackgroundColor: MuraColors.surfaceContainer,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: MuraColors.onSurfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kControlRadius),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: MuraColors.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MuraColors.primary,
      linearTrackColor: MuraColors.surfaceHigh,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: MuraColors.primaryContainer,
      foregroundColor: MuraColors.onPrimaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kControlRadius),
      ),
    ),
  );
}

ThemeData buildMuraLightTheme() {
  // Brand amber seed (#f59e0b) so every generated tone stays in the
  // Obsidian & Amber family, with primary darkened for light-surface contrast.
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFF59E0B),
    brightness: Brightness.light,
  ).copyWith(
    primary: const Color(0xFF785A00),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFFFC174),
    onPrimaryContainer: const Color(0xFF472A00),
    secondary: const Color(0xFF6B5D52),
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFF4E0D2),
    onSecondaryContainer: const Color(0xFF261A10),
    tertiary: const Color(0xFF3C617B),
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFCFE5FF),
    surface: const Color(0xFFFFF9F4),
    onSurface: const Color(0xFF201A15),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFFAF1E9),
    surfaceContainer: const Color(0xFFFFFFFF),
    surfaceContainerHigh: const Color(0xFFF2E8DC),
    surfaceContainerHighest: const Color(0xFFE9DED1),
    onSurfaceVariant: const Color(0xFF534335),
    outline: const Color(0xFF857362),
    outlineVariant: const Color(0xFFD9C2AD),
    error: const Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF410002),
  );
  final base = ThemeData.light(useMaterial3: true).textTheme;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    textTheme: base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.6,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.4,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: .7,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: .5,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: base.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        side: const BorderSide(color: Color(0xFFE3BC83), width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      hintStyle: TextStyle(color: scheme.outline),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kControlRadius),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kControlRadius),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      backgroundColor: scheme.surface.withAlpha(235),
      indicatorColor: scheme.primary.withAlpha(35),
      iconTheme: WidgetStatePropertyAll(
        IconThemeData(color: scheme.onSurfaceVariant),
      ),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kControlRadius),
      ),
    ),
  );
}
