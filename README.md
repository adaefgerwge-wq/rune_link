# 印つなぎバトル（rune_link）

ゆびで「印」を描いて戦う、スマホ向けRPG。Flutter製。

---

## これは何のゲームか

- 画面の**下半分に指で印を描く**と、形が認識されて**その属性で攻撃**する
- 印は3種類：**△＝ひ（火）／◯＝みず（水）／Z＝かみなり（雷）**
- **きれいに描けたほど威力が上がる**。敵の弱点属性なら2倍
- ターン制（自分が印を描く → 敵の反撃 → くり返し）
- 全6ステージ・敵6種。ステージごとに背景とBGMが変わる
- 勝つと⭐がもらえ、**ショップでこうげき・たいりょくを恒久強化**できる
- クリア済みステージは**むずかしさ3段階**で周回でき、⭐が多くもらえる
- **ちょうせん**6種（3ターン以内・道具なし・印しばり など）の特殊ルール戦
- **スタミナ制**。バトル1回で⚡1〜3つかい、5分で1つもどる（さいだい20）

**デザインの参考**：Epop（学習アプリ）＋ぷちっと★ロックシューター
＝ 薄紫の背景に白い角丸カード、ぷっくりボタン、2.5頭身のちびキャラ

---

## 動かし方

このフォルダ（`/Users/tetsuro/practice/rune_link`）が
プロジェクトのルート。accounting とは切り離した独立プロジェクト。

### パソコンで開発しながら見る
```bash
cd /Users/tetsuro/practice/rune_link
flutter run -d web-server --web-port 5179 --web-hostname 127.0.0.1
```
→ ブラウザで http://localhost:5179

（`.claude/launch.json` に `rune-link` の起動設定あり）

> **⚠️ 一番ハマったところ**
> コードを直しても**サーバーは自動で反映しない**。
> 必ず `pkill -9 -f dartvm` で止めてから起動し直すこと。
> （古いサーバーのまま見て「直ってない」と勘違いした事故が実際に起きた）

### スマホの実機で試す
```bash
flutter build web --release --pwa-strategy=none
python3 <スクラッチパッド>/nocache_server.py   # 5181番で配信
ipconfig getifaddr en0                        # MacのIPを調べる
```
→ スマホのブラウザで `http://<MacのIP>:5181`
（**IPはWi-Fi再接続で変わる**ので毎回調べ直す）

キャッシュ対策として、サービスワーカーを切って（`--pwa-strategy=none`）
no-cacheヘッダー付きで配信している。

### テスト
```bash
flutter test        # 62件
flutter analyze     # warning ゼロを保つ（info は元から30件ある）
```

> レイアウトのテストは実機に近い縦長（375×812）でやること。
> 800×600 の初期サイズだと、はみ出しも文字の見切れも見逃す。

#### プレビューで画面を操作する方法

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

## 画面の構成

下タブ5つ（`MainShell` が下タブを固定して中身だけ切り替える）:

| タブ | 中身 |
|---|---|
| ホーム | 連続記録・自動バナー・進捗リング・敵アイコン・週間グラフ |
| ずかん | 敵図鑑6体（倒すと解放） |
| **バトル**（中央） | ステージ選択（2エリア横スワイプ）→ むずかしさ選択 → 戦闘 |
| リーグ | ランキング（相手は仮データ） |
| プレミアム | 課金プラン（見た目だけ） |

上部に **⚡スタミナ・🏆トロフィー・⭐スター** が つねに出る。

他に：**マイページ**（レベル・記録・称号21個）／**ショップ**（強化2種＋アイテム4種）／
**ミッション**（日替わり3つ＋通常）／**ちょうせん**（特殊ルール6種）／
**きせかえ**（枠6種）／**メニュー**（☰）

---

## 主な仕組み（lib/main.dart にすべて入っている）

| クラス | 役割 |
|---|---|
| `RuneRecognizer` | 印の形を認識（$1認識アルゴリズムの簡易版）。**崩れた形のパターンも登録**して親指でも通るようにした |
| `Player` | セーブデータ全部（`shared_preferences`）。⭐🏆・進行・統計・アイテム・きせかえ・デイリー・**強化レベル・ステージ別クリア難易度・ちょうせん達成** |
| `Difficulty` | むずかしさ3段階。敵のHP/攻撃力と ⭐の倍率を持つ |
| `Challenge` | ちょうせん6種。ターン制限・道具禁止・印しばり などの条件をまとめた定義 |
| `StaminaCounter` | ⚡と つぎの回復までの時間。1秒ごとに 自分で見なおす |
| `payStamina()` | バトルに入る前に ⚡をはらう。たりなければ ⭐での回復をすすめる |
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
- `assets/sfx/*.wav` … 効果音・BGM（**Pythonで自作合成**したもの）
- `assets/fonts/` … M PLUS Rounded 1c（日本語の丸ゴシック）

キャラの生成プロンプトは **CHARACTER_PROMPTS.md** にまとめてある。
画像は `~/practice/` 配下に置くこと（Downloads や Desktop は macOS の保護で読めない）。

---

## バランスの数字（いじるならここ）

| もの | いま |
|---|---|
| 印の基礎ダメージ | `24 + こうげきLv*4`（Lv10で64） |
| さいだいHP | `100 + たいりょくLv*20`（Lv10で300） |
| 強化のねだん | `40 + Lv*25`（1本あたり合計1450⭐） |
| 勝利の⭐ | `(15 + (ステージ-1)*5) × むずかしさ倍率(1.0/2.0/3.5)` |
| むずかしさ | 敵HP ×1.0/1.6/2.4、敵こうげき ×1.0/1.3/1.6 |
| ちょうせんの⭐ | 初回120〜400、2回目からは1/4 |
| スタミナ | さいだい20、5分で1つ回復 |
| ⚡の消費 | ふつう1／つよい2／げきつよ3／ちょうせん3 |
| ⭐での全回復 | 60⭐から。1日に使うたび倍（60→120→240…）、5回まで |

> **むずかしいほうが ⚡あたりの⭐が多くなる**ようにしてある
> （ステージ6：ふつう40/1 → げきつよ140/3≒47）。
> 周回するなら むずかしいほうが得、という形にそろえた。

## 次にやること

1. **敵3体の絵**（こおり／ほのお／そらのぬし）を生成して `assets/` に置く
2. 遊びの深み：印の種類を増やす／敵の攻撃予告／属性の精霊キャラ
3. iOS・Androidの実機ビルド（今はWebのみ。`android/` `ios/` フォルダは無い）

## GitHub

https://github.com/adaefgerwge-wq/rune_link （SSH でpush）

```bash
git add -A && git commit -m "メッセージ" && git push
```

---

## 決まっている好み（作るときの指針）

- 目立ちすぎる装飾はしない（中央タブだけ特別扱いは却下された）
- 同じ入口を複数作らない（重複メニューは削除する）
- 半透明で背景が透けて読みにくいのはNG（白と混ぜて不透明にする）
- ループアニメの継ぎ目が見えるのはNG（速度を整数倍にして解決した）
