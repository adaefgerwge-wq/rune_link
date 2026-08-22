import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rune_link/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Player.reset();
  });

  test('さいしょは 満タン', () {
    expect(Player.stamina, Player.maxStamina);
    expect(Player.secondsToNextStamina, 0);
  });

  test('むずかしいほど 多くつかう', () {
    expect(staminaCost(diff: 0), 1);
    expect(staminaCost(diff: 1), 2);
    expect(staminaCost(diff: 2), 3);
    expect(staminaCost(challenge: 0), 3);
  });

  test('むずかしいほうが ⭐の効率がよい（周回する意味が出る）', () {
    // ステージ6でくらべる
    final normal = winStars(6, 0) / staminaCost(diff: 0);
    final hard = winStars(6, 2) / staminaCost(diff: 2);
    expect(hard >= normal, isTrue,
        reason: '★げきつよ($hard/1) が ふつう($normal/1) より 効率がわるい');
  });

  test('つかうと へる。たりなければ つかえない', () {
    expect(Player.spendStamina(3), isTrue);
    expect(Player.stamina, Player.maxStamina - 3);

    expect(Player.canPlay(100), isFalse);
    expect(Player.spendStamina(100), isFalse);
    expect(Player.stamina, Player.maxStamina - 3, reason: '★失敗したのに へっている');
  });

  test('時間がたつと 回復する', () {
    Player.spendStamina(10); // のこり10
    // 12分前に つかったことにする＝5分ごとなので 2つ回復するはず
    Player.staminaAt =
        DateTime.now().millisecondsSinceEpoch - 12 * 60 * 1000;
    expect(Player.stamina, 12);
    // はんぱな2分は捨てられず、つぎまで3分（=180秒）くらい
    expect(Player.secondsToNextStamina, inInclusiveRange(160, 180));
  });

  test('満タンを こえて 回復しない', () {
    Player.spendStamina(2);
    Player.staminaAt =
        DateTime.now().millisecondsSinceEpoch - 999 * 60 * 1000;
    expect(Player.stamina, Player.maxStamina);
    expect(Player.secondsToNextStamina, 0);
  });

  test('アプリを閉じていても 時計で回復する', () async {
    Player.spendStamina(20); // からっぽ
    Player.staminaAt =
        DateTime.now().millisecondsSinceEpoch - 30 * 60 * 1000;
    await Player.save();

    await Player.load();
    expect(Player.stamina, 6, reason: '★30分ぶん(6つ)もどっていない');
  });

  test('⭐で満タンに もどせる。ねだんは 使うたび倍', () {
    Player.stars = 10000;
    Player.spendStamina(20);
    expect(Player.stamina, 0);

    expect(Player.refillCost, 60);
    expect(Player.buyRefill(), isTrue);
    expect(Player.stamina, Player.maxStamina);
    expect(Player.stars, 10000 - 60);

    expect(Player.refillCost, 120);
    Player.buyRefill();
    expect(Player.refillCost, 240);
  });

  test('⭐がたりないと 回復できない', () {
    Player.stars = 10;
    Player.spendStamina(20);
    expect(Player.buyRefill(), isFalse);
    expect(Player.stamina, 0);
    expect(Player.stars, 10);
  });

  test('⭐での回復は 1日5回まで', () {
    Player.stars = 1000000;
    for (var i = 0; i < Player.maxRefillsPerDay; i++) {
      expect(Player.canRefillToday, isTrue);
      expect(Player.buyRefill(), isTrue);
    }
    expect(Player.canRefillToday, isFalse);
    final before = Player.stars;
    expect(Player.buyRefill(), isFalse);
    expect(Player.stars, before);
  });
}
