import 'package:flutter/material.dart';

/// Facare Direction B palette, shared by CareAI's presentation layer.
abstract final class CareAiColors {
  static const canvas = Color(0xFFFAF7F2);
  static const board = Color(0xFFF7F2EB);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF231811);
  static const brown = Color(0xFF4A3020);
  static const secondary = Color(0xFF7D7168);
  static const border = Color(0xFFE4DACD);
  static const muted = Color(0xFFF2ECE4);
  static const sage = Color(0xFF7A9850);
  static const moss = Color(0xFF9BB068);
  static const sageLight = Color(0xFFD5E2BE);
  static const greenSurface = Color(0xFFF0F4E4);
  static const greenInk = Color(0xFF456624);
  static const peach = Color(0xFFF8E5DC);
  static const lavender = Color(0xFFF0EEFA);
  static const lavenderInk = Color(0xFF645796);
  static const coral = Color(0xFFE25C4A);
  static const danger = Color(0xFFC93B2B);
  static const dangerSurface = Color(0xFFFFEDE7);
  static const amber = Color(0xFF916018);
}

abstract final class CareAiTheme {
  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: CareAiColors.brown,
          brightness: Brightness.light,
        ).copyWith(
          primary: CareAiColors.brown,
          onPrimary: Colors.white,
          secondary: CareAiColors.sage,
          onSecondary: CareAiColors.ink,
          surface: CareAiColors.surface,
          onSurface: CareAiColors.ink,
          onSurfaceVariant: CareAiColors.secondary,
          outline: CareAiColors.border,
          error: CareAiColors.danger,
          onError: Colors.white,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'BeVietnamPro',
      scaffoldBackgroundColor: CareAiColors.canvas,
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme.apply(
      bodyColor: CareAiColors.ink,
      displayColor: CareAiColors.ink,
    );
    return base.copyWith(
      textTheme: text.copyWith(
        headlineLarge: text.headlineLarge?.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          height: 1.25,
          letterSpacing: -0.8,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          height: 1.3,
          letterSpacing: -0.6,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          height: 1.3,
          letterSpacing: -0.4,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.55),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
        bodySmall: text.bodySmall?.copyWith(
          fontSize: 12,
          height: 1.5,
          color: CareAiColors.secondary,
        ),
        labelLarge: text.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: CareAiColors.canvas,
        foregroundColor: CareAiColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'BeVietnamPro',
          color: CareAiColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: CareAiColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CareAiColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        labelStyle: const TextStyle(
          color: CareAiColors.secondary,
          fontSize: 14,
        ),
        hintStyle: const TextStyle(color: CareAiColors.secondary),
        prefixIconColor: CareAiColors.brown,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: CareAiColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: CareAiColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: CareAiColors.brown, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: CareAiColors.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CareAiColors.brown,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: 'BeVietnamPro',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: CareAiColors.brown,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: 'BeVietnamPro',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CareAiColors.brown,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: CareAiColors.border),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: CareAiColors.brown,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontFamily: 'BeVietnamPro',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: CareAiColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: CareAiColors.muted,
        height: 80,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'BeVietnamPro',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? CareAiColors.brown
                : CareAiColors.secondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? CareAiColors.brown
                : CareAiColors.secondary,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: CareAiColors.border,
        thickness: 0.7,
        space: 24,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: CareAiColors.sage,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: CareAiColors.brown,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: CareAiColors.canvas,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          fontFamily: 'BeVietnamPro',
          fontSize: 20,
          height: 1.3,
          fontWeight: FontWeight.w800,
          color: CareAiColors.ink,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: CareAiColors.canvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
    );
  }
}
