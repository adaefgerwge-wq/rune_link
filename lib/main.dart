import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Player.load(); // 保存データを読み込んでから起動
  runApp(const RuneLinkApp());
}

// ===== カラー =====
const kBg = Color(0xFFF3EFFB); // うすい紫
const kInk = Color(0xFF3C3C46);
const kInkSoft = Color(0xFFA6A6B3);
const kPurple = Color(0xFF8B6FE0);
const kPurpleDeep = Color(0xFF6E52C4);
const kGreen = Color(0xFF7CC043);
const kGreenDeep = Color(0xFF63A230);
const kGold = Color(0xFFF5B920);
const kStar = Color(0xFF3FA9F5);
const kHeart = Color(0xFFFF6B6B);
const kStroke = Color(0xFF5A5A66);

// プレイヤーの持ち物・進行（ホームとバトルで共有）
class Player {
  static int trophies = 0;
  static int stars = 0;
  static int cleared = 0; // クリア済みステージ数（=解放の進み具合）
  static int streak = 0; // 連続プレイ日数
  static int todayWins = 0; // 今日たおした数
  static int dailyGoal = 5; // 1日の目標
  static String name = 'あなた';

  // 統計：属性ごとの使用回数（ずかん・グラフ用）
  static Map<String, int> elemUses = {'water': 0, 'fire': 0, 'thunder': 0};
  // ずかん：たおした敵ごとの数
  static Map<String, int> defeatedByName = {};
  // もちもの：アイテム名 → 個数
  static Map<String, int> items = {};
  // 今週の記録（月〜日、たおした数）
  static List<int> weekWins = [0, 0, 0, 0, 0, 0, 0];
  static String lastPlayed = ''; // 最後に遊んだ日 yyyy-mm-dd
  static bool tutorialDone = false; // あそびかたを見たか

  // きょうのミッション（日付が変わると入れ替わる）
  static int dailyWins = 0; // 今日たおした数
  static int dailyElems = 0; // 今日つかった印の数
  static int dailyCrits = 0; // 今日のキレイな印
  static List<int> dailyIds = []; // 今日のミッション番号
  static Set<int> dailyClaimed = {}; // 受けとり済み

  // きせかえ（かざり）
  static String cosmetic = 'none'; // いま つけているもの
  static Set<String> ownedCosmetics = {'none'}; // 持っているもの

  // ---- スタミナ（バトルに挑むための げんき）----
  static const int maxStamina = 20;
  static const int staminaMinutes = 5; // 1つ回復するのにかかる分
  static const int maxRefillsPerDay = 5; // 1日に⭐で回復できる回数
  static int _stamina = maxStamina;
  static int staminaAt = 0; // 最後に数えなおした時刻（ミリ秒）
  static int refillsToday = 0; // きょう⭐で回復した回数

  /// いまのスタミナ（読むたびに 時間ぶんを足してから返す）
  static int get stamina {
    _syncStamina();
    return _stamina;
  }

  static int get _stepMillis => staminaMinutes * 60 * 1000;

  /// 前に数えた時からの 経過ぶんを足す
  /// アプリを閉じていても 時計で計算するので ちゃんと回復する
  static void _syncStamina() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (staminaAt == 0) {
      staminaAt = now;
      return;
    }
    if (_stamina >= maxStamina) {
      staminaAt = now; // 満タンの間は 数えはじめを いまに合わせておく
      return;
    }
    final gained = (now - staminaAt) ~/ _stepMillis;
    if (gained <= 0) return;
    _stamina = (_stamina + gained).clamp(0, maxStamina);
    // 満タンになったら いま、まだなら 使ったぶんだけ進める（はんぱを捨てない）
    staminaAt =
        _stamina >= maxStamina ? now : staminaAt + gained * _stepMillis;
  }

  /// つぎの1つが回復するまでの 秒数（満タンなら0）
  static int get secondsToNextStamina {
    _syncStamina();
    if (_stamina >= maxStamina) return 0;
    final left = staminaAt + _stepMillis - DateTime.now().millisecondsSinceEpoch;
    return (left / 1000).ceil().clamp(0, staminaMinutes * 60);
  }

  static bool canPlay(int cost) => stamina >= cost;

  /// スタミナを つかう（たりなければ false）
  static bool spendStamina(int cost) {
    if (!canPlay(cost)) return false;
    // 満タンから減る瞬間に 回復の数えはじめを いまに合わせる
    if (_stamina >= maxStamina) {
      staminaAt = DateTime.now().millisecondsSinceEpoch;
    }
    _stamina -= cost;
    save();
    return true;
  }

  /// ⭐での回復のねだん（きょう使うほど倍になる）
  static int get refillCost => 60 * (1 << refillsToday);

  /// きょう まだ⭐で回復できるか
  static bool get canRefillToday => refillsToday < maxRefillsPerDay;

  /// ⭐をはらって スタミナを満タンにする
  static bool buyRefill() {
    if (!canRefillToday) return false;
    final c = refillCost;
    if (stars < c) return false;
    stars -= c;
    refillsToday += 1;
    _stamina = maxStamina;
    staminaAt = DateTime.now().millisecondsSinceEpoch;
    save();
    return true;
  }

  // クリアした ちょうせん（kChallenges の番号）
  static Set<int> challengeCleared = {};

  /// そのちょうせんに 挑めるか（そのステージまで進んでいれば）
  static bool challengeOpen(int i) => kChallenges[i].stage <= cleared;

  /// ちょうせんクリアを記録して ⭐をわたす
  /// はじめてなら まるごと、2回目からは 少しだけ
  static int recordChallenge(int i) {
    final c = kChallenges[i];
    final first = !challengeCleared.contains(i);
    final gain = first ? c.reward : c.repeatReward;
    challengeCleared.add(i);
    stars += gain;
    save();
    return gain;
  }

  // ステージごとの いちばん上のクリア済みむずかしさ
  // （ステージ番号 → 0=ふつう / 1=つよい / 2=げきつよ。無ければ未クリア）
  static Map<int, int> stageBest = {};

  /// そのステージの むずかしさを選べるか
  /// ふつうは クリア済みなら常に選べる。上は ひとつ下をクリアしてから
  static bool diffUnlocked(int stage, int diff) {
    if (stage > cleared) return diff == 0; // 初挑戦は ふつうだけ
    if (diff == 0) return true;
    return (stageBest[stage] ?? -1) >= diff - 1;
  }

  /// そのステージ・むずかしさを クリア済みか
  static bool diffCleared(int stage, int diff) =>
      (stageBest[stage] ?? -1) >= diff;

  /// クリアを記録する（今までより上なら 更新）
  static void recordStageClear(int stage, int diff) {
    if ((stageBest[stage] ?? -1) < diff) {
      stageBest[stage] = diff;
      save();
    }
  }

  // つよくなる（ずっと効く強化。⭐で上げる）
  static int atkLv = 0; // こうげきの強化レベル
  static int hpLv = 0; // たいりょくの強化レベル
  static const int maxUpgradeLv = 10;

  /// 印の基礎ダメージ（24 → 64）
  static int get atk => 24 + atkLv * 4;

  /// さいだいHP（100 → 300）
  static int get maxHp => 100 + hpLv * 20;

  /// つぎの強化にかかる⭐（上げるほど高くなる）
  static int upgradeCost(int lv) => 40 + lv * 25;

  /// こうげき／たいりょくを1段あげる
  static bool buyUpgrade({required bool isAtk}) {
    final lv = isAtk ? atkLv : hpLv;
    if (lv >= maxUpgradeLv) return false;
    final cost = upgradeCost(lv);
    if (stars < cost) return false;
    stars -= cost;
    if (isAtk) {
      atkLv += 1;
    } else {
      hpLv += 1;
    }
    save();
    return true;
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      trophies = p.getInt('trophies') ?? 0;
      stars = p.getInt('stars') ?? 0;
      cleared = p.getInt('cleared') ?? 0;
      streak = p.getInt('streak') ?? 0;
      todayWins = p.getInt('todayWins') ?? 0;
      dailyGoal = p.getInt('dailyGoal') ?? 5;
      name = p.getString('name') ?? 'あなた';
      lastPlayed = p.getString('lastPlayed') ?? '';
      tutorialDone = p.getBool('tutorialDone') ?? false;
      cosmetic = p.getString('cosmetic') ?? 'none';
      ownedCosmetics =
          (p.getStringList('ownedCosmetics') ?? ['none']).toSet();
      atkLv = (p.getInt('atkLv') ?? 0).clamp(0, maxUpgradeLv);
      hpLv = (p.getInt('hpLv') ?? 0).clamp(0, maxUpgradeLv);
      stageBest = {};
      _stamina = (p.getInt('stamina') ?? maxStamina).clamp(0, maxStamina);
      staminaAt = p.getInt('staminaAt') ?? 0;
      refillsToday = p.getInt('refillsToday') ?? 0;
      challengeCleared = (p.getStringList('challengeCleared') ?? [])
          .map((e) => int.tryParse(e) ?? -1)
          .where((e) => e >= 0 && e < kChallenges.length)
          .toSet();
      for (var n = 1; n <= kStageCount; n++) {
        final v = p.getInt('best_$n');
        if (v != null) stageBest[n] = v.clamp(0, kDifficulties.length - 1);
      }
      dailyWins = p.getInt('dailyWins') ?? 0;
      dailyElems = p.getInt('dailyElems') ?? 0;
      dailyCrits = p.getInt('dailyCrits') ?? 0;
      dailyIds = (p.getStringList('dailyIds') ?? [])
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      dailyClaimed = (p.getStringList('dailyClaimed') ?? [])
          .map((e) => int.tryParse(e) ?? 0)
          .toSet();
      for (final k in elemUses.keys.toList()) {
        elemUses[k] = p.getInt('elem_$k') ?? 0;
      }
      for (final e in kEnemies) {
        final v = p.getInt('def_${e.name}') ?? 0;
        if (v > 0) defeatedByName[e.name] = v;
      }
      for (final it in kShopItems) {
        final v = p.getInt('item_${it.name}') ?? 0;
        if (v > 0) items[it.name] = v;
      }
      final wk = p.getStringList('weekWins');
      if (wk != null && wk.length == 7) {
        weekWins = wk.map((s) => int.tryParse(s) ?? 0).toList();
      }
      _rolloverDay(); // 日付が変わっていたら連続記録を更新
    } catch (_) {}
  }

  // 日付をまたいだ時の処理（連続記録の継続 or リセット）
  static void _rolloverDay() {
    final today = _today();
    if (lastPlayed == today) return;
    if (lastPlayed.isEmpty) {
      streak = 0;
    } else {
      final last = DateTime.tryParse(lastPlayed);
      if (last != null) {
        final diff = DateTime.parse(today).difference(last).inDays;
        if (diff == 1) {
          // 昨日も遊んでいた＝continue（実際の加算は今日プレイ時）
        } else if (diff > 1) {
          streak = 0; // 途切れた
        }
      }
    }
    todayWins = 0; // 新しい日なのでリセット
    refillsToday = 0; // ⭐での回復も 1日ぶん もどす
    _rollDaily(); // ミッションも入れ替える
  }

  /// きょうのミッションを選び直す（日替わり）
  static void _rollDaily() {
    dailyWins = 0;
    dailyElems = 0;
    dailyCrits = 0;
    dailyClaimed = {};
    // 日付をタネにして その日は同じ内容になるようにする
    final seed = _today().hashCode;
    final r = Random(seed);
    final all = List<int>.generate(kDailyMissions.length, (i) => i);
    all.shuffle(r);
    dailyIds = all.take(3).toList();
  }

  /// きょうのミッションが未設定なら用意する
  static void ensureDaily() {
    if (dailyIds.length != 3) _rollDaily();
  }

  /// 今日プレイした記録をつける（連続日数を伸ばす）
  static void markPlayedToday() {
    final today = _today();
    if (lastPlayed != today) {
      streak += 1;
      lastPlayed = today;
      todayWins = 0;
    }
  }

  static Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('trophies', trophies);
      await p.setInt('stars', stars);
      await p.setInt('cleared', cleared);
      await p.setInt('streak', streak);
      await p.setInt('todayWins', todayWins);
      await p.setInt('dailyGoal', dailyGoal);
      await p.setString('name', name);
      await p.setString('lastPlayed', lastPlayed);
      await p.setBool('tutorialDone', tutorialDone);
      await p.setString('cosmetic', cosmetic);
      await p.setStringList('ownedCosmetics', ownedCosmetics.toList());
      await p.setInt('atkLv', atkLv);
      await p.setInt('hpLv', hpLv);
      for (final e in stageBest.entries) {
        await p.setInt('best_${e.key}', e.value);
      }
      await p.setInt('stamina', _stamina);
      await p.setInt('staminaAt', staminaAt);
      await p.setInt('refillsToday', refillsToday);
      await p.setStringList('challengeCleared',
          challengeCleared.map((e) => e.toString()).toList());
      await p.setInt('dailyWins', dailyWins);
      await p.setInt('dailyElems', dailyElems);
      await p.setInt('dailyCrits', dailyCrits);
      await p.setStringList(
          'dailyIds', dailyIds.map((e) => e.toString()).toList());
      await p.setStringList(
          'dailyClaimed', dailyClaimed.map((e) => e.toString()).toList());
      for (final e in elemUses.entries) {
        await p.setInt('elem_${e.key}', e.value);
      }
      for (final e in defeatedByName.entries) {
        await p.setInt('def_${e.key}', e.value);
      }
      for (final e in items.entries) {
        await p.setInt('item_${e.key}', e.value);
      }
      await p.setStringList(
          'weekWins', weekWins.map((v) => v.toString()).toList());
    } catch (_) {}
  }

  /// 勝利時の記録
  static void recordWin(String enemyName, {int reward = 15}) {
    trophies += 1;
    stars += reward;
    todayWins += 1;
    dailyWins += 1;
    defeatedByName[enemyName] = (defeatedByName[enemyName] ?? 0) + 1;
    final wd = DateTime.now().weekday - 1; // 月=0
    if (wd >= 0 && wd < 7) weekWins[wd] += 1;
    save();
  }

  /// かざりを買う
  static bool buyCosmetic(Cosmetic c) {
    if (ownedCosmetics.contains(c.id)) return false;
    if (stars < c.price) return false;
    stars -= c.price;
    ownedCosmetics.add(c.id);
    cosmetic = c.id; // 買ったら すぐつける
    save();
    return true;
  }

  /// かざりをつけかえる
  static void equipCosmetic(String id) {
    if (!ownedCosmetics.contains(id)) return;
    cosmetic = id;
    save();
  }

  /// きょうのミッションの ごほうびを受けとる
  static bool claimDaily(int id) {
    if (dailyClaimed.contains(id)) return false;
    final m = kDailyMissions[id];
    if (m.progress() < m.goal) return false;
    dailyClaimed.add(id);
    stars += m.reward;
    save();
    return true;
  }

  /// アイテムを1つ増やす
  static void addItem(String name) {
    items[name] = (items[name] ?? 0) + 1;
    save();
  }

  /// アイテムを1つ使う（持っていなければ false）
  static bool useItem(String name) {
    final n = items[name] ?? 0;
    if (n <= 0) return false;
    items[name] = n - 1;
    if (items[name] == 0) items.remove(name);
    save();
    return true;
  }

  /// 記録をぜんぶ消す
  static Future<void> reset() async {
    trophies = 0;
    stars = 0;
    cleared = 0;
    streak = 0;
    todayWins = 0;
    lastPlayed = '';
    tutorialDone = false; // あそびかたも 最初から
    dailyWins = 0;
    dailyElems = 0;
    dailyCrits = 0;
    dailyIds = [];
    dailyClaimed = {};
    cosmetic = 'none';
    ownedCosmetics = {'none'};
    atkLv = 0;
    hpLv = 0;
    stageBest = {};
    challengeCleared = {};
    _stamina = maxStamina;
    staminaAt = 0;
    refillsToday = 0;
    elemUses = {'water': 0, 'fire': 0, 'thunder': 0};
    defeatedByName = {};
    items = {};
    weekWins = [0, 0, 0, 0, 0, 0, 0];
    try {
      final p = await SharedPreferences.getInstance();
      await p.clear();
    } catch (_) {}
  }

  static void recordElem(Elem e, {bool crit = false}) {
    final k = e.name;
    elemUses[k] = (elemUses[k] ?? 0) + 1;
    dailyElems += 1;
    if (crit) dailyCrits += 1;
  }
}

/// キャラのかざり（枠・背景・キラキラ）
class Cosmetic {
  final String id;
  final String name;
  final int price;
  final List<Color> frame; // 枠のグラデーション
  final Color bg; // 後ろの色
  final bool sparkle; // キラキラが舞うか
  const Cosmetic(this.id, this.name, this.price, this.frame, this.bg,
      {this.sparkle = false});
}

const List<Cosmetic> kCosmetics = [
  Cosmetic('none', 'ふつう', 0, [Color(0xFFE6E6EC), Color(0xFFE6E6EC)],
      Colors.white),
  Cosmetic('mint', 'みどりの わ', 40, [Color(0xFF7CC043), Color(0xFFB5E27E)],
      Color(0xFFF1FAE8)),
  Cosmetic('sky', 'そらの わ', 40, [Color(0xFF4FA9F5), Color(0xFF9FD8F5)],
      Color(0xFFEAF5FE)),
  Cosmetic('rose', 'ももいろの わ', 60, [Color(0xFFFF6B6B), Color(0xFFFFB0B0)],
      Color(0xFFFFEFEF)),
  Cosmetic('gold', 'きんの わ', 120, [Color(0xFFF5B920), Color(0xFFFFE08A)],
      Color(0xFFFFF7E4), sparkle: true),
  Cosmetic('rainbow', 'にじいろの わ', 240, [
    Color(0xFFFF6B6B),
    Color(0xFFF5B920),
    Color(0xFF7CC043),
    Color(0xFF4FA9F5),
    Color(0xFF8B6FE0),
  ], Color(0xFFF6F1FF), sparkle: true),
];

Cosmetic cosmeticById(String id) =>
    kCosmetics.firstWhere((c) => c.id == id, orElse: () => kCosmetics.first);

/// きょうのミッション（毎日3つ 選ばれる）
class DailyMission {
  final String title;
  final int goal;
  final int reward; // もらえる⭐
  final IconData icon;
  final int Function() progress;
  const DailyMission(
      this.title, this.goal, this.reward, this.icon, this.progress);
}

final List<DailyMission> kDailyMissions = [
  DailyMission('てきを 3たい たおす', 3, 20, Icons.sports_martial_arts,
      () => Player.dailyWins),
  DailyMission('てきを 5たい たおす', 5, 35, Icons.whatshot_rounded,
      () => Player.dailyWins),
  DailyMission('印を 10かい つかう', 10, 20, Icons.gesture_rounded,
      () => Player.dailyElems),
  DailyMission('印を 25かい つかう', 25, 40, Icons.auto_fix_high,
      () => Player.dailyElems),
  DailyMission('キレイな印を 3かい', 3, 30, Icons.star_rounded,
      () => Player.dailyCrits),
  DailyMission('キレイな印を 8かい', 8, 50, Icons.auto_awesome,
      () => Player.dailyCrits),
  DailyMission('きょう 1回 あそぶ', 1, 10, Icons.play_circle_fill_rounded,
      () => Player.dailyElems > 0 ? 1 : 0),
];

/// しょうごう（称号）
class TitleDef {
  final String name;
  final bool Function() check;
  const TitleDef(this.name, this.check);
}

