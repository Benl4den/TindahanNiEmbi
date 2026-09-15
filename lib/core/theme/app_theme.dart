import 'package:flutter/material.dart';

/// Semantic colours kept out of Material's generic [ColorScheme].
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.sidebar,
    required this.surfaceContainer,
    required this.surfaceElevated,
    required this.inputBackground,
    required this.success,
    required this.warning,
    required this.danger,
    required this.utang,
    required this.textDisabled,
  });
  final Color sidebar, surfaceContainer, surfaceElevated, inputBackground;
  final Color success, warning, danger, utang, textDisabled;

  @override
  AppSemanticColors copyWith({
    Color? sidebar,
    Color? surfaceContainer,
    Color? surfaceElevated,
    Color? inputBackground,
    Color? success,
    Color? warning,
    Color? danger,
    Color? utang,
    Color? textDisabled,
  }) => AppSemanticColors(
    sidebar: sidebar ?? this.sidebar,
    surfaceContainer: surfaceContainer ?? this.surfaceContainer,
    surfaceElevated: surfaceElevated ?? this.surfaceElevated,
    inputBackground: inputBackground ?? this.inputBackground,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    utang: utang ?? this.utang,
    textDisabled: textDisabled ?? this.textDisabled,
  );

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other is! AppSemanticColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppSemanticColors(
      sidebar: c(sidebar, other.sidebar),
      surfaceContainer: c(surfaceContainer, other.surfaceContainer),
      surfaceElevated: c(surfaceElevated, other.surfaceElevated),
      inputBackground: c(inputBackground, other.inputBackground),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      utang: c(utang, other.utang),
      textDisabled: c(textDisabled, other.textDisabled),
    );
  }
}

extension AppThemeContext on BuildContext {
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>() ?? AppTheme.lightSemantic;
}

/// Shared visual foundation for every store workspace.
abstract final class AppTheme {
  static const primary = Color(0xFF0F6B46);
  static const mint = Color(0xFFA7D7B4);
  static const canvas = Color(0xFFF8FAF9);
  static const surface = Colors.white;
  static const outline = Color(0xFFDCE3DD);
  static const text = Color(0xFF1F2D28);
  static const mutedText = Color(0xFF5F6B63);
  static const lightSemantic = AppSemanticColors(
    sidebar: Color(0xFFFAFCFB),
    surfaceContainer: Color(0xFFF0F4F0),
    surfaceElevated: Color(0xFFFFFFFF),
    inputBackground: Color(0xFFFFFFFF),
    success: primary,
    warning: Color(0xFFB36B00),
    danger: Color(0xFFBA1A1A),
    utang: Color(0xFFC16E20),
    textDisabled: Color(0xFF7A847D),
  );

  /// Shared typography for light and dark themes. Colours are supplied by
  /// each theme; hierarchy and Inter weights stay identical everywhere.
  static TextTheme _typography(
    TextTheme base, {
    required Color primaryText,
    required Color secondaryText,
  }) => base
      .apply(
        fontFamily: 'Inter',
        bodyColor: primaryText,
        displayColor: primaryText,
      )
      .copyWith(
        displaySmall: TextStyle(
          fontSize: 28,
          height: 1.15,
          fontWeight: FontWeight.w700,
          letterSpacing: -.45,
          color: primaryText,
        ),
        headlineSmall: TextStyle(
          fontSize: 26,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -.3,
          color: primaryText,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: primaryText,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: primaryText,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: primaryText),
        bodyMedium: TextStyle(fontSize: 15, height: 1.45, color: secondaryText),
        bodySmall: TextStyle(fontSize: 14, height: 1.4, color: secondaryText),
        labelLarge: TextStyle(
          fontSize: 16,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: primaryText,
        ),
        labelMedium: TextStyle(
          fontSize: 14,
          height: 1.25,
          fontWeight: FontWeight.w500,
          color: secondaryText,
        ),
        labelSmall: TextStyle(
          fontSize: 12,
          height: 1.25,
          fontWeight: FontWeight.w500,
          color: secondaryText,
        ),
      );

