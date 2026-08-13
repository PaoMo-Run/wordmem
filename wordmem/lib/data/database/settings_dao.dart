import 'package:sqlite3/sqlite3.dart';
import 'app_database.dart';

/// 设置 DAO - app_settings + fsrs_params
class SettingsDao {
  final AppDatabase _db;
  SettingsDao(this._db);

  Database get _v => _db.vocab;

  /// 获取设置值
  String? get(String key) {
    final rows = _v.select('SELECT value FROM app_settings WHERE key = ?', [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  /// 获取设置值（带默认值）
  String getOrDefault(String key, String defaultValue) {
    return get(key) ?? defaultValue;
  }

  /// 设置值
  void set(String key, String value) {
    final now = DateTime.now().toUtc().toIso8601String();
    _v.execute(
      '''INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at''',
      [key, value, now],
    );
  }

  /// 获取 FSRS 参数
  Map<String, dynamic>? getFsrsParams() {
    final rows = _v.select('SELECT * FROM fsrs_params WHERE id = 1');
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// 更新 FSRS 参数
  void updateFsrsParams({
    String? parameters,
    double? desiredRetention,
    String? optimizedAt,
    int? reviewCount,
    int? isActive,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    final sets = <String>[];
    final args = <Object?>[];
    if (parameters != null) { sets.add('parameters = ?'); args.add(parameters); }
    if (desiredRetention != null) { sets.add('desired_retention = ?'); args.add(desiredRetention); }
    if (optimizedAt != null) { sets.add('optimized_at = ?'); args.add(optimizedAt); }
    if (reviewCount != null) { sets.add('review_count = ?'); args.add(reviewCount); }
    if (isActive != null) { sets.add('is_active = ?'); args.add(isActive); }
    sets.add('updated_at = ?');
    args.add(now);
    args.add(1);
    _v.execute('UPDATE fsrs_params SET ${sets.join(', ')} WHERE id = ?', args);
  }

  /// 获取目标记忆率
  double getDesiredRetention() {
    final params = getFsrsParams();
    if (params == null) return 0.9;
    return (params['desired_retention'] as num?)?.toDouble() ?? 0.9;
  }

  /// 设置目标记忆率
  void setDesiredRetention(double value) {
    updateFsrsParams(desiredRetention: value);
  }
}
