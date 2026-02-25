# oath-harness Phase 2a 要件定義書

**文書種別**: 要件定義書 (Requirements Specification)
**フェーズ**: Phase 2a (Phase 1 改良 + Phase 2 準備)
**作成日**: 2026-02-24
**ステータス**: DRAFT
**前提**: Phase 1 (MVP) 完了（全304テスト合格、oath CLI v0.1.0）

---

## 序文

Phase 2a は「Phase 1 を実運用可能にし、Phase 2b の上位機能（#8 Self-Escalation, #13 Retry-with-Feedback, #14 動的モデルルーティング）の基盤を整える」フェーズである。

Phase 1 は全7コンポーネントが実装済みだが、以下の課題が残っている:

1. パラメータが理論値のまま（実運用フィードバックなし）
2. complexity が 0.5 固定（ADR-0006 負債）
3. 失敗時のリカバリパスが不十分（スコア急落からの回復手段が乏しい）
4. save/load に Trust 状態が含まれない
5. hooks API が Phase 1 時点の3イベントしか利用していない（現在17イベント利用可能）

Phase 2a はこれらを解消し、サンプルシナリオで実運用フィードバックを得ることを目的とする。

---

## A. Phase 2a スコープ（6項目）

| ID | 項目 | 概要 | Phase 2b との関係 |
|:--|:--|:--|:--|
| 2a-1 | データモデル拡張 | 連続失敗カウンタ、回復ブースト用フィールド追加 | #8 Self-Escalation の検出トリガー |
| 2a-2 | 失敗回復ブースト | 失敗後の回復を 1.5 倍速にする機構 | #13 Retry-with-Feedback のスコア面基盤 |
| 2a-3 | save/load Trust 統合 | SESSION_STATE.md に Trust サマリーを含める | 実運用・デバッグの前提 |
| 2a-4 | complexity 動的化 | risk_category から complexity を導出 | 自律度計算の精度向上 |
| 2a-5 | hooks API 対応更新 | PostToolUseFailure 追加、updatedInput 対応 | #8 失敗検出、#14 モデルルーティングの基盤 |
| 2a-6 | サンプルシナリオ | oath demo 拡張で実運用シミュレーション | フィードバック取得 |

---

## B. 2a-1: データモデル拡張

### B-1. 変更内容

Trust Score ドメイン構造に3フィールドを追加する。

**現行（Phase 1）**:

```json
{
  "score": 0.3,
  "successes": 0,
  "failures": 0,
  "total_operations": 0,
  "last_operated_at": "...",
  "is_warming_up": false,
  "warmup_remaining": 0
}
```

**Phase 2a 追加フィールド**:

| フィールド | 型 | デフォルト | 説明 |
|:--|:--|:--|:--|
| `consecutive_failures` | integer | `0` | 連続失敗回数。成功時に 0 リセット |
| `pre_failure_score` | float or null | `null` | 失敗発生前のスコア（回復目標値） |
| `is_recovering` | boolean | `false` | 回復ブースト発動中か |

### B-2. 機能要求

| ID | 要求 | 優先度 | 受け入れ条件 |
|:--|:--|:--|:--|
| FR-DM-001 | 成功時に `consecutive_failures` を 0 にリセットする | Must | 成功記録後に consecutive_failures == 0 |
| FR-DM-002 | 失敗時に `consecutive_failures` をインクリメントする | Must | 連続3回失敗後に consecutive_failures == 3 |
| FR-DM-003 | 初回失敗時（consecutive_failures が 0→1 の時）に `pre_failure_score` を記録する | Must | 失敗直前のスコアが pre_failure_score に保存される |
| FR-DM-004 | 既存の trust-scores.json に新フィールドがない場合、デフォルト値で自動補完する | Must | Phase 1 形式のファイルが Phase 2a でもエラーなく読み込まれる |
| FR-DM-005 | `oath status` で新フィールドを表示する | Should | consecutive_failures > 0 の場合に表示される |

### B-3. マイグレーション

Phase 1 → Phase 2a のマイグレーションは `sb_ensure_initialized` 内で行う:

- 新フィールドが存在しないドメイン → デフォルト値で補完
- `version` フィールドは `"2"` のまま（データ構造の小変更、メジャー変更なし）

