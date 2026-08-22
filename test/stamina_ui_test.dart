import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rune_link/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Player.reset();
  });

  void usePhone(WidgetTester tester, {double height = 812}) {
    tester.view.physicalSize = Size(375, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// payStamina を 実際の画面のうえで 走らせるための入れもの
  Future<bool?> runPay(WidgetTester tester, int cost) async {
    bool? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => got = await payStamina(ctx, cost),
              child: const Text('いく'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('いく'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return got;
  }

  testWidgets('たりていれば だまって へる', (tester) async {
    usePhone(tester);
    final ok = await runPay(tester, 3);
    expect(ok, isTrue);
    expect(Player.stamina, Player.maxStamina - 3);
    expect(find.text('スタミナが たりない'), findsNothing);
  });

  testWidgets('たりないと 知らせが出て 「まつ」なら 行かない', (tester) async {
    usePhone(tester);
    Player.spendStamina(Player.maxStamina); // からっぽ
    Player.stars = 1000;

    await runPay(tester, 3);
    expect(find.text('スタミナが たりない'), findsOneWidget);
    expect(find.textContaining('⭐60 で 満タン'), findsOneWidget);

    await tester.tap(find.text('まつ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(Player.stamina, 0);
    expect(Player.stars, 1000, reason: '★まつ を選んだのに ⭐がへっている');
  });

  testWidgets('⭐で満タンにすると そのまま 行ける', (tester) async {
    usePhone(tester);
    Player.spendStamina(Player.maxStamina);
    Player.stars = 1000;

    await runPay(tester, 3);
    await tester.tap(find.textContaining('⭐60 で 満タン'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 満タンにしてから 3つはらった状態になる
    expect(Player.stamina, Player.maxStamina - 3);
    expect(Player.stars, 1000 - 60);
    expect(Player.refillsToday, 1);
  });

  testWidgets('⭐がたりないと 回復ボタンが押せない', (tester) async {
    usePhone(tester);
    Player.spendStamina(Player.maxStamina);
    Player.stars = 10; // 60 にたりない

    await runPay(tester, 3);
    expect(find.text('スタミナが たりない'), findsOneWidget);

    final btn = tester.widget<TextButton>(
        find.ancestor(
            of: find.textContaining('⭐60 で 満タン'),
            matching: find.byType(TextButton)));
    expect(btn.onPressed, isNull, reason: '★⭐がたりないのに 押せてしまう');
  });

  testWidgets('きょうの回復を使いきると 回復ボタンが 出ない', (tester) async {
    usePhone(tester);
    Player.stars = 1000000;
    for (var i = 0; i < Player.maxRefillsPerDay; i++) {
      Player.buyRefill();
    }
    Player.spendStamina(Player.maxStamina);

    await runPay(tester, 3);
    expect(find.text('スタミナが たりない'), findsOneWidget);
    expect(find.textContaining('で 満タン'), findsNothing);
    expect(find.textContaining('つかいきった'), findsOneWidget);
  });

  testWidgets('スタミナ表示は 満タンなら 時間を出さない', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: StaminaCounter()))));
    await tester.pump();
    expect(find.text('20'), findsOneWidget);
    expect(find.textContaining(':'), findsNothing);

    // 1つ使うと のこり時間が出る
    Player.spendStamina(1);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('19'), findsOneWidget);
    expect(find.textContaining(':'), findsOneWidget);
  });
}
