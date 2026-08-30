import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';

/// 快捷入口动作
class QuickAction {
  final String id;
  final IconData icon;
  final String label;
  final String route;
  final Color color;

  const QuickAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.route,
    required this.color,
  });
}

/// 全部可用动作清单（用户可从中挑选加入快捷入口）
/// 颜色统一取自 AppColors.quick* 语义 token（2026-08-30 收敛，禁止裸色值）
const List<QuickAction> kAllQuickActions = [
  QuickAction(
      id: 'add_word',
      icon: Icons.add,
      label: '添加单词',
      route: '/add-word',
      color: AppColors.quickAddWord),
  QuickAction(
      id: 'story',
      icon: Icons.auto_stories_outlined,
      label: '今日短文',
      route: '/story',
      color: AppColors.quickStory),
  QuickAction(
      id: 'text_import',
      icon: Icons.text_snippet_outlined,
      label: '批量导入',
      route: '/text-import',
      color: AppColors.quickImport),
  QuickAction(
      id: 'custom_review',
      icon: Icons.calendar_month_outlined,
      label: '自选复习',
      route: '/custom-review',
      color: AppColors.quickCustomReview),
  QuickAction(
      id: 'word_group_memory',
      icon: Icons.hub_outlined,
      label: '词群记忆',
      route: '/word-group-memory',
      color: AppColors.quickGroupMemory),
  QuickAction(
      id: 'story_memory',
      icon: Icons.bookmarks_outlined,
      label: '短文记忆库',
      route: '/story-memory',
      color: AppColors.quickStoryMemory),
  QuickAction(
      id: 'library',
      icon: Icons.menu_book_outlined,
      label: '词库',
      route: '/library',
      color: AppColors.quickLibrary),
  QuickAction(
      id: 'stats',
      icon: Icons.bar_chart_outlined,
      label: '学习统计',
      route: '/stats',
      color: AppColors.quickStats),
];

/// 默认布局（首次启动无配置时使用）
const List<String> kDefaultQuickActionIds = [
  'add_word',
  'story',
  'text_import',
  'custom_review',
];

/// 上限
const int kMaxQuickActions = 8;

/// 按 id 取动作定义
QuickAction quickActionById(String id) =>
    kAllQuickActions.firstWhere((a) => a.id == id);
