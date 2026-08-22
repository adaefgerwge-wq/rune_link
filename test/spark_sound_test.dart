import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rune_link/main.dart';

void main() {
  // 音のしくみを さわるので バインディングを 先に用意しておく
  TestWidgetsFlutterBinding.ensureInitialized();

  test('キラキラ音のファイルが 3つ ある', () {
    for (var i = 1; i <= 3; i++) {
      final f = File('assets/sfx/spark$i.wav');
      expect(f.existsSync(), isTrue, reason: '★spark$i.wav が ない');
      expect(f.lengthSync() > 1000, isTrue, reason: '★spark$i.wav が 空っぽ');
    }
  });

  test('ミュート中は 鳴らさない（数えかたが 進まない）', () {
    Sound.on = false;
    Sfx.sparkAt = 0;
    Sfx.spark();
    expect(Sfx.sparkAt, 0, reason: '★ミュートなのに 鳴らそうとしている');
  });

  test('たてつづけに呼ばれても 鳴らしすぎない', () {
    Sound.on = true;
    Sfx.sparkAt = 0;

    Sfx.spark(); // 1回目は 鳴る
    final first = Sfx.sparkAt;
    expect(first > 0, isTrue);

    // すぐ呼んでも 間があくまでは 鳴らない
    for (var i = 0; i < 20; i++) {
      Sfx.spark();
    }
    expect(Sfx.sparkAt, first, reason: '★間をあけずに 鳴らしている');

    // 間があいたことにすると また鳴る
    Sfx.sparkAt = DateTime.now().millisecondsSinceEpoch - 200;
    Sfx.spark();
    expect(Sfx.sparkAt > first, isTrue, reason: '★間があいても 鳴らない');

    Sound.on = false;
  });
}
