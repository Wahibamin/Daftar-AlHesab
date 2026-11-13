import 'package:flutter/material.dart';

/// RAF ERP & Inventory Management Design System.
///
/// **Visual Language:** Bright / Clean / Official / Minimalist.
/// Designed specifically for financial and inventory management applications where
/// high clarity, rapid data scannability, and calm contrast are paramount.
abstract final class RafColors {
  // ---------------------------------------------------------------------------
  // Canvas & Surfaces
  // ---------------------------------------------------------------------------

  /// Pure crisp white canvas for all primary routes, views, and containers.
  static const Color background = Color(0xFFFFFFFF);

  /// Primary surface color for cards, dialogs, and sheets.
  static const Color surface = Color(0xFFFFFFFF);

  /// Subtle soft slate-gray tint for secondary surfaces, headers, and backgrounds.
  static const Color surfaceSecondary = Color(0xFFF8FAFC);

  /// Hover and press state surface tint.
  static const Color surfaceHighlight = Color(0xFFF1F5F9);

  // ---------------------------------------------------------------------------
  // Functional Brand & Palette
  // ---------------------------------------------------------------------------

  /// Calm dark navy teal — authoritative, calm, and trustworthy.
  static const Color primary = Color(0xFF0F766E);

  /// Light tint of primary for subtle accents and badges.
  static const Color primarySubtle = Color(0xFFF0FDFA);

  /// Hover/Pressed variant of primary.
  static const Color primaryHover = Color(0xFF115E59);

  /// Soft dark slate gray for secondary actions and structural chrome.
  static const Color secondary = Color(0xFF334155);

  /// Slate 50 background for secondary tags.
  static const Color secondarySubtle = Color(0xFFF8FAFC);

  /// Accounting success green — calm and legible for credits, profits, and paid invoices.
  static const Color success = Color(0xFF15803D);

  /// Soft green background for success pills and badges.
  static const Color successSubtle = Color(0xFFF0FDF4);

  /// Border for success indicators.
  static const Color successBorder = Color(0xFFBBF7D0);

  /// Calm warning red — controlled and official for debits, debts, and errors.
  static const Color danger = Color(0xFFB91C1C);

  /// Soft red background for danger pills and badges.
  static const Color dangerSubtle = Color(0xFFFEF2F2);

  /// Border for danger indicators.
  static const Color dangerBorder = Color(0xFFFECACA);

  /// Amber orange for pending statuses, low stock alerts, and warnings.
  static const Color warning = Color(0xFFB45309);

  /// Soft amber background for warning pills and badges.
  static const Color warningSubtle = Color(0xFFFFFBEB);

  /// Border for warning indicators.
  static const Color warningBorder = Color(0xFFFDE68A);

  /// Very light structural gray (1px) for clean data grids, inputs, and cards.
  static const Color border = Color(0xFFE2E8F0);

  /// Slightly stronger border for focused active states.
  static const Color borderStrong = Color(0xFFCBD5E1);

  /// Standard divider line color.
  static const Color divider = Color(0xFFE2E8F0);

  // ---------------------------------------------------------------------------
  // Typography Hierarchy Colors
  // ---------------------------------------------------------------------------

  /// Deep slate 900 for high readability on white backgrounds.
  static const Color textPrimary = Color(0xFF0F172A);

  /// Slate 600 for secondary text, labels, and table headers.
  static const Color textSecondary = Color(0xFF475569);

  /// Slate 400 for placeholders, hints, and disabled elements.
  static const Color textMuted = Color(0xFF94A3B8);

  /// White text on dark buttons.
  static const Color textInverse = Color(0xFFFFFFFF);
}

/// Spacing and metric tokens for RAF ERP.
abstract final class RafSpacing {
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
}

/// Radii tokens emphasizing clean, subtle curves (Flat/Minimalist).
abstract final class RafRadius {
  static const double xs = 4.0;
  static const double sm = 6.0;
  static const double md = 8.0;
  static const double lg = 10.0;
  static const double xl = 12.0;
  static const double pill = 999.0;

  static const BorderRadius roundedXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius roundedSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius roundedMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius roundedLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius roundedXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius roundedPill = BorderRadius.all(
    Radius.circular(pill),
  );
}

/// Subtle shadow tokens adhering to the flat/minimalist ERP specification.
abstract final class RafShadows {
  /// Zero elevation.
  static const List<BoxShadow> none = [];

