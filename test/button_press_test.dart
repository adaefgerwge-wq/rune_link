import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rune_link/main.dart';

void main() {
  testWidgets('ぷっくりボタンは 押すと沈む', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            child: ChunkyButton(
              label: 'おす',
              color: kGreen,
              edge: kGreenDeep,
              onTap: () => tapped++,
            ),
          ),
        ),
      ),
    ));

    AnimatedContainer box() =>
        tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));

    // ふつうの状態：下がっていない／ふちが濃い
    final before = box();
    final yBefore = before.transform!.getTranslation().y;
    final edgeBefore =
        (before.decoration as BoxDecoration).border!.bottom.color;
    expect(yBefore, 0.0, reason: '最初から下がっている');
    expect(edgeBefore, kGreenDeep, reason: 'ふちが出ていない');

    // 押した状態
    final g = await tester.startGesture(tester.getCenter(find.text('おす')));
    await tester.pump(const Duration(milliseconds: 120));
    final down = box();
    final yDown = down.transform!.getTranslation().y;
    final edgeDown = (down.decoration as BoxDecoration).border!.bottom.color;
    // ignore: avoid_print
    print('PRESS| ふつう y=$yBefore → 押した y=$yDown / ふち $edgeDown');
    expect(yDown > 0, true, reason: '★押しても沈んでいない');
    expect(edgeDown, kGreen, reason: '★押してもふちが消えていない');

    // 指を離すと もどる＆押したことになる
    await g.up();
    await tester.pump(const Duration(milliseconds: 150));
    expect(box().transform!.getTranslation().y, 0.0, reason: 'もどっていない');
    expect(tapped, 1, reason: 'タップが伝わっていない');
  });

  testWidgets('まるいボタンも 押すと沈む', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ChunkyCircle(
            size: 76,
            color: kPurple,
            edge: kPurpleDeep,
            onTap: () => tapped++,
            child: const Icon(Icons.play_arrow_rounded),
          ),
        ),
      ),
    ));
    AnimatedContainer box() =>
        tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect(box().transform!.getTranslation().y, 0.0);

    final g = await tester.startGesture(tester.getCenter(find.byType(Icon)));
    await tester.pump(const Duration(milliseconds: 120));
    expect(box().transform!.getTranslation().y > 0, true, reason: '★沈んでいない');
    await g.up();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tapped, 1);
  });

  testWidgets('ショップの値段ボタンも 押すと沈む', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ChunkyPill(
            color: kGreen,
            edge: kGreenDeep,
            onTap: () => tapped++,
            child: const Text('60'),
          ),
        ),
      ),
    ));
    AnimatedContainer box() =>
        tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect(box().transform!.getTranslation().y, 0.0);

    final g = await tester.startGesture(tester.getCenter(find.text('60')));
    await tester.pump(const Duration(milliseconds: 120));
    // ignore: avoid_print
    print('SHOP| 押した y=${box().transform!.getTranslation().y}');
    expect(box().transform!.getTranslation().y > 0, true, reason: '★沈んでいない');
    await g.up();
    await tester.pump(const Duration(milliseconds: 150));
    expect(box().transform!.getTranslation().y, 0.0);
    expect(tapped, 1);
  });
}
