import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rune_link/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Player.reset();
  });

  // このゲームはスマホ向け。テストも実機に近い たての画面で見る
  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  test('先のステージ・むずかしいほど ⭐が増える', () {
    expect(winStars(1, 0), 15);
    expect(winStars(6, 0), 40); // 15 + 5*5
    expect(winStars(1, 2), 53); // 15 * 3.5
    expect(winStars(6, 2), 140); // 40 * 3.5
    // むずかしくすると 必ず増える
    for (var st = 1; st <= kStageCount; st++) {
      expect(winStars(st, 1) > winStars(st, 0), isTrue);
      expect(winStars(st, 2) > winStars(st, 1), isTrue);
    }
  });

  test('未クリアのステージは ふつうしか選べない', () {
    Player.cleared = 0;
    expect(Player.diffUnlocked(1, 0), isTrue);
    expect(Player.diffUnlocked(1, 1), isFalse);
    expect(Player.diffUnlocked(1, 2), isFalse);
  });

  test('ひとつ下をクリアすると 上のむずかしさが開く', () {
    Player.cleared = 1;
    // クリア済みでも つよいはまだ
    expect(Player.diffUnlocked(1, 1), isFalse);

    Player.recordStageClear(1, 0);
    expect(Player.diffUnlocked(1, 1), isTrue);
    expect(Player.diffUnlocked(1, 2), isFalse);

    Player.recordStageClear(1, 1);
    expect(Player.diffUnlocked(1, 2), isTrue);
  });

  test('前より下のむずかしさで勝っても 記録は下がらない', () {
    Player.cleared = 1;
    Player.recordStageClear(1, 2);
    Player.recordStageClear(1, 0);
    expect(Player.stageBest[1], 2);
    expect(Player.diffCleared(1, 2), isTrue);
  });

  test('クリア記録は セーブされて残る', () async {
    Player.cleared = 2;
    Player.recordStageClear(2, 1);
    await Player.save();
    Player.stageBest = {};
    await Player.load();
    expect(Player.stageBest[2], 1);
  });

  test('ごほうびの⭐が そのまま入る', () {
    Player.stars = 0;
    Player.recordWin('いたずらオバケ', reward: winStars(6, 2));
    expect(Player.stars, 140);
    expect(Player.trophies, 1);
  });

  testWidgets('クリア済みステージを押すと むずかしさを選べる', (tester) async {
    Player.cleared = 2;
    Player.recordStageClear(1, 0); // ふつうクリア済み → つよいが開く

    await tester.pumpWidget(const MaterialApp(home: StageSelectScreen()));
    await tester.pump();

    // ステージ1のノードを押す
    await tester.tap(find.text('ステージ1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ステージ1  むずかしさ'), findsOneWidget);
    expect(find.text('ふつう'), findsOneWidget);
    expect(find.text('つよい'), findsOneWidget);
    expect(find.text('げきつよ'), findsOneWidget);
    // げきつよは まだ開いていない
    expect(find.text('つよいを クリアすると ひらく'), findsOneWidget);
    // ボタンには つかう⚡が出る（もらえる⭐は 説明の行）
    expect(find.text('${staminaCost(diff: 0)}'), findsOneWidget);
    expect(find.text('${staminaCost(diff: 1)}'), findsOneWidget);
    expect(find.textContaining('かつと ⭐${winStars(1, 0)}'), findsOneWidget);
  });

  testWidgets('未クリアのステージは すぐバトルに入る', (tester) async {
    usePhone(tester);
    Player.cleared = 0;
    await tester.pumpWidget(const MaterialApp(home: StageSelectScreen()));
    await tester.pump();

    await tester.tap(find.text('ステージ1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // むずかしさシートは出ない
    expect(find.text('ステージ1  むずかしさ'), findsNothing);
  });

  testWidgets('むずかしくすると 敵のHPが増える', (tester) async {
    // 同じステージを ふつう と げきつよ で開いて 敵のHP表示をくらべる
    usePhone(tester);
    // キーを変えないと State が使い回されて 同じ敵のままになる
    Future<int> maxHpOf(int diff, int seq) async {
      await tester.pumpWidget(MaterialApp(
          home: BattleScreen(key: ValueKey('$diff-$seq'), stage: 1, diff: diff)));
      await tester.pump(const Duration(milliseconds: 2700)); // ローディング明け
      final state = tester.state(find.byType(BattleScreen)) as dynamic;
      return state.enemyMaxHp as int;
    }

    // 乱数ぶんの幅があるので 何回か試して 合計でくらべる
    var normal = 0, hard = 0;
    for (var i = 0; i < 5; i++) {
      normal += await maxHpOf(0, i);
      hard += await maxHpOf(2, i);
    }
    expect(hard > normal, isTrue,
        reason: '★げきつよ($hard)が ふつう($normal)より かたくない');
    // げきつよは 2.4倍なので だいたい2倍以上のはず
    expect(hard / normal > 2.0, isTrue);
  });
}
