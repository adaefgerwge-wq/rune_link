# rune_link をさわるときのメモ

このファイルは **コードを直す人（と Claude Code）向け**。
ゲームの説明や あそびかたは README.md にある。

---

## サーバーの再起動（ここで 一度ハマった）

> **注意：一番ハマったところ**
> コードを直しても**サーバーは自動で反映しない**。
> 必ず `pkill -9 -f dartvm` で止めてから起動し直すこと。
> （古いサーバーのまま見て「直ってない」と勘違いした事故が実際に起きた）

---

## テストの決まり

```bash
flutter test        # 84件
flutter analyze     # warning ゼロを保つ（info は元から30件ある）
```

> レイアウトのテストは実機に近い縦長（375×812）でやること。
> 800×600 の初期サイズだと、はみ出しも文字の見切れも見逃す。

---

## プレビューで画面を操作する方法

`computer` ツールのクリックは**この環境では通らない**（画面表示だけは見える）。
かわりに JavaScript でポインタイベントを送ると動く。
**down と up の間に 90ms ほど空けないと Flutter がタップと認識しない**（ここでハマった）。

```js
window.tap = (x, y) => new Promise(res => {
  const el = document.elementFromPoint(x, y) || document.body;
  const base = {clientX: x, clientY: y, bubbles: true, cancelable: true,
    pointerId: 1, pointerType: 'mouse', isPrimary: true,
    width: 1, height: 1, pressure: 0.5, button: 0};
  el.dispatchEvent(new PointerEvent('pointerdown', {...base, buttons: 1}));
  el.dispatchEvent(new MouseEvent('mousedown', {...base, buttons: 1}));
  setTimeout(() => {
    el.dispatchEvent(new PointerEvent('pointerup', {...base, buttons: 0, pressure: 0}));
    el.dispatchEvent(new MouseEvent('mouseup', {...base, buttons: 0}));
    el.dispatchEvent(new MouseEvent('click', {...base, buttons: 0}));
    setTimeout(() => res('ok'), 700);
  }, 90);
});
```

座標はスクリーンショットから読む（375×812 で1:1）。
`read_page` は Flutter の中身を読めないが、画面いっぱいの
`flt-semantics-placeholder` を1回クリックすると読めるようになる。

---

---

## ヘッダー（上のバー）の決まりごと

**全画面 `screenHeader()` を通すこと。** 画面ごとに Row を組むと そろわない。

375px は かなり きつい。**見出し(19px)と スタミナ(19/15px・ゲージ44px)は
削らない**と決めてあり、そのぶん カウンター(トロフィー・スター)を 小さく(13/10px)し、
音の切りかえは メニューへ 追い出してある。ここに何か足すなら
削るのは カウンター側から。

三本線は `MenuButton`。**`Scaffold.of(context)` は使えない**——
リーグ・プレミアム・サブ画面は 自前の `Scaffold` を持っていて
そこには drawer が無いため 空振りする。外枠の `gShellScaffold` を
名ざしで開くこと（ここで 実際に 反応しない不具合を出した）。

`statCounters()`（トロフィー・スター・音）は **縮小しない**。
以前 `FittedBox` で縮めていたが、**画面ごとに のこり幅も高さも ちがうため
縮みかたが変わり、ずかんだけ 小さく見える** という不具合になった。

なので「いちばん狭い画面（もどるボタン＋長い見出し）でも
そのまま収まる大きさ」にしてある。ここに何か足すときは、
`test/header_size_test.dart` が

- 下タブ5画面で 大きさが そろっているか
- サブ画面の見出しが「…」で けずられていないか

を見ているので、それを通してから入れること。

---

---

## 判定の見せかた（ここは一度つまずいた）

以前は**バナーの背景色だけ**が「何の印と読まれたか」の手がかりで、
数字しか出ていなかった＝**自分の印がどう判定されたのか わからなかった**。

いまは 描くたびに 描画エリアに 判定カードを出す：

