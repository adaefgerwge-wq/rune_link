import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rune_link/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Player.reset();
  });

  testWidgets('ホームのショートカットが4つ 375幅に おさまる', (tester) async {
    // よこ幅は実機どおり375。たては全部が組み立てられるよう長くとる
    // （ショートカット行は スクロールしないと 出てこないため）
    tester.view.physicalSize = const Size(375, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // はみ出しエラーを ひろう
    final overflow = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final msg = d.exception.toString();
      if (msg.contains('overflowed')) {
        overflow.add(msg.split('\n').first);
      } else {
        prev?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prev);

    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: HomeScreen())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 4つとも出ている
    expect(find.text('ショップ'), findsOneWidget);
    expect(find.text('ミッション'), findsOneWidget);
    expect(find.text('ちょうせん'), findsOneWidget);
    expect(find.text('きせかえ'), findsOneWidget);

    // ignore: avoid_print
    print('HOME| はみ出し: ${overflow.toSet().join(" / ")}');
    expect(overflow, isEmpty, reason: '★ショートカット行が はみ出している');

    // よこに はみ出していないか（375の中に おさまっているか）
    for (final label in ['ショップ', 'ミッション', 'ちょうせん', 'きせかえ']) {
      final box = tester.getRect(find.text(label));
      expect(box.left >= 0 && box.right <= 375, isTrue,
          reason: '★「$label」が 画面の外に出ている ($box)');
    }
  });
}
