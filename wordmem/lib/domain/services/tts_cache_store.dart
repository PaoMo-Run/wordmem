import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 判断字节序列是否像有效 mp3 音频（ID3 标签头或 MPEG 帧同步 0xFFEx）。
///
/// 用于拒绝把 HTML 错误页 / JSON 响应当音频缓存或播放。
bool isLikelyMp3(List<int> bytes) {
  if (bytes.length < 4) return false;
  // "ID3" 标签头（ID3v2）
  if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) return true;
  // MPEG 帧同步：0xFF 后跟 0xE0~0xFF（11111111 111xxxxx）
  if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) return true;
  return false;
}

/// 单词发音本地缓存（持久目录，每词仅取一次在线音频）。
///
/// - 文件名：小写清洗白名单 `[a-z0-9]` + md5 前 8 位后缀（防清洗碰撞）；
/// - 读：存在 + 魔数合法才返回（坏文件返回 null）；
/// - 写：tmp → rename 原子写，成功后异步触发限额清理（不阻塞播放）。
class TtsCacheStore {
  TtsCacheStore({required String cacheDir}) : _dir = Directory(cacheDir);

  /// 缓存总大小上限（默认 50MB）。
  static const int defaultMaxBytes = 50 * 1024 * 1024;

  /// 清理目标比例：裁剪到限额的 80%。
  static const double _trimTargetRatio = 0.8;

  final Directory _dir;

  Directory get directory => _dir;

  /// 由单词生成缓存文件名（公开供测试与调试）。
  String fileName(String word) {
    final lower = word.toLowerCase();
    final sanitized = lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final hash = md5.convert(utf8.encode(lower)).toString();
    final stem = sanitized.isEmpty ? 'word' : sanitized;
    return '$stem-${hash.substring(0, 8)}.mp3';
  }

  /// 取已缓存的音频文件；不存在或内容不像 mp3 时返回 null。
  File? get(String word) {
    final f = File(p.join(_dir.path, fileName(word)));
    if (!f.existsSync()) return null;
    RandomAccessFile? raf;
    try {
      if (f.lengthSync() < 4) return null;
      raf = f.openSync();
      final head = raf.readSync(4);
      if (!isLikelyMp3(head)) return null;
      return f;
    } catch (_) {
      return null;
    } finally {
      raf?.closeSync();
    }
  }

  /// 原子写入缓存并异步触发限额清理。
  Future<File> put(String word, List<int> bytes) async {
    await _dir.create(recursive: true);
    final target = File(p.join(_dir.path, fileName(word)));
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
    // 清理不阻塞播放（默认限额 50MB，一般不会触发）
    unawaited(trim());
    return target;
  }

  /// 按修改时间从最旧开始裁剪，直到总大小 ≤ [maxBytes] 的 80%。
  Future<void> trim({int maxBytes = defaultMaxBytes}) async {
    if (!_dir.existsSync()) return;
    final stats = <(File, int, DateTime)>[];
    var total = 0;
    for (final entity in _dir.listSync()) {
      if (entity is! File) continue;
      try {
        final st = entity.statSync();
        total += st.size;
        stats.add((entity, st.size, st.modified));
      } catch (_) {
        // 读不到状态的文件跳过
      }
    }
    if (total <= maxBytes) return;
    stats.sort((a, b) => a.$3.compareTo(b.$3)); // 最旧在前
    final target = (maxBytes * _trimTargetRatio).floor();
    for (final (file, size, _) in stats) {
      if (total <= target) break;
      try {
        await file.delete();
        total -= size;
      } catch (_) {
        // 删除失败（被占用等）跳过，下轮再清
      }
    }
  }
}
