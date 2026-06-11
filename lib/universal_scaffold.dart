import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme_provider.dart';

class UniversalScaffold extends ConsumerWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final bool useSafeArea;
  final Widget? floatingActionButton;

  const UniversalScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.useSafeArea = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTheme = ref.watch(appThemeProvider);
    final config = ThemeHelper.getConfig(activeTheme);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: config.backgroundGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: useSafeArea ? SafeArea(child: body) : body,
      ),
    );
  }
}