int _totalDefeated() =>
    Player.defeatedByName.values.fold<int>(0, (a, b) => a + b);
int _totalElems() => Player.elemUses.values.fold<int>(0, (a, b) => a + b);

final List<TitleDef> kTitles = [
  TitleDef('しんまい', () => true),
  TitleDef('はじめての勝利', () => _totalDefeated() >= 1),
  TitleDef('10たい たおした', () => _totalDefeated() >= 10),
  TitleDef('50たい たおした', () => _totalDefeated() >= 50),
  TitleDef('100たい たおした', () => _totalDefeated() >= 100),
  TitleDef('印つかい', () => _totalElems() >= 30),
  TitleDef('印マスター', () => _totalElems() >= 200),
  TitleDef('みずの達人', () => (Player.elemUses['water'] ?? 0) >= 50),
  TitleDef('ひの達人', () => (Player.elemUses['fire'] ?? 0) >= 50),
  TitleDef('かみなりの達人', () => (Player.elemUses['thunder'] ?? 0) >= 50),
  TitleDef('れんぞく 3日', () => Player.streak >= 3),
  TitleDef('れんぞく 7日', () => Player.streak >= 7),
  TitleDef('れんぞく 30日', () => Player.streak >= 30),
  TitleDef('ずかん はんぶん',
      () => Player.defeatedByName.keys.length >= (kStageCount / 2).ceil()),
  TitleDef('ずかん マスター',
      () => Player.defeatedByName.keys.length >= kStageCount),
  TitleDef('ぼうけんの はじまり', () => Player.cleared >= 1),
  TitleDef('ぼうけん なかば', () => Player.cleared >= 3),
  TitleDef('ぼうけん クリア', () => Player.cleared >= kStageCount),
  TitleDef('⭐100あつめた', () => Player.stars >= 100),
  TitleDef('⭐500あつめた', () => Player.stars >= 500),
  TitleDef('かいものじょうず', () => Player.items.isNotEmpty),
];

// 効果音
class Sfx {
  static final AudioPlayer _p = AudioPlayer();
  static void play(String name) {
    if (!Sound.on) return; // ミュート中は鳴らさない
    try {
      _p.play(AssetSource('sfx/$name'));
    } catch (_) {}
  }

  static Future<void> stopNow() async {
    try {
      await _p.stop();
    } catch (_) {}
  }
}

/// 音のオン・オフ（BGMと効果音のどちらにも効く）
class Sound {
  static bool on = false; // 最初はミュート
}

// BGM（画面ごとに曲を切り替えてループ再生）
class Bgm {
  static final AudioPlayer _p = AudioPlayer();
  static String? _current; // いま鳴っている曲

  /// 音が出る状態か（効果音と共通）
  static bool get on => Sound.on;

  static const home = 'sfx/bgm_home.wav';
  static const battle = 'sfx/bgm_battle.wav';

  /// ステージごとの曲
  static String forStage(int stage) =>
      'sfx/bgm_s${stage.clamp(1, kStageCount)}.wav';

  /// 指定の曲に切り替える（同じ曲ならそのまま流し続ける）
  static Future<void> play(String track) async {
    if (_current == track && on) return;
    _current = track; // ミュート中でも「今の曲」は覚えておく
    if (!on) return;
    try {
      await _p.stop();
      await _p.setReleaseMode(ReleaseMode.loop);
      await _p.setVolume(track == home ? 0.35 : 0.30);
      await _p.play(AssetSource(track));
    } catch (_) {}
  }

  /// いったん止める（負けたときの静けさ用）
  static Future<void> stopNow() async {
    try {
      await _p.stop();
    } catch (_) {}
    _current = null; // 次に同じ曲でも鳴らし直せるように
  }

  static Future<void> toggle() async {
    Sound.on = !Sound.on;
    try {
      if (Sound.on) {
        final t = _current ?? home;
        _current = null; // 強制的に鳴らし直す
        await play(t);
      } else {
        await _p.pause();
        await Sfx.stopNow(); // 鳴っている効果音も止める
      }
    } catch (_) {}
  }
}

// ===== 敵の種類（④バリエーション）=====
class EnemyType {
  final String name;
  final String asset;
  final IconData icon; // 画像が無いとき用
  final Color tint;
  final int baseHp;
  final int atkMin;
  final int atkMax;
  const EnemyType(this.name, this.asset, this.icon, this.tint, this.baseHp,
      this.atkMin, this.atkMax);
}

const List<EnemyType> kEnemies = [
  EnemyType('いたずらオバケ', 'assets/enemy.png', Icons.bug_report,
      Color(0xFFB39DE8), 100, 8, 14),
  EnemyType('あばれオバケ', 'assets/enemy2.png', Icons.local_fire_department,
      Color(0xFFFFA8A8), 130, 11, 18),
  EnemyType('ぬしオバケ', 'assets/enemy3.png', Icons.psychology,
      Color(0xFF8FD9C4), 170, 14, 22),
  EnemyType('こおりオバケ', 'assets/enemy4.png', Icons.ac_unit,
      Color(0xFF9FD8F5), 210, 16, 25),
  EnemyType('ほのおオバケ', 'assets/enemy5.png', Icons.whatshot,
      Color(0xFFFFB27A), 250, 19, 29),
  EnemyType('そらのぬし', 'assets/enemy6.png', Icons.cloud,
      Color(0xFFC7B6F5), 320, 22, 34),
];

/// ステージの数（敵の種類ぶん）
const int kStageCount = 6;

/// ステージの むずかしさ（クリア済みステージを 何度でも遊ぶための段階）
class Difficulty {
  final String label;
  final double hpMul; // 敵のHP倍率
  final double atkMul; // 敵の攻撃力倍率
  final double starMul; // もらえる⭐の倍率
  final Color color;
  final IconData icon;
  const Difficulty(this.label, this.hpMul, this.atkMul, this.starMul,
      this.color, this.icon);
}

const List<Difficulty> kDifficulties = [
  Difficulty('ふつう', 1.0, 1.0, 1.0, kGreen, Icons.sentiment_satisfied_rounded),
  Difficulty('つよい', 1.6, 1.3, 2.0, Color(0xFFF5B920),
      Icons.local_fire_department_rounded),
  Difficulty('げきつよ', 2.4, 1.6, 3.5, kHeart, Icons.whatshot_rounded),
];

/// とくべつなルールで戦う ちょうせん
/// 新しいバトルを作らず、いまのバトルに条件を足して 遊びを増やす
class Challenge {
  final String name;
  final String rule; // 条件の ひとこと説明
  final IconData icon;
  final Color color;
  final int enemyIndex; // どの敵と戦うか（固定）
  final int stage; // 背景と曲に使うステージ
  final int turnLimit; // 0 なら ターン制限なし
  final bool noItems; // もちものを つかえない
  final Elem? onlyElem; // この印しか つかえない
  final double enemyAtkMul; // 敵の攻撃力倍率
  final int hpDrain; // 毎ターン へるHP
  final int reward; // はじめてクリアしたときの⭐
  const Challenge({
    required this.name,
    required this.rule,
    required this.icon,
    required this.color,
    required this.enemyIndex,
    required this.stage,
    required this.reward,
    this.turnLimit = 0,
    this.noItems = false,
    this.onlyElem,
    this.enemyAtkMul = 1.0,
    this.hpDrain = 0,
  });

  /// 2回目からの⭐（くり返し遊べるように 少しだけ入る）
  int get repeatReward => (reward * 0.25).round();
}

const List<Challenge> kChallenges = [
  Challenge(
    name: 'はやうち',
    rule: '3ターン いないに たおす',
    icon: Icons.bolt_rounded,
    color: Color(0xFFF5B920),
    enemyIndex: 0,
    stage: 1,
    turnLimit: 3,
    reward: 120,
  ),
  Challenge(
    name: 'ひとつの印',
    rule: 'ひ の印しか つかえない',
    icon: Icons.local_fire_department_rounded,
    color: Color(0xFFFF6B6B),
    enemyIndex: 1,
    stage: 2,
    onlyElem: Elem.fire,
    reward: 150,
  ),
  Challenge(
    name: 'どうぐなし',
    rule: 'もちものを つかえない',
    icon: Icons.block_rounded,
    color: Color(0xFF8FD9C4),
    enemyIndex: 2,
    stage: 3,
    noItems: true,
    reward: 180,
  ),
  Challenge(
    name: 'はんげき',
    rule: 'てきの こうげきが 2ばい',
    icon: Icons.shield_moon_rounded,
    color: Color(0xFF9FD8F5),
    enemyIndex: 3,
    stage: 4,
    enemyAtkMul: 2.0,
    reward: 220,
  ),
  Challenge(
    name: 'じりひん',
    rule: 'まいターン HPが 5へる',
    icon: Icons.hourglass_bottom_rounded,
    color: Color(0xFFFFB27A),
    enemyIndex: 4,
    stage: 5,
    hpDrain: 5,
    reward: 260,
  ),
  Challenge(
    name: 'さいごの しれん',
    rule: 'もちものなし ＋ こうげき2ばい',
    icon: Icons.workspace_premium_rounded,
    color: Color(0xFFC7B6F5),
    enemyIndex: 5,
    stage: 6,
    noItems: true,
    enemyAtkMul: 2.0,
    reward: 400,
  ),
];

/// バトル1回で つかうスタミナ
/// むずかしいほど 多く要るが、もらえる⭐のほうが 伸びが大きい
int staminaCost({int diff = 0, int challenge = -1}) {
  if (challenge >= 0) return 3; // ちょうせん
  const byDiff = [1, 2, 3];
  return byDiff[diff.clamp(0, byDiff.length - 1)];
}

/// そのステージ・むずかしさで 勝ったときにもらえる⭐
/// 先のステージほど、むずかしいほど 多くもらえる
int winStars(int stage, int diff) {
  final base = 15 + (stage - 1) * 5; // ステージ1:15 → ステージ6:40
  return (base * kDifficulties[diff].starMul).round();
}

enum Elem { water, fire, thunder }

Color elemColor(Elem e) {
  switch (e) {
    case Elem.water:
      return const Color(0xFF4FA9F5);
    case Elem.fire:
      return const Color(0xFFFF6B6B);
    case Elem.thunder:
      return const Color(0xFFFFB84D);
  }
}

/// その印の 形（△◯Z）。凡例と 判定表示で 同じ記号を使う
String elemShape(Elem e) {
  switch (e) {
    case Elem.water:
      return '◯';
    case Elem.fire:
      return '△';
    case Elem.thunder:
      return 'Z';
  }
}

String elemLabel(Elem e) {
  switch (e) {
    case Elem.water:
      return 'みず';
    case Elem.fire:
      return 'ひ';
    case Elem.thunder:
      return 'かみなり';
  }
}

class RuneLinkApp extends StatelessWidget {
  const RuneLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'rune link',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          scaffoldBackgroundColor: kBg, fontFamily: 'MPLUSRounded1c'),
      home: const MainShell(),
    );
  }
}

// ======================= 共通の見た目パーツ =======================

// 画像があれば表示・無ければアイコン
Widget charImage(String asset, IconData icon, double size, Color color) {
  return Image.asset(asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          Icon(icon, size: size * 0.8, color: color));
}

// 角丸・白フチのキャラ額縁
Widget roundedChar(String asset, IconData icon, double size, Color color) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: Container(
      width: size,
      height: size,
      color: Colors.white,
      child: charImage(asset, icon, size, color),
    ),
  );
}

/// かざりつきの キャラ表示（枠・背景・キラキラ）
class DressedChar extends StatefulWidget {
  final double size;
  final String? cosmeticId; // 指定がなければ いまつけているもの
  const DressedChar({super.key, required this.size, this.cosmeticId});

  @override
  State<DressedChar> createState() => _DressedCharState();
}

class _DressedCharState extends State<DressedChar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(seconds: 3));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = cosmeticById(widget.cosmeticId ?? Player.cosmetic);
    // キラキラのある かざりのときだけ animation を回す（むだに動かさない）
    if (c.sparkle && !_c.isAnimating) {
      _c.repeat();
    } else if (!c.sparkle && _c.isAnimating) {
      _c.stop();
    }
    final sz = widget.size;
    final ring = sz * 0.055; // 枠の太さ
    return SizedBox(
      width: sz,
      height: sz,
      child: Stack(alignment: Alignment.center, children: [
        // 枠（グラデーション）
        Container(
          width: sz,
          height: sz,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(sz * 0.24),
            gradient: LinearGradient(
              colors: c.frame.length == 1 ? [...c.frame, ...c.frame] : c.frame,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        // 中身（背景＋キャラ）
        Container(
          width: sz - ring * 2,
          height: sz - ring * 2,
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(sz * 0.20),
          ),
          clipBehavior: Clip.antiAlias,
          child: charImage('assets/hero.png', Icons.pets, sz, kGreen),
        ),
        // キラキラ
        if (c.sparkle)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => CustomPaint(
                  painter: SparkleRingPainter(_c.value, c.frame.first),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// かざりのキラキラ
class SparkleRingPainter extends CustomPainter {
  final double t;
  final Color color;
  SparkleRingPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = size.width * 0.52;
    for (int i = 0; i < 5; i++) {
      final a = (t + i / 5) * 2 * pi;
      final p = Offset(cx + r * cos(a), cy + r * sin(a) * 0.9);
      // まわりながら 大きさが変わる
      final s = 2.0 + (sin(a * 2 + t * 6).abs()) * 2.6;
      canvas.drawCircle(p, s, Paint()..color = color.withValues(alpha: 0.85));
    }
  }

  @override
  bool shouldRepaint(covariant SparkleRingPainter old) => true;
}

// ぷっくり丸ボタン（Epop風・下エッジ付き）
Widget chunkyButton({
  required String label,
  required Color color,
  required Color edge,
  required VoidCallback onTap,
  IconData? icon,
  double width = double.infinity,
  Color textColor = Colors.white,
}) {
  return ChunkyButton(
    label: label,
    color: color,
    edge: edge,
    onTap: onTap,
    icon: icon,
    width: width,
    textColor: textColor,
  );
}

/// 押すと ストンと沈む ぷっくりボタン
class ChunkyButton extends StatefulWidget {
  final String label;
  final Color color;
  final Color edge;
  final VoidCallback onTap;
  final IconData? icon;
  final double width;
  final Color textColor;
  const ChunkyButton({
    super.key,
    required this.label,
    required this.color,
    required this.edge,
    required this.onTap,
    this.icon,
    this.width = double.infinity,
    this.textColor = Colors.white,
  });

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  static const double _edgeH = 4; // 下のふちの厚み
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          // 押すと ふちのぶんだけ下がる（高さは変わらないのでガタつかない）
          transform:
              Matrix4.translationValues(0, _down ? _edgeH : 0, 0),
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(18),
            // 押している間は ふちを消して 沈んで見せる
            border: Border(
              bottom: BorderSide(
                  color: _down ? widget.color : widget.edge, width: _edgeH),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: widget.textColor, size: 22),
                const SizedBox(width: 8),
              ],
              Text(widget.label,
                  style: TextStyle(
                      color: widget.textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 17)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 押すと沈む まるいボタン（ステージの道など）
class ChunkyCircle extends StatefulWidget {
  final double size;
  final Color color;
  final Color edge;
  final Widget child;
  final VoidCallback? onTap;
  const ChunkyCircle({
    super.key,
    required this.size,
    required this.color,
    required this.edge,
    required this.child,
    this.onTap,
  });

  @override
  State<ChunkyCircle> createState() => _ChunkyCircleState();
}

class _ChunkyCircleState extends State<ChunkyCircle> {
  static const double _edgeH = 5;
  bool _down = false;
  void _set(bool v) {
    if (_down != v && widget.onTap != null) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _down ? _edgeH : 0, 0),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          border: Border(
            bottom: BorderSide(
                color: _down ? widget.color : widget.edge, width: _edgeH),
          ),
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

/// 押すと沈む 小さめのボタン（ショップの値段ボタンなど）
class ChunkyPill extends StatefulWidget {
  final Widget child;
  final Color color;
  final Color edge;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;
  const ChunkyPill({
    super.key,
    required this.child,
    required this.color,
    required this.edge,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    this.radius = 14,
  });

  @override
  State<ChunkyPill> createState() => _ChunkyPillState();
}

class _ChunkyPillState extends State<ChunkyPill> {
  static const double _edgeH = 3;
  bool _down = false;
  void _set(bool v) {
    if (_down != v && widget.onTap != null) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _down ? _edgeH : 0, 0),
        padding: widget.padding,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border(
            bottom: BorderSide(
                color: _down ? widget.color : widget.edge, width: _edgeH),
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

Widget hpBar(int hp, int max, Color color) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: Stack(children: [
      Container(height: 14, color: const Color(0xFFEDEDF2)),
      FractionallySizedBox(
        widthFactor: (hp / max).clamp(0.0, 1.0),
        child: Container(height: 14, color: color),
      ),
    ]),
  );
}

/// 音のオン・オフボタン（どの画面でも使える）
class BgmButton extends StatefulWidget {
  final double size;
  const BgmButton({super.key, this.size = 22});
  @override
  State<BgmButton> createState() => _BgmButtonState();
}

class _BgmButtonState extends State<BgmButton> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await Bgm.toggle();
        if (mounted) setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Icon(
            Bgm.on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            color: Bgm.on ? kGold : kInkSoft,
            size: widget.size),
      ),
    );
  }
}

/// 右上に並ぶ トロフィー・スター・音 の3つ
/// スタミナの表示。回復までの のこり時間も出す
class StaminaCounter extends StatefulWidget {
  final double size;
  const StaminaCounter({super.key, this.size = 22});
  @override
  State<StaminaCounter> createState() => _StaminaCounterState();
}

class _StaminaCounterState extends State<StaminaCounter> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // 満タンでないときだけ 1秒ごとに 数字を見なおす
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (Player.stamina < Player.maxStamina) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String mmss(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final now = Player.stamina;
    final full = now >= Player.maxStamina;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.bolt_rounded,
          color: now > 0 ? kStar : kInkSoft, size: widget.size),
      const SizedBox(width: 3),
      Text('$now',
          style: TextStyle(
              color: now > 0 ? kInk : kHeart,
              fontWeight: FontWeight.w800,
              fontSize: widget.size * 0.68)),
      if (!full) ...[
        const SizedBox(width: 4),
        Text(mmss(Player.secondsToNextStamina),
            style: TextStyle(
                color: kInkSoft,
                fontWeight: FontWeight.w700,
                fontSize: widget.size * 0.5)),
      ],
    ]);
  }
}

/// 「⚡3」の 小さいバッジ（名前のとなりに置く）
Widget staminaBadge(int cost) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Color.alphaBlend(kStar.withValues(alpha: 0.18), Colors.white),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.bolt_rounded, color: kStar, size: 12),
        Text('$cost',
            style: const TextStyle(
                color: kInk, fontWeight: FontWeight.w800, fontSize: 11)),
      ]),
    );

