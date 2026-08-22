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

  /// 画面の下半分に その印を描く
  Future<void> draw(WidgetTester tester, Elem e,
      {int settleMs = 2000}) async {
    const c = Offset(187, 620);
    final pts = <Offset>[];
    switch (e) {
      case Elem.water: // ◯
        for (var i = 0; i <= 28; i++) {
          final a = i / 28 * 2 * pi;
          pts.add(c + Offset(cos(a) * 60, sin(a) * 60));
        }
        break;
      case Elem.fire: // △
        const corners = [
          Offset(0, -60),
          Offset(60, 55),
          Offset(-60, 55),
          Offset(0, -60),
        ];
        for (var i = 0; i < corners.length - 1; i++) {
          for (var k = 0; k <= 10; k++) {
            pts.add(c + corners[i] + (corners[i + 1] - corners[i]) * (k / 10));
          }
        }
        break;
      case Elem.thunder: // Z
        const corners = [
          Offset(-60, -50),
          Offset(60, -50),
          Offset(-60, 50),
          Offset(60, 50),
        ];
        for (var i = 0; i < corners.length - 1; i++) {
          for (var k = 0; k <= 10; k++) {
            pts.add(c + corners[i] + (corners[i + 1] - corners[i]) * (k / 10));
          }
        }
        break;
    }
    final g = await tester.startGesture(pts.first);
    for (final p in pts.skip(1)) {
      await g.moveTo(p);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    // 攻撃 → 反撃 → 表示 まで進める（長く待つと 知らせが消えてしまう）
    var waited = 0;
    while (waited < settleMs) {
      await tester.pump(const Duration(milliseconds: 100));
      waited += 100;
    }
  }

  Future<dynamic> openBattle(WidgetTester tester, String key) async {
    await tester.pumpWidget(MaterialApp(
        home: BattleScreen(key: ValueKey(key), stage: 1)));
    await tester.pump(const Duration(milliseconds: 2700));
    return tester.state(find.byType(BattleScreen)) as dynamic;
  }

  testWidgets('予告と おなじ印を描くと ダメージが へる', (tester) async {
    usePhone(tester);
    final st = await openBattle(tester, 'guard');
    st.enemyMaxHp = 100000; // 倒して終わらないように
    st.enemyHp = 100000;

    // 予告どおりの印を描く＝受けながす
    final telegraphed = st.nextAtk as Elem;
    final hpBefore = st.playerHp as int;
    await draw(tester, telegraphed, settleMs: 400);
    final guardedLoss = hpBefore - (st.playerHp as int);

    expect(st.turns, 1, reason: '★印が通っていない');
    expect(guardedLoss > 0, isTrue);

    // 受けながしたときの表示が出る（すぐ消えるので この時点で見る）
    expect(find.textContaining('うけながした'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));

    // つぎは わざと ちがう印を描く
    final other =
        Elem.values.firstWhere((e) => e != (st.nextAtk as Elem));
    final hp2 = st.playerHp as int;
    await draw(tester, other);
    final plainLoss = hp2 - (st.playerHp as int);

    expect(plainLoss > guardedLoss, isTrue,
        reason: '★受けながし($guardedLoss)が ふつう($plainLoss)より 減っていない');

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  });

  testWidgets('3ターンごとに よわ点が 入れかわる', (tester) async {
    usePhone(tester);
    final st = await openBattle(tester, 'rotate');
    st.enemyMaxHp = 100000;
    st.enemyHp = 100000;

    final first = st.weakness as Elem;
    for (var i = 0; i < 2; i++) {
      await draw(tester, Elem.water);
    }
    // 3回目は 知らせが出るところで 止める
    // 反撃(260ms) → 知らせ(450ms) のあと 900ms で消える。その間に見る
    await draw(tester, Elem.water, settleMs: 1000);
    expect(st.turns, 3);
    expect(st.weakness != first, isTrue, reason: '★よわ点が かわっていない');
    expect(find.textContaining('よわ点が'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  });

  testWidgets('印がしばられた ちょうせんでは よわ点は 動かない', (tester) async {
    usePhone(tester);
    Player.cleared = kStageCount;
    // ひとつの印（番号1、ひ のみ）
    await tester.pumpWidget(const MaterialApp(
        home: BattleScreen(key: ValueKey('lock'), stage: 2, challenge: 1)));
    await tester.pump(const Duration(milliseconds: 2700));
    final st = tester.state(find.byType(BattleScreen)) as dynamic;
    st.enemyMaxHp = 100000;
    st.enemyHp = 100000;

    expect(st.weakness, Elem.fire);
    for (var i = 0; i < 3; i++) {
      await draw(tester, Elem.fire);
    }
    expect(st.turns, 3);
    expect(st.weakness, Elem.fire,
        reason: '★ひ しか使えないのに よわ点が 動いた＝勝てなくなる');

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  });
}
