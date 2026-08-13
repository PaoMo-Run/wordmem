import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import 'widgets/word_list_tile.dart';
import 'widgets/filter_bar.dart';

/// 词库页面
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _stateFilter;
  String? _tagFilter;
  bool _favoriteOnly = false;
  List<Map<String, dynamic>> _words = [];
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

      if (_searchQuery.isNotEmpty) {
        final results = repo.search(_searchQuery);
        setState(() {
          _words = reset ? results : [..._words, ...results];
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
          _total = total;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _loadMore() {
    if (_searchQuery.isNotEmpty || _loading || _words.length >= _total) return;
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
  }) {
    setState(() {
      _stateFilter = stateFilter;
      _tagFilter = tagFilter;
      _favoriteOnly = favoriteOnly ?? false;
    });
    _loadWords();
  }

  @override
  Widget build(BuildContext context) {
    // 监听词库版本变化，自动刷新列表
    ref.listen(wordListVersionProvider, (_, __) {
      _loadWords();
    });

    return Scaffold(
      appBar: AppBar(
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
          // 筛选栏
          FilterBar(
            stateFilter: _stateFilter,
            tagFilter: _tagFilter,
            favoriteOnly: _favoriteOnly,
            onChanged: _onFilterChanged,
          ),
          // 列表
          Expanded(
            child: _words.isEmpty && !_loading
                ? EmptyState(
                    icon: _searchQuery.isNotEmpty
                        ? Icons.search_off
                        : Icons.menu_book_outlined,
                    title: _searchQuery.isNotEmpty
                        ? '没有找到匹配的单词'
                        : '词库还是空的',
                    subtitle: _searchQuery.isNotEmpty
                        ? '试试其他关键词'
                        : '点击右上角加号添加单词',
                  )
                : ListView.builder(
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
                  ),
          ),
        ],
      ),
    );
  }
}