/// スタミナがたりないとき：待つか ⭐で回復するかを えらぶ
/// 回復して 遊べるようになったら true
Future<bool> askRefill(BuildContext context, int cost) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final canBuy = Player.canRefillToday && Player.stars >= Player.refillCost;
      return AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('スタミナが たりない',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              'このバトルには ⚡$cost 必要。'
              'いまは ⚡${Player.stamina} しかない。',
              style: const TextStyle(color: kInkSoft)),
          const SizedBox(height: 10),
          Text(
              Player.canRefillToday
                  ? '${Player.staminaMinutes}分ごとに 1つもどる。'
                      '⭐${Player.refillCost} で いますぐ満タンにもできる'
                      '（きょう あと ${Player.maxRefillsPerDay - Player.refillsToday}回）。'
                  : '${Player.staminaMinutes}分ごとに 1つもどる。'
                      'きょうの ⭐での回復は つかいきった。',
              style: const TextStyle(fontSize: 12, color: kInkSoft)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('まつ')),
          if (Player.canRefillToday)
            TextButton(
              onPressed: canBuy
                  ? () {
                      Player.buyRefill();
                      Navigator.of(ctx).pop(true);
                    }
                  : null,
              child: Text('⭐${Player.refillCost} で 満タン'),
            ),
        ],
      );
    },
  );
  return ok ?? false;
}

/// スタミナを はらってバトルに入れるか どうか
/// たりなければ 回復をすすめて、回復できたら true
Future<bool> payStamina(BuildContext context, int cost) async {
  if (Player.spendStamina(cost)) return true;
  final refilled = await askRefill(context, cost);
  if (!refilled) return false;
  return Player.spendStamina(cost);
}

/// 1000以上は「1.2k」のように みじかくする
String shortNum(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '${n ~/ 1000}k';
}

Widget statCounters() {
  Widget counter(IconData i, String t, Color c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, color: c, size: 18),
          const SizedBox(width: 2),
          Text(t,
              style: const TextStyle(
                  color: kInk, fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      );
  return Row(mainAxisSize: MainAxisSize.min, children: [
    const StaminaCounter(size: 18),
    const SizedBox(width: 6),
    counter(Icons.emoji_events, shortNum(Player.trophies), kGold),
    const SizedBox(width: 6),
    counter(Icons.star_rounded, shortNum(Player.stars), kStar),
    const SizedBox(width: 6),
    const BgmButton(),
  ]);
}

Widget statTopBar({VoidCallback? onToggleBgm, Widget? leading}) {
  Widget counter(IconData i, String t, Color c) => Row(children: [
        Icon(i, color: c, size: 24),
        const SizedBox(width: 5),
        Text(t,
            style: const TextStyle(
                color: kInk, fontWeight: FontWeight.w800, fontSize: 16)),
      ]);
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
    child: Row(children: [
      leading ?? const Icon(Icons.menu, color: kInk, size: 26),
      const Spacer(),
      const StaminaCounter(size: 24),
      const SizedBox(width: 12),
      counter(Icons.emoji_events, shortNum(Player.trophies), kGold),
      const SizedBox(width: 12),
      counter(Icons.star_rounded, shortNum(Player.stars), kStar),
      const SizedBox(width: 12),
      // BGMのオン・オフ
      GestureDetector(
        onTap: onToggleBgm,
        child: Icon(Bgm.on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            color: Bgm.on ? kGold : kInkSoft, size: 24),
      ),
    ]),
  );
}

/// いま選ばれているタブ（下メニューの共通の状態）
final ValueNotifier<int> gTab = ValueNotifier<int>(0);

/// ずかんで注目したい敵（ホームから飛んできたとき用）
final ValueNotifier<int?> gZukanFocus = ValueNotifier<int?>(null);

/// 下メニューを固定したまま、中身だけを切り替える外枠
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: gTab,
      builder: (context, index, __) {
        const pages = [
          HomeScreen(),
          ZukanScreen(),
          StageSelectScreen(), // 中央＝バトル
          LeagueScreen(),
          PremiumScreen(),
        ];
        return Scaffold(
          backgroundColor: kBg,
          drawer: const AppDrawer(),
          body: Column(children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => SlideTransition(
                  position:
                      Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
                          .animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, if (current != null) current],
                ),
                child: KeyedSubtree(
                    key: ValueKey(index), child: pages[index]),
              ),
            ),
            // ここは動かない（固定の下メニュー）
            bottomNav(context, index),
          ]),
        );
      },
    );
  }
}

/// 左上の三本線から開くメニュー
class AppDrawer extends StatefulWidget {
  /// バトル中に開いた場合は「ホームへもどる」を出す
  final bool inBattle;
  const AppDrawer({super.key, this.inBattle = false});
  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {



  /// バトル中に画面を離れるときの確認
  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('はい',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('いいえ',
                style: TextStyle(color: kInkSoft)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// バトル中なら確認してから実行する
  /// ※ メニューを閉じると位置情報が使えなくなるので、先に Navigator を確保しておく
  Future<void> _guard(
      String title, String body, void Function(NavigatorState nav) action) async {
    final nav = Navigator.of(context);
    if (widget.inBattle) {
      final ok = await _confirm(title, body);
      if (!ok) return;
    }
    action(nav);
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap,
      {Widget? trailing, Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? kPurple, size: 24),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: color ?? kInk)),
      trailing: trailing,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(children: [
          // プロフィール（押すとマイページへ）
          InkWell(
            onTap: () {
              _guard('マイページを ひらきますか？',
                  'バトルは そのまま。とじると もどれます。', (nav) {
                nav.pop(); // メニューを閉じる
                nav.push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()));
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
              child: Row(children: [
                DressedChar(size: 62),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(Player.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: kInk)),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.emoji_events, color: kGold, size: 16),
                        const SizedBox(width: 3),
                        Text('${Player.trophies}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13)),
                        const SizedBox(width: 10),
                        const Icon(Icons.star_rounded, color: kStar, size: 16),
                        const SizedBox(width: 3),
                        Text('${Player.stars}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13)),
                      ]),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: kInkSoft),
              ]),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEDEDF2)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              children: [
                // バトル中だけ：ホームへ戻る
                if (widget.inBattle) ...[
                  _tile(Icons.home_rounded, 'ホームへ もどる', () {
                    _guard('バトルを やめますか？', 'いま たたかっている バトルは きえます。',
                        (nav) {
                      nav.pop(); // メニューを閉じる
                      nav.popUntil((r) => r.isFirst); // ホームまで戻る
                      gTab.value = 0;
                      Bgm.play(Bgm.home);
                    });
                  }, color: kGreen),
                  _tile(Icons.sports_martial_arts, 'ステージを えらぶ', () {
                    _guard('バトルを やめますか？', 'いま たたかっている バトルは きえます。',
                        (nav) {
                      nav.pop(); // メニューを閉じる
                      nav.popUntil((r) => r.isFirst);
                      gTab.value = 2;
                      Bgm.play(Bgm.home);
                    });
                  }),
                  const Divider(height: 20, color: Color(0xFFEDEDF2)),
                ],
                _tile(Icons.flag_rounded, 'ミッション', () {
                  _guard('ミッションを ひらきますか？',
                      'バトルは そのまま。とじると もどれます。', (nav) {
                    nav.pop(); // メニューを閉じる
                    nav.push(MaterialPageRoute(
                        builder: (_) => const MissionScreen()));
                  });
                }),
                _tile(Icons.military_tech_rounded, 'ちょうせん', () {
                  _guard('ちょうせんを ひらきますか？',
                      'バトルは そのまま。とじると もどれます。', (nav) {
                    nav.pop();
                    nav.push(MaterialPageRoute(
                        builder: (_) => const ChallengeScreen()));
                  });
                }),
                _tile(Icons.checkroom_rounded, 'きせかえ', () {
                  _guard('きせかえを ひらきますか？',
                      'バトルは そのまま。とじると もどれます。', (nav) {
                    nav.pop();
                    nav.push(MaterialPageRoute(
                        builder: (_) => const DressUpScreen()));
                  });
                }),
                _tile(Icons.storefront, 'ショップ', () {
                  _guard('ショップを ひらきますか？',
                      'バトルは そのまま。とじると もどれます。', (nav) {
                    nav.pop(); // メニューを閉じる
                    nav.push(
                        MaterialPageRoute(builder: (_) => const ShopScreen()));
                  });
                }),
                const Divider(height: 20, color: Color(0xFFEDEDF2)),
                _tile(Icons.info_outline_rounded, 'このアプリについて', () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22)),
                      title: const Text('rune link',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      content: const Text('印をかいて たたかう ぼうけんゲーム。\n開発中のプロトタイプです。'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('とじる')),
                      ],
                    ),
                  );
                }),
                _tile(Icons.restart_alt_rounded, 'データをリセット', () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22)),
                      title: const Text('データをリセット',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      content: const Text('ぼうけんの きろくが すべて消えます。よろしいですか？'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('やめる')),
                        TextButton(
                          onPressed: () async {
                            await Player.reset();
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              Navigator.of(context).pop();
                              gTab.value = 0;
                            }
                          },
                          child: const Text('リセット',
                              style: TextStyle(color: kHeart)),
                        ),
                      ],
                    ),
                  );
                }, color: kHeart),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// 下タブ用：下からスッと上がってくる切り替え
/// バトルに入るとき用：ゆっくり暗転して切り替わる
Route<T> fadeSlowRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 750),
    reverseTransitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic);
      return FadeTransition(
        opacity: curved,
        // ほんの少しだけ寄っていく
        child: ScaleTransition(
          scale: Tween<double>(begin: 1.06, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

Route<T> slideUpRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

// 下タブ。タップでそれぞれの画面へ移動する
Widget bottomNav(BuildContext context, int active) {
  void go(int i) {
    if (i == active) return;
    // 上に別の画面が乗っていたら閉じてから切り替える
    Navigator.of(context).popUntil((r) => r.isFirst);
    gTab.value = i;
  }

  Widget tab(IconData icon, String label, int i) {
    final c = active == i ? kPurple : kInkSoft;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => go(i),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: c, size: 26),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  return Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFEDEDF2), width: 1)),
    ),
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
    child: Row(children: [
      tab(Icons.home_rounded, 'ホーム', 0),
      tab(Icons.auto_stories_rounded, 'ずかん', 1),
      tab(Icons.sports_martial_arts, 'バトル', 2), // 中央
      tab(Icons.emoji_events_rounded, 'リーグ', 3),
      tab(Icons.workspace_premium_rounded, 'プレミアム', 4),
    ]),
  );
}

// ===== ホームの背景アニメーション（ふわふわ漂う丸）=====
class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key});
  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Bubble> _bubbles;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(seconds: 18))
      ..repeat();
    final r = Random(7);
    _bubbles = List.generate(14, (_) => _Bubble.random(r));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE8E1F9), Color(0xFFF0E9FC), Color(0xFFF3EFFB)],
        ),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _BubblePainter(_bubbles, _c.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Bubble {
  final double x, size, speed, phase, wobble;
  final Color color;
  _Bubble(this.x, this.size, this.speed, this.phase, this.wobble, this.color);

  factory _Bubble.random(Random r) {
    const colors = [
      Color(0x22AEBEFF),
      Color(0x22D6C2FF),
      Color(0x22BFF3DC),
      Color(0x22FFD9B0),
      Color(0x22FFC2D6),
    ];
    return _Bubble(
      r.nextDouble(),
      18 + r.nextDouble() * 62,
      // 速さは整数倍にする（1周したとき位置がぴったり合ってループが途切れない）
      (1 + r.nextInt(3)).toDouble(),
      r.nextDouble(),
      14 + r.nextDouble() * 34,
      colors[r.nextInt(colors.length)],
    );
  }
}

class _BubblePainter extends CustomPainter {
  final List<_Bubble> bubbles;
  final double t;
  _BubblePainter(this.bubbles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bubbles) {
      // 下から上へゆっくり流れて、ループする
      final prog = (t * b.speed + b.phase) % 1.0;
      final y = size.height + b.size - prog * (size.height + b.size * 2);
      final x = b.x * size.width + sin(prog * pi * 2 + b.phase * 6) * b.wobble;
      canvas.drawCircle(Offset(x, y), b.size, Paint()..color = b.color);
    }
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) => true;
}

// ======================= ホーム画面 =======================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Bgm.play(Bgm.home); // ホームはゆったりした曲
  }

  // 敵の顔を出し、押すと「ずかん」のその敵へ飛ぶ
  Widget _stage(int n) {
    final i = n - 1;
    final unlocked = n <= Player.cleared + 1;
    final cleared = n <= Player.cleared;
    final enemy = kEnemies[i];
    return GestureDetector(
      onTap: () {
        gZukanFocus.value = i;
        gTab.value = 1; // ずかんタブへ
      },
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: cleared
                ? kGold
                : unlocked
                    ? kPurple
                    : const Color(0xFFE0E0E8),
            shape: BoxShape.circle,
          ),
          child: ClipOval(
            child: Container(
              width: 52,
              height: 52,
              color: Colors.white,
              child: unlocked
                  ? charImage(enemy.asset, enemy.icon, 52, enemy.tint)
                  : const Icon(Icons.lock,
                      color: Color(0xFFCFCFDA), size: 26),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(unlocked ? enemy.name : '？？？',
            style: TextStyle(
                color: unlocked ? kInk : kInkSoft,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ② 自動で流れるバナー
  Widget _bannerCarousel() {
    return const _BannerCarousel();
  }

  // 白いカードの共通装飾
  BoxDecoration get _card => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 5)),
        ],
      );

  // ① 連続プレイ日数カード
  Widget _streakCard() {
    const days = ['月', '火', '水', '木', '金', '土', '日'];
    final todayIdx = 4; // 仮：金曜
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: _card,
      child: Row(children: [
        const Icon(Icons.local_fire_department,
            color: Color(0xFFFF9600), size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('れんぞく ',
                    style: TextStyle(
                        fontSize: 13,
                        color: kInkSoft,
                        fontWeight: FontWeight.w700)),
                Text('${Player.streak}日',
                    style: const TextStyle(
                        fontSize: 17,
                        color: kInk,
                        fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (i) {
                  final done = i <= todayIdx;
                  return Column(children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: done
                            ? const Color(0xFFFFE9B8)
                            : const Color(0xFFF0F0F5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                          done ? Icons.emoji_events : Icons.circle_outlined,
                          size: 15,
                          color: done ? kGold : const Color(0xFFCFCFDA)),
                    ),
                    const SizedBox(height: 2),
                    Text(days[i],
                        style: TextStyle(
                            fontSize: 10,
                            color: done ? kInk : kInkSoft,
                            fontWeight: FontWeight.w700)),
                  ]);
                }),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: kInkSoft),
      ]),
    );
  }

  // ② メインカード：キャラ＋今日の進捗リング＋スタートボタン
  Widget _mainCard() {
    final progress =
        (Player.todayWins / Player.dailyGoal).clamp(0.0, 1.0).toDouble();
    final pct = (progress * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: _card,
      child: Column(children: [
        Row(children: [
          // 自キャラを押すとマイページへ
          GestureDetector(
            onTap: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()));
              setState(() {});
            },
            child: DressedChar(size: 96),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: Stack(alignment: Alignment.center, children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: progress),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOut,
                        builder: (_, v, __) => SizedBox(
                          width: 52,
                          height: 52,
                          child: CircularProgressIndicator(
                            value: v,
                            strokeWidth: 6,
                            backgroundColor: const Color(0xFFEDEDF2),
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(kPurple),
                          ),
                        ),
                      ),
                      Text('$pct',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: kInk)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('印のとっくん',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: kInk)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text('きょうの目標： ${Player.todayWins} / ${Player.dailyGoal} たおす',
                    style: const TextStyle(fontSize: 13, color: kInkSoft)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 16),
        chunkyButton(
          label: 'バトル スタート',
          color: kGreen,
          edge: kGreenDeep,
          icon: Icons.play_arrow_rounded,
          onTap: () => gTab.value = 2, // ステージ選択へ
        ),
      ]),
    );
  }

  // ③ ステージ選択カード
  Widget _stageCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: _card,
      child: Column(children: [
        GestureDetector(
          onTap: () => gTab.value = 2, // ぼうけんタブへ
          child: Row(children: [
            const Text('ぼうけんの みち',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: kInk)),
            const Spacer(),
            Text('${Player.cleared} / $kStageCount クリア',
                style: const TextStyle(fontSize: 12, color: kInkSoft)),
            const Icon(Icons.chevron_right, color: kInkSoft, size: 20),
          ]),
        ),
        const SizedBox(height: 14),
        // 敵が増えたので横スクロールで見せる
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kStageCount,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) => _stage(i + 1),
          ),
        ),
      ]),
    );
  }

  // ④ ショップ・ミッション・ずかんの丸アイコン
  Widget _menuRow() {
    // page が null のときは「ずかんタブ」へ切り替える
    Widget item(
        IconData icon, String label, Color bg, Color fg, Widget? page) {
      return GestureDetector(
        onTap: () async {
          if (page == null) {
            gTab.value = 1; // ずかんタブ
            return;
          }
          await Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => page));
          setState(() {});
        },
        child: Column(children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(20)),
            child: Icon(icon, color: fg, size: 30),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
        ]),
      );
    }

    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      item(Icons.storefront, 'ショップ', const Color(0xFFFFF0D6),
          const Color(0xFFE9A41C), const ShopScreen()),
      item(Icons.flag_rounded, 'ミッション', const Color(0xFFD9F5EC),
          const Color(0xFF2FA98A), const MissionScreen()),
      item(Icons.military_tech_rounded, 'ちょうせん', const Color(0xFFFFE4E4),
          const Color(0xFFE05A5A), const ChallengeScreen()),
      item(Icons.checkroom_rounded, 'きせかえ', const Color(0xFFF3E8FC),
          kPurple, const DressUpScreen()),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // Scaffoldは外側（MainShell）のものを使う＝ドロワーが開ける
    return Stack(children: [
        const Positioned.fill(child: AnimatedBackground()), // 動く背景
        SafeArea(
        child: Column(children: [
          // ユーザー名の行
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              // 三本線でメニューを開く
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Scaffold.of(context).openDrawer(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  child: Icon(Icons.menu, color: kInk, size: 26),
                ),
              ),
              const SizedBox(width: 10),
              Text(Player.name,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
              const Spacer(),
              statCounters(),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              children: [
                _streakCard(),
                const SizedBox(height: 14),
                _bannerCarousel(), // 自動で流れるバナー
                const SizedBox(height: 14),
                _mainCard(),
                const SizedBox(height: 14),
                _stageCard(),
                const SizedBox(height: 14),
                _statsCard(),
                const SizedBox(height: 20),
                _menuRow(),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ]),
        ),
      ]);
  }

  // ② 統計グラフカード（今週の記録＋印の使用率）
  Widget _statsCard() {
    const days = ['月', '火', '水', '木', '金', '土', '日'];
    final maxW = Player.weekWins.fold<int>(1, (a, b) => b > a ? b : a);
    final total = Player.elemUses.values.fold<int>(0, (a, b) => a + b);
    Widget bar(String label, int v, Color c) {
      final ratio = total == 0 ? 0.0 : v / total;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(
              width: 56,
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: kInkSoft))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(children: [
                Container(height: 10, color: const Color(0xFFEDEDF2)),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: ratio),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOut,
                  builder: (_, r, __) => FractionallySizedBox(
                    widthFactor: r.clamp(0.0, 1.0),
                    child: Container(height: 10, color: c),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
              width: 26,
              child: Text('$v',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: kInk))),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: _card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('きろく',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: kInk)),
        const SizedBox(height: 14),
        // 週の棒グラフ
        SizedBox(
          height: 92,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final v = Player.weekWins[i];
              final h = maxW == 0 ? 0.0 : (v / maxW) * 56;
              final isToday = DateTime.now().weekday - 1 == i;
              return Expanded(
                  child: Column(children: [
                SizedBox(
                  height: 14,
                  child: Text(v > 0 ? '$v' : '',
                      style: const TextStyle(fontSize: 10, color: kInkSoft)),
                ),
                // 棒は残りの高さいっぱいの中で伸びる（はみ出さない）
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: h),
                      duration: Duration(milliseconds: 500 + i * 60),
                      curve: Curves.easeOut,
                      builder: (_, hh, __) => Container(
                        width: 22,
                        height: hh < 4 ? 4 : hh,
                        decoration: BoxDecoration(
                          color: isToday ? kPurple : const Color(0xFFCFC6F0),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(days[i],
                    style: TextStyle(
                        fontSize: 10,
                        color: isToday ? kInk : kInkSoft,
                        fontWeight: FontWeight.w700)),
              ]));
            }),
          ),
        ),
        const Divider(height: 26, color: Color(0xFFEDEDF2)),
        const Text('よく つかう印',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: kInk)),
        const SizedBox(height: 10),
        bar('◯ みず', Player.elemUses['water'] ?? 0, elemColor(Elem.water)),
        bar('△ ひ', Player.elemUses['fire'] ?? 0, elemColor(Elem.fire)),
        bar('Z かみなり', Player.elemUses['thunder'] ?? 0,
            elemColor(Elem.thunder)),
      ]),
    );
  }
}

