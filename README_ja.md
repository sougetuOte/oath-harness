# oath-harness

Claude Code のための信頼ベース実行制御ハーネス。Earned Autonomy（獲得型自律性）を実現します。

[English](README.md)

---

## oath-harness とは？

### 課題

Claude Code の権限制御には2つの極端しかありません：

| 選択肢 | 問題 |
|--------|------|
| デフォルト（手動承認） | 1日に数十〜数百回の承認プロンプト。承認疲れにより、内容を読まずに承認する習慣がつき、安全性が形骸化する |
| `--dangerouslySkipPermissions` | 全操作がノーチェック。一度有効にすると安全なデフォルトに戻す動機がなくなる |

中間がありません。全部手動か、全部自動か。

Anthropic 自身の 750 セッション分のデータでは、ユーザーは自動承認の範囲を時間とともに拡大する（約20%→40%以上）傾向があります。この「**信頼を獲得して自律度を上げる**」パターンはユーザー行動に存在しますが、ツールには実装されていません。100以上のプロジェクトを調査した結果、実績に基づいてチェックポイント頻度を調整するシステムの実装はゼロでした。

### 解決策

oath-harness は第3の選択肢を導入します：最小権限で開始し、成功した操作を通じて信頼を獲得し、実証された信頼性に基づいて自律度を自動的に上げます。プロンプト指示だけに頼る「Safety-by-Prompt」は敵対的条件下で失敗します（ICLR 2025 の研究で混合攻撃成功率 84.30% が報告）。oath-harness は Claude Code の hooks API を通じて構造的に制約を強制します。

```
セッション開始:   最小権限（デフォルトは安全側）
作業中:           成功操作ごとに信頼が蓄積（Earned Autonomy）
失敗時:           信頼スコアが低下、自律度が自動的に制限
休止後:           蓄積された信頼は保存。以前の自律度レベルに素早く復帰
```

---

## 仕組み

oath-harness はすべてのツール呼び出しを Claude Code の hooks API でインターセプトし、実行前に信頼ベースの判定を行います。

### 信頼のライフサイクル

1. **セッションは低信頼で開始。** 新しいドメインはスコア `0.3` から始まります。
2. **成功するたびにスコアが上昇。** 最初の20操作（初期ブースト期間）では、成功1回あたり約 `+0.05 x (1 - score)` 加算。その後は `+0.02 x (1 - score)` に減速。
3. **失敗で信頼が15%低下。** 1回の失敗で `score = score x 0.85` が適用。
4. **通常使用後、安全な操作の多くが自動承認。** 初日に10回成功するとスコアは約0.45に。3日目には多くの日常操作が自動承認閾値をクリア。
5. **休止中の信頼は保存。** 最後の使用から14日以内（`hibernation_days`）はスコアが凍結。14日後に緩やかな減衰: `score x 0.999^(日数 - 14)`。
6. **復帰時のウォームアップ。** 休止期間を超えたドメインは、最初の5操作が2倍速ブーストで以前の自律度レベルに素早く復帰。

### ドメインベースの信頼

信頼はグローバルな単一スコアではなく、操作ドメインごとに個別追跡されます：

| ドメイン | 対象 |
|----------|------|
| `file_read` | ファイル読み取り、ディレクトリ一覧 |
| `file_write` | ファイル書き込み（`docs/` と `src/` 以外） |
| `file_write_src` | `src/` への書き込み（PLANNING フェーズでブロック） |
| `docs_write` | `docs/` への書き込み（PLANNING フェーズで使用） |
| `test_run` | pytest, npm test, go test など |
| `shell_exec` | 任意のシェルコマンド実行 |
| `git_local` | `git add`, `git commit` などローカル Git 操作 |
| `git_remote` | `git push`, `git pull` などリモート Git 操作 |
| `_global` | ドメイン記録がない場合のフォールバック |

`file_read` の高信頼が `shell_exec` の信頼を上げることはありません。各ドメインが独自に自律性を獲得する必要があります。

---

## アーキテクチャ

oath-harness は4層で実装されています：

```
+--------------------------------------------------------------+
| Layer 1: Model Router                                        |
|  Opus(Architect) / Sonnet(Analyst) / Haiku(Worker/Reporter)  |
|  タスク複雑度 + 信頼レベルに基づくモデル推奨                 |
+--------------------------------------------------------------+
| Layer 2: Trust Engine                                        |
|  ドメイン別スコア蓄積 -> 自律度計算                          |
|  非対称更新（成功/失敗）+ 時間減衰 + ウォームアップ          |
+------------------+-------------------------------------------+
| Layer 3a: Harness| Layer 3b: Guardrail                       |
|  Session Bootstrap  Risk Category Mapper                     |
|  Audit Trail        Tool Profile Engine                      |
|  状態管理           フェーズ別ツール制限                     |
+------------------+-------------------------------------------+
| Layer 4: Execution Layer                                     |
|  hooks/pre-tool-use.sh                                       |
|  hooks/post-tool-use.sh                                      |
|  hooks/stop.sh                                               |
|  (Claude Code hooks API とのインターフェース)                |
+--------------------------------------------------------------+
```

