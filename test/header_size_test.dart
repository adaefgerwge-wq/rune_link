import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rune_link/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Player.reset();
    Player.stars = 9999; // 数字が大きくても そろうこと
    Player.trophies = 999;
  });

  testWidgets('下タブ5画面の 上のバーは 同じ大きさ', (tester) async {
    // よこ幅は実機どおり。たては 全部が組み立てられるよう 長くとる
    tester.view.physicalSize = const Size(375, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final screens = <String, Widget>{
      'ホーム': const Scaffold(body: HomeScreen()),
      'ずかん': const ZukanScreen(),
      'ぼうけん': const StageSelectScreen(),
      'リーグ': const LeagueScreen(),
      'プレミアム': const PremiumScreen(),
    };

    final widths = <String, double>{};
    for (final e in screens.entries) {
      await tester.pumpWidget(MaterialApp(home: e.value));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final box = tester.getRect(find.byType(StaminaRow).first);
      // ignore: avoid_print
      print('  ${e.key}: rect=$box');
      widths[e.key] = box.width;
    }

    // ignore: avoid_print
    print('HEADER| $widths');

    final first = widths.values.first;
    for (final e in widths.entries) {
      // 1px未満のズレは 見た目に出ないので 許す
      expect(e.value, closeTo(first, 1.0),
          reason: '★「${e.key}」だけ 上のバーの大きさが ちがう '
              '(${e.value} vs $first)');
    }

    // タイマーを止める
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('サブ画面の 見出しは けずられない', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const style =
        TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kInk);

    // 下タブの画面（ずかん）は 見出しを出さないので ここでは見ない
    for (final title in ['マイページ', 'ちょうせん', 'ショップ', 'ミッション']) {
      final tp = TextPainter(
          text: TextSpan(text: title, style: style),
          textDirection: TextDirection.ltr)
        ..layout();

      await tester.pumpWidget(
          MaterialApp(home: SubScreen(title: title, children: const [])));
      await tester.pump();

      final box = tester.getRect(find.text(title));
      expect(box.width + 0.5 >= tp.width, isTrue,
          reason: '★「$title」が けずられている (${box.width} < ${tp.width})');
    }

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
