import 'package:flutter/material.dart';

/// 设计令牌 —— 对照原 Demo（DeepSeek 风格）提炼的配色与圆角。
///
/// 浅色：白底 + 冷蓝灰侧栏 + 品牌蓝 #4D6BFE。
/// 深色：深灰底 + 更亮的品牌蓝，保证对比度。
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bgBase,
    required this.bgSidebar,
    required this.bgElevated,
    required this.bgHover,
    required this.bgActive,
    required this.bgInput,
    required this.userBubble,
    required this.codeBg,
    required this.codeBanner,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.brand,
    required this.brandSoft,
    required this.brandText,
    required this.danger,
    required this.success,
    required this.warning,
    required this.shadow,
  });

  final Color bgBase;
  final Color bgSidebar;
  final Color bgElevated;
  final Color bgHover;
  final Color bgActive;
  final Color bgInput;
  final Color userBubble;
  final Color codeBg;
  final Color codeBanner;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color brand;
  final Color brandSoft;
  final Color brandText;
  final Color danger;
  final Color success;
  final Color warning;
  final Color shadow;

  static const AppColors light = AppColors(
    bgBase: Color(0xFFFFFFFF),
    bgSidebar: Color(0xFFF9FBFF),
    bgElevated: Color(0xFFFFFFFF),
    bgHover: Color(0x0F263148),
    bgActive: Color(0x1A263148),
    bgInput: Color(0xFFFFFFFF),
    userBubble: Color(0xFFEFF3FF),
    codeBg: Color(0xFFF6F7F9),
    codeBanner: Color(0xFFEFF1F4),
    border: Color(0x14263148),
    borderStrong: Color(0x24263148),
    textPrimary: Color(0xFF1B1B1F),
    textSecondary: Color(0xFF5C6270),
    textTertiary: Color(0xFF8A91A0),
    brand: Color(0xFF4D6BFE),
    brandSoft: Color(0xFFEDF1FF),
    brandText: Color(0xFF4D6BFE),
    danger: Color(0xFFE5484D),
    success: Color(0xFF12A594),
    warning: Color(0xFFF5A623),
    shadow: Color(0x14000000),
  );

  static const AppColors dark = AppColors(
    bgBase: Color(0xFF1C1D22),
    bgSidebar: Color(0xFF16171B),
    bgElevated: Color(0xFF24252B),
    bgHover: Color(0x14FFFFFF),
    bgActive: Color(0x24FFFFFF),
    bgInput: Color(0xFF24252B),
    userBubble: Color(0xFF2C3040),
    codeBg: Color(0xFF15161A),
    codeBanner: Color(0xFF23242A),
    border: Color(0x1FFFFFFF),
    borderStrong: Color(0x33FFFFFF),
    textPrimary: Color(0xFFECEDF0),
    textSecondary: Color(0xFFA6ABB8),
    textTertiary: Color(0xFF767C8A),
    brand: Color(0xFF6B87FF),
    brandSoft: Color(0xFF232A45),
    brandText: Color(0xFF8DA3FF),
    danger: Color(0xFFFF6B6E),
    success: Color(0xFF3DD9C4),
    warning: Color(0xFFFFC55C),
    shadow: Color(0x66000000),
  );

  @override
  AppColors copyWith({
    Color? bgBase,
    Color? bgSidebar,
    Color? bgElevated,
    Color? bgHover,
    Color? bgActive,
    Color? bgInput,
    Color? userBubble,
    Color? codeBg,
    Color? codeBanner,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? brand,
    Color? brandSoft,
    Color? brandText,
    Color? danger,
    Color? success,
    Color? warning,
    Color? shadow,
  }) {
    return AppColors(
      bgBase: bgBase ?? this.bgBase,
      bgSidebar: bgSidebar ?? this.bgSidebar,
      bgElevated: bgElevated ?? this.bgElevated,
      bgHover: bgHover ?? this.bgHover,
      bgActive: bgActive ?? this.bgActive,
      bgInput: bgInput ?? this.bgInput,
      userBubble: userBubble ?? this.userBubble,
      codeBg: codeBg ?? this.codeBg,
      codeBanner: codeBanner ?? this.codeBanner,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      brand: brand ?? this.brand,
      brandSoft: brandSoft ?? this.brandSoft,
      brandText: brandText ?? this.brandText,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bgBase: Color.lerp(bgBase, other.bgBase, t)!,
      bgSidebar: Color.lerp(bgSidebar, other.bgSidebar, t)!,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t)!,
      bgHover: Color.lerp(bgHover, other.bgHover, t)!,
      bgActive: Color.lerp(bgActive, other.bgActive, t)!,
      bgInput: Color.lerp(bgInput, other.bgInput, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      codeBg: Color.lerp(codeBg, other.codeBg, t)!,
      codeBanner: Color.lerp(codeBanner, other.codeBanner, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      brandText: Color.lerp(brandText, other.brandText, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

/// 圆角与间距令牌。
class AppRadius {
  AppRadius._();
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 24;
  static const double pill = 999;
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light, AppColors.light);

  static ThemeData dark() => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors c) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: c.brand,
        brightness: brightness,
        primary: c.brand,
        surface: c.bgBase,
        error: c.danger,
      ),
      scaffoldBackgroundColor: c.bgBase,
      canvasColor: c.bgBase,
      dividerColor: c.border,
      fontFamily: null,
      splashFactory: InkSparkle.splashFactory,
    );

    final textColor = c.textPrimary;
    final textTheme = base.textTheme.apply(
      bodyColor: textColor,
      displayColor: textColor,
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.7),
        bodySmall: textTheme.bodySmall?.copyWith(fontSize: 12.5),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: textTheme.titleSmall?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.bgBase,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.textSecondary, size: 20),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.bgInput,
        hintStyle: TextStyle(color: c.textTertiary, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: c.brand, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xFF34363D)
            : const Color(0xFF2F3239),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.bgElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.bgElevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : c.bgBase,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.brand
              : c.borderStrong,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.brand),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.brand,
        selectionColor: c.brand.withValues(alpha: 0.25),
        selectionHandleColor: c.brand,
      ),
    );
  }
}

extension AppThemeX on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  TextTheme get texts => Theme.of(this).textTheme;
}
