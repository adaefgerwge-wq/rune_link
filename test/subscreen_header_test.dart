import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rune_link/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Player.reset();
  });

  /// その文字を そのまま描くのに必要な よこ幅
  double naturalWidth(String text, TextStyle style) {
    final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr)
      ..layout();
    return tp.width;
  }

  testWidgets('サブ画面の見出しが 省略されずに 全部出る', (tester) async {
    // 実機の よこ幅で見る
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // ⭐が4けたでも 見出しが つぶれないこと
    Player.stars = 9999;
    Player.trophies = 999;

    const style = TextStyle(
        fontSize: 19, fontWeight: FontWeight.w800, color: kInk);

    for (final title in ['マイページ', 'ちょうせん', 'ショップ', 'ミッション']) {
      await tester.pumpWidget(
          MaterialApp(home: SubScreen(title: title, children: const [])));
      await tester.pump();

      final box = tester.getRect(find.text(title));
      final need = naturalWidth(title, style);
      expect(box.width + 0.5 >= need, isTrue,
          reason: '★「$title」が ${box.width} しかなく '
              '$need 必要＝「…」で けずられている');
    }
  });
}
