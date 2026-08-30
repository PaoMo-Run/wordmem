import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../domain/models/story.dart';
import '../../../domain/models/story_quiz.dart';
import '../../../domain/services/story_quiz_engine.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/glass.dart';

// 路由包装：按 story id + mode 加载短文后进入答题页
class StoryQuizRoute extends ConsumerWidget {
  final int id;
  final String modeName;
  const StoryQuizRoute({super.key, required this.id, required this.modeName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(storyRepositoryProvider);
    final story = repo.getById(id);
    if (story == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('短文测试'),
          backgroundColor: Colors.transparent,
        ),
        body: const Stack(
          fit: StackFit.expand,
          children: [
            AppBackground(),
            Center(child: Text('短文不存在或已被删除')),
          ],
        ),
      );
    }
    return StoryQuizPage(
      story: story,
      mode: StoryQuizMode.fromName(modeName),
    );
  }
}

/// 短文记忆测试页：整篇呈现挖空作答。
///
/// 交互：
/// - 复习模式：点空格 → 底部弹 4 选项
/// - 巩固/拓展：点空格 → 弹出输入框
/// - 提交后统一判分，错空标红；结果页可勾选错词加入词库
class StoryQuizPage extends ConsumerStatefulWidget {
  final Story story;
  final StoryQuizMode mode;

  const StoryQuizPage({super.key, required this.story, required this.mode});

  @override
  ConsumerState<StoryQuizPage> createState() => _StoryQuizPageState();
}

class _StoryQuizPageState extends ConsumerState<StoryQuizPage> {
  late final QuizContent _quiz;
  // 拓展模式：逐句题目（一句一题）
  List<QuizSentenceContent> _sentences = const [];
  // 是否显示中文翻译（拓展模式逐句对照，默认隐藏）
  bool _showTranslation = false;
  // 空格索引 -> 用户答案
  final Map<int, String> _answers = {};
  bool _submitted = false;
  // 判分结果：空格索引 -> 是否正确
  final Map<int, bool> _results = {};
  // 错词勾选（结果区）
  final Set<String> _selectedWrongWords = {};
  // 下一篇短文的 id（记忆库列表中当前篇的下一篇；无则 null）
  int? _nextStoryId;
  bool _addingToLibrary = false;
  // 当前聚焦的空格索引（-1 = 无；巩固/拓展模式用）
  int _focusIndex = 0;
  // 内联输入控制器（巩固/拓展模式）
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final engine = ref.read(storyQuizEngineProvider);
    if (widget.mode == StoryQuizMode.extend) {
      // 拓展模式：一句一题
      _sentences = engine.generateSentences(
        text: widget.story.content,
        translation: widget.story.translation,
        highlightWords: widget.story.words,
      );
      // 汇总所有空格（判分/输入共用全局索引）
      final allTokens = <QuizToken>[];
      final allBlanks = <QuizBlank>[];
      for (final s in _sentences) {
        allTokens.addAll(s.tokens);
        allBlanks.addAll(s.blanks);
      }
      _quiz = QuizContent(tokens: allTokens, blanks: allBlanks);
    } else {
      _quiz = engine.generate(
        text: widget.story.content,
        highlightWords: widget.story.words,
        mode: widget.mode,
      );
    }
    // 进入页面后聚焦第一个空格，自动弹出键盘（巩固/拓展模式）
    if (widget.mode != StoryQuizMode.review && _quiz.blanks.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
    _findNextStory();
  }

