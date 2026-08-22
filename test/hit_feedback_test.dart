import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rune_link/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Player.reset();
    Player.tutorialDone = true;
  });

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  List<Offset> shape(Elem e) {
    const c = Offset(187, 620);
    final pts = <Offset>[];
    void line(List<Offset> corners) {
      for (var i = 0; i < corners.length - 1; i++) {
        for (var k = 0; k <= 10; k++) {
          pts.add(c + corners[i] + (corners[i + 1] - corners[i]) * (k / 10));
        }
      }
    }

    switch (e) {
      case Elem.water:
        for (var i = 0; i <= 28; i++) {
          final a = i / 28 * 2 * pi;
          pts.add(c + Offset(cos(a) * 60, sin(a) * 60));
        }
        break;
      case Elem.fire:
        line(const [
          Offset(0, -60),
          Offset(60, 55),
          Offset(-60, 55),
          Offset(0, -60),
        ]);
        break;
      case Elem.thunder:
        line(const [
          Offset(-60, -50),
          Offset(60, -50),
          Offset(-60, 50),
          Offset(60, 50),
        ]);
        break;
    }
    return pts;
  }

  Future<void> drawPoints(WidgetTester tester, List<Offset> pts,
      {int settleMs = 500}) async {
    final g = await tester.startGesture(pts.first);
    for (final p in pts.skip(1)) {
      await g.moveTo(p);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    var waited = 0;
    while (waited < settleMs) {
      await tester.pump(const Duration(milliseconds: 100));
      waited += 100;
    }
  }

  Future<dynamic> openBattle(WidgetTester tester, String key) async {
    await tester.pumpWidget(
        MaterialApp(home: BattleScreen(key: ValueKey(key), stage: 1)));
    await tester.pump(const Duration(milliseconds: 2700));
    return tester.state(find.byType(BattleScreen)) as dynamic;
  }

  Future<void> cleanup(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('描いた印が 何と よまれたか 出る', (tester) async {
    usePhone(tester);
    final st = await openBattle(tester, 'read');
    st.enemyMaxHp = 100000;
    st.enemyHp = 100000;

    await drawPoints(tester, shape(Elem.water));

    // 形・名前・きれいさ が そろって出る
    expect(find.text('◯'), findsWidgets, reason: '★形が 出ていない');
    expect(find.text('みず'), findsWidgets, reason: '★名前が 出ていない');
    expect(find.textContaining('きれいさ'), findsOneWidget,
        reason: '★どれくらい きれいだったか 出ていない');

    await cleanup(tester);
  });

  testWidgets('弱点だったときは そう書いてある', (tester) async {
    usePhone(tester);
    final st = await openBattle(tester, 'weak');
    st.enemyMaxHp = 100000;
    st.enemyHp = 100000;
    st.weakness = Elem.fire; // △が弱点になるようにしておく
    st.nextAtk = Elem.water; // うけには ならないように

    await drawPoints(tester, shape(Elem.fire));
    expect(find.text('弱点 ×2'), findsOneWidget,
        reason: '★2ばいだった理由が 出ていない');

    await cleanup(tester);
  });

  testWidgets('うけの かまえに なったときも そう書いてある', (tester) async {
    usePhone(tester);
    final st = await openBattle(tester, 'guard');
    st.enemyMaxHp = 100000;
    st.enemyHp = 100000;
    st.weakness = Elem.thunder;
    st.nextAtk = Elem.water; // ◯を描けば うけ

    await drawPoints(tester, shape(Elem.water));
    expect(find.text('うけの かまえ'), findsOneWidget);
    expect(find.text('弱点 ×2'), findsNothing, reason: '★弱点でないのに 2ばい表示');

    await cleanup(tester);
  });

  testWidgets('よみとれないときは 近かった印を 教える', (tester) async {
    usePhone(tester);
    final st = await openBattle(tester, 'miss');
    st.enemyMaxHp = 100000;
    st.enemyHp = 100000;

    // 点が少なすぎる線＝形として読み取れない
    // （認識器は かなり ゆるいので、崩れた形は だいたい通ってしまう）
    await drawPoints(tester, const [
      Offset(120, 620),
      Offset(150, 624),
      Offset(180, 628),
      Offset(205, 632),
    ]);

    expect(find.text('よみとれなかった'), findsOneWidget);
    expect(find.textContaining('ゆっくり'), findsOneWidget,
        reason: '★どう直せばいいか 出ていない');
    expect(st.turns, 0, reason: '★よみとれていないのに ターンが進んだ');

    await cleanup(tester);
  });

  testWidgets('つぎを描きはじめると 前の判定は 消える', (tester) async {
    usePhone(tester);
    final st = await openBattle(tester, 'clear');
    st.enemyMaxHp = 100000;
    st.enemyHp = 100000;

    await drawPoints(tester, shape(Elem.water));
    expect(find.textContaining('きれいさ'), findsOneWidget);

    // つぎの線を 描きはじめる
    final g = await tester.startGesture(const Offset(120, 620));
    await g.moveBy(const Offset(10, 4));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.textContaining('きれいさ'), findsNothing);
    await g.up();

    await cleanup(tester);
  });
}