**Model Router** -- タスク複雑度（AoT基準）とドメイン信頼レベルに基づき Opus, Sonnet, Haiku を推奨。低信頼ドメインは Opus（Architect ペルソナ）にエスカレーション。

**Trust Engine** -- `autonomy = 1 - (lambda1 * risk + lambda2 * complexity) * (1 - trust)` の式で自律度スコアを計算。ツール呼び出しごとに4段階の判定を生成。

**Harness + Guardrail Layer** -- Session Bootstrap が永続化スコアを読み込み、起動時に時間減衰を適用。Audit Trail Logger がすべてのツール呼び出しを JSONL 形式で記録。Risk Category Mapper がツール呼び出しを `low / medium / high / critical` に分類。Tool Profile Engine がフェーズ別のツール制限を構造的に強制。

**Execution Layer** -- Claude Code hooks API と直接統合する3つの bash スクリプト。

---

## 前提条件

- Linux (bash + 標準 Unix ツール)
- `jq` (JSON 処理)
- Claude Code (hooks API サポートが必要)

これ以外の外部パッケージインストールは不要です。

---

## インストール

```bash
git clone https://github.com/sougetuOte/oath-harness.git
cd oath-harness
bash install/install.sh
```

インストーラが Claude Code のプロジェクト設定（`.claude/settings.json`）に hooks を登録し、必要な state / audit ディレクトリを作成します。

---

## 使い方

インストール後、hooks はすべてのツール呼び出しで自動的に発火します。手動での呼び出しは不要です。

### フェーズ切り替え

oath-harness は開発フェーズごとに異なるツール制限を適用します。Claude Code セッションでスラッシュコマンドを使ってフェーズを切り替えます：

| コマンド | フェーズ | 制限 |
|----------|---------|------|
| `/planning` | PLANNING | `shell_exec` ブロック、`src/` 書き込みブロック、`docs/` 書き込みのみ許可 |
| `/building` | BUILDING | `git_remote` ブロック、`shell_exec` と `git_local` は信頼ゲーティング |
| `/auditing` | AUDITING | `file_write`, `shell_exec`, 全 Git 書き込みブロック（読み取り専用） |

フェーズ制限は Tool Profile Engine が hooks レベルで強制します。プロンプト指示ではありません。現在のフェーズは `.claude/current-phase.md` に記録されます。

フェーズが不明または未設定の場合、oath-harness は最も制限の強いプロファイル（AUDITING 相当）を安全なデフォルトとして適用します。

---

## oath CLI

oath-harness にはステータス可視化 CLI が含まれています。ハーネス本体以外の追加インストールは不要です。

```bash
bin/oath                      # 信頼スコアサマリー
bin/oath status file_read     # ドメイン詳細と自律度推定
bin/oath audit --tail 20      # 最近の監査ログエントリ
bin/oath config               # 現在の設定値
bin/oath phase                # 現在の実行フェーズ
bin/oath demo                 # サンプルデータで全コマンドを実行
```

`oath demo` はリアルなサンプルデータを生成し、すべてのサブコマンドを実行します。ライブセッションなしで出力を確認するのに便利です。

---

## 信頼スコアの確認

信頼スコアは `state/trust-scores.json` にセッション間で永続化されます：

```bash
cat state/trust-scores.json | jq .
```

出力例：

```json
{
  "version": "2",
  "updated_at": "2026-02-23T10:00:00Z",
  "global_operation_count": 47,
  "domains": {
    "file_read": {
      "score": 0.82,
      "successes": 34,
      "failures": 1,
      "total_operations": 35,
      "last_operated_at": "2026-02-23T09:55:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    },
    "shell_exec": {
      "score": 0.51,
      "successes": 9,
      "failures": 2,
      "total_operations": 11,
      "last_operated_at": "2026-02-23T09:30:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0
    }
  }
}
```

書き込み時の制約: `initial_score` は 0.5 を超えられません（安全なデフォルトの強制）。設定オーバーライドによる信頼スコアの直接設定は拒否されます。

---

## 監査証跡の確認

すべてのツール呼び出しが日次 JSONL ファイルに記録されます：

```bash
cat audit/$(date +%Y-%m-%d).jsonl | jq .
```