// ===== ホームの自動スライドバナー =====
class BannerItem {
  final String title;
  final String sub;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback? onTap;
  const BannerItem(this.title, this.sub, this.icon, this.colors, this.onTap);
}

class _BannerCarousel extends StatefulWidget {
  const _BannerCarousel();
  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  final _ctrl = PageController();
  int _page = 0;
  Timer? _timer;

  List<BannerItem> get _items => [
        BannerItem('あたらしい ステージ！', 'ゆきはら・かざん・そらが とうじょう',
            Icons.map_rounded, [const Color(0xFF8B6FE0), const Color(0xFFB79BF5)],
            () => gTab.value = 2),
        BannerItem('ミッションに ちょうせん', 'クリアして ⭐をゲットしよう',
            Icons.flag_rounded, [const Color(0xFF2FA98A), const Color(0xFF6DD3B4)],
            () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MissionScreen()))),
        BannerItem('リーグで きそおう', 'じょうい3にんは しょうかく！',
            Icons.emoji_events_rounded,
            [const Color(0xFFE9A41C), const Color(0xFFFFD37A)],
            () => gTab.value = 3),
      ];

  @override
  void initState() {
    super.initState();
    // 4秒ごとにゆっくり次のバナーへ
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_ctrl.hasClients) return;
      final next = (_page + 1) % _items.length;
      _ctrl.animateToPage(next,
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeInOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(children: [
      SizedBox(
        height: 88,
        child: PageView.builder(
          controller: _ctrl,
          itemCount: items.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) {
            final b = items[i];
            return GestureDetector(
              onTap: b.onTap,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: b.colors,
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(14)),
                    child: Icon(b.icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(b.sub,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      // 今どのバナーかの点
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(items.length, (i) {
          final on = i == _page;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: on ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: on ? kPurple : const Color(0xFFD8D8E2),
              borderRadius: BorderRadius.circular(999),
            ),
          );
        }),
      ),
    ]);
  }
}

// ======================= サブ画面の共通枠 =======================
class SubScreen extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool showBack; // 戻るボタンを出すか（タブ画面では出さない）
  const SubScreen(
      {super.key,
      required this.title,
      required this.children,
      this.showBack = true});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        const Positioned.fill(child: AnimatedBackground()),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(showBack ? 8 : 20, 8, 16, 4),
              child: Row(children: [
                if (showBack)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: kInk),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                Expanded(
                  child: Text(title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: kInk)),
                ),
                // 見出しを けずらないため、カウンターの幅に上限をつけて
                // 入りきらないときは そのまま小さく縮める
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: statCounters()),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: children,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

BoxDecoration cardDeco() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5)),
      ],
    );

// ======================= プロフィール（マイページ）=======================
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // トロフィー数からレベルを出す
  int get level => Player.trophies ~/ 3 + 1;
  int get expInLevel => Player.trophies % 3;

  void _editName() {
    final ctrl = TextEditingController(text: Player.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('なまえを かえる',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          maxLength: 10,
          decoration: const InputDecoration(
            hintText: 'なまえ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('やめる')),
          TextButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) {
                Player.name = v;
                Player.save();
              }
              Navigator.of(context).pop();
              setState(() {});
            },
            child: const Text('けってい',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _statTile(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          // 背景が透けないよう、白と混ぜた不透明な色にする
          color: Color.alphaBlend(color.withValues(alpha: 0.16), Colors.white),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: Color.alphaBlend(
                  color.withValues(alpha: 0.35), Colors.white),
              width: 2),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 18, color: kInk)),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8A8A96),
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalDefeated =
        Player.defeatedByName.values.fold<int>(0, (a, b) => a + b);
    final totalElems = Player.elemUses.values.fold<int>(0, (a, b) => a + b);
    // いちばん使っている印
    String favLabel = 'まだ なし';
    Color favColor = kInkSoft;
    if (totalElems > 0) {
      final top = Player.elemUses.entries
          .reduce((a, b) => a.value >= b.value ? a : b);
      final e = Elem.values.firstWhere((x) => x.name == top.key);
      favLabel = elemLabel(e);
      favColor = elemColor(e);
    }

    return SubScreen(title: 'マイページ', children: [
      // プロフィールカード
      Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: cardDeco(),
        child: Column(children: [
          Stack(children: [
            DressedChar(size: 120),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                    color: kPurple,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 2)),
                child: Text('Lv.$level',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _editName,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(Player.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: kInk)),
              const SizedBox(width: 6),
              const Icon(Icons.edit, size: 16, color: kInkSoft),
            ]),
          ),
          const SizedBox(height: 12),
          // 次のレベルまで
          Row(children: [
            Text('Lv.$level',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: kInkSoft)),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(children: [
                  Container(height: 10, color: const Color(0xFFEDEDF2)),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: expInLevel / 3),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOut,
                    builder: (_, v, __) => FractionallySizedBox(
                      widthFactor: v.clamp(0.0, 1.0),
                      child: Container(height: 10, color: kPurple),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            Text('$expInLevel/3',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: kInkSoft)),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      // 数字でみる記録
      Row(children: [
        _statTile(Icons.emoji_events, 'トロフィー', '${Player.trophies}', kGold),
        const SizedBox(width: 10),
        _statTile(Icons.star_rounded, 'スター', '${Player.stars}', kStar),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _statTile(Icons.local_fire_department, 'れんぞく', '${Player.streak}日',
            const Color(0xFFFF9600)),
        const SizedBox(width: 10),
        _statTile(Icons.sports_martial_arts, 'たおした', '$totalDefeated',
            kHeart),
      ]),
      const SizedBox(height: 14),
      // 冒険の記録
      Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: cardDeco(),
        child: Column(children: [
          _row('ぼうけんの しんちょく', '${Player.cleared} / $kStageCount ステージ'),
          const Divider(height: 22, color: Color(0xFFEDEDF2)),
          _row('ずかん', '${Player.defeatedByName.keys.length} / $kStageCount たい'),
          const Divider(height: 22, color: Color(0xFFEDEDF2)),
          _row('つかった印', '$totalElems かい'),
          const Divider(height: 22, color: Color(0xFFEDEDF2)),
          Row(children: [
            const Text('とくいな印',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kInkSoft)),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                  color: favColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999)),
              child: Text(favLabel,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: favColor)),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      // ためしたバッジ
      Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('しょうごう',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: kInk)),
          const SizedBox(height: 14),
          Builder(builder: (_) {
            final list = kTitles;
            final got = list.where((t) => t.check()).length;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$got / ${list.length} こ ゲット',
                      style: const TextStyle(fontSize: 12, color: kInkSoft)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: list
                        .map((t) => _badge(t.name, t.check()))
                        .toList(),
                  ),
                ]);
          }),
        ]),
      ),
    ]);
  }

  Widget _row(String label, String value) {
    return Row(children: [
      Text(label,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: kInkSoft)),
      const Spacer(),
      Text(value,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w800, color: kInk)),
    ]);
  }

  Widget _badge(String label, bool got) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: got ? kGold.withValues(alpha: 0.15) : const Color(0xFFF2F2F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: got ? kGold : const Color(0xFFE4E4EC), width: 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(got ? Icons.workspace_premium : Icons.lock,
            size: 15, color: got ? const Color(0xFFB8860B) : kInkSoft),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: got ? const Color(0xFFB8860B) : kInkSoft)),
      ]),
    );
  }
}

// ======================= きせかえ =======================
class DressUpScreen extends StatefulWidget {
  const DressUpScreen({super.key});
  @override
  State<DressUpScreen> createState() => _DressUpScreenState();
}

class _DressUpScreenState extends State<DressUpScreen> {
  String? message;

  void _tap(Cosmetic c) {
    if (Player.ownedCosmetics.contains(c.id)) {
      Player.equipCosmetic(c.id);
      Sfx.play('hit.wav');
      setState(() => message = '${c.name}に かえた！');
      return;
    }
    if (Player.stars < c.price) {
      setState(() => message = '⭐が たりない…');
      return;
    }
    Player.buyCosmetic(c);
    Sfx.play('win.wav');
    setState(() => message = '${c.name}を てにいれた！');
  }

  @override
  Widget build(BuildContext context) {
    return SubScreen(title: 'きせかえ', children: [
      // いまの見た目
      Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: cardDeco(),
        child: Column(children: [
          DressedChar(size: 140, key: ValueKey(Player.cosmetic)),
          const SizedBox(height: 12),
          Text(cosmeticById(Player.cosmetic).name,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16, color: kInk)),
        ]),
      ),
      if (message != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
              color: kPurple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14)),
          child: Text(message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: kPurpleDeep, fontWeight: FontWeight.w800)),
        ),
      ],
      const SizedBox(height: 16),
      const Text('もっている かざり・かえる かざり',
          style: TextStyle(fontSize: 12, color: kInkSoft)),
      const SizedBox(height: 12),
      // ならんだ かざり
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
        children: kCosmetics.map((c) {
          final owned = Player.ownedCosmetics.contains(c.id);
          final on = Player.cosmetic == c.id;
          return GestureDetector(
            onTap: () => _tap(c),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: on ? kPurple : const Color(0xFFE6E6EC),
                    width: on ? 3 : 2),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DressedChar(size: 58, cosmeticId: c.id),
                const SizedBox(height: 6),
                Text(c.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: owned ? kInk : kInkSoft)),
                const SizedBox(height: 4),
                if (on)
                  const Text('つけてる',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: kPurple))
                else if (owned)
                  const Text('タップで つける',
                      style: TextStyle(fontSize: 9, color: kInkSoft))
                else
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.star_rounded,
                        size: 13,
                        color: Player.stars >= c.price ? kStar : kInkSoft),
                    const SizedBox(width: 2),
                    Text('${c.price}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color:
                                Player.stars >= c.price ? kInk : kInkSoft)),
                  ]),
              ]),
            ),
          );
        }).toList(),
      ),
    ]);
  }
}

// ======================= ショップ =======================
class ShopItem {
  final String name;
  final String desc;
  final IconData icon;
  final Color color;
  final int price;
  const ShopItem(this.name, this.desc, this.icon, this.color, this.price);
}

const kShopItems = [
  ShopItem('かいふくポーション', 'バトル中にHPが少し回復', Icons.local_drink, Color(0xFF7CC043), 60),
  ShopItem('ちからのおまもり', '印のダメージが上がる', Icons.auto_awesome, Color(0xFFF5B920), 120),
  ShopItem('まもりのマント', '敵の攻撃を軽くする', Icons.shield_rounded, Color(0xFF4FA9F5), 150),
  ShopItem('しあわせのカギ', 'つぎのステージが開く', Icons.vpn_key_rounded, Color(0xFF8B6FE0), 300),
];

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  String? message;

  void _buyUpgrade({required bool isAtk}) {
    final lv = isAtk ? Player.atkLv : Player.hpLv;
    final label = isAtk ? 'こうげき' : 'たいりょく';
    if (lv >= Player.maxUpgradeLv) {
      setState(() => message = '$labelは これいじょう あがらない！');
      return;
    }
    if (!Player.buyUpgrade(isAtk: isAtk)) {
      setState(() => message = '⭐がたりない…');
      return;
    }
    setState(() => message = '$labelが つよくなった！');
    Sfx.play('win.wav');
  }

  /// つよくなるカード（こうげき／たいりょく）
  Widget _upgradeCard({
    required bool isAtk,
    required String title,
    required String unit,
    required int now,
    required int step,
    required IconData icon,
    required Color color,
  }) {
    final lv = isAtk ? Player.atkLv : Player.hpLv;
    final maxed = lv >= Player.maxUpgradeLv;
    final cost = Player.upgradeCost(lv);
    final canBuy = !maxed && Player.stars >= cost;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Row(children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: kInk)),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                      color: kPurple.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999)),
                  child: Text('Lv.$lv / ${Player.maxUpgradeLv}',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: kPurpleDeep)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                  maxed
                      ? 'いま $now$unit（さいだい）'
                      : 'いま $now$unit → $step$unit に あがる',
                  style: const TextStyle(fontSize: 12, color: kInkSoft)),
              const SizedBox(height: 6),
              // 強化の進みぐあい
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: lv / Player.maxUpgradeLv,
                  minHeight: 6,
                  backgroundColor: color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ChunkyPill(
          onTap: () => _buyUpgrade(isAtk: isAtk),
          color: canBuy ? kGreen : const Color(0xFFD6D6E0),
          edge: canBuy ? kGreenDeep : const Color(0xFFBFBFCC),
          child: maxed
              ? const Text('MAX',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 3),
                  Text('$cost',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ]),
        ),
      ]),
    );
  }

  void _buy(ShopItem item) {
    if (Player.stars < item.price) {
      setState(() => message = '⭐がたりない…');
      return;
    }
    Player.stars -= item.price;
    // カギはその場でつぎのステージが開く
    if (item.name == 'しあわせのカギ') {
      if (Player.cleared >= kStageCount) {
        setState(() {
          Player.stars += item.price; // 買い戻し
          message = 'ぜんぶ クリアずみ！';
        });
        return;
      }
      Player.cleared += 1;
      Player.save();
      setState(() => message = 'つぎのステージが ひらいた！');
    } else {
      Player.addItem(item.name);
      setState(() => message = '${item.name}を かった！');
    }
    Sfx.play('win.wav');
  }

  @override
  Widget build(BuildContext context) {
    return SubScreen(title: 'ショップ', children: [
      if (message != null)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
              color: kPurple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14)),
          child: Text(message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: kPurpleDeep, fontWeight: FontWeight.w800)),
        ),
      const _ShopHeading('つよくなる', 'ずっと 効く'),
      _upgradeCard(
        isAtk: true,
        title: 'こうげき',
        unit: '',
        now: Player.atk,
        step: Player.atk + 4,
        icon: Icons.bolt_rounded,
        color: const Color(0xFFF5B920),
      ),
      _upgradeCard(
        isAtk: false,
        title: 'たいりょく',
        unit: '',
        now: Player.maxHp,
        step: Player.maxHp + 20,
        icon: Icons.favorite_rounded,
        color: kHeart,
      ),
      const _ShopHeading('もちもの', 'バトル中に つかう'),
      ...kShopItems.map((item) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(),
            child: Row(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16)),
                child: Icon(item.icon, color: item.color, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(item.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: kInk)),
                      if ((Player.items[item.name] ?? 0) > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(
                              color: kPurple.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999)),
                          child: Text('${Player.items[item.name]}こ',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: kPurpleDeep)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(item.desc,
                        style:
                            const TextStyle(fontSize: 12, color: kInkSoft)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ChunkyPill(
                onTap: () => _buy(item),
                // ⭐がたりないと 押せない見た目にする
                color: Player.stars >= item.price
                    ? kGreen
                    : const Color(0xFFD6D6E0),
                edge: Player.stars >= item.price
                    ? kGreenDeep
                    : const Color(0xFFBFBFCC),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 3),
                  Text('${item.price}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ]),
              ),
            ]),
          )),
    ]);
  }
}

// ======================= ちょうせん =======================
class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key});
  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  void _go(int i) async {
    final c = kChallenges[i];
    if (!await payStamina(context, staminaCost(challenge: i))) {
      if (mounted) setState(() {});
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(fadeSlowRoute(
        BattleScreen(stage: c.stage, challenge: i)));
    Bgm.play(Bgm.home);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final done = kChallenges
        .asMap()
        .keys
        .where(Player.challengeCleared.contains)
        .length;
    return SubScreen(title: 'ちょうせん', children: [
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: cardDeco(),
        child: Row(children: [
          DressedChar(size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$done / ${kChallenges.length} たっせい',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: kInk)),
                const SizedBox(height: 2),
                const Text('とくべつな ルールで たたかう',
                    style: TextStyle(fontSize: 12, color: kInkSoft)),
              ],
            ),
          ),
        ]),
      ),
      for (var i = 0; i < kChallenges.length; i++) _row(i),
    ]);
  }

  Widget _row(int i) {
    final c = kChallenges[i];
    final open = Player.challengeOpen(i);
    final cleared = Player.challengeCleared.contains(i);
    // クリア済みは 2回目からの⭐を出す（もらえる数を偽らない）
    final gain = cleared ? c.repeatReward : c.reward;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Row(children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
              color: open
                  ? c.color.withValues(alpha: 0.15)
                  : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(16)),
          child: Icon(open ? c.icon : Icons.lock,
              color: open ? c.color : const Color(0xFFCFCFDA), size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(c.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: open ? kInk : kInkSoft)),
                ),
                if (open) ...[
                  const SizedBox(width: 6),
                  staminaBadge(staminaCost(challenge: i)),
                ],
                if (cleared) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check_circle_rounded,
                      color: kGreen, size: 16),
                ],
              ]),
              const SizedBox(height: 2),
              Text(open ? c.rule : 'ステージ${c.stage}を クリアすると ひらく',
                  style: const TextStyle(fontSize: 12, color: kInkSoft)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (open)
          ChunkyPill(
            onTap: () => _go(i),
            color: kGreen,
            edge: kGreenDeep,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 3),
              Text('$gain',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
            ]),
          ),
      ]),
    );
  }
}

/// ショップの区切り見出し
class _ShopHeading extends StatelessWidget {
  final String title;
  final String note;
  const _ShopHeading(this.title, this.note);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Row(children: [
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 16, color: kInk)),
        const SizedBox(width: 8),
        Text(note, style: const TextStyle(fontSize: 11, color: kInkSoft)),
      ]),
    );
  }
}

