import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rune_link/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Player.reset();
  });

  // このゲームはスマホ向け。テストも実機に近い縦長の画面で見る
  void usePhone(WidgetTester tester, {double height = 812}) {
    tester.view.physicalSize = Size(375, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  test('すすんだステージまでの ちょうせんが ひらく', () {
    Player.cleared = 0;
    expect(Player.challengeOpen(0), isFalse); // ステージ1が必要
    Player.cleared = 1;
    expect(Player.challengeOpen(0), isTrue);
    expect(Player.challengeOpen(1), isFalse); // ステージ2が必要
    Player.cleared = kStageCount;
    for (var i = 0; i < kChallenges.length; i++) {
      expect(Player.challengeOpen(i), isTrue);
    }
  });

  test('はじめては まるごと、2回目からは 少しだけ⭐が入る', () {
    Player.stars = 0;
    final first = Player.recordChallenge(0);
    expect(first, kChallenges[0].reward);
    expect(Player.stars, kChallenges[0].reward);

    final again = Player.recordChallenge(0);
    expect(again, kChallenges[0].repeatReward);
    expect(again < first, isTrue, reason: '★2回目のほうが 多い');
    expect(Player.stars, kChallenges[0].reward + kChallenges[0].repeatReward);
  });

  test('クリアした ちょうせんは セーブされて残る', () async {
    Player.recordChallenge(2);
    await Player.save();
    Player.challengeCleared = {};
    await Player.load();
    expect(Player.challengeCleared, {2});
  });

  test('ちょうせんの敵とHPは 毎回おなじ（乱数で ぶれない）', () {
    // 定義どおりの敵が使われる
    for (final c in kChallenges) {
      expect(c.enemyIndex >= 0 && c.enemyIndex < kEnemies.length, isTrue);
      expect(c.stage >= 1 && c.stage <= kStageCount, isTrue);
    }
  });

  testWidgets('ちょうせん一覧に 6つ出て 未開放は鍵になる', (tester) async {
    usePhone(tester, height: 1400); // 6つぶん 全部見えるように
    Player.cleared = 1; // ステージ1だけクリア
    await tester.pumpWidget(const MaterialApp(home: ChallengeScreen()));
    await tester.pump();

    expect(find.text('はやうち'), findsOneWidget);
    expect(find.text('さいごの しれん'), findsOneWidget);
    expect(find.text('0 / 6 たっせい'), findsOneWidget);
    // ひらいているのは 1つめだけ
    expect(find.text('3ターン いないに たおす'), findsOneWidget);
    expect(find.text('ステージ2を クリアすると ひらく'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNWidgets(5));
  });

  testWidgets('クリア済みは チェックが付き ⭐の表示が2回目の値になる', (tester) async {
    usePhone(tester, height: 1400);
    Player.cleared = kStageCount;
    Player.recordChallenge(0);
    await tester.pumpWidget(const MaterialApp(home: ChallengeScreen()));
    await tester.pump();

    expect(find.text('1 / 6 たっせい'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    // 1つめは 2回目の⭐、まだのものは まるごとの⭐
    expect(find.text('${kChallenges[0].repeatReward}'), findsOneWidget);
    expect(find.text('${kChallenges[1].reward}'), findsOneWidget);
  });

  testWidgets('もちものなしの ちょうせんでは アイテム欄が出ない', (tester) async {
    usePhone(tester);
    Player.cleared = kStageCount;
    Player.addItem('かいふくポーション');

    // どうぐなし（番号2）
    await tester.pumpWidget(const MaterialApp(
        home: BattleScreen(key: ValueKey('ch'), stage: 3, challenge: 2)));
    await tester.pump(const Duration(milliseconds: 2700));
    expect(find.byIcon(Icons.local_drink), findsNothing);

    // ふつうのバトルなら 出る
    await tester.pumpWidget(const MaterialApp(
        home: BattleScreen(key: ValueKey('normal'), stage: 3)));
    await tester.pump(const Duration(milliseconds: 2700));
    expect(find.byIcon(Icons.local_drink), findsOneWidget);
  });

  testWidgets('ちょうせん中は 条件が画面に出る', (tester) async {
    usePhone(tester);
    Player.cleared = kStageCount;
    await tester.pumpWidget(const MaterialApp(
        home: BattleScreen(key: ValueKey('c0'), stage: 1, challenge: 0)));
    await tester.pump(const Duration(milliseconds: 2700));

    expect(find.text('3ターン いないに たおす'), findsOneWidget);
    expect(find.text('のこり 3'), findsOneWidget);
  });

  testWidgets('印がしばられた ちょうせんは その印が弱点になる', (tester) async {
    usePhone(tester);
    Player.cleared = kStageCount;
    // ひとつの印（番号1、ひ のみ）
    await tester.pumpWidget(const MaterialApp(
        home: BattleScreen(key: ValueKey('c1'), stage: 2, challenge: 1)));
    await tester.pump(const Duration(milliseconds: 2700));

    final state = tester.state(find.byType(BattleScreen)) as dynamic;
    expect(state.weakness, Elem.fire);
    expect(find.text('弱点 ひ'), findsOneWidget);
  });

  testWidgets('ちょうせんの敵HPは 何度ひらいても おなじ', (tester) async {
    usePhone(tester);
    Player.cleared = kStageCount;
    Future<int> hpOf(int seq) async {
      await tester.pumpWidget(MaterialApp(
          home: BattleScreen(
              key: ValueKey('seq$seq'), stage: 4, challenge: 3)));
      await tester.pump(const Duration(milliseconds: 2700));
      final st = tester.state(find.byType(BattleScreen)) as dynamic;
      return st.enemyMaxHp as int;
    }

    final a = await hpOf(1);
    final b = await hpOf(2);
    final c = await hpOf(3);
    expect(a, b);
    expect(b, c);
  });

  testWidgets('3ターンで たおせないと ターンぎれで まける', (tester) async {
    usePhone(tester);
    Player.tutorialDone = true;
    Player.cleared = kStageCount;

    await tester.pumpWidget(const MaterialApp(
        home: BattleScreen(key: ValueKey('limit'), stage: 1, challenge: 0)));
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    final state = tester.state(find.byType(BattleScreen)) as dynamic;
    // 3ターンでは 絶対に たおせない量のHPにしておく
    state.enemyMaxHp = 100000;
    state.enemyHp = 100000;

    // 画面の下半分に ◯ を描く＝みずの印（当たらなくても ターンは進む）
    Future<void> drawCircle() async {
      const center = Offset(187, 620);
      const r = 60.0;
      final g = await tester.startGesture(center + const Offset(r, 0));
      for (var i = 1; i <= 28; i++) {
        final a = i / 28 * 2 * pi;
        await g.moveTo(center + Offset(cos(a) * r, sin(a) * r));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      // 攻撃 → 反撃 → 次のターン まで進める
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    expect(state.turns, 0);
    await drawCircle();
    await drawCircle();
    expect(state.turns, 2, reason: '★印が2回 通っていない');
    expect(state.result, isNull, reason: '★2ターン目で もう終わっている');

    await drawCircle();
    expect(state.turns, 3);
    expect(state.result, 'lose', reason: '★3ターンすぎても まけていない');

    // 後片づけ
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  });
}