  static ThemeData get light {
    final colors = ColorScheme.fromSeed(seedColor: primary).copyWith(
      primary: primary,
      surface: surface,
      outline: outline,
      outlineVariant: const Color(0xFFE8ECE8),
      error: const Color(0xFFBA1A1A),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: 'Inter',
    );
    final textTheme = _typography(
      base.textTheme,
      primaryText: text,
      secondaryText: mutedText,
    );

    ButtonStyle buttonStyle({required bool outlined}) => ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevation: const WidgetStatePropertyAll(0),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return mutedText;
        return outlined ? primary : null;
      }),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? const Color(0xFFE2E7E3)
            : null,
      ),
      side: outlined
          ? WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? const Color(0xFFB8C0BA)
                    : const Color(0xFFB7C6BA),
              ),
            )
          : null,
    );

    return base.copyWith(
      extensions: const [lightSemantic],
      scaffoldBackgroundColor: canvas,
      textTheme: textTheme,
      dividerColor: outline,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        shape: Border(bottom: BorderSide(color: outline)),
        iconTheme: IconThemeData(size: 25, color: text),
        actionsIconTheme: IconThemeData(size: 25, color: text),
        titleTextStyle: TextStyle(
          fontSize: 23,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: textTheme.titleLarge,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: buttonStyle(outlined: false),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttonStyle(outlined: true),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 2,
        focusElevation: 3,
        highlightElevation: 3,
        shape: StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: const TextStyle(fontSize: 16, color: mutedText),
        hintStyle: const TextStyle(fontSize: 16, color: Color(0xFF7A847D)),
        prefixIconColor: mutedText,
        suffixIconColor: mutedText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: const Color(0xFFDCEEDF),
        disabledColor: const Color(0xFFE7EBE8),
        checkmarkColor: primary,
        iconTheme: const IconThemeData(color: primary, size: 19),
        side: const BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: text,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        iconColor: mutedText,
        minTileHeight: 60,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(Color(0xFFF0F4F0)),
        headingTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: text,
        ),
        dataTextStyle: TextStyle(fontSize: 15, color: text),
        dividerThickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF26342B),
        contentTextStyle: const TextStyle(fontSize: 15, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFFDCEEDF),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          ),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: mutedText,
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF26342B),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Charcoal green: neutral large surfaces, with green reserved for emphasis.
  static ThemeData get dark {
    const background = Color(0xFF141816), surface = Color(0xFF1B211F);
    const container = Color(0xFF222927), elevated = Color(0xFF2A3230);
    const input = Color(0xFF202725), border = Color(0xFF36403C);
    const primary = Color(0xFF2FA66F), bright = Color(0xFF39B77B);
    const muted = Color(0xFF245D47), onSurface = Color(0xFFF4F6F5);
    const secondary = Color(0xFFB7BFBB), disabled = Color(0xFF7A8580);
    final colors =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: primary,
          onPrimary: const Color(0xFF061C11),
          primaryContainer: muted,
          onPrimaryContainer: onSurface,
          surface: surface,
          onSurface: onSurface,
          surfaceContainer: container,
          surfaceContainerHighest: elevated,
          outline: border,
          outlineVariant: border,
          error: const Color(0xFFD9534F),
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: 'Inter',
    );
    final textTheme = _typography(
      base.textTheme,
      primaryText: onSurface,
      secondaryText: secondary,
    );
    ButtonStyle buttonStyle({required bool outlined}) => ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevation: const WidgetStatePropertyAll(0),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? disabled
            : outlined
            ? primary
            : null,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? container : null,
      ),
      side: outlined
          ? WidgetStateProperty.resolveWith(
              (s) => BorderSide(
                color: s.contains(WidgetState.disabled) ? disabled : border,
              ),
            )
          : null,
    );
    return base.copyWith(
      extensions: const [
        AppSemanticColors(
          sidebar: Color(0xFF18201D),
          surfaceContainer: container,
          surfaceElevated: elevated,
          inputBackground: input,
          success: primary,
          warning: Color(0xFFD89B3C),
          danger: Color(0xFFD9534F),
          utang: Color(0xFFF39C4A),
          textDisabled: disabled,
        ),
      ],
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      dividerColor: border,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        shape: Border(bottom: BorderSide(color: border)),
      ),
      cardTheme: CardThemeData(
        color: elevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: textTheme.titleLarge,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: buttonStyle(outlined: false),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttonStyle(outlined: true),
      ),
      textButtonTheme: light.textButtonTheme,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input,
        // Match light mode's style inheritance during animated theme changes.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: const TextStyle(fontSize: 16, color: secondary),
        hintStyle: const TextStyle(fontSize: 16, color: disabled),
        prefixIconColor: secondary,
        suffixIconColor: secondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: bright, width: 2),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: elevated,
        selectedColor: muted,
        disabledColor: container,
        checkmarkColor: bright,
        iconTheme: const IconThemeData(color: bright, size: 19),
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: bright,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        iconColor: secondary,
        minTileHeight: 60,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(container),
        headingTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        dataTextStyle: TextStyle(fontSize: 15, color: onSurface),
        dividerThickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: elevated,
        contentTextStyle: const TextStyle(fontSize: 15, color: onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: bright),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: muted,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: bright,
        unselectedLabelColor: secondary,
        indicatorColor: bright,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: const TextStyle(color: onSurface, fontSize: 14),
        decoration: BoxDecoration(
          color: elevated,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
