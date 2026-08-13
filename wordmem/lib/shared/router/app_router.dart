import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/today/presentation/today_page.dart';
import '../../features/library/presentation/library_page.dart';
import '../../features/review/presentation/review_page.dart';
import '../../features/review/presentation/custom_review_page.dart';
import '../../features/review/presentation/synonym_challenge_page.dart';
import '../../features/stats/presentation/stats_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/add_word/presentation/add_word_page.dart';
import '../../features/add_word/presentation/text_import_page.dart';
import '../../features/word_detail/presentation/word_detail_page.dart';

/// 路由配置
final appRouter = GoRouter(
  initialLocation: '/today',
  routes: [
    // 底部导航 Shell Route
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/today',
          name: 'today',
          builder: (context, state) => const TodayPage(),
        ),
        GoRoute(
          path: '/library',
          name: 'library',
          builder: (context, state) => const LibraryPage(),
        ),
        GoRoute(
          path: '/stats',
          name: 'stats',
          builder: (context, state) => const StatsPage(),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),
    // 非底部导航页面
    GoRoute(
      path: '/review',
      name: 'review',
      builder: (context, state) => const ReviewPage(),
    ),
    GoRoute(
      path: '/custom-review',
      name: 'customReview',
      builder: (context, state) => const CustomReviewPage(),
    ),
    GoRoute(
      path: '/synonym-challenge',
      name: 'synonymChallenge',
      builder: (context, state) => const SynonymChallengePage(),
    ),
    GoRoute(
      path: '/add-word',
      name: 'addWord',
      builder: (context, state) => const AddWordPage(),
    ),
    GoRoute(
      path: '/text-import',
      name: 'textImport',
      builder: (context, state) => const TextImportPage(),
    ),
    GoRoute(
      path: '/word/:id',
      name: 'wordDetail',
      builder: (context, state) {
        final id = int.parse(state.pathParameters['id']!);
        return WordDetailPage(wordId: id);
      },
    ),
  ],
);

/// 底部导航 Shell
class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _destinations = [
    (icon: Icons.today_outlined, selectedIcon: Icons.today, label: '今日', path: '/today'),
    (icon: Icons.menu_book_outlined, selectedIcon: Icons.menu_book, label: '词库', path: '/library'),
    (icon: Icons.bar_chart_outlined, selectedIcon: Icons.bar_chart, label: '统计', path: '/stats'),
    (icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: '设置', path: '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _destinations.indexWhere((d) => location.startsWith(d.path));

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) => context.go(_destinations[i].path),
        destinations: _destinations
            .map((d) => NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ))
            .toList(),
      ),
    );
  }
}
