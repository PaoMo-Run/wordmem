import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../domain/models/word.dart';
import 'widgets/word_list_tile.dart';
import 'widgets/filter_bar.dart';

/// 词库搜索范围：我的词库（已添加单词）/ 词典（内置词典全量检索）
enum _SearchScope { myWords, dictionary }

/// 词库页面
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  /// 当前搜索范围（我的词库 / 词典）
  _SearchScope _scope = _SearchScope.myWords;
  String? _stateFilter;
  String? _tagFilter;
  bool _favoriteOnly = false;
  bool _quizOnly = false;
  List<Map<String, dynamic>> _words = [];
  /// 词典命中结果（词典搜索模式填充，点击跳转添加页）
  List<DictWord> _dictResults = [];
  int _total = 0;
  bool _loading = false;
  int _offset = 0;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadWords();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _loadWords({bool reset = true}) {
    if (_loading) return;
    setState(() => _loading = true);

    if (reset) {
      _offset = 0;
    }

    try {
      final repo = ref.read(wordRepositoryProvider);

      // 词典模式：只检索内置词典（英文前缀 / 中文释义），不查个人词库
      if (_scope == _SearchScope.dictionary) {
        final q = _searchQuery.trim();
        final dictResults = q.isEmpty ? <DictWord>[] : repo.searchDict(q, limit: 100);
        setState(() {
          _words = [];
          _dictResults = reset ? dictResults : [];
          _total = dictResults.length;
          _loading = false;
        });
        return;
      }

      // 我的词库模式
      if (_searchQuery.isNotEmpty) {
        final results = repo.search(_searchQuery);
        setState(() {
          _words = reset ? results : [..._words, ...results];
          _dictResults = [];
          _total = _words.length;
          _loading = false;
        });
      } else {
        final results = repo.getAllWords(
          offset: _offset,
          limit: 50,
          stateFilter: _stateFilter,
          tagFilter: _tagFilter,
          favoriteOnly: _favoriteOnly,
        );
        final total = repo.getAllWords(limit: 100000).length;
        setState(() {
          _words = reset ? results : [..._words, ...results];
          _dictResults = [];
          _total = total;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _loadMore() {
    if (_scope == _SearchScope.dictionary ||
        _searchQuery.isNotEmpty ||
        _loading ||
        _words.length >= _total) {
      return;
    }
    _offset += 50;
    _loadWords(reset: false);
  }

  void _onSearch(String value) {
    setState(() => _searchQuery = value);
    _loadWords();
  }

  void _onFilterChanged({
    String? stateFilter,
    String? tagFilter,
    bool? favoriteOnly,
    bool? quizOnly,
  }) {
    setState(() {
      _stateFilter = stateFilter;
      _tagFilter = tagFilter;
      _favoriteOnly = favoriteOnly ?? false;
      _quizOnly = quizOnly ?? false;
    });
    _loadWords();
  }

  /// 词典命中条目：显示单词 + 释义，点击跳转添加页并预填单词
  Widget _buildDictTile(DictWord dict) {
    return ListTile(
      leading: const Icon(Icons.menu_book_outlined),
      title: Text(dict.word),
      subtitle: Text(
        dict.translation ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.add_circle_outline, size: 20),
      onTap: () => context.push('/add-word', extra: dict.word),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 监听词库版本变化，自动刷新列表
    ref.listen(wordListVersionProvider, (_, __) {
      _loadWords();
    });

    return Scaffold(
      // 液体玻璃布局：背景由 MainShell 的 aurora 光斑提供，Scaffold 透明
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: '搜索单词、释义、标签...',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: _onSearch,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/add-word'),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索范围切换：我的词库 / 词典（两个独立搜索入口）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_SearchScope>(
                segments: const [
                  ButtonSegment(
                    value: _SearchScope.myWords,
                    label: Text('我的词库'),
                    icon: Icon(Icons.star_outline, size: 18),
                  ),
                  ButtonSegment(
                    value: _SearchScope.dictionary,
                    label: Text('词典'),
                    icon: Icon(Icons.menu_book_outlined, size: 18),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: (s) {
                  setState(() => _scope = s.first);
                  _loadWords();
                },
              ),
            ),
          ),
          // 筛选栏（仅我的词库模式）
          if (_scope == _SearchScope.myWords)
            FilterBar(
              stateFilter: _stateFilter,
              tagFilter: _tagFilter,
              favoriteOnly: _favoriteOnly,
              quizOnly: _quizOnly,
              onChanged: _onFilterChanged,
            ),
          // 正文视图：按搜索范围分流
          Expanded(
            child: _scope == _SearchScope.dictionary
                ? _buildDictView()
                : _buildWordListView(),
          ),
        ],
      ),
    );
  }

  /// 词典模式视图：只显示词典命中（英文前缀 / 中文释义）
  Widget _buildDictView() {
    final q = _searchQuery.trim();
    if (q.isEmpty) {
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        title: '查词典',
        subtitle: '输入英文单词或中文释义，检索内置词典（含航空专业词）',
      );
    }
    if (_dictResults.isEmpty && !_loading) {
      return const EmptyState(
        icon: Icons.search_off,
        title: '词典中没有找到',
        subtitle: '试试其他拼写或中文关键词',
      );
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: _dictResults.length + (_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _dictResults.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _buildDictTile(_dictResults[index]);
      },
    );
  }

  /// 我的词库模式视图：筛选 + 分页列表 / 短文测试分组
  Widget _buildWordListView() {
    if (_quizOnly && _searchQuery.isEmpty) {
      return _buildQuizGroups();
    }
    if (_words.isEmpty && !_loading) {
      return EmptyState(
        icon: _searchQuery.isNotEmpty ? Icons.search_off : Icons.menu_book_outlined,
        title: _searchQuery.isNotEmpty ? '没有找到匹配的单词' : '词库还是空的',
        subtitle: _searchQuery.isNotEmpty ? '试试其他关键词' : '点击右上角加号添加单词',
      );
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: _words.length + (_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _words.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final word = _words[index];
        return WordListTile(
          word: word,
          onTap: () => context.push('/word/${word['id']}'),
        );
      },
    );
  }

  /// 短文测试分组视图（方案 B：按短文折叠展开）
  Widget _buildQuizGroups() {
    try {
      final groups = ref.watch(storyQuizDaoProvider).getLibraryGroups();
      final quizGroups =
          groups.where((g) => g['type'] == 'quiz').toList();

      if (quizGroups.isEmpty) {
        return const EmptyState(
          icon: Icons.quiz_outlined,
          title: '还没有测试错词',
          subtitle: '在短文详情页做测试，答错的词可加入词库后会显示在这里',
        );
      }

      final theme = Theme.of(context);
      return ListView.builder(
        // 显式 padding 需自行避让悬浮 dock 底部（≈116）
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 116),
        itemCount: quizGroups.length,
        itemBuilder: (context, i) {
          final group = quizGroups[i];
          final words = (group['words'] as List).cast<String>();
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ExpansionTile(
              title: Text(
                group['title'] as String? ?? '短文测试',
                style: theme.textTheme.titleSmall,
              ),
              subtitle: Text('${words.length} 个词'),
              children: words
                    .map((w) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.arrow_right, size: 18),
                        title: Text(w),
                        onTap: () {
                          // 跳到该词详情（查 id）
                          Map<String, dynamic>? row;
                          final all = ref
                              .read(wordRepositoryProvider)
                              .getAllWords(limit: 100000);
                          for (final r in all) {
                            if ((r['word'] as String).toLowerCase() ==
                                w.toLowerCase()) {
                              row = r;
                              break;
                            }
                          }
                          if (row != null && context.mounted) {
                            context.push('/word/${row['id']}');
                          }
                        },
                      ))
                  .toList(),
            ),
          );
        },
      );
    } catch (_) {
      return const Center(child: Text('分组加载失败'));
    }
  }
}
