import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

abstract final class AppTheme {
  static const _brand = Color(0xFF2563EB);

  static final light = _build(
    colors: FColors.neutralLight.copyWith(
      background: const Color(0xFFF7F9FC),
      foreground: const Color(0xFF0F172A),
      primary: _brand,
      primaryForeground: const Color(0xFFFAFAFA),
      secondary: const Color(0xFFEEF4FF),
      secondaryForeground: const Color(0xFF0F172A),
      muted: const Color(0xFFF1F5F9),
      mutedForeground: const Color(0xFF64748B),
      card: const Color(0xFFFFFFFF),
      border: const Color(0xFFE2E8F0),
    ),
    debugLabel: 'FitFlow Light',
  );

  static final dark = _build(
    colors: FColors.neutralDark.copyWith(
      background: const Color(0xFF0B1220),
      foreground: const Color(0xFFF8FAFC),
      primary: const Color(0xFF3B82F6),
      primaryForeground: const Color(0xFFF8FAFC),
      secondary: const Color(0xFF1E293B),
      secondaryForeground: const Color(0xFFF1F5F9),
      muted: const Color(0xFF1E293B),
      mutedForeground: const Color(0xFF94A3B8),
      card: const Color(0xFF111C31),
      border: const Color(0xFF26344D),
    ),
    debugLabel: 'FitFlow Dark',
  );

  static FThemeData _build({required FColors colors, String? debugLabel}) {
    final typography = FTypography.inherit(colors: colors, touch: true);
    final borderRadius = const FBorderRadius().scale(1.4);
    final style = FStyle(
      formFieldStyle: .inherit(
        colors: colors,
        typography: typography,
        touch: true,
      ),
      focusedOutlineStyle: FFocusedOutlineStyle(
        color: colors.primary,
        borderRadius: borderRadius.md,
      ),
      iconStyle: IconThemeData(
        color: colors.foreground,
        size: typography.body.lg.fontSize,
      ),
      sizes: FSizes.inherit(touch: true),
      tappableStyle: FTappableStyle(),
      borderRadius: borderRadius,
      // Headers line up with page content, which is inset by md.
      pagePadding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.md,
      ),
    );
    return FThemeData(
      debugLabel: debugLabel,
      touch: true,
      colors: colors,
      typography: typography,
      style: style,
      // Pages pad their own content (like the tabs do); the scaffold's
      // extra padding doubled it on every pushed page.
      scaffoldStyle: FScaffoldStyle.inherit(
        colors: colors,
        style: style,
      ).copyWith(childPadding: const .value(EdgeInsets.zero)),
    );
  }
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}
