/// ECDICT 标签转换工具
/// 将 ECDICT 编码标签（如 cet4, ky, ielts）转为用户友好标签
class TagUtils {
  TagUtils._();

  /// ECDICT 标签编码 → 用户友好标签
  static const Map<String, String> _tagMap = {
    'zk': '中考',
    'gk': '高考',
    'cet4': 'CET-4',
    'cet6': 'CET-6',
    'ky': '考研',
    'ielts': '雅思',
    'toefl': '托福',
    'gre': 'GRE',
  };

  /// 将 ECDICT 标签字符串转为用户友好标签（逗号分隔）
  /// 例: "cet4 ky ielts" → "CET-4,考研,雅思"
  static String convertTags(String? ecdictTags) {
    if (ecdictTags == null || ecdictTags.trim().isEmpty) return '';
    final parts = ecdictTags.split(' ').where((t) => t.trim().isNotEmpty);
    final labels = parts.map((t) => _tagMap[t.trim()] ?? t.trim());
    return labels.join(',');
  }

  /// 将 ECDICT 标签字符串转为用户友好标签列表
  /// 例: "cet4 ky ielts" → ["CET-4", "考研", "雅思"]
  static List<String> convertTagList(String? ecdictTags) {
    if (ecdictTags == null || ecdictTags.trim().isEmpty) return [];
    final parts = ecdictTags.split(' ').where((t) => t.trim().isNotEmpty);
    return parts.map((t) => _tagMap[t.trim()] ?? t.trim()).toList();
  }

  /// 将用户友好标签列表转为逗号分隔字符串
  static String joinTags(List<String> tags) {
    return tags.where((t) => t.trim().isNotEmpty).join(',');
  }
}
