import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rune_link/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Player.reset();
  });

  testWidgets('メニューを閉じるときの 暗幕に 青みが入らない', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const RuneLinkApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 外枠の Scaffold（ドロワーを持っているもの）を見る
    final shell = tester.widgetList<Scaffold>(find.byType(Scaffold))
        .firstWhere((w) => w.drawer != null);

    final scrim = shell.drawerScrimColor;
    expect(scrim, isNotNull, reason: '★暗幕の色を 決めていない＝既定の青みが出る');
    // 灰色（赤緑青が同じ）であること＝色みが無い
    expect(scrim!.r == scrim.g && scrim.g == scrim.b, isTrue,
        reason: '★暗幕に 色みが入っている ($scrim)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('タップの波紋も 青ではなく アプリの紫', (tester) async {
    await tester.pumpWidget(const RuneLinkApp());
    await tester.pump();

    final ctx = tester.element(find.byType(MainShell));
    final theme = Theme.of(ctx);

    // 波紋は アプリの紫そのもの（濃さだけ ちがう）
    final splash = theme.splashColor;
    expect(splash.r, closeTo(kPurple.r, 0.001), reason: '★波紋が 紫でない');
    expect(splash.g, closeTo(kPurple.g, 0.001), reason: '★波紋が 紫でない');
    expect(splash.b, closeTo(kPurple.b, 0.001), reason: '★波紋が 紫でない');

    // 配色は 紫から作ったもの＝Material の 既定(青)ではない
    final want = ColorScheme.fromSeed(seedColor: kPurple);
    expect(theme.colorScheme.primary, want.primary,
        reason: '★配色が アプリの紫から 作られていない');
    expect(theme.colorScheme.primary != ColorScheme.fromSeed(
            seedColor: Colors.blue).primary, isTrue,
        reason: '★配色が Material の 既定(青)のまま');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