---

## C. 2a-2: 失敗回復ブースト

### C-1. 設計

既存の warmup 機構と同じパターンで、失敗からの回復を加速する。

**発動条件**: 失敗が発生し `is_recovering == false` の場合

**動作**:

```
失敗発生:
  consecutive_failures == 0 の場合:
    pre_failure_score = 現在のスコア（失敗適用前）
    is_recovering = true
  score = score × failure_decay（既存の 0.85 減衰は変更なし）
  consecutive_failures += 1

成功時:
  is_recovering == true の場合:
    通常の加算係数 × recovery_boost_multiplier（デフォルト 1.5）
  score >= pre_failure_score の場合:
    is_recovering = false
    pre_failure_score = null
  consecutive_failures = 0
```

### C-2. 設定項目追加

| キー | 型 | デフォルト | 説明 |
|:--|:--|:--|:--|
| `trust.recovery_boost_multiplier` | float | `1.5` | 回復ブースト時の加算係数倍率 |

### C-3. 機能要求

| ID | 要求 | 優先度 | 受け入れ条件 |
|:--|:--|:--|:--|
| FR-RB-001 | 失敗後の成功で通常の 1.5 倍の速度でスコアが回復する | Must | 回復中の加算が通常時の 1.5 倍であること |
| FR-RB-002 | スコアが失敗前の値に到達したら回復ブーストが自動終了する | Must | score >= pre_failure_score で is_recovering == false になること |
| FR-RB-003 | 回復中に再度失敗した場合、pre_failure_score は最初の値を維持する | Must | 連続失敗で pre_failure_score が上書きされないこと |
| FR-RB-004 | recovery_boost_multiplier は settings.json で変更可能 | Should | 設定値 2.0 で 2 倍速回復になること |
| FR-RB-005 | warmup と recovery が同時発動する場合、両方の倍率を適用する | Should | warmup(2倍) × recovery(1.5倍) = 3倍速になること |

### C-4. 計算例

```
初期状態: score = 0.60, total_operations = 25（通常期間）

失敗発生:
  pre_failure_score = 0.60
  is_recovering = true
  score = 0.60 × 0.85 = 0.51

通常の回復（recovery なし）:
  rate = (1 - 0.51) × 0.02 = 0.0098
  → 0.51 → 0.5198 → 0.5294 → ... → 0.60 まで約 10 回

回復ブースト（recovery あり、1.5 倍）:
  rate = (1 - 0.51) × 0.02 × 1.5 = 0.0147
  → 0.51 → 0.5247 → 0.5392 → ... → 0.60 まで約 7 回
```

---

## D. 2a-3: save/load Trust 統合

### D-1. 変更内容

`/quick-save` と `/quick-load` の SESSION_STATE.md に Trust サマリーセクションを追加する。

### D-2. SESSION_STATE.md の追加セクション

```markdown
## Trust State
- Global Operations: 47
- Session Operations: 12
- Domains:
  - file_read: 0.72 (successes: 35, failures: 1)
  - shell_exec: 0.45 (successes: 8, failures: 3) [RECOVERING → 0.52]
  - git_local: 0.38 (successes: 4, failures: 0)
- Recovering: shell_exec (target: 0.52, consecutive_failures: 0)
```

### D-3. 機能要求

| ID | 要求 | 優先度 | 受け入れ条件 |
|:--|:--|:--|:--|
| FR-SL-001 | `/quick-save` で Trust サマリーが SESSION_STATE.md に含まれる | Must | Trust State セクションが出力に存在すること |
| FR-SL-002 | `/quick-load` で Trust サマリーが報告に含まれる | Must | ロード時に Trust 概要が表示されること |
| FR-SL-003 | 回復中のドメインが明示される | Should | is_recovering == true のドメインが識別可能であること |
| FR-SL-004 | trust-scores.json が存在しない場合でもエラーにならない | Must | ファイル未生成の状態で save/load がエラーなく動作すること |

---

## E. 2a-4: complexity 動的化

### E-1. 変更内容

ADR-0006 で先送りされた complexity の固定値（0.5）を、risk_category から導出する方式に変更する。

### E-2. 導出ルール

