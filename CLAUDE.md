# rune_link をさわるときのメモ

このファイルは **コードを直す人（と Claude Code）向け**。
ゲームの説明や あそびかたは README.md にある。


## 見た目の方針

**デザインの参考**：Epop（学習アプリ）＋ぷちっとロックシューター
＝ 薄紫の背景に白い角丸カード、ぷっくりボタン、2.5頭身のちびキャラ

---

## 主な仕組み（lib/main.dart にすべて入っている）

| クラス | 役割 |
|---|---|
| `RuneRecognizer` | 印の形を認識（$1認識アルゴリズムの簡易版）。**崩れた形のパターンも登録**して親指でも通るようにした |
| `Player` | セーブデータ全部（`shared_preferences`）。スタートロフィー・進行・統計・アイテム・きせかえ・デイリー・強化レベル・ステージ別クリア難易度・ちょうせん達成 |
| `Difficulty` | むずかしさ3段階。敵のHP/攻撃力と スターの倍率を持つ |
| `Challenge` | ちょうせん6種。ターン制限・道具禁止・印しばり などの条件をまとめた定義 |
| `_telegraphChip()` | てきの つぎの手の予告。ここを見て 攻めるか受けるかを決める |
| `HitInfo` / `_hitCard()` | 描いた印の判定。よみとれた印・きれいさ・弱点×2・うけ・キレイ を出す |
| `screenHeader()` | 全画面 共通のヘッダー。三本線・見出し・カウンター・スタミナ |
| `MenuButton` | 三本線。どの画面からでも メニューを開ける |
| `StaminaRow` | ヘッダーのスタミナ。トロフィーの左。数・ゲージ・のこり時間 |
| `StaminaGauge` | ホームの バトルスタート直前に出す ゲージ |
| `StaminaBar` | ゲージ本体。色は いつも青。のこりは 長さだけで あらわす |
| `payStamina()` | バトルに入る前に スタミナをはらう。たりなければ スターでの回復をすすめる |
| `MainShell` | 下タブを固定して中身だけ差し替える外枠 |
| `DressedChar` | きせかえを反映したキャラ表示（全画面で共通） |
| `ChunkyButton` / `ChunkyCircle` / `ChunkyPill` | 押すと沈むボタン |
| `StageBackground` | ステージ別の背景を描く（森/洞窟/祠/雪原/火山/天空） |
| `TutorialOverlay` | 初回だけ出るあそびかた |
| `Spark` | 指の軌跡に舞う光の粒 |

---

## 素材

- `assets/hero.png` … 主人公（AI生成・導入済み）
- `assets/enemy.png` … 敵1体目（AI生成・導入済み）
- `assets/enemy2〜6.png` … **未作成**（無い間はアイコンで代用される）
- `assets/sfx/*.wav` … 効果音・BGM（Pythonで自作合成したもの）
- `assets/sfx/spark1〜3.wav` … 印をなぞる間の キラキラ音。
  高さちがいを3つ用意して 順に鳴らす（同じ音の連打に 聞こえないように）
- `assets/fonts/` … M PLUS Rounded 1c（日本語の丸ゴシック）

キャラの生成プロンプトは **CHARACTER_PROMPTS.md** にまとめてある。
画像は `~/practice/` 配下に置くこと（Downloads や Desktop は macOS の保護で読めない）。

---

## スマホの実機で試す

```bash
flutter build web --release --pwa-strategy=none
python3 <スクラッチパッド>/nocache_server.py   # 5181番で配信
ipconfig getifaddr en0                        # MacのIPを調べる
```

→ スマホのブラウザで `http://<MacのIP>:5181`
（**IPはWi-Fi再接続で変わる**ので毎回調べ直す）

キャッシュ対策として、サービスワーカーを切って（`--pwa-strategy=none`）
no-cacheヘッダー付きで配信している。

---

## つぎにやること・のこっている穴

1. 敵3体の絵（こおり／ほのお／そらのぬし）を作る
2. 読みこみを軽くする（フォントのサブセット化・BGMのMP3化）
3. リーグとプレミアムを ちゃんと動くようにする
4. コンボ（3種類を続けて描くと大ダメージ）
5. iOS・Androidの実機ビルド（今はWebのみ）

くわしくは：

- リーグは仮データのまま（ライバル7人が定数で埋め込まれていて 永久に動かない）。
  プレミアムも見た目だけ＝**下タブ5つのうち2つが飾り**になっている
- スターは強化を上げ切る（合計2900スター）と 使い道が きせかえとスタミナ回復だけになる

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
