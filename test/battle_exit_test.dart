import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rune_link/main.dart';

void main() {
  testWidgets('本物のバトル画面から「ホームへ もどる」できる', (tester) async {
    // スマホと同じ画面サイズにする
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final overflow = <String>[];
    Future<void> settle(int times, [int ms = 200]) async {
      for (var i = 0; i < times; i++) {
        await tester.pump(Duration(milliseconds: ms));
        final e = tester.takeException();
        if (e != null) overflow.add(e.toString().split('\n').first);
      }
    }

    await tester.pumpWidget(const RuneLinkApp());
    await settle(3, 100);

    final ctx = tester.element(find.byType(MainShell));
    Navigator.of(ctx).push(fadeSlowRoute(const BattleScreen(stage: 1)));
    await settle(14, 300);
    expect(find.byType(BattleScreen), findsOneWidget, reason: 'バトル画面が出ていない');

    final scaffold = tester.firstState<ScaffoldState>(find.descendant(
        of: find.byType(BattleScreen), matching: find.byType(Scaffold)));
    scaffold.openDrawer();
    await settle(6, 150);
    expect(find.text('ホームへ もどる'), findsOneWidget, reason: 'メニューが開いていない');

    await tester.tap(find.text('ホームへ もどる'));
    await settle(6, 150);
    expect(find.text('バトルを やめますか？'), findsOneWidget, reason: '確認が出ていない');

    await tester.tap(find.text('はい'));
    await settle(12, 200);

    // ignore: avoid_print
    print('--- はみ出しエラー: ${overflow.toSet().join(" / ")}');
    expect(find.byType(BattleScreen), findsNothing, reason: '★バトル画面から戻れていない');
    expect(gTab.value, 0, reason: 'ホームタブになっていない');
  });
}
