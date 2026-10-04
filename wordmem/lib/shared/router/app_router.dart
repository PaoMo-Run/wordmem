import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/glass.dart';
import '../../features/today/presentation/today_page.dart';
import '../../features/library/presentation/library_page.dart';
import '../../features/review/presentation/review_center_page.dart';
import '../../features/review/presentation/review_page.dart';
import '../../features/review/presentation/custom_review_page.dart';
import '../../features/review/presentation/synonym_challenge_page.dart';
import '../../features/review/presentation/synonym_group_challenge_page.dart';
import '../../features/review/presentation/word_group_memory_page.dart';
import '../../features/review/presentation/root_challenge_page.dart';
import '../../features/story/presentation/story_center_page.dart';
import '../../features/stats/presentation/stats_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/settings/presentation/me_page.dart';
import '../../features/settings/presentation/about_page.dart';
import '../../features/settings/presentation/ai_config_page.dart';
import '../../features/settings/presentation/schedule_tuning_page.dart';
import '../../features/settings/presentation/sync_page.dart';
import '../../features/add_word/presentation/add_word_page.dart';
import '../../features/add_word/presentation/text_import_page.dart';
import '../../features/today/presentation/today_quick_actions_editor_page.dart';
import '../../features/word_detail/presentation/word_detail_page.dart';
import '../../features/story/presentation/story_page.dart';
import '../../features/story/presentation/story_memory_page.dart';
import '../../features/story/presentation/story_quiz_page.dart';
import '../../domain/services/root_matcher.dart';

/// 路由配置（B 方案：5 tab = 今日 / 复习中心 / 短文 / 词库 / 我的）
final appRouter = GoRouter(
  initialLocation: '/today',
  routes: [
    // ── 全局背景壳（v5/v8 演进）──
    // 所有路由（tab + push 详情页）都包一层 aurora 背景（v8 起为纯静态，
    // 不再走 60fps 时钟动画），保证视觉一致、过渡期间无闪屏。
    ShellRoute(
      builder: (context, state, child) => Stack(
        fit: StackFit.expand,
        children: [
          const AppBackground(),
          child,
        ],
      ),
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
          path: '/review-center',
          name: 'reviewCenter',
          builder: (context, state) => const ReviewCenterPage(),
        ),
        GoRoute(
          path: '/story-center',
          name: 'storyCenter',
          builder: (context, state) => const StoryCenterPage(),
        ),
        GoRoute(
          path: '/library',
          name: 'library',
          builder: (context, state) => const LibraryPage(),
        ),
        GoRoute(
          path: '/me',
          name: 'me',
          builder: (context, state) => const MePage(),
        ),
      ],
    ),
    // 非底部导航页面（从对应 tab push 进入）
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
    GoRoute(
      path: '/about',
      name: 'about',
      builder: (context, state) => const AboutPage(),
    ),
    GoRoute(
      path: '/today-quick-actions',
      name: 'todayQuickActions',
      builder: (context, state) => const TodayQuickActionsEditorPage(),
    ),
    GoRoute(
      path: '/review',
      name: 'review',
      // v2.1.11：`?mode=early` = 提前背（只复习未来 3 小时内到期的词）
      builder: (context, state) =>
          ReviewPage(early: state.uri.queryParameters['mode'] == 'early'),
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
      path: '/synonym-group-challenge',
      name: 'synonymGroupChallenge',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final groups =
            (extra?['groups'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final start = (extra?['start'] as int?) ?? 0;
        return SynonymGroupChallengePage(groups: groups, startIndex: start);
      },
    ),
    GoRoute(
      path: '/add-word',
      name: 'addWord',
      builder: (context, state) => AddWordPage(
        initialWord: state.extra is String ? state.extra as String : null,
      ),
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
    GoRoute(
      path: '/ai-config',
      name: 'aiConfig',
      builder: (context, state) => const AiConfigPage(),
    ),
    GoRoute(
      path: '/schedule-tuning',
      name: 'scheduleTuning',
      builder: (context, state) => const ScheduleTuningPage(),
    ),
    GoRoute(
      path: '/network-sync',
      name: 'networkSync',
      builder: (context, state) => const SyncPage(),
    ),
    GoRoute(
      path: '/word-group-memory',
      name: 'wordGroupMemory',
      builder: (context, state) => const WordGroupMemoryPage(),
    ),
    GoRoute(
      path: '/root-challenge',
      name: 'rootChallenge',
      builder: (context, state) {
        final extra = state.extra;
        // v2.2.0 需求3：payload 形式（matches + index，支持「下一词根」）
        if (extra is Map<String, dynamic>) {
          final matches =
              (extra['matches'] as List?)?.cast<RootMatch>() ?? const [];
          final i = (extra['index'] as int?) ?? 0;
          final m = extra['match'] as RootMatch? ??
              (matches.isNotEmpty
                  ? matches[i.clamp(0, matches.length - 1)]
                  : null);
          if (m == null) {
            return const PlaceholderPage(title: '词根挑战');
          }
          return RootChallengePage(
            match: m,
            matches: matches.isNotEmpty ? matches : null,
            index: i,
          );
        }
        // 兼容旧形态：直传单个 RootMatch
        if (extra is RootMatch) {
          return RootChallengePage(match: extra);
        }
        return const PlaceholderPage(title: '词根挑战');
      },
    ),
    GoRoute(
      path: '/story',
      name: 'story',
      builder: (context, state) => const StoryPage(),
    ),
    GoRoute(
      path: '/story-memory',
      name: 'storyMemory',
      builder: (context, state) => const StoryMemoryPage(),
    ),
    GoRoute(
      path: '/story-quiz/:id/:mode',
      name: 'storyQuiz',
      builder: (context, state) {
        final id = int.parse(state.pathParameters['id']!);
        final mode = state.pathParameters['mode']!;
        return StoryQuizRoute(id: id, modeName: mode);
      },
    ),
      ],
    ),
  ],
);