  /// 定位记忆库列表中当前篇的下一篇（用于"下一篇短文"按钮）
  void _findNextStory() {
    try {
      final repo = ref.read(storyRepositoryProvider);
      final stories = repo.getAll(archived: true);
      final idx = stories.indexWhere((s) => s.id == widget.story.id);
      if (idx >= 0 && idx < stories.length - 1) {
        _nextStoryId = stories[idx + 1].id;
      }
    } catch (_) {
      // 查询失败则不显示下一篇入口
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// 内联输入回车：填入当前焦点空格，自动跳到下一个未填空格
  void _onInputSubmitted(String value) {
    final blanks = _quiz.blanks;
    if (blanks.isEmpty || _focusIndex < 0) return;
    final v = value.trim();
    setState(() {
      _answers[_focusIndex] = v;
    });
    // 找下一个未填空格
    var next = _focusIndex + 1;
    while (next < blanks.length && _answers.containsKey(next)) {
      next++;
    }
    if (next < blanks.length) {
      setState(() => _focusIndex = next);
      _inputCtrl.clear();
      _inputFocus.requestFocus();
    } else {
      // 全部填完：清输入框、移除焦点
      setState(() => _focusIndex = -1);
      _inputCtrl.clear();
      _inputFocus.unfocus();
    }
  }

  /// 提交判分：统一判分 + 保存测试记录
  void _submit() {
    final engine = ref.read(storyQuizEngineProvider);
    final blanks = _quiz.blanks;
    final results = <int, bool>{};
    final wrongs = <WrongBlank>[];
    for (var i = 0; i < blanks.length; i++) {
      final userAnswer = _answers[i] ?? '';
      final ok = engine.isCorrect(userAnswer, blanks[i].word);
      results[i] = ok;
      if (!ok) {
        wrongs.add(WrongBlank(
          word: blanks[i].word,
          userAnswer: userAnswer.isEmpty ? '（未填）' : userAnswer,
          correctAnswer: blanks[i].word,
        ));
      }
    }
    setState(() {
      _submitted = true;
      _results.addAll(results);
      _selectedWrongWords.addAll(wrongs.map((w) => w.word));
    });
    // 保存测试记录
    try {
      ref.read(storyQuizDaoProvider).insertRecord(StoryQuizRecord(
            storyId: widget.story.id ?? 0,
            mode: widget.mode,
            total: blanks.length,
            correct: blanks.length - wrongs.length,
            wrongBlanks: wrongs,
            createdAt: DateTime.now(),
          ));
      // 通知短文中心 / 记忆库刷新（测试统计变化）
      ref.read(storyVersionProvider.notifier).state++;
    } catch (_) {
      // 记录失败不影响答题体验
    }
  }

  /// 将勾选的错词加入词库
  Future<void> _addWrongToLibrary() async {
    if (_selectedWrongWords.isEmpty) return;
    setState(() => _addingToLibrary = true);
    try {
      final dao = ref.read(storyQuizDaoProvider);
      final added = dao.addWrongWordsToLibrary(
        _selectedWrongWords.toList(),
        storyId: widget.story.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(added.isEmpty
              ? '所选词均已在词库中'
              : '已加入 ${added.length} 个词到词库')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加入词库失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _addingToLibrary = false);
    }
  }

  /// 点击空格：复习弹 4 选项；巩固/拓展设置焦点（键盘输入+回车跳下一个）；
  /// 提交后点击错词 → 弹正确答案卡
  Future<void> _tapBlank(int index) async {
    final blank = _quiz.blanks[index];

    // 提交后：答对无动作；答错弹正确答案卡
    if (_submitted) {
      if (_results[index] == true) return;
      await _showAnswerCard(index, blank);
      return;
    }

    if (widget.mode == StoryQuizMode.review) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选择填空的单词', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: blank.options
                      .map((opt) => ChoiceChip(
                            label: Text(opt),
                            selected: _answers[index] == opt,
                            onSelected: (_) {
                              setState(() => _answers[index] = opt);
                              Navigator.pop(ctx);
                            },
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      );
      if (picked != null) setState(() => _answers[index] = picked);
    } else {
      // 巩固/拓展：点击空格 = 聚焦该空格，直接键盘输入
      setState(() {
        _focusIndex = index;
        _inputCtrl.text = _answers[index] ?? '';
        _inputCtrl.selection =
            TextSelection.collapsed(offset: _inputCtrl.text.length);
      });
      _inputFocus.requestFocus();
    }
  }

  /// 提交后点击错词：弹正确答案卡（含加入词库快捷操作）
  Future<void> _showAnswerCard(int index, QuizBlank blank) async {
    final theme = Theme.of(context);
    final isSelected = _selectedWrongWords.contains(blank.word);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Text(
                '${index + 1}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('错题答案'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '你的答案：${_answers[index]?.isEmpty == true ? '未填' : _answers[index]}',
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '正确答案：${blank.word}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              setState(() {
                if (isSelected) {
                  _selectedWrongWords.remove(blank.word);
                } else {
                  _selectedWrongWords.add(blank.word);
                }
              });
              Navigator.pop(ctx, true);
            },
            icon: Icon(
              isSelected ? Icons.check_box_outlined : Icons.playlist_add,
              size: 18,
            ),
            label: Text(isSelected ? '已选，点击取消' : '加入词库'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      // 弹窗内已更新勾选状态，无需额外处理
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final story = widget.story;
    final correctCount =
        _results.values.where((ok) => ok).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('${widget.mode.label}测试'),
        actions: [
          // 拓展模式：中文翻译显示开关
          if (widget.mode == StoryQuizMode.extend &&
              !_submitted &&
              _sentences.any((s) => s.translation.isNotEmpty))
            TextButton.icon(
              onPressed: () =>
                  setState(() => _showTranslation = !_showTranslation),
              icon: Icon(
                _showTranslation
                    ? Icons.translate
                    : Icons.translate_outlined,
                size: 18,
              ),
              label: Text(_showTranslation ? '隐藏翻译' : '显示翻译'),
            ),
          if (!_submitted)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  '${_answers.length}/${_quiz.blanks.length}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          const AppBackground(),
          _quiz.isEmpty
              ? Center(
                  child: Text(
                    '该短文没有可挖空的词',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // 短文整篇呈现（复习/巩固）或逐句卡片（拓展）
                          if (widget.mode == StoryQuizMode.extend)
                            _buildSentenceList(theme)
                          else
                            GlassContainer(
                              blur: 16,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    story.title.isEmpty
                                        ? '未命名短文'
                                        : story.title,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.mode.desc,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _buildStoryBody(theme),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),
                          if (!_submitted)
                            GlassButton(
                              onPressed: _quiz.isEmpty ? null : _submit,
                              icon: Icons.task_alt,
                              label: '提交判定',
                              tinted: true,
                            )
                          else ...[
                            _buildResultSection(theme, correctCount),
                          ],
                        ],
                      ),
                    ),
                    // 底部内联输入栏（巩固/拓展模式，未提交时显示）
                    if (!_submitted &&
                        widget.mode != StoryQuizMode.review &&
                        _quiz.blanks.isNotEmpty)
                      _buildInputBar(theme),
                  ],
                ),
        ],
      ),
    );
  }

  /// 底部内联输入栏：输入 + 回车自动跳下一个空格
  Widget _buildInputBar(ThemeData theme) {
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _focusIndex < 0
                      ? '已填完'
                      : '第 ${_focusIndex + 1} 空',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  focusNode: _inputFocus,
                  enabled: _focusIndex >= 0,
                  autofocus: widget.mode != StoryQuizMode.review,
                  textCapitalization: TextCapitalization.none,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: _focusIndex < 0
                        ? '全部填完，可提交判定'
                        : '输入第 ${_focusIndex + 1} 空的单词，回车跳到下一个',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onSubmitted: _onInputSubmitted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 拓展模式：一句一题渲染
  Widget _buildSentenceList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '逐句默写：每句一题，默写句中所有实词',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_sentences.any((s) => s.translation.isNotEmpty))
              Text(
                _showTranslation ? '已显示中文对照' : '中文对照已隐藏',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ..._sentences.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassContainer(
                // 逐句卡片：静态玻璃（blur 0）避免滚动掉帧
                blur: 0,
                elevated: false,
                radius: 14,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      // 句子序号
                      Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${s.index}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '第 ${s.index} 句',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // 挖空句
                      _buildTokensLine(theme, s.tokens),
                      // 中文翻译（开关控制）
                      if (_showTranslation) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            s.translation.isEmpty
                                ? '（暂无中文翻译）'
                                : s.translation,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            )),
      ],
    );
  }

  /// 渲染单行 token（逐句模式共用，聚焦/判分样式一致）
  Widget _buildTokensLine(ThemeData theme, List<QuizToken> tokens) {
    final children = <Widget>[];
    for (final token in tokens) {
      if (token.isBlank) {
        final idx = token.blankIndex!;
        children.add(_BlankWidget(
          theme: theme,
          token: _quiz.blanks[idx].word,
          isBlank: true,
          index: idx + 1,
          answer: _answers[idx],
          submitted: _submitted,
          isCorrect: _results[idx],
          isFocused: !_submitted && _focusIndex == idx,
          onTap: () => _tapBlank(idx),
          mode: widget.mode,
        ));
      } else {
        children.add(Text(token.text));
      }
    }
    return Wrap(
      spacing: 0,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  /// 整篇渲染：按引擎返回的 token 序列渲染，空格渲染为可点击填空框
  Widget _buildStoryBody(ThemeData theme) {
    final children = <Widget>[];
    for (final token in _quiz.tokens) {
      if (token.isBlank) {
        final idx = token.blankIndex!;
        children.add(_BlankWidget(
          theme: theme,
          token: _quiz.blanks[idx].word,
          isBlank: true,
          index: idx + 1,
          answer: _answers[idx],
          submitted: _submitted,
          isCorrect: _results[idx],
          isFocused: !_submitted && _focusIndex == idx,
          onTap: () => _tapBlank(idx),
          mode: widget.mode,
        ));
      } else {
        children.add(Text(token.text));
      }
    }
    return Wrap(
      spacing: 0,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  /// 结果区：得分 + 错题回顾 + 错词勾选加入词库
  Widget _buildResultSection(ThemeData theme, int correctCount) {
    final blanks = _quiz.blanks;
    final wrongs = <int>[];
    _results.forEach((i, ok) {
      if (!ok) wrongs.add(i);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassContainer(
          blur: 16,
          tint: theme.colorScheme.primary,
          child: Column(
            children: [
              Text(
                '得分 $correctCount/${blanks.length}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                correctCount == blanks.length
                    ? '全部答对，太棒了！'
                    : '答错的词可加入词库继续复习',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (wrongs.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('错题回顾', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          GlassContainer(
            blur: 0,
            elevated: false,
            radius: 14,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: wrongs.map((i) {
                  final blank = blanks[i];
                  final isSelected = _selectedWrongWords.contains(blank.word);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 你的答案（错误，删除线）
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer
                                  .withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '你的答案：${_answers[i]?.isEmpty == true ? '未填' : _answers[i]}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                decoration: TextDecoration.lineThrough,
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 正确答案（直接显示，无需展开）
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '正确答案：${blank.word}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 勾选加入词库
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: isSelected,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedWrongWords.add(blank.word);
                          } else {
                            _selectedWrongWords.remove(blank.word);
                          }
                        }),
                        title: Text(
                          '加入词库',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (i != wrongs.last)
                        const Divider(height: 1),
                    ],
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() {
                  if (_selectedWrongWords.length == wrongs.length) {
                    _selectedWrongWords.clear();
                  } else {
                    _selectedWrongWords
                        .addAll(wrongs.map((i) => blanks[i].word));
                  }
                }),
                icon: const Icon(Icons.select_all, size: 18),
                label: Text(_selectedWrongWords.length == wrongs.length
                    ? '取消全选'
                    : '全部选择'),
              ),
              const Spacer(),
              GlassButton(
                onPressed: _addingToLibrary
                    ? null
                    : (_selectedWrongWords.isEmpty
                        ? null
                        : _addWrongToLibrary),
                icon: Icons.playlist_add,
                label: _addingToLibrary
                    ? '加入中...'
                    : '加入词库 (${_selectedWrongWords.length})',
                tinted: true,
                height: 44,
                blur: 0,
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回'),
              ),
            ),
            if (_nextStoryId != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: GlassButton(
                  onPressed: () => context.pushReplacement(
                      '/story-quiz/$_nextStoryId/${widget.mode.name}'),
                  icon: Icons.arrow_forward,
                  label: '下一篇短文',
                  tinted: true,
                  height: 48,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 单个填空框组件（带题号角标 + 焦点高亮）
class _BlankWidget extends StatelessWidget {
  final ThemeData theme;
  final String token;
  final bool isBlank;
  /// 题号（1 起）
  final int? index;
  final String? answer;
  final bool submitted;
  final bool? isCorrect;
  /// 是否当前聚焦（巩固/拓展模式）
  final bool isFocused;
  final VoidCallback onTap;
  final StoryQuizMode mode;

  const _BlankWidget({
    required this.theme,
    required this.token,
    required this.isBlank,
    this.index,
    required this.answer,
    required this.submitted,
    required this.isCorrect,
    this.isFocused = false,
    required this.onTap,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    if (!isBlank) return Text(token);

    final hasAnswer = answer != null && answer!.isNotEmpty;
    Color? color;
    if (submitted) {
      color = isCorrect == true
          ? (Theme.of(context).brightness == Brightness.dark
              ? AppColors.ratingGoodDark
              : AppColors.ratingGood)
          : theme.colorScheme.error;
    } else if (hasAnswer) {
      color = theme.colorScheme.primary;
    }

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 题号角标
          Text(
            '${index ?? ''}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.0,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: hasAnswer
                  ? (color ?? theme.colorScheme.primaryContainer)
                      .withValues(alpha: 0.15)
                  : theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isFocused
                    ? theme.colorScheme.primary
                    : (color ?? theme.colorScheme.outlineVariant),
                width: isFocused ? 2 : (submitted ? 1.5 : 1),
              ),
            ),
            child: Text(
              hasAnswer ? answer! : '____',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isFocused ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
