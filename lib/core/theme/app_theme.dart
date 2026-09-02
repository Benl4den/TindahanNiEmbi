import 'package:flutter/material.dart';

/// Shared visual foundation for every store workspace.
abstract final class AppTheme {
  static const primary = Color(0xFF176B3A);
  static const canvas = Color(0xFFF5F7F4);
  static const surface = Colors.white;
  static const outline = Color(0xFFDCE3DD);
  static const text = Color(0xFF17211A);
  static const mutedText = Color(0xFF5F6B63);

  static ThemeData get light {
    final colors = ColorScheme.fromSeed(seedColor: primary).copyWith(
      primary: primary,
      surface: surface,
      outline: outline,
      outlineVariant: const Color(0xFFE8ECE8),
      error: const Color(0xFFBA1A1A),
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    final textTheme = base.textTheme.copyWith(
      displaySmall: const TextStyle(
        fontSize: 36,
        height: 1.12,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: text,
      ),
      headlineSmall: const TextStyle(
        fontSize: 27,
        height: 1.2,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.35,
        color: text,
      ),
      titleLarge: const TextStyle(
        fontSize: 21,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      titleMedium: const TextStyle(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      bodyLarge: const TextStyle(fontSize: 17, height: 1.45, color: text),
      bodyMedium: const TextStyle(fontSize: 15, height: 1.4, color: mutedText),
      labelLarge: const TextStyle(
        fontSize: 16,
        height: 1.2,
        fontWeight: FontWeight.w700,
      ),
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
          fontWeight: FontWeight.w800,
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
          fontWeight: FontWeight.w800,
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
          fontWeight: FontWeight.w800,
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
                ? FontWeight.w800
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
        labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
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
}
