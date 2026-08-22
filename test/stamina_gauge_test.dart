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

  /// ゲージの のびぐあいを 読む
  double fillOf(WidgetTester tester) {
    final f = tester.widget<FractionallySizedBox>(
        find.descendant(
            of: find.byType(StaminaBar),
            matching: find.byType(FractionallySizedBox)));
    return f.widthFactor ?? 0;
  }

  Future<void> pumpBar(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SizedBox(width: 200, child: StaminaBar()))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // のびきるまで
  }

  testWidgets('満タンなら ゲージも いっぱい', (tester) async {
    usePhone(tester);
    await pumpBar(tester);
    expect(fillOf(tester), 1.0);
  });

  testWidgets('へらすと ゲージも へる', (tester) async {
    usePhone(tester);
    Player.spendStamina(10); // 20 → 10
    await pumpBar(tester);
    expect(fillOf(tester), closeTo(0.5, 0.001));
  });

  testWidgets('からっぽなら 0', (tester) async {
    usePhone(tester);
    Player.spendStamina(Player.maxStamina);
    await pumpBar(tester);
    expect(fillOf(tester), 0.0);
  });

  testWidgets('ホームのゲージに 数と のこり時間が 出る', (tester) async {
    usePhone(tester, height: 2400); // 下までぜんぶ 組み立てる
    Player.spendStamina(3);

    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: HomeScreen())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(StaminaGauge), findsOneWidget);
    expect(find.text('17'), findsWidgets);
    expect(find.text(' / 20'), findsOneWidget);
    expect(find.textContaining('つぎまで'), findsOneWidget);
  });

  testWidgets('満タンのときは 満タン！と 出る', (tester) async {
    usePhone(tester, height: 2400);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: HomeScreen())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('満タン！'), findsOneWidget);
    expect(find.textContaining('つぎまで'), findsNothing);
  });

  testWidgets('ヘッダーの表示は ゲージを足しても よこ幅が ふえていない',
      (tester) async {
    usePhone(tester);
    Player.stars = 9999;
    Player.trophies = 999;

    // 見出しが 省略されないこと＝ヘッダーが まだ余っていること
    const style = TextStyle(
        fontSize: 19, fontWeight: FontWeight.w800, color: kInk);
    final tp = TextPainter(
        text: const TextSpan(text: 'マイページ', style: style),
        textDirection: TextDirection.ltr)
      ..layout();

    await tester.pumpWidget(const MaterialApp(
        home: SubScreen(title: 'マイページ', children: [])));
    await tester.pump();

    final box = tester.getRect(find.text('マイページ'));
    expect(box.width + 0.5 >= tp.width, isTrue,
        reason: '★ゲージを足したせいで 見出しが けずられた '
            '(${box.width} < ${tp.width})');
  });
}
