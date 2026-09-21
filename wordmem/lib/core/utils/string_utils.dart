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

  /// 格式化相对时间（过去）
  ///
  /// v2.1.8：**每一级都要带上下级单位**——原来超过 24 小时就只剩「N天前」，
  /// 把小时丢掉了（用户反馈：复习时间记录看不出"到底多久之前"）。
  /// 现在天级显示 `N天M小时前`，周/月/年级同样带下级。
  static String relativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时${diff.inMinutes % 60}分钟前';
    if (diff.inDays < 7) return '${diff.inDays}天${diff.inHours % 24}小时前';
    if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()}周${diff.inDays % 7}天前';
    }
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      final restDays = diff.inDays - months * 30;
      return '${months}个月${restDays}天前';
    }
    final years = (diff.inDays / 365).floor();
    return '${years}年${diff.inDays - years * 365}天前';
  }

  /// 格式化下次复习时间（未来）
  ///
  /// v2.1.8：同 [relativeTime]，每一级带上下级单位（`N天M小时后`），
  /// 不再出现"超过 24 小时就只显示 N天后"的信息损失。
  static String formatDue(DateTime? due) {
    if (due == null) return '未安排';
    final now = DateTime.now();
    final diff = due.difference(now);
    if (diff.isNegative) return '待复习';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟后';
    if (diff.inHours < 24) return '${diff.inHours}小时${diff.inMinutes % 60}分钟后';
    if (diff.inDays < 30) return '${diff.inDays}天${diff.inHours % 24}小时后';
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      final restDays = diff.inDays - months * 30;
      return '${months}个月${restDays}天后';
    }
    final years = (diff.inDays / 365).floor();
    return '${years}年${diff.inDays - years * 365}天后';
  }
}
