import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rune_link/main.dart';

void main() {
  test('光の粒は時間とともに動いて消える', () {
    final r = Random(3);
    final s = Spark.at(const Offset(100, 100), 0, r);
    final p0 = s.posAt(0);
    final p1 = s.posAt(0.3);
    expect(p0, const Offset(100, 100));
    expect(p1 != p0, true, reason: '動いていない');
    expect(s.fadeAt(0), closeTo(1.0, 0.01), reason: '出た直後は くっきり');
    expect(s.fadeAt(Spark.life / 2), closeTo(0.5, 0.05), reason: '半分で うすく');
    expect(s.fadeAt(Spark.life + 0.1), 0.0, reason: '寿命がきたら 消える');
  });

  testWidgets('指でなぞると 軌跡に光の粒が出る', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    Player.tutorialDone = true; // あそびかたは 見たことにする
    await tester.pumpWidget(const MaterialApp(home: BattleScreen(stage: 1)));
    // ローディングが終わるまで待つ
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    StrokePainter painter() => tester
        .widget<CustomPaint>(find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is StrokePainter))
        .painter as StrokePainter;

    expect(painter().sparks.isEmpty, true, reason: '描く前から粒がある');

    // 下半分をゆっくりなぞる
    final g = await tester.startGesture(const Offset(120, 620));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(14, 6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final n = painter().sparks.length;
    // ignore: avoid_print
    print('SPARKS| なぞった直後の粒の数: $n');
    expect(n > 0, true, reason: '★粒が出ていない');

    await g.up();
    await tester.pump(const Duration(milliseconds: 100));
    // 後片づけ
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  });
}
