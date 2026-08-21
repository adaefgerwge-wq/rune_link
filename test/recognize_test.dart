import 'dart:math';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:rune_link/main.dart';

// 折れ線を密な点列にする＋手ブレを足す
List<Offset> dense(List<Offset> corners, {double jitter = 0, int seed = 1}) {
  final r = Random(seed);
  final out = <Offset>[];
  for (int i = 0; i < corners.length - 1; i++) {
    for (int k = 0; k < 8; k++) {
      final t = k / 8;
      final p = Offset(
        corners[i].dx + (corners[i + 1].dx - corners[i].dx) * t,
        corners[i].dy + (corners[i + 1].dy - corners[i].dy) * t,
      );
      out.add(Offset(p.dx * 200 + (r.nextDouble() - 0.5) * jitter,
          p.dy * 200 + (r.nextDouble() - 0.5) * jitter));
    }
  }
  out.add(Offset(corners.last.dx * 200, corners.last.dy * 200));
  return out;
}

List<Offset> arc(double from, double to, double rx, double ry,
    {double jitter = 0, int seed = 2}) {
  final r = Random(seed);
  final l = <Offset>[];
  for (int i = 0; i <= 30; i++) {
    final a = from + (to - from) * i / 30;
    l.add(Offset(100 + rx * 200 * cos(a) + (r.nextDouble() - 0.5) * jitter,
        100 + ry * 200 * sin(a) + (r.nextDouble() - 0.5) * jitter));
  }
  return l;
}

void main() {
  final rec = RuneRecognizer();

  void check(String name, List<Offset> pts, Elem want) {
    final res = rec.recognize(pts);
    final got = res.key;
    final score = res.value;
    final ok = got == want && score >= 0.20;
    // ignore: avoid_print
    print('${ok ? "OK  " : "NG  "} $name -> '
        '${got == null ? "みとめられず" : elemLabel(got)} '
        '(score ${score.toStringAsFixed(2)})');
    expect(got, want, reason: name);
    expect(score >= 0.20, true, reason: '$name score too low');
  }

  test('親指で描いた雑な形でも認識できる', () {
    // ◯ みず
    check('きれいな丸', arc(0, 2 * pi, 0.5, 0.5), Elem.water);
    check('手ブレした丸', arc(0, 2 * pi, 0.5, 0.5, jitter: 26), Elem.water);
    check('閉じてない丸', arc(0, 1.7 * pi, 0.5, 0.5, jitter: 18), Elem.water);
    check('横につぶれた丸', arc(0, 2 * pi, 0.5, 0.3, jitter: 18), Elem.water);
    check('縦につぶれた丸', arc(0, 2 * pi, 0.3, 0.5, jitter: 18), Elem.water);
    check('大きく開いた弧', arc(0.2, 1.6 * pi, 0.5, 0.45, jitter: 20), Elem.water);

    // Z かみなり
    check('きれいなZ', dense(const [
      Offset(0, 0), Offset(1, 0), Offset(0, 1), Offset(1, 1)
    ]), Elem.thunder);
    check('手ブレしたZ', dense(const [
      Offset(0, 0), Offset(1, 0), Offset(0, 1), Offset(1, 1)
    ], jitter: 26), Elem.thunder);
    check('角が丸いZ', dense(const [
      Offset(0.05, 0.05), Offset(0.9, 0.02), Offset(0.5, 0.5),
      Offset(0.08, 0.95), Offset(0.95, 0.98)
    ], jitter: 20), Elem.thunder);
    check('ななめが強いZ', dense(const [
      Offset(0.15, 0), Offset(1, 0.2), Offset(0.1, 0.85), Offset(0.9, 1)
    ], jitter: 20), Elem.thunder);

    // △ ひ（ゆるくしても 取られていないこと）
    check('きれいな三角', dense(const [
      Offset(0.5, 0), Offset(1, 1), Offset(0, 1), Offset(0.5, 0)
    ]), Elem.fire);
    check('手ブレした三角', dense(const [
      Offset(0.5, 0), Offset(1, 1), Offset(0, 1), Offset(0.5, 0)
    ], jitter: 24), Elem.fire);
  });
}
