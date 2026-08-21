import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rune_link/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Player.reset();
  });

  Future<void> openShop(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ShopScreen()));
    await tester.pump();
  }

  testWidgets('ショップに つよくなるカードが出る', (tester) async {
    await openShop(tester);
    expect(find.text('つよくなる'), findsOneWidget);
    expect(find.text('こうげき'), findsOneWidget);
    expect(find.text('たいりょく'), findsOneWidget);
    expect(find.text('もちもの'), findsOneWidget);
    // レベル表示と いまの数値
    expect(find.text('Lv.0 / 10'), findsNWidgets(2));
    expect(find.text('いま 24 → 28 に あがる'), findsOneWidget);
    expect(find.text('いま 100 → 120 に あがる'), findsOneWidget);
  });

  testWidgets('⭐があれば ボタンを押して こうげきが上がる', (tester) async {
    Player.stars = 500;
    await openShop(tester);

    // ねだん40は 強化カード2枚だけ（もちものは 60/120/150/300）
    final prices = find.text('40');
    expect(prices, findsNWidgets(2), reason: '★ねだんボタンが見つからない');

    // 上が こうげき、下が たいりょく
    await tester.tap(prices.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(Player.atkLv, 1);
    expect(Player.atk, 28);
    expect(Player.stars, 460);
    expect(find.text('こうげきが つよくなった！'), findsOneWidget);
    // 表示も追従している
    expect(find.text('いま 28 → 32 に あがる'), findsOneWidget);
  });

  testWidgets('⭐がたりないと 上がらず メッセージが出る', (tester) async {
    Player.stars = 10;
    await openShop(tester);

    await tester.tap(find.text('40').last); // たいりょく側
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(Player.hpLv, 0);
    expect(Player.stars, 10);
    expect(find.text('⭐がたりない…'), findsOneWidget);
  });

  testWidgets('さいだいレベルだと MAX と出て 押しても増えない', (tester) async {
    Player.stars = 100000;
    Player.atkLv = Player.maxUpgradeLv;
    await openShop(tester);

    expect(find.text('MAX'), findsOneWidget);
    expect(find.text('いま 64（さいだい）'), findsOneWidget);

    await tester.tap(find.text('MAX'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(Player.atkLv, Player.maxUpgradeLv);
    expect(find.text('こうげきは これいじょう あがらない！'), findsOneWidget);
  });
}
