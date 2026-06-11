import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme_provider.dart';

class AdaptiveCard extends ConsumerWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  const AdaptiveCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.borderRadius = 16.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTheme = ref.watch(appThemeProvider);
    final config = ThemeHelper.getConfig(activeTheme);

    final cardContent = AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: padding,
      decoration: BoxDecoration(
        color: config.cardColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: config.borderColor,
          width: config.isGlass ? 1.0 : 1.5,
        ),
        boxShadow: config.shadowOpacity > 0
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(config.shadowOpacity),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                )
              ]
            : null,
      ),
      child: child,
    );

    if (config.isGlass) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}
