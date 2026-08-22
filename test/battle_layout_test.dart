import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rune_link/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Player.reset();
  });

  /// はみ出しエラーだけ ひろって 他はそのまま流す
  List<String> catchOverflow() {
    final found = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final msg = d.exception.toString();
      if (msg.contains('overflowed')) {
        found.add(msg.split('\n').first);
      } else {
        prev?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prev);
    return found;
  }

  testWidgets('バトル画面が 実機サイズで はみ出さない', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Player.tutorialDone = true;
    Player.cleared = kStageCount;
    Player.addItem('かいふくポーション'); // アイテム欄も出した状態で見る

    final overflow = catchOverflow();

    // ふつうのバトルと ちょうせん（条件チップが1つ増える）の両方
    for (final c in [-1, 5]) {
      await tester.pumpWidget(MaterialApp(
          home: BattleScreen(key: ValueKey('b$c'), stage: 6, challenge: c)));
      await tester.pump(const Duration(milliseconds: 2700));
      expect(find.byType(BattleScreen), findsOneWidget);
    }

    // ignore: avoid_print
    print('BATTLE| はみ出し: ${overflow.toSet().join(" / ")}');
    expect(overflow, isEmpty, reason: '★バトル画面が はみ出している');
  });

  testWidgets('てきの つぎの手が 予告される', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Player.tutorialDone = true;
    await tester.pumpWidget(const MaterialApp(
        home: BattleScreen(key: ValueKey('t'), stage: 1)));
    await tester.pump(const Duration(milliseconds: 2700));

    // 「つぎ ○○の こうげき」か「大こうげき」が かならず出ている
    expect(find.textContaining('つぎ '), findsOneWidget);
    expect(find.textContaining('こうげき'), findsOneWidget);
  });
}
