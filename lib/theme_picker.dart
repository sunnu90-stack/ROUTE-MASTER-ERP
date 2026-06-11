import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme_provider.dart';

/// Drop this widget anywhere in your settings/profile screen
/// It shows 4 theme cards — tap one to apply it instantly across the whole app
class ThemePicker extends ConsumerWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTheme = ref.watch(appThemeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('App Theme',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B))),
        const SizedBox(height: 10),
        Row(
          children: AppThemeType.values.map((theme) {
            final config = ThemeHelper.getConfig(theme);
            final isSelected = theme == activeTheme;
            return Expanded(
              child: GestureDetector(
                onTap: () => ref.read(appThemeProvider.notifier).setTheme(theme),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: config.backgroundGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF0EA5E9)
                          : Colors.transparent,
                      width: 2.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF0EA5E9).withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            )
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(config.emoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 4),
                      Text(
                        config.displayName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: config.primaryTextColor,
                        ),
                      ),
                      if (isSelected)
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          width: 16,
                          height: 3,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0EA5E9),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
