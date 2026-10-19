import 'dart:math' as math;

import 'package:flutter/material.dart';

abstract final class StudentColors {
  static const primary = Color(0xFF00288E);
  static const primaryBright = Color(0xFF1E40AF);
  static const secondary = Color(0xFF0051D5);
  static const ink = Color(0xFF131B2E);
  static const muted = Color(0xFF626B80);
  static const surface = Color(0xFFFAF8FF);
  static const surfaceLow = Color(0xFFF2F3FF);
  static const surfaceHigh = Color(0xFFE2E7FF);
  static const border = Color(0xFFDCE1EF);
  static const green = Color(0xFF167A42);
  static const greenSoft = Color(0xFFE4F5E9);
  static const amber = Color(0xFF9A5B00);
  static const amberSoft = Color(0xFFFFF1D8);
  static const red = Color(0xFFB42318);
  static const redSoft = Color(0xFFFFE8E5);
}

final studentTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  scaffoldBackgroundColor: StudentColors.surface,
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: StudentColors.primaryBright,
        brightness: Brightness.light,
      ).copyWith(
        primary: StudentColors.primary,
        secondary: StudentColors.secondary,
        surface: StudentColors.surface,
        error: StudentColors.red,
      ),
  fontFamily: 'Inter',
  fontFamilyFallback: const ['Arial', 'sans-serif'],
  appBarTheme: const AppBarTheme(
    backgroundColor: StudentColors.surface,
    foregroundColor: StudentColors.ink,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: StudentColors.surfaceLow,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: StudentColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: StudentColors.secondary, width: 1.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      backgroundColor: StudentColors.primaryBright,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: StudentColors.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
);

class StudentAppViewport extends StatelessWidget {
  const StudentAppViewport({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 430.0;
      final width = math.min(availableWidth, 430.0);
      final height = constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : MediaQuery.sizeOf(context).height;
      return ColoredBox(
        color: const Color(0xFFE8ECF4),
        child: Center(
          child: Container(
            key: const ValueKey('student-app-viewport'),
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: StudentColors.surface,
              boxShadow: availableWidth > 430
                  ? const [
                      BoxShadow(
                        color: Color(0x160D1B39),
                        blurRadius: 24,
                        offset: Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        ),
      );
    },
  );
}

class StudentSurface extends StatelessWidget {
  const StudentSurface({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: StudentColors.border),
    ),
    child: child,
  );
}

class StudentStatusPill extends StatelessWidget {
  const StudentStatusPill({
    required this.label,
    required this.color,
    required this.background,
    this.icon,
    super.key,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class StudentTabBar extends StatelessWidget {
  const StudentTabBar({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = [
    (Icons.calendar_month_outlined, 'Lịch thi'),
    (Icons.menu_book_outlined, 'Luyện tập'),
    (Icons.bar_chart_outlined, 'Kết quả'),
    (Icons.person_outline, 'Tài khoản'),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      height: 62,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: StudentColors.border)),
      ),
      child: Row(
        children: [
          for (var index = 0; index < _items.length; index++)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(index),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _items[index].$1,
                      size: 21,
                      color: selectedIndex == index
                          ? StudentColors.primaryBright
                          : StudentColors.muted,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _items[index].$2,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: selectedIndex == index
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selectedIndex == index
                            ? StudentColors.primary
                            : StudentColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