- よみとれた印の **形（△◯Z）と名前** … 凡例と同じ記号にそろえてある
- **きれいさ ○○%** … 威力が accMul で変わるので その根拠を見せる
- **弱点 ×2 / うけの かまえ / キレイ！** のバッジ … なぜ その威力かの内訳
- よみとれないときは **「？ よみとれなかった／もうすこし ゆっくり 大きく」**

**時間で消さず、つぎの印を描きはじめるまで出しっぱなし**にしている。
（最初2.2秒で消していたが、反撃の演出と重なって読む間がなかった）

---

## バランスの数字（いじるならここ）

| もの | いま |
|---|---|
| 印の基礎ダメージ | `24 + こうげきLv*4`（Lv10で64） |
| さいだいHP | `100 + たいりょくLv*20`（Lv10で300） |
| 強化のねだん | `40 + Lv*25`（1本あたり合計1450スター） |
| 勝利のスター | `(15 + (ステージ-1)*5) × むずかしさ倍率(1.0/2.0/3.5)` |
| むずかしさ | 敵HP ×1.0/1.6/2.4、敵こうげき ×1.0/1.3/1.6 |
| 弱点の入れかわり | 3ターンごと（印しばりの ちょうせんでは 動かさない） |
| 予告どおり受けた | ダメージ ×0.3 |
| 大こうげき | ダメージ ×1.7、4回に1回くらい |
| ちょうせんのスター | 初回120〜400、2回目からは1/4 |
| スタミナ | さいだい20、5分で1つ回復 |
| スタミナの消費 | ふつう1／つよい2／げきつよ3／ちょうせん3 |
| スターでの全回復 | 60スターから。1日に使うたび倍（60→120→240…）、5回まで |
| キラキラ音の間 | 110ms（これより短いと 鳴りすぎて うるさい） |

> **むずかしいほうが スタミナあたりのスターが多くなる**ようにしてある
> （ステージ6：ふつう40/1 → げきつよ140/3≒47）。
> 周回するなら むずかしいほうが得、という形にそろえた。

---

## 決まっている好み（作るときの指針）

- 目立ちすぎる装飾はしない（中央タブだけ特別扱いは却下された）
- 同じ入口を複数作らない（重複メニューは削除する）
- 半透明で背景が透けて読みにくいのはNG（白と混ぜて不透明にする）
- ループアニメの継ぎ目が見えるのはNG（速度を整数倍にして解決した）

---

---

## 公開のくわしいところ

### GitHub Pages（本番・自動）

https://adaefgerwge-wq.github.io/rune_link/

ワークフローの中身：

1. `flutter analyze --no-fatal-infos`
   … info は もとから30件あるので 止めない。warning と error だけ 失敗にする
2. `flutter test`（84件）
3. `flutter build web --release --pwa-strategy=none --base-href /rune_link/`

進み具合は `gh run list` か GitHubの Actions タブ。
初回は Flutter SDK の取得もあるので 4〜5分かかる。

`--pwa-strategy=none` は 古い版が キャッシュされ続けるのを防ぐため。

### Vercel（手動・おまけ）

https://rune-link.vercel.app

push しても 自動では更新されない。更新するには 毎回この2つ：

```bash
flutter build web --release --pwa-strategy=none
npx vercel deploy build/web --prod --yes
```

Vercel はルート直下なので `--base-href` は要らない（Pages とちがう）。
`npx` が `EACCES` で落ちるときは `sudo chown -R $(id -u):$(id -g) ~/.npm`。

### 読みこみの重さ

初回に 5MBほど 落ちてくる（brotli圧縮後の実測）。

| 中身 | 転送量 |
|---|---|
| `canvaskit.wasm`（描画エンジン） | 2.8MB |
| 日本語フォント | 1.5MB |
| `main.dart.js` | 0.8MB |
| BGM・効果音（再生時に追加） | 4.1MB（非圧縮WAV） |

減らすなら 効く順に：
**フォントのサブセット化**（1.5MB→数十KB）→ **BGMをMP3化**（4.1MB→300KB前後）
→ 画像のPNG最適化。CanvasKit を切ると `CustomPaint` の描画が落ちるので さわらない。