| risk_category | complexity 値 | 根拠 |
|:--|:--|:--|
| low | 0.2 | 安全が確立された操作は複雑度が低い |
| medium | 0.5 | 未分類操作は中程度（Phase 1 と同じ） |
| high | 0.7 | Deny List 収録の操作は判断の複雑度が高い |
| critical | 1.0 | 不可逆な操作は最大複雑度 |

### E-3. 影響範囲

自律度計算式は変更なし:

```
autonomy = 1 - (λ1 × risk_norm + λ2 × complexity) × (1 - trust)
```

complexity の入力値が固定 0.5 → risk 連動に変わるのみ。

**Phase 1 との比較（trust = 0.5 の場合）**:

| risk | Phase 1 (c=0.5) | Phase 2a (c=dynamic) | 変化 |
|:--|:--|:--|:--|
| low (1) | 0.80 | 0.85 | +0.05（自動承認に入りやすくなる） |
| medium (2) | 0.65 | 0.65 | 変化なし |
| high (3) | 0.50 | 0.45 | -0.05（human_required に近づく） |
| critical (4) | — | — | 常に blocked（変化なし） |

low リスク操作がより自動承認されやすく、high リスク操作がより慎重になる。直感に合致する変化。

### E-4. 機能要求

| ID | 要求 | 優先度 | 受け入れ条件 |
|:--|:--|:--|:--|
| FR-CX-001 | risk_category から complexity を導出する | Must | low→0.2, medium→0.5, high→0.7, critical→1.0 |
| FR-CX-002 | 自律度計算に導出された complexity が使用される | Must | te_calc_autonomy の第3引数が動的に変わること |
| FR-CX-003 | audit ログに complexity 値を記録する | Must | 監査エントリに complexity フィールドが含まれること |
| FR-CX-004 | ADR-0006 を更新し、Phase 2a での変更を記録する | Must | ADR が Superseded 状態に更新されること |

---

## F. 2a-5: hooks API 対応更新

### F-1. 背景

Phase 1 時点では hooks API は3イベント（PreToolUse, PostToolUse, Stop）のみを使用していた。
2026年2月時点で hooks API は17イベントに拡張されており、以下が Phase 2a/2b に直接関連する:

| フック | 用途 | Phase |
|:--|:--|:--|
| `PostToolUseFailure` | ツール実行失敗の専用フック | 2a（#8 基盤） |
| `SubagentStart` | Subagent 起動の検知 | 2b（参考情報） |
| `SessionStart` | セッション開始時のモデル情報取得 | 2a（診断用） |
| PreToolUse `updatedInput` | Task tool の model パラメータ動的注入 | 2b（#14 の実装手段） |

### F-2. Phase 2a での実装範囲

#### F-2-1. PostToolUseFailure フック追加

Phase 1 の PostToolUse は `is_error` フィールドで成功/失敗を判定していたが、
`PostToolUseFailure` は失敗時のみ発火する専用フックである。

**Phase 2a での対応**:
- `hooks/post-tool-use-failure.sh` を新規作成
- PostToolUse の失敗ロジックとの重複回避（PostToolUseFailure がある場合はそちらを優先）
- `consecutive_failures` のインクリメントを PostToolUseFailure で行う

#### F-2-2. PreToolUse の updatedInput 対応準備

Phase 2b の #14（動的モデルルーティング）は、PreToolUse で Task tool をインターセプトし
`updatedInput.model` でモデルを注入する方式で実現する。

**Phase 2a での対応**:
- PreToolUse の出力形式に `updatedInput` フィールドのサポートを追加
- Model Router (`mr_recommend`) の結果を `updatedInput` に変換する関数を用意
- Phase 2a では**記録のみ**（実際の注入は Phase 2b で有効化）

#### F-2-3. SessionStart フック追加（任意）

セッション開始時のモデル・環境情報を audit ログに記録する。

### F-3. 機能要求

