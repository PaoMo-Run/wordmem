import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/string_utils.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass.dart';

/// 抽查错题本（v2.2.1）：汇总所有熟练词抽检中答错过的词。
///
/// - 数据源 = `review_logs`（kind='quiz' 且 rating=again）聚合：答错次数 +
///   最近一次答错时间，附带词的当前学习状态（打回/毕业等编排动作不删日志，
///   历史是事实记录；当前状态变化会实时体现在列表的状态标签上）。
/// - 排序：按上次答错时间 / 按答错次数，均支持正序倒序切换，选择持久化。
/// - 点击词卡进入详情页（可手动打回），返回后列表自动刷新。
class QuizWrongBookPage extends ConsumerStatefulWidget {
  const QuizWrongBookPage({super.key});

  @override
  ConsumerState<QuizWrongBookPage> createState() => _QuizWrongBookPageState();
}

enum _SortKey { lastWrongTime, wrongCount }

class _QuizWrongBookPageState extends ConsumerState<QuizWrongBookPage> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  _SortKey _sortKey = _SortKey.lastWrongTime;
  bool _desc = true; // true = 时间最近在前 / 次数最多在前

  @override
  void initState() {
    super.initState();
    _loadSortPref();
    _loadEntries();
  }

  void _loadSortPref() {
    // SharedPreferencesProvider 启动即预热，同步取缓存值即可；取不到用默认
    final cached = ref.read(sharedPreferencesProvider).valueOrNull;
    final raw = cached?.getString(AppConstants.keyQuizWrongBookSort);
    switch (raw) {
      case 'time_asc':
        _sortKey = _SortKey.lastWrongTime;
        _desc = false;
      case 'count_asc':
        _sortKey = _SortKey.wrongCount;
        _desc = false;
      case 'count_desc':
        _sortKey = _SortKey.wrongCount;
        _desc = true;
      default: // 'time_desc' 与脏值 → 默认
        break;
    }
  }

  Future<void> _loadEntries() async {
    try {
      final entries =
          ref.read(reviewRepositoryProvider).getQuizWrongEntries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
      _sortEntries();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _sortEntries() {
    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
      int r;
      switch (_sortKey) {
        case _SortKey.lastWrongTime:
          final ta = _parseTime(a['last_wrong_at']);
          final tb = _parseTime(b['last_wrong_at']);
          r = ta.compareTo(tb);
          if (r == 0) {
            r = _countOf(a).compareTo(_countOf(b));
          }
        case _SortKey.wrongCount:
          r = _countOf(a).compareTo(_countOf(b));
          if (r == 0) {
            r = _parseTime(a['last_wrong_at']).compareTo(_parseTime(b['last_wrong_at']));
          }
      }
      return _desc ? -r : r;
    }

    setState(() => _entries.sort(cmp));
  }

  DateTime _parseTime(dynamic s) =>
      DateTime.tryParse(s as String? ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  int _countOf(Map<String, dynamic> e) => (e['wrong_count'] as int?) ?? 0;

  void _setSortKey(_SortKey key) {
    setState(() {
      // 换维度时恢复该维度的默认方向：时间最近在前 / 次数最多在前
      _sortKey = key;
      _desc = true;
    });
    _persistSort();
    _sortEntries();
  }

  void _toggleDir() {
    setState(() => _desc = !_desc);
    _persistSort();
    _sortEntries();
  }

  Future<void> _persistSort() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyQuizWrongBookSort,
          '${_sortKey == _SortKey.lastWrongTime ? 'time' : 'count'}_${_desc ? 'desc' : 'asc'}');
    } catch (_) {
      // 持久化失败不影响功能
    }
  }

  Future<void> _openWord(int id) async {
    await context.push('/word/$id');
    if (!mounted) return;
    // 详情页里可能已打回：回来后重查，状态标签实时更新
    _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('抽查错题本')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<_SortKey>(
                    segments: const [
                      ButtonSegment(
                        value: _SortKey.lastWrongTime,
                        label: Text('答错时间'),
                      ),
                      ButtonSegment(
                        value: _SortKey.wrongCount,
                        label: Text('答错次数'),
                      ),
                    ],
                    selected: {_sortKey},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => _setSortKey(s.first),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _desc
                      ? (_sortKey == _SortKey.lastWrongTime
                          ? '最近答错在前，点一下切换为最久在前'
                          : '答错最多在前，点一下切换为最少在前')
                      : (_sortKey == _SortKey.lastWrongTime
                          ? '最久答错在前，点一下切换为最近在前'
                          : '答错最少在前，点一下切换为最多在前'),
                  onPressed: _toggleDir,
                  icon: Icon(_desc ? Icons.arrow_downward : Icons.arrow_upward),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _loading ? '' : '共 ${_entries.length} 个词 · 点按进入详情可手动打回',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? const EmptyState(
                        icon: Icons.fact_check_outlined,
                        title: '还没有抽查错题',
                        subtitle: '熟练词抽检中答错的词会集中出现在这里',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: _entries.length,
                        itemBuilder: (context, i) =>
                            _buildTile(theme, _entries[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(ThemeData theme, Map<String, dynamic> e) {
    final id = e['id'] as int;
    final word = e['word'] as String;
    final cardState = e['card_state'] as String? ?? 'new';
    final reps = (e['reps'] as int?) ?? 0;
    final lapses = (e['lapses'] as int?) ?? 0;
    final wrongCount = _countOf(e);
    final lastWrong = _parseTime(e['last_wrong_at']);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GlassContainer(
        onTap: () => _openWord(id),
        blur: 0,
        elevated: false,
        radius: 14,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: masteryColor(cardState, reps, lapses),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          word,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        masteryLabel(cardState, reps, lapses),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: masteryColor(cardState, reps, lapses),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '答错 $wrongCount 次 · 上次答错 ${StringUtils.relativeTime(lastWrong)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.open_in_new,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
