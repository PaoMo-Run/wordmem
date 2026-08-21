import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quick_action.dart';

/// 快捷入口配置持久化（shared_preferences）
class QuickActionsRepo {
  static const String _key = 'today.quick_actions';

  /// 读取当前布局（首次使用返回默认布局）
  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return List.of(kDefaultQuickActionIds);
    }
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => e.toString())
          .where((id) => kAllQuickActions.any((a) => a.id == id))
          .toList();
      return list.isEmpty ? List.of(kDefaultQuickActionIds) : list;
    } catch (_) {
      return List.of(kDefaultQuickActionIds);
    }
  }

  /// 保存布局（自动过滤非法 id、限制上限）
  Future<void> save(List<String> ids) async {
    final cleaned = ids
        .where((id) => kAllQuickActions.any((a) => a.id == id))
        .toSet()
        .toList();
    final trimmed = cleaned.take(kMaxQuickActions).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(trimmed));
  }

  /// 根据 id 列表解析出动作对象（保持用户顺序）
  List<QuickAction> resolve(List<String> ids) {
    final byId = {for (final a in kAllQuickActions) a.id: a};
    return ids
        .map((id) => byId[id])
        .whereType<QuickAction>()
        .toList();
  }
}
