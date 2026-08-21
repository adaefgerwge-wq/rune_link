# キャラ画像 生成プロンプト（Epop × ぷちっとロックシューター風）

AI画像生成ツールにコピペして使う。まず「共通スタイル」を土台に、各キャラの1行を足す。
**全キャラで共通スタイルを同じにすると、絵柄が揃う（＝リリース版っぽくなる）。**

## 共通スタイル（土台）
```
cute chibi character, 2.5-head-tall super-deformed proportions, big glossy sparkly eyes,
small round body, soft rounded shapes, clean vector cel-shading, thick soft outline,
pastel color palette with one bold accent color, kawaii but slightly cool and pop,
mobile game mascot, sticker style, full body, front view, centered, simple flat style,
plain solid white background, high quality, 1:1 square
```

## 敵：いたずらオバケ → `assets/enemy.png`
```
（共通スタイル）, a small mischievous ghost monster (obake), round blobby body,
tiny fangs, playful cheeky grin, big cute eyes, floating, soft purple color,
funny not scary
```

## 自分：YOU → `assets/hero.png`
```
（共通スタイル）, a brave little chibi apprentice mage kid, round hood,
a glowing magic rune spark on the fingertip, friendly determined smile,
mint green and purple accents
```
※ 主人公は「動物マスコット（Epopのニニ風）」でもOK。その場合は上を
`a cute chibi mascot creature (small fox / shiba), ...` に差し替え。

## 敵バリエーション（単体で出すこと）
共通スタイルの先頭に必ず `a single one ..., solo, only one character alone` を付け、`sticker` は使わず
`die-cut single character on plain solid white background` にする。ネガティブ:
`two characters, multiple characters, duplicate, pair, group, sticker sheet, extra character`

### あばれオバケ → `assets/enemy2.png`（ステージ2〜）
```
（共通スタイル・単体指定）, an angry little ghost monster, round body with small horns,
puffed cheeks, flame-like wisps, coral red and orange, energetic and feisty, funny not scary
```

### ぬしオバケ → `assets/enemy3.png`（ステージ3・ボス）
```
（共通スタイル・単体指定）, a wise elder boss ghost monster, bigger round body, tiny crown,
closed calm eyes, mint green and gold accents, majestic but cute, funny not scary
```

## 使い方のコツ
- **背景**：透過PNGがベスト。透過を選べないツールは「plain solid white background」で出して、後で remove.bg などで白抜き。
- **形式**：正方形（1:1）で生成 → ファイル名を `hero.png` / `enemy.png` にして `assets/` に保存。
- **枚数**：1回で数枚出して一番良いのを選ぶ。
- **おすすめツール**：Bing Image Creator（DALL·E 3・無料）／Gemini の画像生成／Niji·journey（アニメ系に強い）／Leonardo.ai。
- 置いたら `flutter run` を再起動 → 枠が自動で絵に替わる。

## 次に欲しくなったら（追加で作るキャラ）
- 属性の精霊：火 / 水 / 雷 のちびキャラ（共通スタイル＋ each: `a tiny fire spirit` など）
- 敵のバリエーション、背景、勝利エフェクト など

## のこり3体（ステージ4〜6）
共通の書き出し（単体指定）:
`a single one cute chibi monster, solo, only one character alone, 2.5-head-tall super-deformed, big glossy sparkly eyes, soft rounded shapes, clean vector cel-shading, thick soft outline, pastel palette, kawaii but pop, die-cut single character on plain solid white background, 1:1,`

### こおりオバケ → assets/enemy4.png
`..., a chilly ice ghost monster, round body made of soft ice, tiny icicle crown, frosty pale blue and white, sparkling snowflakes around, cute not scary`

### ほのおオバケ → assets/enemy5.png
`..., a blazing fire ghost monster, round body with flame tufts, glowing orange and red, small fangs, energetic grin, cute not scary`

### そらのぬし → assets/enemy6.png
`..., a majestic sky guardian ghost boss, round cloud-like body, tiny star crown, soft lavender and sky blue, small wings, serene closed eyes, cute not scary`