// ======================= ミッション =======================
class MissionScreen extends StatefulWidget {
  const MissionScreen({super.key});
  @override
  State<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends State<MissionScreen> {
  @override
  void initState() {
    super.initState();
    Player.ensureDaily(); // きょうのぶんを用意
  }

  // きょうのミッション1つぶん
  Widget _dailyCard(int id) {
    final m = kDailyMissions[id];
    final cur = m.progress().clamp(0, m.goal);
    final done = cur >= m.goal;
    final claimed = Player.dailyClaimed.contains(id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: cardDeco().copyWith(
        border: done && !claimed ? Border.all(color: kGold, width: 3) : null,
      ),
      child: Row(children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
              color: claimed
                  ? const Color(0xFFF0F0F5)
                  : kGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16)),
          child: Icon(claimed ? Icons.check_rounded : m.icon,
              color: claimed ? kInkSoft : const Color(0xFFE9A41C), size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(m.title,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: claimed ? kInkSoft : kInk)),
                ),
                Text('$cur / ${m.goal}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: kInkSoft)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(children: [
                  Container(height: 8, color: const Color(0xFFEDEDF2)),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (cur / m.goal).toDouble()),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOut,
                    builder: (_, v, __) => FractionallySizedBox(
                      widthFactor: v.clamp(0.0, 1.0),
                      child: Container(
                          height: 8, color: claimed ? kInkSoft : kGold),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // ごほうび
        if (claimed)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('うけとり\nずみ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: kInkSoft)),
          )
        else
          ChunkyPill(
            color: done ? kGold : const Color(0xFFE4E4EC),
            edge: done ? const Color(0xFFD79B10) : const Color(0xFFCFCFDA),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            onTap: done
                ? () {
                    if (Player.claimDaily(id)) {
                      Sfx.play('win.wav');
                      setState(() {});
                    }
                  }
                : null,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, color: Colors.white, size: 15),
              const SizedBox(width: 2),
              Text('${m.reward}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalDefeated =
        Player.defeatedByName.values.fold<int>(0, (a, b) => a + b);
    final totalElems =
        Player.elemUses.values.fold<int>(0, (a, b) => a + b);
    final missions = [
      ['はじめての勝利', '敵を1体たおす', totalDefeated, 1, Icons.flag_rounded],
      ['たおしまくり', '敵を10体たおす', totalDefeated, 10, Icons.whatshot_rounded],
      ['きょうの目標', '今日 ${Player.dailyGoal}体たおす', Player.todayWins,
        Player.dailyGoal, Icons.today_rounded],
      ['印マスター', '印を30回つかう', totalElems, 30, Icons.gesture_rounded],
      ['れんぞく3日', '3日つづけて遊ぶ', Player.streak, 3, Icons.local_fire_department],
      ['ぼうけんクリア', 'ステージを $kStageCount つクリア', Player.cleared,
        kStageCount, Icons.emoji_events],
    ];

    Player.ensureDaily();
    final remain = Player.dailyIds
        .where((id) => !Player.dailyClaimed.contains(id))
        .length;

    return SubScreen(title: 'ミッション', children: [
      // ===== きょうのミッション =====
      Row(children: [
        const Icon(Icons.today_rounded, color: kGold, size: 20),
        const SizedBox(width: 8),
        const Text('きょうの ミッション',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: kInk)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999)),
          child: Text(remain > 0 ? 'のこり $remain こ' : 'ぜんぶ クリア！',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFB8860B))),
        ),
      ]),
      const SizedBox(height: 4),
      const Text('あしたには あたらしいミッションに かわるよ',
          style: TextStyle(fontSize: 11, color: kInkSoft)),
      const SizedBox(height: 12),
      ...Player.dailyIds.map(_dailyCard),
      const SizedBox(height: 10),
      // ===== ずっとつづく ミッション =====
      Row(children: const [
        Icon(Icons.flag_rounded, color: kPurple, size: 20),
        SizedBox(width: 8),
        Text('ぜんたいの ミッション',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: kInk)),
      ]),
      const SizedBox(height: 12),
      ...missions.map((m) {
        final title = m[0] as String;
        final desc = m[1] as String;
        final cur = m[2] as int;
        final goal = m[3] as int;
        final icon = m[4] as IconData;
        final done = cur >= goal;
        final ratio = (cur / goal).clamp(0.0, 1.0);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: cardDeco(),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                  color: done
                      ? kGreen.withValues(alpha: 0.15)
                      : const Color(0xFFF0F0F5),
                  borderRadius: BorderRadius.circular(16)),
              child: Icon(done ? Icons.check_rounded : icon,
                  color: done ? kGreen : kInkSoft, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: done ? kGreen : kInk)),
                    const Spacer(),
                    Text('$cur / $goal',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: kInkSoft)),
                  ]),
                  const SizedBox(height: 3),
                  Text(desc,
                      style: const TextStyle(fontSize: 12, color: kInkSoft)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Stack(children: [
                      Container(height: 8, color: const Color(0xFFEDEDF2)),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: ratio.toDouble()),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOut,
                        builder: (_, v, __) => FractionallySizedBox(
                          widthFactor: v,
                          child: Container(
                              height: 8, color: done ? kGreen : kPurple),
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ]),
        );
      }),
    ]);
  }
}

// ======================= ずかん =======================
class ZukanScreen extends StatelessWidget {
  const ZukanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: gZukanFocus,
      builder: (context, focus, __) => _build(context, focus),
    );
  }

  Widget _build(BuildContext context, int? focus) {
    final found = Player.defeatedByName.keys.length;
    return SubScreen(title: 'ずかん', showBack: false, children: [
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: cardDeco(),
        child: Row(children: [
          const Icon(Icons.auto_stories_rounded, color: kPurple, size: 30),
          const SizedBox(width: 12),
          Text('$found / ${kEnemies.length} たいはっけん',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16, color: kInk)),
        ]),
      ),
      ...List.generate(kEnemies.length, (idx) {
        final e = kEnemies[idx];
        final count = Player.defeatedByName[e.name] ?? 0;
        final found = count > 0;
        final isFocus = focus == idx; // ホームから飛んできた敵
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: cardDeco().copyWith(
            border: isFocus ? Border.all(color: kPurple, width: 3) : null,
          ),
          child: Row(children: [
            found
                ? roundedChar(e.asset, e.icon, 64, e.tint)
                : Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F5),
                        borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.question_mark_rounded,
                        color: Color(0xFFCFCFDA), size: 30),
                  ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(found ? e.name : '？？？',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: found ? kInk : kInkSoft)),
                  const SizedBox(height: 4),
                  if (found) ...[
                    Text('HP ${e.baseHp}  こうげき ${e.atkMin}〜${e.atkMax}',
                        style:
                            const TextStyle(fontSize: 12, color: kInkSoft)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                          color: kGold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999)),
                      child: Text('$count たいたおした',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB8860B))),
                    ),
                  ] else
                    const Text('まだ であっていない',
                        style: TextStyle(fontSize: 12, color: kInkSoft)),
                ],
              ),
            ),
          ]),
        );
      }),
    ]);
  }
}

// ===== ステージごとの背景（森・洞窟・祠）=====
class StageTheme {
  final String label;
  final List<Color> sky; // 空のグラデーション
  final Color ground; // 地面
  final Color deco; // 木や岩などの色
  final Color decoDark;
  final Color sparkle; // 舞う粒
  final bool dark; // 暗い背景なら文字を白にする
  const StageTheme(this.label, this.sky, this.ground, this.deco, this.decoDark,
      this.sparkle, this.dark);
}

const kStageThemes = [
  // 1: 森
  StageTheme('はじまりの もり', [Color(0xFFDDF3FF), Color(0xFFE9F7DC)],
      Color(0xFF9AD46F), Color(0xFF6FBF4B), Color(0xFF4A9433),
      Color(0x99FFF2A8), false),
  // 2: 洞窟
  StageTheme('ざわめく どうくつ', [Color(0xFF3B3A5C), Color(0xFF5A5480)],
      Color(0xFF2E2D47), Color(0xFF6B6590), Color(0xFF4A4670),
      Color(0xAA9FE8FF), true),
  // 3: 祠
  StageTheme('ぬしの ほこら', [Color(0xFF2B2350), Color(0xFF6B3F7A)],
      Color(0xFF241C42), Color(0xFFD9A441), Color(0xFF9B6B1F),
      Color(0xCCFFD98A), true),
  // 4: 雪原
  StageTheme('こごえる ゆきはら', [Color(0xFFDCEEFB), Color(0xFFF2F8FF)],
      Color(0xFFEAF4FC), Color(0xFFB6D9F0), Color(0xFF8FBEDC),
      Color(0xCCFFFFFF), false),
  // 5: 火山
  StageTheme('もえる かざん', [Color(0xFF4A1F22), Color(0xFF8C3A24)],
      Color(0xFF35171A), Color(0xFFE2703A), Color(0xFF9C3B18),
      Color(0xCCFFC46B), true),
  // 6: 天空
  StageTheme('そらの さいはて', [Color(0xFF1E2C63), Color(0xFF5B7BD0)],
      Color(0xFF16204A), Color(0xFFBFD4FF), Color(0xFF7E9BE0),
      Color(0xCCFFFFFF), true),
];

class StageBackground extends StatefulWidget {
  final int stage; // 1..3
  const StageBackground({super.key, required this.stage});
  @override
  State<StageBackground> createState() => _StageBackgroundState();
}

class _StageBackgroundState extends State<StageBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = kStageThemes[(widget.stage - 1).clamp(0, kStageCount - 1)];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: t.sky),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _StagePainter(widget.stage, t, _c.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _StagePainter extends CustomPainter {
  final int stage;
  final StageTheme t;
  final double time;
  _StagePainter(this.stage, this.t, this.time);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    switch (stage) {
      case 1:
        _forest(canvas, w, h);
        break;
      case 2:
        _cave(canvas, w, h);
        break;
      case 3:
        _shrine(canvas, w, h);
        break;
      case 4:
        _snow(canvas, w, h);
        break;
      case 5:
        _volcano(canvas, w, h);
        break;
      default:
        _sky(canvas, w, h);
    }
    _sparkles(canvas, w, h);
  }

  // --- 森：なだらかな丘＋三角の木 ---
  void _forest(Canvas canvas, double w, double h) {
    // 奥の丘
    final hill = Paint()..color = t.deco.withValues(alpha: 0.35);
    final p1 = Path()
      ..moveTo(0, h * 0.72)
      ..quadraticBezierTo(w * 0.3, h * 0.58, w * 0.6, h * 0.72)
      ..quadraticBezierTo(w * 0.85, h * 0.82, w, h * 0.70)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(p1, hill);
    // 地面
    final ground = Paint()..color = t.ground.withValues(alpha: 0.55);
    final p2 = Path()
      ..moveTo(0, h * 0.86)
      ..quadraticBezierTo(w * 0.5, h * 0.78, w, h * 0.88)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(p2, ground);
    // 木
    void tree(double x, double y, double s) {
      canvas.drawRect(
          Rect.fromLTWH(x - s * 0.08, y, s * 0.16, s * 0.42),
          Paint()..color = const Color(0xFF8B5E3C).withValues(alpha: 0.5));
      for (int i = 0; i < 3; i++) {
        final top = y - s * (0.75 - i * 0.22);
        final half = s * (0.30 + i * 0.11);
        final path = Path()
          ..moveTo(x, top)
          ..lineTo(x + half, top + s * 0.42)
          ..lineTo(x - half, top + s * 0.42)
          ..close();
        canvas.drawPath(
            path,
            Paint()
              ..color = (i.isEven ? t.deco : t.decoDark)
                  .withValues(alpha: 0.55));
      }
    }

    tree(w * 0.10, h * 0.80, 62);
    tree(w * 0.88, h * 0.84, 74);
    tree(w * 0.72, h * 0.74, 44);
  }

  // --- 洞窟：上から鍾乳石・下に岩 ---
  void _cave(Canvas canvas, double w, double h) {
    final rock = Paint()..color = t.deco.withValues(alpha: 0.45);
    final rockD = Paint()..color = t.decoDark.withValues(alpha: 0.6);
    // 天井の鍾乳石
    for (int i = 0; i < 7; i++) {
      final x = w * (0.06 + i * 0.145);
      final len = 34 + (i % 3) * 26;
      final wid = 16 + (i % 2) * 8;
      final p = Path()
        ..moveTo(x - wid, 0)
        ..lineTo(x + wid, 0)
        ..lineTo(x, len.toDouble())
        ..close();
      canvas.drawPath(p, i.isEven ? rock : rockD);
    }
    // 床の岩
    final floor = Path()
      ..moveTo(0, h * 0.90)
      ..quadraticBezierTo(w * 0.25, h * 0.84, w * 0.5, h * 0.90)
      ..quadraticBezierTo(w * 0.75, h * 0.96, w, h * 0.88)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(floor, Paint()..color = t.ground.withValues(alpha: 0.75));
    // 石筍
    for (int i = 0; i < 4; i++) {
      final x = w * (0.13 + i * 0.25);
      final p = Path()
        ..moveTo(x - 14, h * 0.92)
        ..lineTo(x + 14, h * 0.92)
        ..lineTo(x, h * 0.92 - (26 + (i % 2) * 18))
        ..close();
      canvas.drawPath(p, rockD);
    }
  }

  // --- 祠：鳥居のような柱＋灯り ---
  void _shrine(Canvas canvas, double w, double h) {
    final pillar = Paint()..color = t.deco.withValues(alpha: 0.40);
    final pillarD = Paint()..color = t.decoDark.withValues(alpha: 0.5);
    // 左右の柱
    for (final x in [w * 0.12, w * 0.88]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 13, h * 0.18, 26, h * 0.70),
            const Radius.circular(6)),
        pillar,
      );
    }
    // 上の梁
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.04, h * 0.15, w * 0.92, 18),
          const Radius.circular(8)),
      pillar,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.09, h * 0.25, w * 0.82, 11),
          const Radius.circular(6)),
      pillarD,
    );
    // 床
    final floor = Path()
      ..moveTo(0, h * 0.88)
      ..lineTo(w, h * 0.88)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(floor, Paint()..color = t.ground.withValues(alpha: 0.8));
    // 灯籠の光（ゆらぐ）
    for (int i = 0; i < 2; i++) {
      final x = i == 0 ? w * 0.12 : w * 0.88;
      final glow = 16 + sin(time * pi * 2 + i * 2) * 4;
      canvas.drawCircle(Offset(x, h * 0.36), glow,
          Paint()..color = const Color(0x66FFD98A));
      canvas.drawCircle(Offset(x, h * 0.36), 7,
          Paint()..color = const Color(0xFFFFE9B8));
    }
  }

  // --- 雪原：雪の丘＋氷柱 ---
  void _snow(Canvas canvas, double w, double h) {
    final far = Paint()..color = t.deco.withValues(alpha: 0.45);
    final p1 = Path()
      ..moveTo(0, h * 0.70)
      ..quadraticBezierTo(w * 0.28, h * 0.56, w * 0.55, h * 0.70)
      ..quadraticBezierTo(w * 0.8, h * 0.80, w, h * 0.66)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(p1, far);
    final ground = Path()
      ..moveTo(0, h * 0.86)
      ..quadraticBezierTo(w * 0.5, h * 0.78, w, h * 0.88)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(ground, Paint()..color = t.ground.withValues(alpha: 0.9));
    // 氷の柱
    for (int i = 0; i < 3; i++) {
      final x = w * (0.14 + i * 0.36);
      final top = h * (0.62 + (i % 2) * 0.06);
      final p = Path()
        ..moveTo(x, top)
        ..lineTo(x + 16, h * 0.88)
        ..lineTo(x - 16, h * 0.88)
        ..close();
      canvas.drawPath(
          p, Paint()..color = t.decoDark.withValues(alpha: 0.45));
    }
  }

  // --- 火山：溶岩の池＋岩 ---
  void _volcano(Canvas canvas, double w, double h) {
    // 奥の山
    final mtn = Path()
      ..moveTo(-20, h * 0.72)
      ..lineTo(w * 0.34, h * 0.30)
      ..lineTo(w * 0.68, h * 0.72)
      ..close();
    canvas.drawPath(
        mtn, Paint()..color = t.decoDark.withValues(alpha: 0.55));
    final mtn2 = Path()
      ..moveTo(w * 0.55, h * 0.74)
      ..lineTo(w * 0.85, h * 0.42)
      ..lineTo(w + 20, h * 0.74)
      ..close();
    canvas.drawPath(mtn2, Paint()..color = t.decoDark.withValues(alpha: 0.4));
    // 地面
    canvas.drawRect(Rect.fromLTWH(0, h * 0.80, w, h * 0.20),
        Paint()..color = t.ground.withValues(alpha: 0.92));
    // 溶岩の川（ゆらぐ）
    for (int i = 0; i < 3; i++) {
      final y = h * (0.85 + i * 0.045);
      final glow = 0.45 + sin(time * pi * 2 + i) * 0.18;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * (0.05 + i * 0.12), y, w * 0.62, 7),
            const Radius.circular(999)),
        Paint()..color = t.deco.withValues(alpha: glow),
      );
    }
  }

  // --- 天空：浮かぶ島と雲 ---
  void _sky(Canvas canvas, double w, double h) {
    // 雲（ゆっくり流れる）
    void cloud(double cx, double cy, double s, double alpha) {
      final p = Paint()..color = t.deco.withValues(alpha: alpha);
      canvas.drawCircle(Offset(cx, cy), s, p);
      canvas.drawCircle(Offset(cx + s * 0.8, cy + s * 0.15), s * 0.75, p);
      canvas.drawCircle(Offset(cx - s * 0.8, cy + s * 0.2), s * 0.65, p);
    }

    // 画面外→画面外へ1周ぶんで移動させる（つなぎ目が見えない）
    final drift = time * (w + 260) - 130;
    cloud(drift, h * 0.22, 26, 0.30);
    cloud(w + 130 - drift, h * 0.42, 20, 0.22);
    // 浮島
    final isle = Path()
      ..moveTo(w * 0.18, h * 0.84)
      ..lineTo(w * 0.82, h * 0.84)
      ..lineTo(w * 0.62, h * 0.99)
      ..lineTo(w * 0.38, h * 0.99)
      ..close();
    canvas.drawPath(isle, Paint()..color = t.ground.withValues(alpha: 0.9));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.16, h * 0.80, w * 0.68, 16),
          const Radius.circular(10)),
      Paint()..color = t.decoDark.withValues(alpha: 0.75),
    );
  }

  // --- 共通：ふわふわ舞う粒（葉・光の粒）---
  void _sparkles(Canvas canvas, double w, double h) {
    final r = Random(stage * 13);
    for (int i = 0; i < 12; i++) {
      final baseX = r.nextDouble();
      // 速さは整数倍（ループのつなぎ目で位置が飛ばない）
      final speed = (1 + r.nextInt(3)).toDouble();
      final sz = 2.5 + r.nextDouble() * 3.5;
      final prog = (time * speed + r.nextDouble()) % 1.0;
      // 森・雪原は上から降る／それ以外は下から昇る
      final falls = stage == 1 || stage == 4;
      final y = falls ? prog * h : h - prog * h;
      // 横ゆれは1周で整数回にする（つなぎ目で揺れが飛ばない）
      final x = baseX * w + sin(prog * pi * 4 + i) * 18;
      // 出はじめと消えぎわを薄くして、急に現れ/消えないようにする
      final fade = (prog < 0.12)
          ? prog / 0.12
          : (prog > 0.88 ? (1 - prog) / 0.12 : 1.0);
      canvas.drawCircle(
          Offset(x, y),
          sz,
          Paint()
            ..color = t.sparkle
                .withValues(alpha: t.sparkle.a * fade.clamp(0.0, 1.0)));
    }
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => true;
}

// ======================= ステージ選択 =======================
class StageSelectScreen extends StatefulWidget {
  const StageSelectScreen({super.key});
  @override
  State<StageSelectScreen> createState() => _StageSelectScreenState();
}

class _StageSelectScreenState extends State<StageSelectScreen> {
  // 3ステージで1エリア
  static const int perArea = 3;
  static const List<String> areaNames = ['はじまりの ちいき', 'さいはての ちいき'];

  // いま挑戦中のエリアを最初に開く
  late final int _startPage =
      (Player.cleared ~/ perArea).clamp(0, (kStageCount / perArea).ceil() - 1);
  late final PageController _pageCtrl =
      PageController(initialPage: _startPage);
  late int _page = _startPage;