| ID | 要求 | 優先度 | 受け入れ条件 |
|:--|:--|:--|:--|
| FR-HK-006 | PostToolUseFailure フックで失敗を検出し consecutive_failures を更新する | Must | 失敗時に PostToolUseFailure が発火し、consecutive_failures がインクリメントされること |
| FR-HK-007 | PostToolUse と PostToolUseFailure の重複処理を回避する | Must | 同一失敗イベントでスコアが二重減衰しないこと |
| FR-HK-008 | PreToolUse が updatedInput フィールドを出力できる | Must | JSON 出力に updatedInput が含まれること |
| FR-HK-009 | updatedInput による model 注入は Phase 2a では無効（記録のみ） | Must | Phase 2a では実際のモデル切替が発生しないこと |
| FR-HK-010 | install.sh が新フック（PostToolUseFailure）を登録する | Must | インストール後に PostToolUseFailure が .claude/settings.json に登録されていること |

---

## G. 2a-6: サンプルシナリオ

### G-1. 目的

`oath demo` コマンドを拡張し、Phase 2a の全機能を含むシミュレーションシナリオを提供する。
実運用フィードバックの取得に使用する。

### G-2. シナリオ構成

```
シナリオ 1: 正常な信頼蓄積
  10回連続成功（file_read ドメイン）
  → スコア推移、complexity=0.2（low）の影響を表示

シナリオ 2: 失敗と回復ブースト
  5回成功 → 2回連続失敗 → 回復ブースト発動 → 回復完了まで
  → pre_failure_score, is_recovering, 1.5倍回復の推移を表示

シナリオ 3: complexity 動的化の影響
  同じ trust で low / medium / high の自律度を比較
  → Phase 1 (c=0.5固定) vs Phase 2a (c=dynamic) の差を表示

シナリオ 4: consecutive_failures の蓄積
  5回連続失敗
  → consecutive_failures の推移、スコア急落の様子を表示
  → Phase 2b の Self-Escalation がここで発動する予定であることを注記
```

### G-3. 機能要求

| ID | 要求 | 優先度 | 受け入れ条件 |
|:--|:--|:--|:--|
| FR-DM-001 | `oath demo` が Phase 2a の全機能をシミュレーションする | Must | 4シナリオが全て実行・表示されること |
| FR-DM-002 | 各シナリオでスコア推移がテーブル表示される | Must | ステップごとの score, autonomy, decision が表示されること |
| FR-DM-003 | Phase 1 と Phase 2a の差が視覚的に比較できる | Should | complexity 固定 vs 動的の比較表示があること |

---

## H. Phase 2b との接続点

Phase 2a の成果物が Phase 2b の各コンポーネントにどう接続するかを明示する。

| Phase 2b | Phase 2a の接続点 |
|:--|:--|
| **#8 Self-Escalation Detector** | `consecutive_failures` が閾値（例: 3）を超えた場合に上位ペルソナへ委譲。PostToolUseFailure フックが検出基盤 |
| **#13 Retry-with-Feedback Loop** | `is_recovering` 状態での再試行。失敗回復ブーストがスコア面をサポート |
| **#14 動的モデルルーティング** | PreToolUse の `updatedInput.model` で Task tool のモデルを動的注入。mr_recommend の結果を直接使用 |

---

## I. Perspective Check (3 Agents Model)

### AoT 分解

| Atom | 判断内容 | 依存 |
|:--|:--|:--|
| I1 | データモデル拡張の後方互換性 | なし |
| I2 | 失敗回復ブーストのパラメータ妥当性 | なし |
| I3 | hooks API 更新の安全性（重複処理回避） | I1 |

---

### Atom I1: データモデル拡張の後方互換性

**[Affirmative]**
3フィールド追加は全てデフォルト値を持ち、既存データを壊さない。`sb_ensure_initialized` での自動補完は Phase 1 の v1→v2 マイグレーションと同じパターンであり、実績がある。version フィールドを変更しないことで、Phase 1 のコードとの互換性も維持される。

**[Critical]**
version を変更しないことは、「どの時点のスキーマか」が不明瞭になるリスクがある。将来的にフィールドが増え続けると、version による判別が効かなくなる。また、`pre_failure_score = null` という nullable フィールドは jq での扱いに注意が必要（null チェックの漏れによるバグ）。

**[Mediator]**
結論: version は `"2"` のまま維持し、フィールドの有無で判定する方式を採用する。nullable フィールドの jq 処理にはテストケースを十分に用意する。将来的に version `"3"` への移行が必要になった場合は ADR で判断する。

---

### Atom I2: 失敗回復ブーストのパラメータ妥当性

