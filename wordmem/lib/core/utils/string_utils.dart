/// 字符串工具
class StringUtils {
  StringUtils._();

  /// 从文本中提取英文单词
  static List<String> extractWords(String text) {
    final regex = RegExp(r"[a-zA-Z][a-zA-Z'\-]*[a-zA-Z]|[a-zA-Z]");
    final words = <String>[];
    for (final match in regex.allMatches(text)) {
      final word = match.group(0)!;
      if (word.length >= 2) {
        words.add(word);
      }
    }
    return words;
  }

  /// 判断是否包含中文
  static bool containsChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  }

  /// 截断字符串
  static String truncate(String text, int maxLen, {String suffix = '...'}) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}$suffix';
  }

  /// 格式化日期
  static String formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 格式化相对时间
  static String relativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}周前';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月前';
    return '${(diff.inDays / 365).floor()}年前';
  }

  /// 格式化下次复习时间
  static String formatDue(DateTime? due) {
    if (due == null) return '未安排';
    final now = DateTime.now();
    final diff = due.difference(now);
    if (diff.isNegative) return '待复习';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟后';
    if (diff.inHours < 24) return '${diff.inHours}小时后';
    if (diff.inDays < 30) return '${diff.inDays}天后';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月后';
    return '${(diff.inDays / 365).floor()}年后';
  }
}