  int get areaCount => (kStageCount / perArea).ceil();

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _go(int stage, [int diff = 0]) async {
    if (!await payStamina(context, staminaCost(diff: diff))) {
      if (mounted) setState(() {}); // ⭐や のこりの表示を見なおす
      return;
    }
    if (!mounted) return;
    await Navigator.of(context)
        .push(fadeSlowRoute(BattleScreen(stage: stage, diff: diff)));
    Bgm.play(Bgm.home);
    setState(() {});
  }

  /// ステージを押したとき
  /// はじめてのステージは そのまま／クリア済みなら むずかしさを選ぶ
  void _tapStage(int stage) {
    if (stage > Player.cleared) {
      _go(stage);
      return;
    }
    _pickDifficulty(stage);
  }

  /// むずかしさを選ぶシート
  void _pickDifficulty(int stage) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      // 画面が短くても はみ出さないように スクロールできるようにする
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          // つまみ
          Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: const Color(0xFFE0E0E8),
                borderRadius: BorderRadius.circular(999)),
          ),
          Text('ステージ$stage  むずかしさ',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 17, color: kInk)),
          const SizedBox(height: 4),
          const Text('むずかしいほど ⭐がたくさん もらえる（⚡も おおく つかう）',
              style: TextStyle(fontSize: 12, color: kInkSoft)),
          const SizedBox(height: 14),
            for (var d = 0; d < kDifficulties.length; d++)
              _diffRow(sheetCtx, stage, d),
          ]),
        ),
      ),
    );
  }

  /// むずかしさ1つぶんの行
  Widget _diffRow(BuildContext sheetCtx, int stage, int d) {
    final def = kDifficulties[d];
    final open = Player.diffUnlocked(stage, d);
    final done = Player.diffCleared(stage, d);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: open ? def.color.withValues(alpha: 0.10) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
              color: open ? def.color.withValues(alpha: 0.20) : Colors.white,
              borderRadius: BorderRadius.circular(14)),
          child: Icon(open ? def.icon : Icons.lock,
              color: open ? def.color : const Color(0xFFCFCFDA), size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(def.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: open ? kInk : kInkSoft)),
                ),
                if (open) ...[
                  const SizedBox(width: 6),
                  staminaBadge(staminaCost(diff: d)),
                ],
                if (done) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check_circle_rounded,
                      color: kGreen, size: 16),
                ],
              ]),
              const SizedBox(height: 2),
              Text(
                  open
                      ? 'てきのHP ${def.hpMul}ばい ／ こうげき ${def.atkMul}ばい'
                      : '${kDifficulties[d - 1].label}を クリアすると ひらく',
                  style: const TextStyle(fontSize: 11, color: kInkSoft)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (open)
          ChunkyPill(
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _go(stage, d);
            },
            color: kGreen,
            edge: kGreenDeep,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, color: Colors.white, size: 15),
              const SizedBox(width: 3),
              Text('${winStars(stage, d)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
            ]),
          ),
      ]),
    );
  }

  // 1ステージぶんの表示
  Widget _stageNode(int n, double offsetX) {
    final i = n - 1;
    final unlocked = n <= Player.cleared + 1;
    final cleared = n <= Player.cleared;
    final next = unlocked && !cleared;
    final enemy = kEnemies[i];
    return Align(
      alignment: Alignment(offsetX, 0),
      child: GestureDetector(
        onTap: unlocked ? () => _tapStage(n) : null,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (next)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                  color: kGreen, borderRadius: BorderRadius.circular(999)),
              child: const Text('いま ここ',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11)),
            ),
          ChunkyCircle(
            size: 76,
            color: cleared
                ? kGold
                : unlocked
                    ? kPurple
                    : const Color(0xFFE0E0E8),
            edge: cleared
                ? const Color(0xFFD79B10)
                : unlocked
                    ? kPurpleDeep
                    : const Color(0xFFCFCFDA),
            onTap: unlocked ? () => _tapStage(n) : null,
            child: Icon(
                cleared
                    ? Icons.star_rounded
                    : unlocked
                        ? Icons.play_arrow_rounded
                        : Icons.lock,
                color: Colors.white,
                size: 38),
          ),
          const SizedBox(height: 6),
          Text('ステージ$n',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: unlocked ? kInk : kInkSoft)),
          Text(unlocked ? kStageThemes[i].label : '？？？',
              style: const TextStyle(fontSize: 11, color: kInkSoft)),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (unlocked)
                roundedChar(enemy.asset, enemy.icon, 24, enemy.tint)
              else
                const Icon(Icons.question_mark_rounded,
                    size: 17, color: Color(0xFFCFCFDA)),
              const SizedBox(width: 5),
              if (cleared)
                // クリア済み：どのむずかしさまで倒したかが ひと目でわかる
                Row(
                  children: List.generate(
                      kDifficulties.length,
                      (d) => Padding(
                            padding: const EdgeInsets.only(right: 1),
                            child: Icon(kDifficulties[d].icon,
                                size: 12,
                                color: Player.diffCleared(n, d)
                                    ? kDifficulties[d].color
                                    : const Color(0xFFE0E0E8)),
                          )),
                )
              else
                // まだ：このステージの手ごわさの目安
                Row(
                  children: List.generate(
                      3,
                      (s) => Icon(Icons.local_fire_department,
                          size: 12,
                          color: s <= (i ~/ 2)
                              ? const Color(0xFFFF9600)
                              : const Color(0xFFE0E0E8))),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  // 点線の道
  Widget _dots() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
            children: List.generate(
                3,
                (d) => Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: Color(0xFFDCDCE6), shape: BoxShape.circle),
                    ))),
      );

  // エリア1ページぶん
  Widget _areaPage(int area) {
    const offsets = [0.0, 0.44, -0.38];
    final from = area * perArea + 1;
    final to = min(from + perArea - 1, kStageCount);
    final clearedInArea =
        (Player.cleared - area * perArea).clamp(0, perArea);
    final children = <Widget>[];
    for (int n = from; n <= to; n++) {
      children.add(_stageNode(n, offsets[(n - from) % offsets.length]));
      if (n < to) children.add(_dots());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(children: [
        // エリアの見出し
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(area == 0 ? Icons.park_rounded : Icons.ac_unit,
                color: kPurple, size: 18),
            const SizedBox(width: 8),
            Text(areaNames[area.clamp(0, areaNames.length - 1)],
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14, color: kInk)),
            const SizedBox(width: 10),
            Text('$clearedInArea / $perArea',
                style: const TextStyle(fontSize: 12, color: kInkSoft)),
          ]),
        ),
        ...children,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      const Positioned.fill(child: AnimatedBackground()),
      SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(children: [
              const Text('ぼうけん',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: kInk)),
              const Spacer(),
              statCounters(),
            ]),
          ),
          // ぜんたいの進み具合
          Container(
            margin: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(),
            child: Row(children: [
              DressedChar(size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${Player.cleared} / $kStageCount クリア',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: kInk)),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: Stack(children: [
                        Container(height: 9, color: const Color(0xFFEDEDF2)),
                        FractionallySizedBox(
                          widthFactor:
                              (Player.cleared / kStageCount).clamp(0.0, 1.0),
                          child: Container(height: 9, color: kGold),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          // 横スワイプでエリアを移動
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: areaCount,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _areaPage(i),
            ),
          ),
          // 今どのエリアかの点
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(areaCount, (i) {
                final on = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: on ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: on ? kPurple : const Color(0xFFD8D8E2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ======================= リーグ =======================
class LeagueScreen extends StatelessWidget {
  const LeagueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 対戦相手（仮のライバルたち）＋自分を混ぜてランキングにする
    final rivals = [
      ['ミナ', 320],
      ['ソウタ', 265],
      ['ゆうき', 210],
      ['カエデ', 155],
      ['りく', 120],
      ['ハル', 85],
      ['あおい', 40],
    ];
    final rows = [
      ...rivals.map((r) => {'name': r[0], 'stars': r[1], 'me': false}),
      {'name': Player.name, 'stars': Player.stars, 'me': true},
    ]..sort((a, b) => (b['stars'] as int).compareTo(a['stars'] as int));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        const Positioned.fill(child: AnimatedBackground()),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(children: [
                const Text('リーグ',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: kInk)),
                const Spacer(),
                statCounters(),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                children: [
                  // リーグの見出し
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: cardDeco(),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                              color: kGold.withValues(alpha: 0.15),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.emoji_events,
                              color: kGold, size: 30),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ブロンズリーグ',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: kInk)),
                              Text('のこり 3日',
                                  style: TextStyle(
                                      fontSize: 12, color: kInkSoft)),
                            ]),
                      ]),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                            color: kGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999)),
                        child: const Text('上位3人が つぎのリーグへ！',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF4E8A22))),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  // ランキング
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: cardDeco(),
                    child: Column(
                      children: List.generate(rows.length, (i) {
                        final r = rows[i];
                        final me = r['me'] as bool;
                        final rank = i + 1;
                        final promo = rank <= 3;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 11),
                          decoration: BoxDecoration(
                            color: me
                                ? kPurple.withValues(alpha: 0.08)
                                : Colors.transparent,
                            border: i == 2
                                ? const Border(
                                    bottom: BorderSide(
                                        color: Color(0xFFDFF0CC), width: 2))
                                : null,
                          ),
                          child: Row(children: [
                            SizedBox(
                              width: 30,
                              child: promo
                                  ? Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                          color: rank == 1
                                              ? kGold
                                              : rank == 2
                                                  ? const Color(0xFFBFC5CF)
                                                  : const Color(0xFFD8A06A),
                                          shape: BoxShape.circle),
                                      alignment: Alignment.center,
                                      child: Text('$rank',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13)),
                                    )
                                  : Text('$rank',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: kInkSoft)),
                            ),
                            const SizedBox(width: 10),
                            if (me)
                              DressedChar(size: 34)
                            else
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                    color: const Color(0xFFF0F0F5),
                                    borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.person,
                                    color: Color(0xFFBFBFCC), size: 20),
                              ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(r['name'] as String,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: me ? kPurpleDeep : kInk)),
                            ),
                            const Icon(Icons.star_rounded,
                                color: kStar, size: 18),
                            const SizedBox(width: 4),
                            Text('${r['stars']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: kInk)),
                          ]),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text('⭐をあつめて 順位をあげよう',
                        style: TextStyle(fontSize: 12, color: kInkSoft)),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ======================= プレミアム =======================
