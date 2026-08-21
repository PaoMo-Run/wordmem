/// 短文生成来源
enum StorySource {
  /// 离线模板引擎（已弃用，仅兼容历史数据）
  template,
  /// AI 生成
  ai,
  /// 手动导入（剪贴板/分享中转自其它 AI App）
  manual;

  static StorySource fromName(String? name) {
    return switch (name) {
      'ai' => StorySource.ai,
      'manual' => StorySource.manual,
      _ => StorySource.template,
    };
  }
}

/// 短文实体（生成历史 / 记忆库条目）
class Story {
  final int? id;
  final String title;
  /// 英文正文
  final String content;
  /// 中文对照（AI 生成或模板逐句翻译）
  final String translation;
  /// 生成所用单词（逗号分隔存储，模型为列表）
  final List<String> words;
  final StorySource source;
  /// 是否归档到记忆库（true 才在记忆库页展示）
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Story({
    this.id,
    this.title = '',
    required this.content,
    this.translation = '',
    this.words = const [],
    this.source = StorySource.template,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Story.fromMap(Map<String, dynamic> m) {
    final wordsStr = (m['words'] as String?) ?? '';
    return Story(
      id: m['id'] as int,
      title: (m['title'] as String?) ?? '',
      content: (m['content'] as String?) ?? '',
      translation: (m['translation'] as String?) ?? '',
      words: wordsStr.isEmpty
          ? const []
          : wordsStr.split(',').where((w) => w.trim().isNotEmpty).toList(),
      source: StorySource.fromName(m['source'] as String?),
      archived: ((m['archived'] as int?) ?? 0) == 1,
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'content': content,
        'translation': translation,
        'words': words.join(','),
        'source': source.name,
        'archived': archived ? 1 : 0,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  Story copyWith({
    int? id,
    String? title,
    String? content,
    String? translation,
    List<String>? words,
    StorySource? source,
    bool? archived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Story(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      translation: translation ?? this.translation,
      words: words ?? this.words,
      source: source ?? this.source,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 生成所用的富化单词（词 + 词性 + 中文释义）
class StoryWord {
  final String word;
  final String? pos;
  final String translation;

  const StoryWord({required this.word, this.pos, required this.translation});
}
