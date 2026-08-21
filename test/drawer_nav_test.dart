import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rune_link/main.dart';

void main() {
  testWidgets('バトル中メニューの「ホームへ もどる」で ホームまで戻れる', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: const Scaffold(body: Center(child: Text('ホーム画面'))),
      builder: (context, child) => child!,
    ));

    // バトル画面のかわりに 同じ作りの画面を積む
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Center(child: Text('ホーム画面'))),
    ));
    await tester.pumpAndSettle();

    navKey.currentState!.push(MaterialPageRoute(
      builder: (_) => Scaffold(
        drawer: const AppDrawer(inBattle: true),
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              child: const Text('バトル画面'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('バトル画面'), findsOneWidget);
    expect(find.text('ホーム画面'), findsNothing);

    // メニューを開く
    await tester.tap(find.text('バトル画面'));
    await tester.pumpAndSettle();
    expect(find.text('ホームへ もどる'), findsOneWidget);

    // 「ホームへ もどる」→ 確認ダイアログ
    await tester.tap(find.text('ホームへ もどる'));
    await tester.pumpAndSettle();
    expect(find.text('バトルを やめますか？'), findsOneWidget);

    // 「はい」を押す
    await tester.tap(find.text('はい'));
    await tester.pumpAndSettle();

    // ホームに戻れているか
    expect(find.text('ホーム画面'), findsOneWidget, reason: 'ホームに戻れていない');
    expect(find.text('バトル画面'), findsNothing, reason: 'バトル画面が残っている');
    expect(gTab.value, 0, reason: 'ホームタブになっていない');
  });

  testWidgets('「いいえ」なら戻らない', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Center(child: Text('ホーム画面'))),
    ));
    await tester.pumpAndSettle();

    navKey.currentState!.push(MaterialPageRoute(
      builder: (_) => Scaffold(
        drawer: const AppDrawer(inBattle: true),
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              child: const Text('バトル画面'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('バトル画面'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ホームへ もどる'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('いいえ'));
    await tester.pumpAndSettle();

    expect(find.text('ホーム画面'), findsNothing, reason: '戻ってしまっている');
  });
}
