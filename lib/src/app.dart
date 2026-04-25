import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/core/theme/app_theme.dart';
import 'package:uff/src/core/theme/theme_providers.dart';
import 'package:uff/src/routing/app_router.dart';

class UffApp extends ConsumerWidget {
  const UffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Uff',
      routerConfig: ref.watch(appRouterProvider),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
    );
  }
}
