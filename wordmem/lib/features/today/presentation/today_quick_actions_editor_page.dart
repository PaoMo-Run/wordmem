import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/widgets/glass.dart';
import '../models/quick_action.dart';
import '../data/quick_actions_repo.dart';

/// 快捷入口编辑页：已添加（拖拽排序）+ 可添加列表
///
/// 设计约定（2026-08-30 液体玻璃）：aurora 背景 + 玻璃容器。
class TodayQuickActionsEditorPage extends StatefulWidget {
  const TodayQuickActionsEditorPage({super.key});

  @override
  State<TodayQuickActionsEditorPage> createState() =>
      _TodayQuickActionsEditorPageState();
}

class _TodayQuickActionsEditorPageState
    extends State<TodayQuickActionsEditorPage> {
  final _repo = QuickActionsRepo();
  List<String> _selected = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await _repo.load();
    if (mounted) {
      setState(() {
        _selected = ids;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    await _repo.save(_selected);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('快捷入口已更新')),
      );
    }
  }

  void _add(String id) {
    if (_selected.length >= kMaxQuickActions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多添加 $kMaxQuickActions 个快捷入口')),
      );
      return;
    }
    setState(() => _selected.add(id));
  }

  void _remove(String id) {
    setState(() => _selected.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available =
        kAllQuickActions.where((a) => !_selected.contains(a.id)).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('自定义快捷入口'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 已添加
                    Row(
                      children: [
                        Text('我的快捷入口',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('${_selected.length}/$kMaxQuickActions',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '长按拖拽排序',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    if (_selected.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: Text('还没有添加快捷入口')),
                      )
                    else
                      GlassContainer(
                        blur: 0,
                        elevated: false,
                        radius: 14,
                        padding: EdgeInsets.zero,
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _selected.length,
                          onReorderItem: (oldIndex, newIndex) {
                            setState(() {
                              // onReorderItem 的 newIndex 已针对移除项调整，直接插入
                              final item = _selected.removeAt(oldIndex);
                              _selected.insert(newIndex, item);
                            });
                          },
                          itemBuilder: (context, i) {
                            final id = _selected[i];
                            final action = quickActionById(id);
                            return ListTile(
                              key: ValueKey(id),
                              leading: Icon(action.icon, color: action.color),
                              title: Text(action.label),
                              trailing: IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: AppColors.error),
                                onPressed: () => _remove(id),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 24),

                    // 可添加
                    Text('可添加',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (available.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                            child: Text('已全部添加（最多 $kMaxQuickActions 个）')),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: available
                            .map((a) => ActionChip(
                                  avatar:
                                      Icon(a.icon, size: 18, color: a.color),
                                  label: Text(a.label),
                                  onPressed: () => _add(a.id),
                                ))
                            .toList(),
                      ),
                  ],
                ),
        ],
      ),
    );
  }
}
