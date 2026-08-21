import 'package:sqlite3/sqlite3.dart';
import 'app_database.dart';
import '../../domain/models/story.dart';

/// 短文 DAO - story_logs 表操作（生成历史 + 记忆库）
class StoryDao {
  final AppDatabase _db;
  StoryDao(this._db);

  Database get _v => _db.vocab;

  /// 插入短文，返回自增 id
  int insert(Story story) {
    _v.execute(
      '''INSERT INTO story_logs
         (title, content, translation, words, source, archived, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        story.title,
        story.content,
        story.translation,
        story.words.join(','),
        story.source.name,
        story.archived ? 1 : 0,
        story.createdAt.toUtc().toIso8601String(),
        story.updatedAt.toUtc().toIso8601String(),
      ],
    );
    return _v.select('SELECT last_insert_rowid() as id').first['id'] as int;
  }

  /// 更新短文（编辑内容 / 标题 / 翻译 / 归档状态），刷新 updated_at
  void update(Story story) {
    _v.execute(
      '''UPDATE story_logs SET
         title = ?, content = ?, translation = ?, words = ?,
         source = ?, archived = ?, updated_at = ?
         WHERE id = ?''',
      [
        story.title,
        story.content,
        story.translation,
        story.words.join(','),
        story.source.name,
        story.archived ? 1 : 0,
        DateTime.now().toUtc().toIso8601String(),
        story.id,
      ],
    );
  }

  /// 按 id 查询
  Story? getById(int id) {
    final rows = _v.select('SELECT * FROM story_logs WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return Story.fromMap(rows.first);
  }

  /// 查询列表（记忆库按更新时间倒序）
  /// [archived] 为空查全部；true 只查已归档；false 只查未归档
  List<Story> getAll({bool? archived}) {
    final args = <Object?>[];
    var where = '';
    if (archived != null) {
      where = 'WHERE archived = ?';
      args.add(archived ? 1 : 0);
    }
    final rows =
        _v.select('SELECT * FROM story_logs $where ORDER BY updated_at DESC', args);
    return rows.map((r) => Story.fromMap(r)).toList();
  }

  /// 设置归档状态
  void setArchived(int id, bool archived) {
    _v.execute(
      'UPDATE story_logs SET archived = ?, updated_at = ? WHERE id = ?',
      [archived ? 1 : 0, DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  /// 删除短文
  void delete(int id) {
    _v.execute('DELETE FROM story_logs WHERE id = ?', [id]);
  }

  /// 总条数
  int count() {
    return _v.select('SELECT COUNT(*) as c FROM story_logs').first['c'] as int;
  }
}
