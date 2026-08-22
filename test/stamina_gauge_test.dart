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

    final gauge = find.byType(StaminaGauge);
    expect(gauge, findsOneWidget);
    // ヘッダーにも スタミナ行が出るので ホームのゲージの中だけを見る
    expect(find.descendant(of: gauge, matching: find.text('17')),
        findsOneWidget);
    expect(find.descendant(of: gauge, matching: find.text(' / 20')),
        findsOneWidget);
    expect(find.descendant(of: gauge, matching: find.textContaining('つぎまで')),
        findsOneWidget);
  });

  testWidgets('満タンのときは 文字を出さない（色でわかる）', (tester) async {
    usePhone(tester, height: 2400);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: HomeScreen())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('満タン！'), findsNothing);
    expect(find.textContaining('つぎまで'), findsNothing);
    // ゲージは いっぱい
    final f = tester.widget<FractionallySizedBox>(find.descendant(
        of: find.byType(StaminaGauge),
        matching: find.byType(FractionallySizedBox)));
    expect(f.widthFactor, 1.0);
  });
}
