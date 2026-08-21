import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rune_link/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Player.reset();
  });

  test('強化していないときは 元の数値', () {
    expect(Player.atk, 24);
    expect(Player.maxHp, 100);
  });

  test('⭐がたりないと 強化できない', () {
    Player.stars = 0;
    expect(Player.buyUpgrade(isAtk: true), isFalse);
    expect(Player.atkLv, 0);
    expect(Player.atk, 24);
  });

  test('こうげきを上げると ダメージの基礎値が上がる', () {
    Player.stars = 1000;
    expect(Player.buyUpgrade(isAtk: true), isTrue);
    expect(Player.atkLv, 1);
    expect(Player.atk, 28); // 24 + 4
    expect(Player.stars, 1000 - 40); // Lv0 のねだんを引く
  });

  test('たいりょくを上げると さいだいHPが上がる', () {
    Player.stars = 1000;
    expect(Player.buyUpgrade(isAtk: false), isTrue);
    expect(Player.maxHp, 120); // 100 + 20
    expect(Player.stars, 1000 - 40);
  });

  test('上げるほど ねだんが高くなる', () {
    expect(Player.upgradeCost(0), 40);
    expect(Player.upgradeCost(1), 65);
    expect(Player.upgradeCost(9), 265);
  });

  test('さいだいレベルで 打ち止めになる', () {
    Player.stars = 100000;
    for (var i = 0; i < Player.maxUpgradeLv; i++) {
      expect(Player.buyUpgrade(isAtk: true), isTrue);
    }
    expect(Player.atkLv, Player.maxUpgradeLv);
    expect(Player.atk, 64); // 24 + 10*4
    // これ以上は買えない＝⭐も減らない
    final before = Player.stars;
    expect(Player.buyUpgrade(isAtk: true), isFalse);
    expect(Player.stars, before);
  });

  test('強化はセーブされて 読み直しても残る', () async {
    Player.stars = 1000;
    Player.buyUpgrade(isAtk: true);
    Player.buyUpgrade(isAtk: false);
    await Player.save();
    Player.atkLv = 0; // メモリ上だけ消して
    Player.hpLv = 0;
    await Player.load();
    expect(Player.atkLv, 1);
    expect(Player.hpLv, 1);
  });
}