**[Affirmative]**
1.5 倍は保守的な値であり、回復を「少し加速する」程度の効果。warmup の 2 倍と比較しても控えめ。回復目標（pre_failure_score）を明確に持つことで、無制限なブーストを防げる。settings.json で変更可能にすることで、実運用後の調整も容易。

**[Critical]**
warmup と recovery が同時発動する場合、2 × 1.5 = 3 倍速になる。これは初期ブーストの 0.05 × 3 = 0.15 の加算に相当し、やや急激な回復となる可能性がある。また、意図的に失敗→回復を繰り返すことで回復ブーストを悪用するパターンは考慮されているか。

**[Mediator]**
結論: 1.5 倍は妥当。warmup との同時発動は「稀なケース（休眠後の復帰直後に失敗）」であり、3 倍速になっても回復目標で自動停止するため無制限にはならない。悪用パターンについては、失敗によるスコア減衰（× 0.85）の方が回復ブーストより常に大きいため、意図的失敗は損になる設計。

---

### Atom I3: hooks API 更新の安全性

**[Affirmative]**
PostToolUseFailure は失敗専用フックとして明確に分離されており、責務が明快。PostToolUse の既存ロジック（is_error 判定）と PostToolUseFailure の共存は、PostToolUseFailure を優先し PostToolUse 側の失敗パスを無効化することで整理できる。

**[Critical]**
PostToolUse と PostToolUseFailure の両方が発火する可能性がある（Claude Code の仕様による）。両方が同一失敗に対して処理すると、スコアが二重減衰する。Phase 1 の PostToolUse テスト（約10件）が Phase 2a の変更で壊れるリスクがある。

**[Mediator]**
結論: PostToolUseFailure を追加する際に、PostToolUse 側の失敗処理は保持したまま、PostToolUseFailure 側で「既に PostToolUse で処理済みかどうか」を確認するガード機構を入れる。具体的には、audit ログのタイムスタンプで重複を検出する。Phase 1 のテストは全て維持し、Phase 2a の追加テストで二重発火シナリオを網羅する。

---

## J. 受け入れ条件（Phase 2a 全体）

| # | 条件 | 検証方法 |
|:--|:--|:--|
| AC-2a-001 | Phase 1 の全304テストが引き続きパスする | 回帰テスト実行 |
| AC-2a-002 | Phase 1 形式の trust-scores.json が Phase 2a でエラーなく読み込まれる | 統合テスト: Phase 1 フィクスチャで起動 |
| AC-2a-003 | 失敗後の回復が通常の 1.5 倍速で進む | 単体テスト: 回復ブースト計算の検証 |
| AC-2a-004 | score >= pre_failure_score で回復ブーストが自動終了する | 単体テスト: 回復完了の判定検証 |
| AC-2a-005 | consecutive_failures が正確にカウントされる | 単体テスト: 失敗→成功→失敗のシーケンス |
| AC-2a-006 | `/quick-save` に Trust State セクションが含まれる | 手動テスト: SESSION_STATE.md の内容確認 |
| AC-2a-007 | complexity が risk_category に連動して変化する | 単体テスト: 4種のリスクで自律度を比較 |
| AC-2a-008 | PostToolUseFailure が失敗時に発火し、スコアが二重減衰しない | 統合テスト: 二重発火シナリオ |
| AC-2a-009 | `oath demo` が Phase 2a の4シナリオを表示する | 手動テスト: デモ実行 |
| AC-2a-010 | install.sh が PostToolUseFailure フックを登録する | 統合テスト: インストール後の設定確認 |

---

## K. Phase 2a 完了後の Next Steps

Phase 2a 完了後、以下の手順で Phase 2b に移行する:

1. `oath demo` でサンプルシナリオを実行し、フィードバックを収集
2. フィードバックが不十分でも、もう1回イテレーションしたら Phase 2b に着手
3. Phase 2b: #8 Self-Escalation Detector → #13 Retry-with-Feedback → #14 動的モデルルーティング

---

*本文書は oath-harness Phase 2a の要件定義書である。*
*Phase 1 要件定義書 (docs/specs/requirements.md) の全制約（三法則、技術制約、設計制約）は Phase 2a にも適用される。*