/// 底部导航 Shell
class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _destinations = [
    (icon: Icons.today_outlined, selectedIcon: Icons.today, label: '今日', path: '/today'),
    (icon: Icons.play_circle_outline, selectedIcon: Icons.play_circle, label: '复习', path: '/review-center'),
    (icon: Icons.auto_stories_outlined, selectedIcon: Icons.auto_stories, label: '短文', path: '/story-center'),
    (icon: Icons.menu_book_outlined, selectedIcon: Icons.menu_book, label: '词库', path: '/library'),
    (icon: Icons.person_outline, selectedIcon: Icons.person, label: '我的', path: '/me'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _destinations.indexWhere((d) => location.startsWith(d.path));
    final selected = index < 0 ? 0 : index;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        // 平板横屏（≥840dp）：改用侧边 NavigationRail，节省竖向空间
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: selected,
                  onDestinationSelected: (i) =>
                      context.go(_destinations[i].path),
                  labelType: NavigationRailLabelType.all,
                  leading: const SizedBox(height: 8),
                  destinations: _destinations
                      .map((d) => NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          );
        }
        return Scaffold(
          // extendBody：内容延伸到悬浮 dock 之后，玻璃才有背景可透（液体玻璃关键）
          extendBody: true,
          // 背景由路由层全局 ShellRoute 的 AppBackground 统一提供（v5 起，全项目唯一一份）
          body: child,
          bottomNavigationBar: GlassNavBar(
            currentIndex: selected,
            onChanged: (i) => context.go(_destinations[i].path),
            destinations: _destinations
                .map((d) => GlassNavDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon,
                      label: d.label,
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}

/// 占位页面（P5 替换为真正的「关于」页）
class PlaceholderPage extends StatelessWidget {
  final String title;
  const PlaceholderPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(child: Text('建设中…')),
    );
  }
}