class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget benefit(IconData icon, String title, String desc) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: const Color(0xFFE9A41C), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: kInk)),
                  Text(desc,
                      style: const TextStyle(fontSize: 12, color: kInkSoft)),
                ],
              ),
            ),
          ]),
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        const Positioned.fill(child: AnimatedBackground()),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(children: [
                const Text('プレミアム',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: kInk)),
                const Spacer(),
                statCounters(),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                    decoration: cardDeco(),
                    child: Column(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                            color: kGold.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999)),
                        child: const Text('PREMIUM',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: Color(0xFFB8860B),
                                letterSpacing: 1.2)),
                      ),
                      const SizedBox(height: 14),
                      DressedChar(size: 110),
                      const SizedBox(height: 14),
                      const Text('もっと ぼうけんを たのしもう',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: kInk)),
                      const SizedBox(height: 6),
                      const Text('プレミアムで できることが ふえるよ',
                          style: TextStyle(fontSize: 13, color: kInkSoft)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
                    decoration: cardDeco(),
                    child: Column(children: [
                      benefit(Icons.favorite, 'ライフが むげん', 'なんど まけても すぐ再挑戦'),
                      benefit(Icons.auto_awesome, 'とくべつな印', 'かくれた印が つかえる'),
                      benefit(Icons.pets, 'レアなキャラ', 'プレミアム限定の なかま'),
                      benefit(Icons.block, 'こうこく なし', 'あそびに しゅうちゅう'),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  // プラン
                  Row(children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFFE6E6EC), width: 2),
                        ),
                        child: const Column(children: [
                          Text('1かげつ',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: kInk)),
                          SizedBox(height: 4),
                          Text('¥480',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                  color: kInk)),
                          Text('/ 月',
                              style:
                                  TextStyle(fontSize: 11, color: kInkSoft)),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: kGold, width: 3),
                        ),
                        child: Column(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                                color: kGold,
                                borderRadius: BorderRadius.circular(999)),
                            child: const Text('おとく',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10)),
                          ),
                          const SizedBox(height: 4),
                          const Text('12かげつ',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: kInk)),
                          const SizedBox(height: 2),
                          const Text('¥280',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                  color: kInk)),
                          const Text('/ 月',
                              style:
                                  TextStyle(fontSize: 11, color: kInkSoft)),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  chunkyButton(
                    label: '7日間 むりょうで ためす',
                    color: kGold,
                    edge: const Color(0xFFD79B10),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22)),
                          title: const Text('準備中',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          content: const Text('この機能はまだ作っていません。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('とじる'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text('いつでも かいやくできます',
                        style: TextStyle(fontSize: 11, color: kInkSoft)),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ======================= 印の認識（$1簡易版） =======================
class RuneRecognizer {
  static const int n = 32;
  // 印ごとに「描き方のバリエーション」を持つ（親指で崩れた形も拾えるように）
  final Map<Elem, List<List<Offset>>> templates = {};

  /// 判定のゆるさ（小さいほど ゆるい）
  static const Map<Elem, double> tolerance = {
    Elem.fire: 1.0, // △はきれいに描きやすいので そのまま
    Elem.water: 0.74, // ◯は親指だと つぶれやすいので ゆるく
    Elem.thunder: 0.74, // Zも 角が丸まりやすいので ゆるく
  };

  RuneRecognizer() {
    templates[Elem.fire] = [_prep(_triangle())];
    templates[Elem.water] = [
      _prep(_circle()),
      _prep(_openCircle()), // 閉じきらない丸
      _prep(_flatCircle()), // 横につぶれた丸
      _prep(_tallCircle()), // 縦につぶれた丸
    ];
    templates[Elem.thunder] = [
      _prep(_zigzag()),
      _prep(_softZigzag()), // 角が丸いZ
      _prep(_steepZigzag()), // ななめが強いZ
    ];
  }

  List<Offset> _triangle() =>
      const [Offset(0.5, 0), Offset(1, 1), Offset(0, 1), Offset(0.5, 0)];
  List<Offset> _zigzag() =>
      const [Offset(0, 0), Offset(1, 0), Offset(0, 1), Offset(1, 1)];
  List<Offset> _softZigzag() => const [
        Offset(0, 0.05),
        Offset(0.5, 0),
        Offset(0.95, 0.1),
        Offset(0.5, 0.5),
        Offset(0.05, 0.9),
        Offset(0.5, 1),
        Offset(1, 0.95),
      ];
  List<Offset> _steepZigzag() => const [
        Offset(0.1, 0),
        Offset(1, 0.15),
        Offset(0.15, 0.85),
        Offset(0.9, 1),
      ];

  // 丸のバリエーション
  List<Offset> _arc(double from, double to, double rx, double ry) {
    final l = <Offset>[];
    const steps = 24;
    for (int i = 0; i <= steps; i++) {
      final a = from + (to - from) * i / steps;
      l.add(Offset(0.5 + rx * cos(a), 0.5 + ry * sin(a)));
    }
    return l;
  }

  List<Offset> _circle() => _arc(0, 2 * pi, 0.5, 0.5);
  List<Offset> _openCircle() => _arc(0, 1.75 * pi, 0.5, 0.5);
  List<Offset> _flatCircle() => _arc(0, 2 * pi, 0.5, 0.34);
  List<Offset> _tallCircle() => _arc(0, 2 * pi, 0.34, 0.5);

  List<Offset> _prep(List<Offset> pts) =>
      _center(_scaleSquare(_resample(pts, n)));

  MapEntry<Elem?, double> recognize(List<Offset> raw) {
    if (raw.length < 8) return const MapEntry(null, 0);
    final cand = _prep(raw);
    final candRev = cand.reversed.toList();
    Elem? best;
    double bestDist = double.infinity;
    templates.forEach((e, variants) {
      // その印の どのバリエーションに一番近いか
      double d = double.infinity;
      for (final t in variants) {
        final v = min(_dist(cand, t), _dist(candRev, t));
        if (v < d) d = v;
      }
      d *= tolerance[e] ?? 1.0; // ゆるさを反映
      if (d < bestDist) {
        bestDist = d;
        best = e;
      }
    });
    final score = (1 - bestDist / 0.5).clamp(0.0, 1.0);
    return MapEntry(best, score);
  }

  double _dist(List<Offset> a, List<Offset> b) {
    double s = 0;
    for (int i = 0; i < a.length; i++) {
      s += (a[i] - b[i]).distance;
    }
    return s / a.length;
  }

  List<Offset> _resample(List<Offset> pts, int target) {
    final src = List<Offset>.from(pts);
    double total = 0;
    for (int i = 1; i < src.length; i++) {
      total += (src[i] - src[i - 1]).distance;
    }
    if (total == 0) return List.filled(target, src.first);
    final interval = total / (target - 1);
    final out = <Offset>[src.first];
    double acc = 0;
    int i = 1;
    var prev = src.first;
    while (i < src.length) {
      final cur = src[i];
      final d = (cur - prev).distance;
      if (acc + d >= interval && d > 0) {
        final t = (interval - acc) / d;
        final np = Offset(prev.dx + t * (cur.dx - prev.dx),
            prev.dy + t * (cur.dy - prev.dy));
        out.add(np);
        src.insert(i, np);
        prev = np;
        acc = 0;
      } else {
        acc += d;
        prev = cur;
        i++;
      }
    }
    while (out.length < target) {
      out.add(src.last);
    }
    return out.take(target).toList();
  }

  List<Offset> _scaleSquare(List<Offset> pts) {
    double minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    for (final p in pts) {
      minX = min(minX, p.dx);
      minY = min(minY, p.dy);
      maxX = max(maxX, p.dx);
      maxY = max(maxY, p.dy);
    }
    final w = (maxX - minX) == 0 ? 1 : (maxX - minX);
    final h = (maxY - minY) == 0 ? 1 : (maxY - minY);
    return pts.map((p) => Offset((p.dx - minX) / w, (p.dy - minY) / h)).toList();
  }

  List<Offset> _center(List<Offset> pts) {
    double cx = 0, cy = 0;
    for (final p in pts) {
      cx += p.dx;
      cy += p.dy;
    }
    cx /= pts.length;
    cy /= pts.length;
    return pts.map((p) => Offset(p.dx - cx, p.dy - cy)).toList();
  }
}

// ======================= バトル画面 =======================
/// 描いた印が どう判定されたかの 記録
/// 「何と読まれたか」「なぜ その威力か」を 画面に出すために使う
class HitInfo {
  /// よみとれた印（null なら よみとれなかった）
  final Elem? elem;

  /// よみとれなかったとき いちばん近かった印
  final Elem? closest;

  /// どれくらい きれいに描けたか（0〜1）
  final double score;

  final int dmg;
  final bool weak; // 弱点だった＝2ばい
  final bool guarded; // 予告と おなじ＝うけの かまえ
  final bool crit; // とくに きれいに描けた

  /// ちょうせんの しばりで はじかれたときの 理由
  final String? reject;

  const HitInfo({
    this.elem,
    this.closest,
    this.score = 0,
    this.dmg = 0,
    this.weak = false,
    this.guarded = false,
    this.crit = false,
    this.reject,
  });

  bool get ok => elem != null && reject == null;
}

enum Phase { playerTurn, resolving }

class BattleScreen extends StatefulWidget {
  final int stage; // 1..kStageCount
  final int diff; // むずかしさ（kDifficulties の番号）
  final int challenge; // ちょうせんの番号（-1 なら ふつうのバトル）
  const BattleScreen(
      {super.key, this.stage = 1, this.diff = 0, this.challenge = -1});
  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen>
    with TickerProviderStateMixin {
  final _rng = Random();
  final _recognizer = RuneRecognizer();
  late final AnimationController _shake;
  late final AnimationController _celebrate; // クリア演出（紙吹雪）
  List<Confetti> _confetti = [];

  List<Offset> stroke = [];

  // はじめての人にだけ あそびかたを出す
  bool _showTutorial = false;

  // 指の軌跡につく光の粒
  final List<Spark> _sparks = [];
  final Stopwatch _clock = Stopwatch()..start();
  double get _now => _clock.elapsedMilliseconds / 1000.0;
  Size boardSize = Size.zero;

  int enemyMaxHp = 120;
  int enemyHp = 120;
  Elem weakness = Elem.water;
  late EnemyType enemy;
  int defeated = 0; // このバトルで倒した数
  int playerMaxHp = Player.maxHp;
  int playerHp = Player.maxHp;

  /// このバトルの ちょうせん（ふつうのバトルなら null）
  Challenge? get _ch =>
      (widget.challenge >= 0 && widget.challenge < kChallenges.length)
          ? kChallenges[widget.challenge]
          : null;

  /// このバトルで つかったターン数
  int turns = 0;

  /// 勝ったとき じっさいにもらった⭐（勝利画面に出す）
  int _gained = 0;

  /// このバトル1回ぶんの スタミナ
  int get _cost =>
      staminaCost(diff: widget.diff, challenge: widget.challenge);

  // ---- 読みあい ----
  /// つぎに てきが使ってくる印（予告）
  Elem nextAtk = Elem.fire;

  /// つぎが 大きいこうげきか
  bool nextBig = false;

  /// このターン 予告と おなじ印を描いて 受けながしたか
  bool _guarded = false;

  /// 直前に描いた印が どう判定されたか（描画エリアに出す）
  /// つぎを描きはじめるまで 消えない＝じっくり見られる
  HitInfo? hit;

  void _showHit(HitInfo info) => setState(() => hit = info);

  /// 弱点が入れかわるまでの ターン数
  static const int weaknessTurns = 3;

  /// てきの つぎの手を決める
  void _rollNextAttack() {
    nextAtk = Elem.values[_rng.nextInt(Elem.values.length)];
    nextBig = _rng.nextInt(4) == 0; // ときどき 大きいのが来る
  }

  /// 何ターンかごとに 弱点が入れかわる（同じ印を描きつづけられないように）
  /// 印がしばられている ちょうせんでは 変えない（勝てなくなるため）
  bool _maybeRotateWeakness() {
    if (_ch?.onlyElem != null) return false;
    if (turns == 0 || turns % weaknessTurns != 0) return false;
    final others = Elem.values.where((e) => e != weakness).toList();
    weakness = others[_rng.nextInt(others.length)];
    return true;
  }

  /// このバトルの むずかしさ
  Difficulty get _diff =>
      kDifficulties[widget.diff.clamp(0, kDifficulties.length - 1)];

  /// 勝ったときにもらえる⭐
  int get _reward {
    final c = _ch;
    if (c != null) {
      // はじめてクリアなら まるごと、2回目からは 少しだけ
      return Player.challengeCleared.contains(widget.challenge)
          ? c.repeatReward
          : c.reward;
    }
    return winStars(
        widget.stage, widget.diff.clamp(0, kDifficulties.length - 1));
  }

  Phase phase = Phase.playerTurn;
  String banner = '';
  Color bannerColor = kGreen;
  String? result; // null / 'win' / 'lose'

  // アイテムの効果（このバトル中つづく）
  bool powerUp = false; // ちからのおまもり
  bool guardUp = false; // まもりのマント

  // 負けたときの演出
  bool _showResult = false; // 少し間をおいて結果を出す
  Timer? _resultTimer;

  // ピンチ演出（HPが少ないとき）
  late final AnimationController _pulse;
  bool get _inDanger =>
      !_loading &&
      result == null &&
      playerHp > 0 &&
      playerHp <= playerMaxHp * 0.3;

  // バトルに入る前のローディング
  bool _loading = true;
  int _dots = 1;
  Timer? _dotTimer;
  Timer? _loadTimer;
  late final AnimationController _wobble;

  static const double minScore = 0.20;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _celebrate = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200));
    // ピンチのときの脈打ち
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 750))
      ..repeat(reverse: true);
    // ローディングの文字ゆれ
    _wobble = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();
    // 「.」「..」「...」と変わる
    _dotTimer = Timer.periodic(const Duration(milliseconds: 380), (_) {
      if (mounted) setState(() => _dots = _dots % 3 + 1);
    });
    // 2秒たったらバトル開始
    _loadTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) {
        setState(() {
          _loading = false;
          _showTutorial = !Player.tutorialDone; // 初回だけ
        });
      }
    });
    _newEnemy();
    Player.markPlayedToday(); // 連続記録を伸ばす
    Player.save();
    Bgm.play(Bgm.forStage(widget.stage)); // ステージごとの曲
  }

  @override
  void dispose() {
    _shake.dispose();
    _celebrate.dispose();
    _wobble.dispose();
    _pulse.dispose();
    _dotTimer?.cancel();
    _loadTimer?.cancel();
    _resultTimer?.cancel();
    super.dispose();
  }

  // 負けたときの流れ：静けさ → 色が抜ける → 少し間をおいて結果
  void _startDefeat() {
    Bgm.stopNow(); // 音楽を止めて しずかにする
    Sfx.play('lose.wav');
    _shake.forward(from: 0); // 画面がゆれる
    setState(() {
      result = 'lose';
      _showResult = false; // 結果はまだ出さない
    });
    _celebrate.forward(from: 0); // キャラが しょんぼり沈む
    // たっぷり間をおいてから結果を見せる
    _resultTimer = Timer(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _showResult = true);
    });
  }

  // 紙吹雪を作って降らせる
  void _startCelebration() {
    _confetti = List.generate(46, (_) => Confetti.random(_rng));
    _celebrate.forward(from: 0);
  }

  void _newEnemy() {
    turns = 0;
    _guarded = false;
    hit = null;
    _rollNextAttack();
    final c = _ch;
    if (c != null) {
      // ちょうせん：毎回おなじ条件で挑めるように 敵もHPも固定する
      enemy = kEnemies[c.enemyIndex];
      enemyMaxHp = enemy.baseHp + (c.stage - 1) * 20;
      enemyHp = enemyMaxHp;
      // つかえる印がしばられているときは その印を弱点にする（勝てる条件にする）
      weakness = c.onlyElem ?? Elem.values[_rng.nextInt(Elem.values.length)];
      return;
    }
    // ステージが進むほど強い敵が出やすい
    final maxIdx = (widget.stage - 1).clamp(0, kEnemies.length - 1);
    final idx = _rng.nextInt(maxIdx + 1);
    enemy = kEnemies[idx];
    final base = enemy.baseHp + _rng.nextInt(40) + (widget.stage - 1) * 20;
    enemyMaxHp = (base * _diff.hpMul).round();
    enemyHp = enemyMaxHp;
    weakness = Elem.values[_rng.nextInt(Elem.values.length)];
  }

  // アイテムを使う
  void _useItem(ShopItem item) {
    if (_loading || _showTutorial || result != null) return;
    if (_ch?.noItems ?? false) {
      setState(() {
        banner = 'この ちょうせんでは つかえない';
        bannerColor = kInkSoft;
      });
      return;
    }
    if (item.name == 'ちからのおまもり' && powerUp) {
      setState(() {
        banner = 'もう つかっている';
        bannerColor = kInkSoft;
      });
      return;
    }
    if (item.name == 'まもりのマント' && guardUp) {
      setState(() {
        banner = 'もう つかっている';
        bannerColor = kInkSoft;
      });
      return;
    }
    if (!Player.useItem(item.name)) return;
    Sfx.play('win.wav');
    setState(() {
      switch (item.name) {
        case 'かいふくポーション':
          final before = playerHp;
          playerHp = (playerHp + 40).clamp(0, playerMaxHp);
          banner = 'かいふく +${playerHp - before}';
          bannerColor = kGreen;
          break;
        case 'ちからのおまもり':
          powerUp = true;
          banner = 'こうげき UP！';
          bannerColor = kGold;
          break;
        case 'まもりのマント':
          guardUp = true;
          banner = 'ぼうぎょ UP！';
          bannerColor = kStar;
          break;
      }
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted && result == null && phase == Phase.playerTurn) {
        setState(() => banner = '');
      }
    });
  }

  void _onStart(Offset p) {
    // つぎを描きはじめたら 前の判定は 引っこめる
    if (hit != null) setState(() => hit = null);
    if (_loading || _showTutorial || phase != Phase.playerTurn || result != null) return;
    setState(() {
      stroke = [p];
      banner = '';
    });
  }

  void _onUpdate(Offset p) {
    if (_loading || _showTutorial || phase != Phase.playerTurn || result != null) return;
    setState(() {
      stroke.add(p);
      // 指の通ったところに光の粒をこぼす
      if (stroke.length % 2 == 0) _sparks.add(Spark.at(p, _now, _rng));
      _sparks.removeWhere((s) => _now - s.born > Spark.life); // 古い粒は捨てる
    });
  }

  void _onEnd() {
    if (_loading || _showTutorial || phase != Phase.playerTurn || result != null) return;
    final res = _recognizer.recognize(stroke);
    final elem = res.key;
    final score = res.value;

    // 認識失敗：罰なし・すぐ描き直せる
    // 何が近かったかを 出す（出さないと どう直せばいいか わからない）
    if (elem == null || score < minScore) {
      setState(() => stroke = []);
      _showHit(HitInfo(closest: elem, score: score));
      return;
    }

    // ちょうせん：つかえる印がしばられていることがある
    final only = _ch?.onlyElem;
    if (only != null && elem != only) {
      setState(() => stroke = []);
      _showHit(HitInfo(
          elem: elem, score: score, reject: '${elemLabel(only)} の印だけ！'));
      return;
    }

    // 予告と おなじ印なら 受けながす（そのぶん 弱点をねらえない）
    _guarded = elem == nextAtk;

    final weaknessMul = elem == weakness ? 2 : 1;
    final accMul = 0.6 + score * 0.8;
    final itemMul = powerUp ? 1.5 : 1.0; // ちからのおまもり
    final dmg = (Player.atk * weaknessMul * accMul * itemMul).round();
    final crit = score > 0.85;
    Player.recordElem(elem, crit: crit); // 統計：どの印をよく使うか

    // 攻撃 → 即ダメージ・シェイク・音
    // 数字は 判定カードのほうに出すので バナーは 敵の反撃用にあけておく
    setState(() {
      phase = Phase.resolving;
      stroke = [];
      turns += 1;
      enemyHp = (enemyHp - dmg).clamp(0, enemyMaxHp);
    });
    _showHit(HitInfo(
      elem: elem,
      score: score,
      dmg: dmg,
      weak: weaknessMul == 2,
      guarded: _guarded,
      crit: crit,
    ));
    _shake.forward(from: 0);
    Sfx.play('hit.wav');

    // テンポよく：短い間で勝敗判定 → 敵の反撃 → すぐ再開
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      if (enemyHp <= 0) {
        Sfx.play('win.wav');
        if (_ch != null) {
          // ちょうせん：ステージの解放はせず、ちょうせんのクリアだけ記録する
          Player.recordWin(enemy.name, reward: 0);
          _gained = Player.recordChallenge(widget.challenge);
        } else {
          _gained = _reward;
          Player.recordWin(enemy.name, reward: _reward);
          // ステージ解放：クリアしたら次のステージが開く
          if (widget.stage > Player.cleared) {
            Player.cleared = widget.stage;
            Player.save();
          }
          // このむずかしさをクリアした記録（上のむずかしさが開く）
          Player.recordStageClear(
              widget.stage, widget.diff.clamp(0, kDifficulties.length - 1));
        }
        setState(() {
          result = 'win';
          _showResult = true;
        });
        _startCelebration();
        return;
      }
      // 敵の反撃（シームレスに続く）＋ここで入力を再開
      final c = _ch;
      var atk = enemy.atkMin + _rng.nextInt(enemy.atkMax - enemy.atkMin + 1);
      atk = (atk * _diff.atkMul).round(); // むずかしさ
      if (c != null) atk = (atk * c.enemyAtkMul).round(); // ちょうせん
      if (guardUp) atk = (atk * 0.5).round(); // まもりのマント
      if (nextBig) atk = (atk * 1.7).round(); // 予告どおり 大きいのが来る
      if (_guarded) atk = (atk * 0.3).round(); // 同じ印で 受けながした
      final drain = c?.hpDrain ?? 0; // じりひん：まいターン へる
      var rotated = false;
      setState(() {
        playerHp = (playerHp - atk - drain).clamp(0, playerMaxHp);
        final head = _guarded
            ? 'うけながした！  -$atk'
            : (nextBig ? 'てきの 大こうげき  -$atk' : 'てきの こうげき  -$atk');
        banner = drain > 0 ? '$head  ／ じりひん -$drain' : head;
        bannerColor = _guarded ? kGreen : kHeart;
        phase = Phase.playerTurn; // すぐ次の印を描ける
        _guarded = false;
        _rollNextAttack(); // つぎの手を 予告する
        rotated = _maybeRotateWeakness();
      });
      if (playerHp <= 0) {
        _startDefeat();
        return;
      }
      // ちょうせん：ターン制限を こえたら まけ
      if (c != null && c.turnLimit > 0 && turns >= c.turnLimit) {
        setState(() {
          banner = 'ターンぎれ…';
          bannerColor = kHeart;
        });
        _startDefeat();
        return;
      }
      Future.delayed(const Duration(milliseconds: 450), () {
        if (!mounted || phase != Phase.playerTurn || result != null) return;
        if (!rotated) {
          setState(() => banner = '');
          return;
        }
        setState(() {
          banner = 'よわ点が ${elemLabel(weakness)} に かわった！';
          bannerColor = elemColor(weakness);
        });
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted && phase == Phase.playerTurn && result == null) {
            setState(() => banner = '');
          }
        });
      });
    });
  }

  /// 「つぎのてき」「もういちど」も バトル1回ぶん スタミナを はらう
  /// はらえなければ 結果画面のまま（ホームへは もどれる）
  void _again(bool win) async {
    if (!await payStamina(context, _cost)) {
      if (mounted) setState(() {});
      return;
    }
    if (!mounted) return;
    if (win) {
      _continue();
    } else {
      _retry();
    }
  }

  void _continue() {
    _newEnemy();
    _celebrate.reset();
    setState(() {
      _confetti = [];
      result = null;
      _showResult = false;
      banner = '';
      phase = Phase.playerTurn;
    });
  }

  void _retry() {
    _newEnemy();
    _celebrate.reset();
    Bgm.play(Bgm.forStage(widget.stage)); // 曲をかけ直す
    setState(() {
      playerMaxHp = Player.maxHp; // ショップで強化していたら反映する
      playerHp = playerMaxHp;
      result = null;
      _showResult = false;
      powerUp = false;
      guardUp = false;
      banner = '';
      phase = Phase.playerTurn;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(inBattle: true), // バトル中もメニューを開ける
      body: Stack(children: [
        SafeArea(
          child: Column(children: [
            Builder(
              builder: (ctx) => statTopBar(
                  // 三本線でメニューを開く
                  leading: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Scaffold.of(ctx).openDrawer(),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Icon(Icons.menu, color: kInk, size: 26),
                    ),
                  ),
                  onToggleBgm: () async {
                    await Bgm.toggle();
                    setState(() {});
                  }),
            ),
            Expanded(child: _battleScene()),
            Expanded(child: _boardArea()),
          ]),
        ),
        if (result != null && _showResult) _resultOverlay(),
        if (_loading) _loadingOverlay(),
        if (_showTutorial)
          TutorialOverlay(onDone: () {
            Player.tutorialDone = true;
            Player.save();
            setState(() => _showTutorial = false);
          }),
      ]),
    );
  }

  Widget _battleScene() {
    final theme = kStageThemes[(widget.stage - 1).clamp(0, kStageCount - 1)];
    final fg = theme.dark ? Colors.white : kInk; // 暗い背景では文字を白に
    return ClipRect(
      child: Stack(children: [
        Positioned.fill(child: StageBackground(stage: widget.stage)),
        // ステージ名の小さな見出し
        Positioned(
          top: 6,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                color: theme.dark
                    ? Colors.white.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(theme.label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: theme.dark ? Colors.white : kInkSoft)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (_, child) {
                      final t = _shake.value;
                      final dx = sin(t * pi * 6) * 12 * (1 - t);
                      return Transform.translate(
                          offset: Offset(dx, 0), child: child);
                    },
                    child: roundedChar(
                        enemy.asset, enemy.icon, 108, enemy.tint),
                  ),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(enemy.name,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: fg)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: elemColor(weakness).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('弱点 ${elemLabel(weakness)}',
                          style: TextStyle(
                              color: elemColor(weakness),
                              fontWeight: FontWeight.w800,
                              fontSize: 12)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  _telegraphChip(),
                  if (_ch != null) ...[
                    const SizedBox(height: 6),
                    _challengeChip(_ch!),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(width: 220, child: hpBar(enemyHp, enemyMaxHp, kHeart)),
                ],
              ),
            ),
            Row(children: [
              DressedChar(size: 72),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Text('YOU',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: fg)),
                      // ピンチのときだけ 光るバッジ
                      if (_inDanger) ...[
                        const SizedBox(width: 8),
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (_, __) => Opacity(
                            opacity: 0.55 + _pulse.value * 0.45,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 2),
                              decoration: BoxDecoration(
                                  color: kHeart,
                                  borderRadius: BorderRadius.circular(999)),
                              child: const Text('ピンチ！',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11)),
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text('$playerHp',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: _inDanger ? kHeart : fg)),
                    ]),
                    const SizedBox(height: 6),
                    // ピンチのときは HPバーが赤く点滅する
                    _inDanger
                        ? AnimatedBuilder(
                            animation: _pulse,
                            builder: (_, __) => hpBar(
                                playerHp,
                                playerMaxHp,
                                Color.lerp(kHeart, const Color(0xFFFFA8A8),
                                    _pulse.value)!),
                          )
                        : hpBar(playerHp, playerMaxHp, kGreen),
                  ],
                ),
              ),
            ]),
          ]),
        ),
        // ピンチのときは画面のふちが赤く脈打つ
        if (_inDanger)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 0.95,
                      colors: [
                        Colors.transparent,
                        kHeart.withValues(
                            alpha: 0.10 + _pulse.value * 0.28),
                      ],
                      stops: const [0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (banner.isNotEmpty)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: TweenAnimationBuilder<double>(
                key: ValueKey(banner),
                tween: Tween(begin: 0.6, end: 1.0),
                duration: const Duration(milliseconds: 280),
                curve: Curves.elasticOut,
                builder: (_, s, child) =>
                    Transform.scale(scale: s, child: child),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: bannerColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(banner,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  // ===== バトル前のローディング画面 =====
  // 紫＋白フチの文字（アプリのフォントのまま）
  Widget _runeChar(String ch) {
    const size = 26.0;
    return Stack(children: [
      // 白いフチ
      Text(ch,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.white,
          )),
      // 紫の本体
      Text(ch,
          style: const TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            color: kPurple,
          )),
    ]);
  }

  Widget _loadingOverlay() {
    const label = 'Now loading';
    return Positioned.fill(
      child: Stack(children: [
        Positioned.fill(child: StageBackground(stage: widget.stage)),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.35)),
        ),
        Center(
          // せまい画面でも はみ出さないように縮めて収める
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FittedBox(
          fit: BoxFit.scaleDown,
          // 画面が切り替わってから文字がふわっと出る
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            builder: (_, v, child) =>
                Opacity(opacity: v.clamp(0.0, 1.0), child: child),
            child: AnimatedBuilder(
            animation: _wobble,
            builder: (_, __) {
              // 波が1文字ずつ通りすぎるように跳ねる
              final n = label.length;
              final cycle = _wobble.value * n;
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ...List.generate(n, (i) {
                    final d = (cycle - i) % n; // この文字の順番からの経過
                    final bump = d < 1.0 ? sin(d * pi) : 0.0; // 1文字だけ跳ねる
                    return Transform.translate(
                      offset: Offset(0, -bump * 5),
                      child: _runeChar(label[i]),
                    );
                  }),
                  // 「.」が増えていく
                  // 3つぶん常に置いて、まだの分は透明にする（幅が動かない）
                  ...List.generate(
                    3,
                    (i) => Opacity(
                      opacity: i < _dots ? 1.0 : 0.0,
                      child: _runeChar('.'),
                    ),
                  ),
                ],
              );
            },
          ),
          ),
          ),
          ),
        ),
      ]),
    );
  }

  /// てきの つぎの手を 予告する
  /// おなじ印を描けば 受けながせる＝毎ターン「攻める／守る」を えらべる
  Widget _telegraphChip() {
    final c = elemColor(nextAtk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        // 背景が透けて 読みにくくならないよう 白と混ぜて不透明にする
        color: Color.alphaBlend(
            c.withValues(alpha: nextBig ? 0.26 : 0.16), Colors.white),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c, width: nextBig ? 3 : 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(nextBig ? Icons.warning_rounded : Icons.schedule_rounded,
            color: c, size: 15),
        const SizedBox(width: 6),
        Text(
            nextBig
                ? 'つぎ ${elemLabel(nextAtk)}の 大こうげき'
                : 'つぎ ${elemLabel(nextAtk)}の こうげき',
            style: const TextStyle(
                color: kInk, fontWeight: FontWeight.w800, fontSize: 12)),
      ]),
    );
  }

  /// ちょうせん中に 条件と のこりターンを出す
  Widget _challengeChip(Challenge c) {
    final limited = c.turnLimit > 0;
    final left = c.turnLimit - turns;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        // 背景が透けて読みにくくならないよう 白と混ぜて不透明にする
        color: Color.alphaBlend(c.color.withValues(alpha: 0.18), Colors.white),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.color, width: 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(c.icon, color: c.color, size: 15),
        const SizedBox(width: 6),
        Text(c.rule,
            style: const TextStyle(
                color: kInk, fontWeight: FontWeight.w800, fontSize: 12)),
        if (limited) ...[
          const SizedBox(width: 8),
          Text('のこり $left',
              style: TextStyle(
                  color: left <= 1 ? kHeart : kInkSoft,
                  fontWeight: FontWeight.w800,
                  fontSize: 12)),
        ],
      ]),
    );
  }

  // 右側に並ぶアイテムボタン（持っているものだけ出る）
  Widget _itemBar() {
    if (_ch?.noItems ?? false) return const SizedBox.shrink();
    final usable = kShopItems
        .where((it) =>
            it.name != 'しあわせのカギ' && (Player.items[it.name] ?? 0) > 0)
        .toList();
    if (usable.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: usable.map((it) {
          final count = Player.items[it.name] ?? 0;
          final active = (it.name == 'ちからのおまもり' && powerUp) ||
              (it.name == 'まもりのマント' && guardUp);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GestureDetector(
              onTap: () => _useItem(it),
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: active
                        ? it.color.withValues(alpha: 0.14)
                        : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: active ? it.color : const Color(0xFFE6E6EC),
                        width: active ? 3 : 2),
                  ),
                  child: Icon(it.icon, color: it.color, size: 22),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: it.color,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 2)),
                    child: Text('$count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10)),
                  ),
                ),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _boardArea() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE6E6EC), width: 1)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _legend('△', 'ひ', elemColor(Elem.fire)),
            _legend('◯', 'みず', elemColor(Elem.water)),
            _legend('Z', 'かみなり', elemColor(Elem.thunder)),
          ]),
        ),
        _itemBar(), // 印の下にアイテム
        Expanded(
          child: GestureDetector(
            onPanStart: (d) => _onStart(d.localPosition),
            onPanUpdate: (d) => _onUpdate(d.localPosition),
            onPanEnd: (_) => _onEnd(),
            // 光の粒を動かすため 毎フレーム描き直す
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) => CustomPaint(
                painter: StrokePainter(stroke, sparks: _sparks, now: _now),
                child: child,
              ),
              child: Center(
                child: stroke.isNotEmpty
                    ? const SizedBox.expand()
                    : hit != null
                        ? _hitCard(hit!)
                        : banner.isEmpty
                            ? const Text('ここに印を描く',
                                style: TextStyle(
                                    color: Color(0xFFCFCFD8),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700))
                            : const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// 「いま描いた印が どう判定されたか」を出すカード
  /// 何と読まれたか・きれいさ・なぜ その威力か を いっぺんに見せる
  Widget _hitCard(HitInfo h) {
    final shown = h.elem ?? h.closest;
    final c = shown == null ? kInkSoft : elemColor(shown);
    final pct = (h.score * 100).round();

    Widget badge(String text, Color bg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            // 背景が透けて 読みにくくならないよう 白と混ぜて不透明にする
            color: Color.alphaBlend(bg.withValues(alpha: 0.20), Colors.white),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: bg, width: 1.5),
          ),
          child: Text(text,
              style: const TextStyle(
                  color: kInk, fontWeight: FontWeight.w800, fontSize: 12)),
        );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (_, t, child) => Transform.scale(
          scale: 0.85 + 0.15 * t.clamp(0.0, 1.0), child: child),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c, width: 2.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            // 何の印と 読まれたか（凡例と おなじ記号）
            Text(shown == null ? '？' : elemShape(shown),
                style: TextStyle(
                    color: c, fontWeight: FontWeight.w800, fontSize: 30)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    h.ok
                        ? elemLabel(shown!)
                        : (h.reject != null
                            ? '${elemLabel(shown!)} と よまれた'
                            : 'よみとれなかった'),
                    style: const TextStyle(
                        color: kInk,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                Text(
                    h.ok
                        ? 'きれいさ $pct%'
                        : (h.reject ?? 'もうすこし ゆっくり 大きく'),
                    style: const TextStyle(
                        color: kInkSoft,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ],
            ),
            if (h.ok) ...[
              const SizedBox(width: 14),
              Text('${h.dmg}',
                  style: TextStyle(
                      color: c, fontWeight: FontWeight.w800, fontSize: 30)),
            ],
          ]),
          if (h.ok && (h.weak || h.guarded || h.crit)) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (h.weak) badge('弱点 ×2', kHeart),
              if (h.guarded) badge('うけの かまえ', kGreen),
              if (h.crit) badge('キレイ！', kGold),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _legend(String shape, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [
        Text(shape,
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: kInkSoft, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // 勝敗オーバーレイ
  Widget _resultOverlay() {
    final win = result == 'win';
    return Positioned.fill(
      child: Stack(children: [
        // 背景の暗幕（ふわっと出る）
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 260),
          builder: (_, v, __) => Container(
              color: Colors.black.withValues(alpha: 0.45 * v)),
        ),
        // クリア時：後光がぶわっと広がる
        if (win)
          Center(
            child: AnimatedBuilder(
              animation: _celebrate,
              builder: (_, __) {
                final t = Curves.easeOut.transform(
                    (_celebrate.value * 1.6).clamp(0.0, 1.0));
                return Container(
                  width: 200 + 260 * t,
                  height: 200 + 260 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kGold.withValues(alpha: 0.30 * (1 - t)),
                  ),
                );
              },
            ),
          ),
        Center(child: _resultCard(win)),
        // クリア時：紙吹雪が降る（カードの手前）
        if (win)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _celebrate,
                builder: (_, __) => CustomPaint(
                    painter: ConfettiPainter(_confetti, _celebrate.value)),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _resultCard(bool win) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      // 勝ちは はずむ／負けは ゆっくり降りてくる
      duration: Duration(milliseconds: win ? 420 : 900),
      curve: win ? Curves.elasticOut : Curves.easeOutCubic,
      builder: (_, t, child) {
        if (win) {
          return Transform.scale(scale: 0.7 + 0.3 * t, child: child);
        }
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
              offset: Offset(0, (1 - t) * -26), child: child),
        );
      },
      child: Container(
        width: 280,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 26,
                offset: const Offset(0, 10)),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // タイトル（クリアは少し遅れてポンッ）
          _pop(
            tag: 'title',
            delay: win ? 180 : 0,
            child: Text(win ? 'クリア！' : 'まけちゃった…',
                style: TextStyle(
                    fontSize: win ? 32 : 26,
                    fontWeight: FontWeight.w800,
                    color: win ? kGreen : kInk)),
          ),
          const SizedBox(height: 16),
          // キャラは勝ったときだけ出す（跳ねる）
          if (win)
            AnimatedBuilder(
              animation: _celebrate,
              builder: (_, child) {
                final t = _celebrate.value;
                final hop = (sin(t * pi * 5).abs()) * 12 * (1 - t * 0.6);
                return Transform.translate(
                    offset: Offset(0, -hop), child: child);
              },
              child: DressedChar(size: 96),
            ),
          SizedBox(height: win ? 14 : 4),
          if (!win)
            _pop(
              tag: 'broken',
              delay: 220,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.heart_broken_rounded,
                    color: kHeart.withValues(alpha: 0.75), size: 26),
                const SizedBox(width: 8),
                const Text('HP 0',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: kInkSoft)),
              ]),
            ),
          if (!win) const SizedBox(height: 10),
          if (win)
            _pop(
              tag: 'reward',
              delay: 420,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: kStar.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded, color: kStar, size: 26),
                  const SizedBox(width: 8),
                  Text('+$_gained',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: kInk)),
                  const SizedBox(width: 12),
                  const Icon(Icons.emoji_events, color: kGold, size: 24),
                  const SizedBox(width: 6),
                  const Text('+1',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: kInk)),
                ]),
              ),
            )
          else ...[
            // どれくらい おしかったか
            Text(
              enemyHp <= enemyMaxHp * 0.25
                  ? 'あと ちょっとだったのに…'
                  : 'つよかった…',
              style: const TextStyle(fontSize: 14, color: kInkSoft),
            ),
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('てきの のこりHP',
                      style: TextStyle(fontSize: 12, color: kInkSoft)),
                  const SizedBox(width: 10),
                  Text('$enemyHp',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: kInk)),
                ]),
                const SizedBox(height: 6),
                SizedBox(
                  width: 170,
                  child: hpBar(enemyHp, enemyMaxHp, kHeart),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          _pop(
            tag: 'main-btn',
            delay: win ? 620 : 0,
            child: chunkyButton(
              label: win ? 'つぎのてき  ⚡$_cost' : 'もういちど  ⚡$_cost',
              color: win ? kGreen : kPurple,
              edge: win ? kGreenDeep : kPurpleDeep,
              onTap: () => _again(win),
            ),
          ),
          const SizedBox(height: 10),
          _pop(
            tag: 'home-btn',
            delay: win ? 720 : 0,
            child: chunkyButton(
              label: 'ホームへ',
              color: const Color(0xFFEDEDF2),
              edge: const Color(0xFFD3D3DE),
              textColor: kInk,
              icon: Icons.home_rounded,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ]),
      ),
    );
  }

  // 少し遅れてポンッと出る（tagは画面内で重複しない名前）
  Widget _pop(
      {required int delay, required String tag, required Widget child}) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('$tag-$delay-$result'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 380 + delay),
      curve: Interval(
          delay / (380 + delay) * 0.999, 1.0, curve: Curves.elasticOut),
      builder: (_, v, c) =>
          Transform.scale(scale: v.clamp(0.001, 2.0), child: c),
      child: child,
    );
  }
}

