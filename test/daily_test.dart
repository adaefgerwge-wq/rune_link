import 'package:flutter_test/flutter_test.dart';
import 'package:rune_link/main.dart';

void main() {
  setUp(() {
    Player.dailyIds = [];
    Player.dailyClaimed = {};
    Player.dailyWins = 0;
    Player.dailyElems = 0;
    Player.dailyCrits = 0;
    Player.stars = 0;
  });

  test('きょうのミッションが3つ用意される', () {
    Player.ensureDaily();
    expect(Player.dailyIds.length, 3);
    expect(Player.dailyIds.toSet().length, 3, reason: '同じものが混ざっている');
  });

  test('達成していないと ごほうびを受けとれない', () {
    Player.ensureDaily();
    final id = Player.dailyIds.first;
    expect(Player.claimDaily(id), false, reason: '未達成なのに 受けとれた');
    expect(Player.stars, 0);
  });

  test('達成すると ⭐がもらえる／2回はもらえない', () {
    Player.ensureDaily();
    // すべての条件を満たす状態にする
    Player.dailyWins = 99;
    Player.dailyElems = 99;
    Player.dailyCrits = 99;
    final id = Player.dailyIds.first;
    final reward = kDailyMissions[id].reward;

    expect(Player.claimDaily(id), true, reason: '受けとれない');
    expect(Player.stars, reward, reason: '⭐が増えていない');

    expect(Player.claimDaily(id), false, reason: '2回もらえてしまう');
    expect(Player.stars, reward, reason: '⭐が二重に増えた');
  });

  test('しょうごうは 条件で解放される', () {
    Player.defeatedByName = {};
    final first = kTitles.firstWhere((t) => t.name == '10たい たおした');
    expect(first.check(), false);
    Player.defeatedByName = {'てき': 10};
    expect(first.check(), true);
    // ignore: avoid_print
    print('TITLES| ぜんぶで ${kTitles.length} こ');
  });
}