各エントリには、ツール名、引数（機密値はマスク済み）、ドメイン、リスクカテゴリ、操作前後の信頼スコア、自律度スコア、最終判定が含まれます。特定の操作がなぜ承認/フラグ/ブロックされたかを完全に可視化します。

---

## 設定

`config/settings.json` の主要パラメータ：

| キー | デフォルト | 説明 |
|------|-----------|------|
| `trust.initial_score` | `0.3` | 新規ドメインの開始スコア（最大 0.5 を強制） |
| `trust.hibernation_days` | `14` | 最終使用からの時間減衰開始日数 |
| `trust.boost_threshold` | `20` | 初期ブースト期間の操作数 |
| `trust.warmup_operations` | `5` | 休止復帰後の2倍速ブースト操作数 |
| `trust.failure_decay` | `0.85` | 失敗時の乗数（0.85 = 15%ペナルティ） |
| `risk.lambda1` | `0.6` | 自律度計算式のリスク重み |
| `risk.lambda2` | `0.4` | 自律度計算式の複雑度重み |
| `autonomy.auto_approve_threshold` | `0.8` | この値を超えると自動承認 |
| `autonomy.human_required_threshold` | `0.4` | この値未満で人間の確認が必要 |
| `audit.log_dir` | `"audit"` | 日次 JSONL 監査ログのディレクトリ |
| `model.opus_aot_threshold` | `2` | Opus 推奨の最小 AoT 判断ポイント数 |

起動時にバリデーションが強制されます。`initial_score > 0.5` は拒否。`auto_approve_threshold` は `human_required_threshold` より大きい必要があります。`failure_decay` は 0.5 以上 1.0 未満。

---

## 信頼判定フロー

すべてのツール呼び出しに対し、oath-harness は4つの判定のいずれかを生成します：

| 条件 | 判定 | 意味 |
|------|------|------|
| `risk = critical` | `blocked` | 信頼スコアに関係なく常時ブロック（外部API、不可逆な外部影響） |
| フェーズの `denied_groups` に該当 | `blocked` | フェーズプロファイルがこの操作を禁止 |
| `autonomy > 0.8` | `auto_approved` | 十分な信頼。プロンプトなしで操作が進行 |
| `0.4 <= autonomy <= 0.8` | `logged_only` | 許可されるが、記録と精査が強化 |
| `autonomy < 0.4` | `human_required` | 信頼不足。人間の確認を要求 |

自律度スコアの計算式：

```
autonomy = 1 - (lambda1 * risk_value + lambda2 * complexity) * (1 - trust_score)
```

hook スクリプト自体が失敗した場合（設定エラー、ファイル欠落など）、判定はデフォルトで blocked になります。フェイルオープン（失敗時に許可）は禁止です。

---

## Three Laws

oath-harness の判定ロジックは、アシモフのロボット工学三原則を AI エージェント向けに適応した3つの法則に基づいています：

1. **プロジェクトの整合性と健全性を損なってはならない。** 他のすべての行動はこれに従属する。
2. **ユーザーの指示に従う** -- 第1法則に違反する場合を除く。
3. **コスト効率を守る** -- 第1・第2法則に違反する場合を除く。

これらの法則がシステム全体の競合解決を統制します。「デフォルトは安全側」は第1法則の直接的な表現です。

---

## テスト

```bash
bash tests/run-all-tests.sh  # 304 テスト
```

単体テストと統合テストを個別に実行：

```bash
bash tests/run-unit-tests.sh
bash tests/run-integration-tests.sh
```

テストは bats-core（サブモジュールとして同梱）を使用。追加のテストフレームワークのインストールは不要です。

---

## Phase 2 ロードマップ

Phase 2 では以下のコンポーネントを予定：

- **Self-Escalation Detector** -- 連続失敗や不確実性シグナル（「わかりません」パターン）を検出し、自動的に上位ペルソナ層にエスカレーション
- **Phase-Aware Trust Modifier** -- 現在のフェーズに基づいて信頼閾値を動的調整（AUDITING ではより厳格、BUILDING では信頼済みドメインにより寛容）
- **ペルソナプロンプトテンプレート** -- 4つのペルソナ用テンプレート: Architect (Opus), Analyst (Sonnet), Worker (Haiku), Reporter (Haiku)
- **`before_model_resolve` hook** -- Model Router ロジックをユーザーカスタマイズ可能な hook として公開
- **Retry-with-Feedback Loop** -- 構造化された 失敗→フィードバック→リトライ サイクル
- **Security Audit Runner** -- `/auditing` フェーズ開始時にトリガーされる自動セキュリティチェック
- **save/load Trust 統合** -- `/quick-save` と `/quick-load` セッションコマンドに信頼状態を統合

---

## ライセンス

MIT License. 詳細は [LICENSE](LICENSE) を参照してください。
