import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'shared/router/app_router.dart';

class WordMemApp extends StatelessWidget {
  const WordMemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '词记',
      debugShowCheckedModeBanner: false,
      // v2.1.4：仅保留深色模式（浅色模式与主题切换已移除）
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      // v8：aurora 背景改纯静态（见 glass.dart AppBackground），无动画时钟
      builder: (context, child) => child ?? const SizedBox.shrink(),
    );
  }
}