// ===== 紙吹雪 =====
class Confetti {
  final double x; // 0..1 の横位置
  final double delay; // 降り始めの遅れ 0..0.4
  final double speed;
  final double size;
  final double spin;
  final Color color;
  final bool isStar;

  Confetti(this.x, this.delay, this.speed, this.size, this.spin, this.color,
      this.isStar);

  factory Confetti.random(Random r) {
    const colors = [kGreen, kStar, kGold, kHeart, kPurple, Color(0xFF4FA9F5)];
    return Confetti(
      r.nextDouble(),
      r.nextDouble() * 0.35,
      0.7 + r.nextDouble() * 0.7,
      7 + r.nextDouble() * 9,
      (r.nextDouble() - 0.5) * 10,
      colors[r.nextInt(colors.length)],
      r.nextInt(4) == 0,
    );
  }
}

class ConfettiPainter extends CustomPainter {
  final List<Confetti> items;
  final double t; // 0..1
  ConfettiPainter(this.items, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in items) {
      // 残り時間で必ず落ち切るよう正規化（速度差は落ち方のカーブで表現）
      final p = ((t - c.delay) / (1.0 - c.delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final local = pow(p, 1 / c.speed).toDouble();
      final dx = c.x * size.width + sin(local * pi * 3 + c.x * 6) * 26;
      final dy = -30 + local * (size.height + 60);
      final fade = local > 0.93 ? (1 - (local - 0.93) / 0.07) : 1.0;
      final paint = Paint()..color = c.color.withValues(alpha: fade);

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(local * c.spin);
      if (c.isStar) {
        _star(canvas, c.size * 0.9, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: c.size, height: c.size * 0.6),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  void _star(Canvas canvas, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final rad = (i.isEven ? r : r * 0.45);
      final a = -pi / 2 + i * pi / 5;
      final p = Offset(cos(a) * rad, sin(a) * rad);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ConfettiPainter old) => true;
}

// ===== はじめての人へのあそびかた =====
class TutorialOverlay extends StatefulWidget {
  final VoidCallback onDone;
  const TutorialOverlay({super.key, required this.onDone});
  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  int _step = 0;

  static const _steps = [
    ['ゆびで 印を なぞろう', '画面の下半分に 形を描くと こうげきできるよ'],
    ['3つの印が あるよ', '△ ひ ／ ◯ みず ／ Z かみなり'],
    ['よわ点を ねらおう', 'てきの よわ点の印は ダメージが2ばい！'],
    ['よわ点は かわる', '3ターンごとに 入れかわるよ。見てから えらぼう'],
    ['うけながせる', 'てきの「つぎ」と おなじ印を描くと ダメージを へらせる'],
    ['アイテムも つかえる', '印の下のボタンで かいふく や ちからアップ'],
  ];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.62),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // お手本の印が なぞられていくアニメ
              Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => CustomPaint(
                    painter: DemoRunePainter(_step, _c.value),
                    size: const Size(190, 190),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Text(step[0],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22)),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(step[1],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 14)),
              ),
              const SizedBox(height: 26),
              // いま何ページ目か
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) {
                  final on = i == _step;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: on ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: on ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: 220,
                child: chunkyButton(
                  label: _step < _steps.length - 1 ? 'つぎへ' : 'はじめる！',
                  color: kGreen,
                  edge: kGreenDeep,
                  onTap: _next,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: widget.onDone,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('スキップ',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// お手本の印を なぞって見せる絵
class DemoRunePainter extends CustomPainter {
  final int step;
  final double t; // 0..1
  DemoRunePainter(this.step, this.t);

  List<Offset> _shape(Size s) {
    final w = s.width, h = s.height;
    Offset p(double x, double y) => Offset(w * x, h * y);
    switch (step) {
      case 1: // ◯
        return List.generate(37, (i) {
          final a = i / 36 * 2 * pi - pi / 2;
          return Offset(w * 0.5 + w * 0.28 * cos(a), h * 0.5 + h * 0.28 * sin(a));
        });
      case 2: // Z
        return [p(0.24, 0.28), p(0.76, 0.28), p(0.24, 0.72), p(0.76, 0.72)];
      case 3: // △
      case 0:
      default:
        return [p(0.5, 0.22), p(0.78, 0.74), p(0.22, 0.74), p(0.5, 0.22)];
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = _shape(size);
    // 全体の うすい下書き
    final full = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      full.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(
      full,
      Paint()
        ..color = kInkSoft.withValues(alpha: 0.30)
        ..strokeWidth = 10
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // なぞっている途中まで
    final metrics = full.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final m = metrics.first;
    final drawn = m.extractPath(0, m.length * t.clamp(0.0, 1.0));
    canvas.drawPath(
      drawn,
      Paint()
        ..color = kPurple
        ..strokeWidth = 10
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 指の先
    final tan = m.getTangentForOffset(m.length * t.clamp(0.0, 1.0));
    if (tan != null) {
      canvas.drawCircle(tan.position, 13,
          Paint()..color = kPurple.withValues(alpha: 0.25));
      canvas.drawCircle(tan.position, 7, Paint()..color = kPurple);
    }
  }

  @override
  bool shouldRepaint(covariant DemoRunePainter old) =>
      old.t != t || old.step != step;
}

// 指の軌跡にこぼれる光の粒
class Spark {
  static const double life = 0.75; // 消えるまでの秒数
  final Offset from;
  final Offset vel;
  final double born;
  final double size;
  final Color color;
  Spark(this.from, this.vel, this.born, this.size, this.color);

  factory Spark.at(Offset p, double now, Random r) {
    const colors = [kPurple, Color(0xFF9B82E8), Color(0xFFCBBBF7), kGold];
    final a = r.nextDouble() * 2 * pi;
    final sp = 10 + r.nextDouble() * 34;
    return Spark(
      p,
      Offset(cos(a) * sp, sin(a) * sp - 12), // 少し上に舞う
      now,
      2.0 + r.nextDouble() * 3.4,
      colors[r.nextInt(colors.length)],
    );
  }

  /// いまの位置と濃さ
  Offset posAt(double now) {
    final t = now - born;
    return Offset(
      from.dx + vel.dx * t,
      from.dy + vel.dy * t + 40 * t * t, // だんだん落ちる
    );
  }

  double fadeAt(double now) => (1 - (now - born) / life).clamp(0.0, 1.0);
}

class StrokePainter extends CustomPainter {
  final List<Offset> stroke;
  final List<Spark> sparks;
  final double now;
  StrokePainter(this.stroke, {this.sparks = const [], this.now = 0});

  @override
  void paint(Canvas canvas, Size size) {
    if (stroke.length >= 2) {
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      // 外側のふんわり光
      canvas.drawPath(
        path,
        Paint()
          ..color = kPurple.withValues(alpha: 0.22)
          ..strokeWidth = 20
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // 本体の線
      canvas.drawPath(
        path,
        Paint()
          ..color = kStroke
          ..strokeWidth = 8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // 光の粒
    for (final s in sparks) {
      final f = s.fadeAt(now);
      if (f <= 0) continue;
      final p = s.posAt(now);
      canvas.drawCircle(
          p, s.size * f, Paint()..color = s.color.withValues(alpha: f));
    }
  }

  @override
  bool shouldRepaint(covariant StrokePainter old) => true;
}
