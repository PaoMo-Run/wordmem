import 'package:flutter/material.dart';

/// 复习方向
enum ReviewDirection {
  /// 英译汉：看英文回想中文释义
  enToZh,
  /// 汉译英：看中文释义拼写英文单词
  zhToEn,
  /// 混合：每张卡片随机选择方向
  mixed,
}

extension ReviewDirectionX on ReviewDirection {
  String get label => switch (this) {
        ReviewDirection.enToZh => '英译汉',
        ReviewDirection.zhToEn => '汉译英',
        ReviewDirection.mixed => '混合',
      };

  String get desc => switch (this) {
        ReviewDirection.enToZh => '看单词，回想释义',
        ReviewDirection.zhToEn => '看释义，拼写单词',
        ReviewDirection.mixed => '两种方向随机出现',
      };

  IconData get icon => switch (this) {
        ReviewDirection.enToZh => Icons.translate,
        ReviewDirection.zhToEn => Icons.spellcheck,
        ReviewDirection.mixed => Icons.shuffle,
      };
}
