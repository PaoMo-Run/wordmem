import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('flutter 引擎探针：flutter_tester 是否可用', (tester) async {
    await tester.pumpWidget(const SizedBox());
    expect(true, isTrue);
  });
}
