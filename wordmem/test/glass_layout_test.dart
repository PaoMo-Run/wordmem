import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordmem/shared/widgets/glass.dart';

/// 玻璃组件尺寸回归测试
///
/// 背景（2026-08-31）：点击修复把 GlassContainer 改成
/// `Stack(fit: StackFit.expand)`，导致 Stack 撑到父约束最大尺寸——
/// nav dock 5 个胶囊全部全屏高、盖死内容。修复后装饰层走
/// `Positioned.fill`、内容层决定尺寸。
void main() {
  const seed = Color(0xFF00897B);

  Widget navBarApp(ValueChanged<int> onChanged) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
      ),
      home: Scaffold(
        bottomNavigationBar: GlassNavBar(
          currentIndex: 0,
          onChanged: onChanged,
          destinations: const [
            GlassNavDestination(
                icon: Icons.today_outlined,
                selectedIcon: Icons.today,
                label: '今日'),
            GlassNavDestination(
                icon: Icons.play_circle_outline,
                selectedIcon: Icons.play_circle,
                label: '复习'),
            GlassNavDestination(
                icon: Icons.auto_stories_outlined,
                selectedIcon: Icons.auto_stories,
                label: '短文'),
            GlassNavDestination(
                icon: Icons.menu_book_outlined,
                selectedIcon: Icons.menu_book,
                label: '词库'),
            GlassNavDestination(
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
                label: '我的'),
          ],
        ),
      ),
    );
  }

  testWidgets('GlassNavBar 高度由内容决定，不铺满全屏（回归：全屏 bug）',
      (tester) async {
    // 逻辑屏幕 360×800（1080/3.0 × 2400/3.0）
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(navBarApp((_) {}));

    final size = tester.getSize(find.byType(GlassNavBar));
    // 修复前：每个胶囊 StackFit.expand → 高 = 全屏 800；
    // 修复后：内容高（图标+标签+padding）≈ 60-90。
    expect(
      size.height,
      lessThan(150),
      reason: '悬浮 dock 不应铺满全屏，实际高度 ${size.height}',
    );
  });

  testWidgets('GlassButton 高度 = 指定值，不撑满可用高度', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
      home: Scaffold(
        body: Center(
          child: GlassButton(onPressed: () {}, label: '添加单词'),
        ),
      ),
    ));

    final size = tester.getSize(find.byType(GlassButton));
    expect(size.height, 54, reason: '按钮高度应等于指定 height');
    // 宽度：内部 Row(mainAxisSize.max) 在宽松约束下撑满可用宽（预期行为，
    // 空态等场景按钮即满宽）；修复前高度会撑到 600 全屏。
    expect(size.width, 360, reason: '宽松约束下按钮应撑满可用宽度');
  });

  testWidgets('点击 nav 胶囊触发 onChanged（点击修复回归保护）', (tester) async {
    var tapped = -1;
    await tester.pumpWidget(navBarApp((i) => tapped = i));

    await tester.tap(find.text('复习'));
    expect(tapped, 1, reason: '点击「复习」胶囊应回调 index=1');

    await tester.tap(find.text('我的'));
    expect(tapped, 4, reason: '点击「我的」胶囊应回调 index=4');
  });
}
