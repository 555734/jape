# NSMB DS のプレイヤー物理（調査記録）

New Super Mario Bros.（Nintendo DS）の操作感を Jape で再現するための、数値と状態遷移の調査記録。
**このファイルが物理値の出典表であり、`data/tuning.gd` の値はここから来る。**

数値を動かすときは、まず `tests/test_nsmb_feel.gd`（受け入れ条件）に観測できる形で1行足すこと。
「マリオっぽいから」で数値を決めない。

---

## 1. 著作権の扱い

Nintendo のコード・デコンパイルされた関数は**コピーしていない**。使っているのは

- 数値
- アルゴリズム上の事実（速度段・重力帯の切り替わり方）
- 状態遷移
- 入力条件

だけで、Jape 側は GDScript として独立に書き直している。

## 2. 参照した公開資料

| 資料 | 内容 | このファイルでの呼び名 |
|---|---|---|
| [NSMB-Decomp/nsmb](https://github.com/NSMB-Decomp/nsmb) | NSMB DS の matching decompilation | decomp |
| [MammaMiaTeam/NSMB-Code-Reference](https://github.com/MammaMiaTeam/NSMB-Code-Reference) | 逆解析で判明したクラス・構造体・関数の名前付き定義 | code-ref |
| [ipodtouch0218/NSMB-MarioVsLuigi](https://github.com/ipodtouch0218/NSMB-MarioVsLuigi) | NSMB DS の「Mario vs Luigi」を再現した Unity 実装 | MvsL |

### decomp に物理値は無い

`src/Bases/stubs/Player.hpp` の `Player` は中身が空のスタブで、プレイヤーの移動処理は**まだ
デコンパイルされていない**。したがって「デコンパイルから直接確認できる値」は下の3つだけだった。

```
src/AAA.hpp        #define _FixedFlt(flt) ((i32)(flt * 4096.0))   → fx32・12bit小数
src/Bases/Player/PlayerBase.cpp
                   case POWERUP_MINI: return _FixedMul(gravity, 0xD00);  → MINI は重力 0.8125倍
                   1フレームの移動量クランプ ±0x4000 (= ±4.0 単位)
```

### code-ref には構造がある（値は ROM 内データなので無い）

```
include/nsmb/game/stage/player/playerbase.hpp
  struct Constants { scale, walkMaxVelocity, dashThreshold, dashMaxVelocity,
                     dashMaxVelocityStarman, swimMaxVelocity, walkMaxVelocityWater,
                     jumpVelocity, quicksandJumpVelocity, width, height };   ← パワーアップ毎
  bool getBufferedJumpPressed();                                             ← 先行入力が原作にある

include/nsmb/game/stage/player/player.hpp
  struct JumpCurveAccelTable {
    fx32 jumpGravity;
    fx32 jumpAscend;   // 上昇中 (velocity.y > 2.5)
    fx32 jumpPeak;     // 頂点の直前 (1.5 < velocity.y <= 2.5)
    fx32 fallPeak;     // 頂点の直後 (-2 < velocity.y < 0)
    ...
  };
  struct JumpCurveLimitTable { standard, unused4, wallSlide, groundPound, megaJump };
```

→ **重力が上昇/頂点前/頂点後で切り替わること、落下速度上限が状況別にあること、先行入力があること**が
原作の事実として確定した。値そのものは ROM のデータ領域にあるため、この資料からは読めない。

### 数値は MvsL から取る

`Assets/QuantumUser/Simulation/NSMB/Entity/Player/MarioPlayerPhysicsInfo.cs`。
採用の根拠は、**構造が code-ref と一致している**こと:

| code-ref の事実 | MvsL の対応 |
|---|---|
| 速度段（`walkMaxVelocity` / `dashMaxVelocity` / `dashMaxVelocityStarman`） | `WalkMaxVelocity[5]` と `WalkSpeedStage=1 / RunSpeedStage=3 / StarSpeedStage=4` |
| 速度帯で切り替わる重力（上昇 / 頂点前 / 頂点後） | `GravityVelocity[4]` と `GravityAcceleration[5]` |
| `JumpCurveLimitTable { standard, wallSlide, groundPound, megaJump }` | `TerminalVelocity` / `TerminalVelocityWallslide` / `TerminalVelocityGroundpound` / `TerminalVelocityMegaMultiplier` |
| `getBufferedJumpPressed()` | `JumpBufferFrames = 12` |
| MINI の重力・落下速度が別 | `GravityMiniAcceleration` / `TerminalVelocityMiniMultiplier = 0.625` |

値も fx32 のきれいな分数（0.9375 = 15/16 など）で、ROM から取られたものと強く示唆される。
ただし **decomp で直接確認したわけではない**ので、確度は `exact` ではなく `reimpl` とする。

## 3. 単位の換算

MvsL は **1マス = 0.5 単位**。根拠:

1. 小マリオの当たり判定 `SmallHitboxHeight = 0.42` 単位 → 0.84マス。NSMB の小マリオはほぼ1マス弱で、
   Jape の当たり判定 0.9 とも近い。
2. ダッシュ上限（段3）`5.625` 単位/秒 → 11.25 マス/秒 → **3.0 ドット/フレーム**。
   `docs/RULES.md` に残る Jape 自身の動画実測「約3.0ドット/フレーム」および TASVideos の解析値と一致する。

したがって

```
Jape の マス/秒   = MvsL の値 × 2
Jape の マス/秒²  = MvsL の値 × 2
ドット/フレーム   = マス/秒 × 16 / 60          (1マス = 16ドット、60fps)
NSMB 内部 fx32    = 値 × 4096                  (12bit小数)
```

Jape は 1マス = 1.0、60 tick/秒 の固定シミュレーション（`Simulation.DT = 1/60`）。

## 4. 物理値の表

確度: `exact` = decomp から直接確認 / `reimpl` = MvsL 由来（構造は code-ref で裏取り）/
`measured` = 動画・実機から測定 / `unknown` = 未確定

### 4.1 横移動

速度段は**入力ではなく「今の速度」で決まる**。`|vx| - 0.01` を最高速表と先頭から比べ、
最初に `<=` になった段を使う（MvsL `MarioPlayer.GetSpeedStage`）。加速はその段の値。
上限段はボタンで決まる: 歩き = 段1 / ダッシュ押下 = 段3 / スター = 段4。

| 項目 | NSMB DS内部値 | Jape換算値 | 出典 | 確度 |
|---|---|---|---|---|
| 最高速 段0 | 0.9375 | 1.875 マス/秒 | MvsL `WalkMaxVelocity[0]` | reimpl |
| 最高速 段1（歩き上限） | 2.8125 | **5.625 マス/秒** (1.5 ドット/F) | MvsL `WalkMaxVelocity[1]` | reimpl |
| 最高速 段2 | 4.21875 | 8.4375 マス/秒 | MvsL `WalkMaxVelocity[2]` | reimpl |
| 最高速 段3（ダッシュ上限） | 5.625 | **11.25 マス/秒** (3.0 ドット/F) | MvsL `WalkMaxVelocity[3]` | reimpl |
| 最高速 段4（スター） | 8.4375 | 16.875 マス/秒 | MvsL `WalkMaxVelocity[4]` | reimpl |
| 加速 段0〜4 | 7.910 / 3.955 / 3.516 / 2.637 / 84.375 | 15.8203 / 7.9102 / 7.0313 / 5.2734 / 168.75 マス/秒² | MvsL `WalkAcceleration` | reimpl |
| 入力を離したときの減速 | 3.9550781 | 7.9102 マス/秒² | MvsL `WalkButtonReleaseDeceleration` | reimpl |
| 逆入力の減速（段別） | 3.955 / 8.789 / 8.789 / 21.094 | 7.9102 / 17.5781 / 17.5781 / 42.1875 マス/秒² | MvsL `SlowTurnaroundAcceleration` | reimpl |
| 逆入力の減速（高速時） | 28.125 | 56.25 マス/秒² | MvsL `FastTurnaroundAcceleration` | reimpl |
| スキッド開始速度 | 4.6875 | 9.375 マス/秒 | MvsL `SkiddingMinimumVelocity` | reimpl |
| スキッド減速 | 10.546875 | 21.0938 マス/秒² | MvsL `SkiddingDeceleration` | reimpl |
| 空中加速 | （地上と同じ表） | 地上と同じ | MvsL `MarioPlayerSystem.HandleWalk` は接地判定で加速表を変えない | reimpl |

スキッドと fast-turnaround は**地上のみ**（空中では発生しない）。

### 4.2 ジャンプ

| 項目 | NSMB DS内部値 | Jape換算値 | 出典 | 確度 |
|---|---|---|---|---|
| ジャンプ初速 | 6.62109375 | **13.2422 マス/秒** | MvsL `JumpVelocity` | reimpl |
| 速度ボーナス（最大） | 0.46875 | 0.9375 マス/秒 | MvsL `JumpSpeedBonusVelocity` | reimpl |
| 3段目ボーナス | 0.5 | 1.0 マス/秒 | MvsL `JumpTripleBonusVelocity` | reimpl |
| 壁キック 横 | 4.21875 | 8.4375 マス/秒 | MvsL `WalljumpHorizontalVelocity` | reimpl |
| 壁キック 縦 | 6.4453125 | 12.8906 マス/秒 | MvsL `WalljumpVerticalVelocity` | reimpl |
| 先行入力 | 12 フレーム | 12 フレーム | MvsL `JumpBufferFrames`、code-ref `getBufferedJumpPressed()` | reimpl（存在は exact） |
| コヨーテタイム | 3 フレーム | 3 フレーム | MvsL `CoyoteTimeFrames` | reimpl |

速度ボーナスは `alpha = clamp01(|vx| - 歩き最高速 + 歩き最高速/2)` で 0〜最大を補間（MvsL `Jump()`）。

### 4.3 重力（速度帯で5段に切り替わる）

`vy` を閾値と先頭から比べ、最初に `vy >= 閾値[i]` になった段 i を使う（MvsL `GetGravityStage`）。

| 段 | 条件 (Jape単位 マス/秒) | NSMB内部の重力 | Jape換算 (マス/秒²) |
|---|---|---|---|
| 0 | vy ≥ 8.3203 | -7.03125 | **14.0625** |
| 1 | vy ≥ 4.2188 | -28.125 | 56.25 |
| 2 | vy ≥ 0 | -38.671875 | **77.3438**（頂点の直前が最も重い） |
| 3 | vy ≥ -11.7188 | -28.125 | 56.25 |
| 4 | それ未満 | -38.671875 | 77.3438 |

閾値の内部値は `GravityVelocity = { 4.16015625, 2.109375, 0, -5.859375 }`（出典 MvsL、確度 reimpl）。

**段0（勢いよく上昇中）はジャンプボタンを押している間だけ。離していれば最終段（77.3438）を使う。**
これが短押しジャンプの仕組み（MvsL `HandleGravity`）。接地中の重力は段0の値。

code-ref の `JumpCurveAccelTable` が「上昇中 / 頂点の直前 / 頂点の直後」で別の重力を持つと書いている
構造と一致する。**頂点でふわっと浮くのではなく、頂点の直前が最も重い。**

### 4.4 落下速度の上限

| 項目 | NSMB DS内部値 | Jape換算値 | 出典 | 確度 |
|---|---|---|---|---|
| 通常 | -7.5 | 15.0 マス/秒 (4.0 ドット/F) | MvsL `TerminalVelocity` | reimpl |
| 壁すべり | -4.6875 | 9.375 マス/秒 | MvsL `TerminalVelocityWallslide` | reimpl |
| ヒップドロップ | -11.25 | 22.5 マス/秒 | MvsL `TerminalVelocityGroundpound` | reimpl |
| MINI 倍率 | 0.625 | 0.625 倍 | MvsL `TerminalVelocityMiniMultiplier` | reimpl |

### 4.5 当たり判定

| 項目 | NSMB DS内部値 | Jape換算値 | 出典 | 確度 |
|---|---|---|---|---|
| 小さい状態の高さ | 0.42 | 0.84 マス | MvsL `SmallHitboxHeight` | reimpl |
| 大きい状態の高さ | 0.82 | 1.64 マス | MvsL `LargeHitboxHeight` | reimpl |
| 幅 | — | — | — | unknown |

### 4.6 実装するときに効いてくる細かい挙動

| 事実 | 出典 | 確度 |
|---|---|---|
| 2段目のジャンプに**縦の上乗せは無い**（3段目だけ `JUMP_TRIPLE_BONUS` が乗る） | MvsL `Jump()` は `JumpState.TripleJump` のときだけ `newY += JumpTripleBonusVelocity` | reimpl |
| スキッドは一度入ったら、速度が落ちても**止まるまでスキッドのまま** | MvsL `mario->IsSkidding` は速度が0を跨ぐか入力が向きと揃うまで保持される | reimpl |
| ジャンプの先行入力は、ジャンプが出た時点で消費される（コヨーテも同時に0になる） | MvsL `Jump()` が `JumpBufferFrames = 0` と `CoyoteTimeFrames = 0` を両方リセット | reimpl |
| 入力を離したときの摩擦は**地上のみ**（空中では横の速度を保つ） | MvsL `HandleWalk` の減速は接地時のみ | reimpl |
| 接地中の重力は重力表の段0の値 | MvsL `HandleGravity` の先頭で接地時に `GravityAcceleration[0]` を入れている | reimpl |

### 4.7 計算上そうなるはずの結果（テストが実測して確かめる）

| 項目 | 計算値 | 確度 |
|---|---|---|
| 立ちジャンプの高さ | 約 4.34 マス | derived |
| 立ちジャンプの上昇時間 | 約 0.48 秒 | derived |
| 助走ジャンプの高さ（速度ボーナス満） | 約 5.26 マス | derived |
| ダッシュ最高速までの時間 | 約 1.5 秒（段ごとに加速が落ちるため） | derived |

## 5. 特定できなかったもの（unknown。推測で埋めない）

- `Player::Constants` の各パワーアップの実値（ROM データ。decomp 未到達）
- `dashThreshold` の実値（ダッシュ段に入るための速度しきい値）
- `JumpCurveAccelTable` の ROM 実値そのもの（MvsL の値と一致するかは未確認）
- code-ref のコメントにある閾値「velocity.y > 2.5 / 1.5 < v <= 2.5」と、MvsL の閾値
  （換算すると 2.22 / 1.125 ドット/フレーム）が**一致しない**。どちらが ROM 実値かは未確認。
  Jape は MvsL 側を採用している。
- プレイヤーの当たり判定の**幅**
- 壁すべりの開始条件の厳密なフレーム条件
- 坂・氷・水中（Jape に該当地形が無いため、取り込んでいない）

## 6. Jape 独自仕様（NSMB DS に無い／確認できていないもの）

原作準拠と混ぜないため、ここに列挙する。

| 要素 | 扱い |
|---|---|
| 3段ジャンプ | **原作準拠**（MvsL `JumpTripleBonusVelocity`。NSMB にも存在する） |
| 壁キック | **原作準拠**（MvsL `Walljump*`） |
| ヒップドロップ | **原作準拠**（落下上限のみ。溜め時間は Jape 独自） |
| 踏みつけの跳ね返り | Jape 独自（`STOMP_BOUNCE_LOW/HIGH`） |
| ヒップドロップの溜め時間・着地硬直 | Jape 独自（`GP_HOVER` / `GP_LAND_STUN`） |
| 敵・落下物の重力 | Jape 独自（`ACTOR_GRAVITY` / `ACTOR_MAX_FALL`）。プレイヤーの重力を変えても敵は変えない |
| スター・コイン・残機などの対戦ルール | Jape 独自（`docs/RULES.md`） |

## 7. 入力の扱い

原作は**デジタル十字キー + ダッシュボタン**。Jape はスマホのスティックUIを持つが、
**物理に渡す前に DS 互換のデジタル信号へ量子化する**（`actors/player/virtual_controller.gd`）。

```
タッチ / キーボード / パッド / CPU
        ↓  ここで量子化（左右は -1 / 0 / +1、ダッシュは ON/OFF）
PlayerInput
        ↓
Simulation（60Hz 固定）
```

**スマホだからという理由の物理補正（ジャンプを高く・重力を弱く・ダッシュを遅く等）は入れない。**
どの入力機器でも同じ物理になる。