  /// Extremely subtle card elevation (0.04 alpha).
  static const List<BoxShadow> subtle = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  /// Elevated popover or modal shadow.
  static const List<BoxShadow> elevated = [
    BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 4)),
  ];
}

/// Typography scale optimized for Arabic RTL and numerical ERP data.
abstract final class RafTypography {
  static const String fontFamily = 'Cairo';

  static const List<String> fontFallbacks = [
    'Cairo',
    'Tajawal',
    'Segoe UI',
    'Roboto',
    'sans-serif',
  ];

  static const TextStyle display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: RafColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.3,
  );

  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: RafColors.textPrimary,
    height: 1.3,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: RafColors.textPrimary,
    height: 1.3,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: RafColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: RafColors.textSecondary,
    height: 1.5,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: RafColors.textMuted,
    height: 1.4,
  );

  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: RafColors.textSecondary,
    height: 1.3,
  );

  static const TextStyle titleSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: RafColors.textPrimary,
    height: 1.3,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: RafColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: RafColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: RafColors.textSecondary,
    height: 1.4,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: RafColors.textSecondary,
    height: 1.3,
  );

  /// Tabular font style for monetary values to guarantee numerical alignment.
  static const TextStyle financialAmount = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: RafColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Emphasized balance display.
  static const TextStyle financialHero = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: RafColors.primary,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// Official status badges and card decorations for financial tables.
abstract final class RafDecorations {
  /// Base clean card decoration with 1px border.
  static final BoxDecoration card = BoxDecoration(
    color: RafColors.surface,
    borderRadius: RafRadius.roundedMd,
    border: Border.all(color: RafColors.border, width: 1.0),
    boxShadow: RafShadows.subtle,
  );

  /// Flat card decoration without shadow.
  static final BoxDecoration cardFlat = BoxDecoration(
    color: RafColors.surface,
    borderRadius: RafRadius.roundedMd,
    border: Border.all(color: RafColors.border, width: 1.0),
  );

  /// Secondary surface panel decoration (e.g. Filter bar or summary strip).
  static final BoxDecoration panelSecondary = BoxDecoration(
    color: RafColors.surfaceSecondary,
    borderRadius: RafRadius.roundedMd,
    border: Border.all(color: RafColors.border, width: 1.0),
  );

  /// Status badge decoration: Success (Paid, Available).
  static final BoxDecoration badgeSuccess = BoxDecoration(
    color: RafColors.successSubtle,
    borderRadius: RafRadius.roundedPill,
    border: Border.all(color: RafColors.successBorder, width: 1.0),
  );

  /// Status badge decoration: Danger (Overdue, Out of Stock, Deficit).
  static final BoxDecoration badgeDanger = BoxDecoration(
    color: RafColors.dangerSubtle,
    borderRadius: RafRadius.roundedPill,
    border: Border.all(color: RafColors.dangerBorder, width: 1.0),
  );

  /// Status badge decoration: Warning (Pending, Low Stock).
  static final BoxDecoration badgeWarning = BoxDecoration(
    color: RafColors.warningSubtle,
    borderRadius: RafRadius.roundedPill,
    border: Border.all(color: RafColors.warningBorder, width: 1.0),
  );

  /// Status badge decoration: Neutral/Draft.
  static final BoxDecoration badgeNeutral = BoxDecoration(
    color: RafColors.surfaceSecondary,
    borderRadius: RafRadius.roundedPill,
    border: Border.all(color: RafColors.border, width: 1.0),
  );

  /// Status badge decoration: Primary Active.
  static final BoxDecoration badgePrimary = BoxDecoration(
    color: RafColors.primarySubtle,
    borderRadius: RafRadius.roundedPill,
    border: Border.all(color: const Color(0xFF99F6E4), width: 1.0),
  );
}

/// Central Theme Definition for the RAF Management Engine.
class RafTheme {
  const RafTheme._();

  /// Constructs the official Bright & Clean light theme for RAF.
  static ThemeData get lightTheme {
    const textTheme = TextTheme(
      displayLarge: RafTypography.display,
      titleLarge: RafTypography.titleLarge,
      titleMedium: RafTypography.titleMedium,
      bodyLarge: RafTypography.body,
      bodyMedium: RafTypography.bodySecondary,
      bodySmall: RafTypography.caption,
      labelLarge: RafTypography.label,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: RafTypography.fontFamily,
      fontFamilyFallback: RafTypography.fontFallbacks,
      scaffoldBackgroundColor: RafColors.background,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: RafColors.primary,
        onPrimary: RafColors.textInverse,
        primaryContainer: RafColors.primarySubtle,
        onPrimaryContainer: RafColors.primary,
        secondary: RafColors.secondary,
        onSecondary: RafColors.textInverse,
        secondaryContainer: RafColors.surfaceSecondary,
        onSecondaryContainer: RafColors.secondary,
        surface: RafColors.surface,
        onSurface: RafColors.textPrimary,
        error: RafColors.danger,
        onError: RafColors.textInverse,
        outline: RafColors.border,
        outlineVariant: RafColors.surfaceHighlight,
      ),

      // Minimalist, uncluttered AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: RafColors.surface,
        foregroundColor: RafColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 56.0,
        shape: Border(bottom: BorderSide(color: RafColors.border, width: 1.0)),
        iconTheme: IconThemeData(color: RafColors.secondary, size: 22),
        titleTextStyle: TextStyle(
          fontFamily: RafTypography.fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: RafColors.textPrimary,
        ),
      ),

      // Clean, 1px bordered cards
      cardTheme: const CardThemeData(
        color: RafColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: RafRadius.roundedMd,
          side: BorderSide(color: RafColors.border, width: 1.0),
        ),
      ),

      // Form input decoration: Crisp, legible, 1px smooth border
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RafColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: RafSpacing.lg,
          vertical: RafSpacing.md + 2,
        ),
        hintStyle: const TextStyle(
          color: RafColors.textMuted,
          fontSize: 14,
          fontFamily: RafTypography.fontFamily,
        ),
        labelStyle: const TextStyle(
          color: RafColors.textSecondary,
          fontSize: 14,
          fontFamily: RafTypography.fontFamily,
        ),
        border: OutlineInputBorder(
          borderRadius: RafRadius.roundedMd,
          borderSide: const BorderSide(color: RafColors.border, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: RafRadius.roundedMd,
          borderSide: const BorderSide(color: RafColors.border, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: RafRadius.roundedMd,
          borderSide: const BorderSide(color: RafColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: RafRadius.roundedMd,
          borderSide: const BorderSide(color: RafColors.danger, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: RafRadius.roundedMd,
          borderSide: const BorderSide(color: RafColors.danger, width: 1.5),
        ),
      ),

      // Buttons with flat, reliable feel
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: RafColors.primary,
          foregroundColor: RafColors.textInverse,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(64, 42),
          padding: const EdgeInsets.symmetric(
            horizontal: RafSpacing.lg,
            vertical: RafSpacing.md,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: RafRadius.roundedMd,
          ),
          textStyle: const TextStyle(
            fontFamily: RafTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: RafColors.secondary,
          minimumSize: const Size(64, 42),
          side: const BorderSide(color: RafColors.border, width: 1.0),
          padding: const EdgeInsets.symmetric(
            horizontal: RafSpacing.lg,
            vertical: RafSpacing.md,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: RafRadius.roundedMd,
          ),
          textStyle: const TextStyle(
            fontFamily: RafTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: RafColors.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: RafSpacing.md,
            vertical: RafSpacing.sm,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: RafRadius.roundedMd,
          ),
          textStyle: const TextStyle(
            fontFamily: RafTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Accounting and Inventory Data Table theme
      dataTableTheme: DataTableThemeData(
        headingRowColor: const WidgetStatePropertyAll(
          RafColors.surfaceSecondary,
        ),
        headingTextStyle: const TextStyle(
          fontFamily: RafTypography.fontFamily,
          fontWeight: FontWeight.w600,
          color: RafColors.textSecondary,
          fontSize: 13,
        ),
        dataRowColor: const WidgetStatePropertyAll(RafColors.surface),
        dataTextStyle: const TextStyle(
          fontFamily: RafTypography.fontFamily,
          color: RafColors.textPrimary,
          fontSize: 13,
        ),
        dividerThickness: 1.0,
        horizontalMargin: RafSpacing.lg,
        columnSpacing: RafSpacing.lg,
      ),

      dividerTheme: const DividerThemeData(
        color: RafColors.divider,
        thickness: 1.0,
        space: 1.0,
      ),

      textTheme: textTheme,
    );
  }
}
