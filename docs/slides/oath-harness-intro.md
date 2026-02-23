---
marp: true
theme: default
paginate: true
---

# oath-harness

## Trust-Based Execution Control for Claude Code

~ Earned Autonomy の実装 ~

---

## 問題: 権限制御の二択

Claude Code の権限制御には、**2 つの極端**しかない。

| 選択肢 | 問題 |
|--------|------|
| 全手動承認（デフォルト） | 1 日に数十〜数百回の承認要求 → 承認疲れ |
| `--dangerouslySkipPermissions` | 制御喪失。一度設定すると安全側に戻りにくい |

**この中間がない。**

> 慣れるにつれて承認内容を確認せずに「OK」するようになり、
> かえって安全性が低下するという逆説。

---

## Gap: 誰も作っていない

**100 以上のプロジェクト**を調査した結果——

- OwnPilot（95 stars）、mcp-human-loop（16 stars）、agentsh（35 stars）
  いずれも「あと一歩」で Earned Autonomy に届いていない
- Anthropic の **750 セッションデータ**で Earned Autonomy の自然発生を実証
  - 使い続けると auto-approve 比率が 20% → 40% 以上に自然上昇
- しかしシステムとして実装したプロジェクトは**ゼロ**

> 需要はデータで証明されている。空白地帯がある。

---

## Concept: Earned Autonomy とは

**「最小権限から始めて、実績で信頼を獲得する」**

```
セッション開始時:   最小権限から始まる（安全がデフォルト）
使い続けることで:   実績に基づいて自律度が自然に上昇する
失敗が起きたとき:   信頼スコアが低下し、自律度が自動的に制限される
数日後に戻ったとき: 蓄積された信頼は維持され、短期間で元の自律度に復帰できる
```

**自然に最適なバランスへ収束する。**

---

## Three Laws: 三法則

アシモフのロボット三原則を AI エージェント向けに再解釈:

**第一法則**
プロジェクトの整合性と健全性を損なってはならない。

**第二法則**
ユーザーの指示に従わなければならない（第一法則に反する場合を除く）。

**第三法則**
自己のコスト効率を守らなければならない（第一・二法則に反する場合を除く）。

> 「デフォルトは安全側」はこの第一法則の直接的な具体化。

---

## Architecture: 4 層構造

```
┌─────────────────────────────────────────┐
│  Layer 1: Model Router                  │
│           Opus / Sonnet / Haiku の動的振り分け │
├─────────────────────────────────────────┤
│  Layer 2: Trust Engine                  │
│           信頼スコア計算・自律度判定          │
├─────────────────────────────────────────┤
│  Layer 3: Harness + Guardrail Layer     │
│           フェーズ制御・リスク分類・アクセス制御  │
├─────────────────────────────────────────┤
│  Layer 4: Execution Layer               │
│           Claude Code hooks API         │
└─────────────────────────────────────────┘
```

---

## How Trust Works: 信頼の仕組み

信頼スコアのライフサイクル:

| タイミング | 処理 |
|------------|------|
| 初期値 | **0.3**（低い。安全がデフォルト） |
| 成功時（初期ブースト、≤20 操作） | `score + (1 - score) × 0.05` |
| 成功時（通常期間、>20 操作） | `score + (1 - score) × 0.02` |
| 失敗時 | `score × 0.85`（15% 減衰） |
| 14 日以内の放置 | 減衰なし（休眠凍結） |
| 14 日超過後 | `score × 0.999^(経過日数 - 14)` |

> Day 1 で trust ≈ 0.5、Day 3 で ≈ 0.72、Day 7 で ≈ 0.85

---

## Domain-Based Trust: ドメイン別信頼

ツール種別ごとに**独立したスコア**を管理する。

| ドメイン | 対象操作 |
|----------|----------|
| `file_read` | ファイル読取、ディレクトリ参照 |
| `file_write` | ファイル書込、作成、削除 |
| `shell_exec` | 任意シェルコマンド実行 |
| `git_local` | `git add`, `git commit` 等 |
| `git_remote` | `git push`, `git pull` 等 |
| `test_run` | pytest, npm test, go test 等 |

> 「ファイル読取は信頼済み、でも `git push` はまだ確認が必要」

---

## Risk Classification: リスク分類

4 段階のリスクカテゴリで動的に分類:

| レベル | 値 | 例 | デフォルト処理 |
|--------|----|----|----------------|
| `low` | 1 | `ls`, `cat`, `grep`, `pytest` | 自動承認候補 |
| `medium` | 2 | 未分類コマンド | 信頼スコアで判定 |
| `high` | 3 | `rm -rf`, `chmod`, `git push` | 低信頼時はブロック |
| `critical` | 4 | `curl`, `wget`、外部 API | **常にブロック** |

```
1. Deny List に合致       → high 以上に自動分類
2. Allow List に合致      → low に自動分類
3. critical パターンに合致 → critical に自動分類
4. それ以外（Gray Area）  → medium として動的判定
```

---

## The Decision Formula: 判定式

```
autonomy = 1 - (λ1 × risk + λ2 × complexity) × (1 - trust)
           λ1 = 0.6, λ2 = 0.4
```

4 段階の最終判定:

| autonomy 値 | risk | 判定 |
|-------------|------|------|
| > 0.8 | critical 以外 | `auto_approved` |
| 0.4 ≤ x ≤ 0.8 | — | `logged_only`（実行許可、記録のみ） |
| < 0.4 | — | `human_required`（人間確認要求） |
| — | `critical` | `blocked`（常時、スコア無関係） |

---

## Phase-Based Control: フェーズ制御

Safety-by-Prompt ではなく、**構造的にフェーズ制約を強制**する。

| フェーズ | 許可 | 禁止 |
|----------|------|------|
| PLANNING | `file_read`, `docs_write`, `git_read` | `shell_exec`, `file_write_src`, `git_remote` |
| BUILDING | `file_read`, `file_write`, `test_run`, `git_local` | `git_remote` |
| AUDITING | `file_read`, `git_read` | `file_write`, `shell_exec`, `git_local`, `git_remote` |

> フェーズ不明時は最も制限の強いプロファイル（AUDITING 相当）を適用。

---

## Data Flow: 一連の流れ

```
Tool Call
    │
    ▼
pre-tool-use.sh
    │── ドメイン特定
    │── リスク分類
    │── 信頼スコア読み込み
    │── autonomy 計算
    │── フェーズ制約確認
    │── 最終判定
    │
    ▼
実行 / ブロック
    │
    ▼
post-tool-use.sh
    │── 結果記録
    │── 信頼スコア更新
    └── audit JSONL に追記
```

---

## Installation: インストール

```bash
git clone <repo>
cd oath-harness
bash install/install.sh
```

**以上。設定不要で動き始める。**

- 外部パッケージのインストール不要
- インターネット接続不要（hooks 実行時）
- デフォルト値は全て保守的（安全側）

必要なもの: Linux + bash + jq

---

## Trust Score Timeline: 信頼スコアの推移イメージ

初期ブーストにより、最初の数日で急速に信頼が蓄積される。

```
Day 0: [===·······] 0.30  初期値（安全がデフォルト）
Day 1: [=====·····] 0.50  初期ブースト（最初の 20 操作）
Day 3: [=======···] 0.72  通常学習フェーズ
Day 7: [=========-] 0.85  自動承認域（autonomy > 0.8）
```

> 1 日 10 操作程度の通常使用で Day 1 中に「ログのみ」ゾーンに到達。
> Day 3 には大半の操作が自動化される設計。

---

## Audit Trail: 完全な透明性

全操作を **JSONL** 形式で記録。ブラックボックスは一切ない。

```json
{
  "timestamp": "2026-02-23T10:00:00Z",
  "session_id": "550e8400-e29b-41d4-a716...",
  "tool_name": "Bash",
  "domain": "shell_exec",
  "risk_category": "high",
  "trust_score_before": 0.45,
  "autonomy_score": 0.67,
  "decision": "human_required",
  "outcome": "success",
  "trust_score_after": 0.47
}
```

- センシティブ情報（API キー等）は自動マスク
- 保存先: `oath-harness/audit/YYYY-MM-DD.jsonl`（日別分割）

---

## Comparison: 既存ツールとの比較

| 特徴 | oath-harness | `--yolo` | Default |
|------|-------------|----------|---------|
| 承認頻度 | 動的（信頼に応じて自然に減少） | なし | 常に |
| 安全性 | 実績ベース（失敗で自動的に制限） | なし | 高（だが疲労） |
| Earned Autonomy | **あり** | なし | なし |
| 監査証跡 | **完全な JSONL ログ** | なし | なし |
| フェーズ制御 | **構造的に強制** | なし | なし |
| 外部依存 | **なし** | なし | なし |

---

## Tech Stack: 技術スタック

シンプルさと可搬性を最優先。

| 要素 | 選択 | 理由 |
|------|------|------|
| 言語 | **Bash（POSIX 互換）** | 外部依存ゼロ、Linux 標準 |
| JSON 処理 | **jq** | 標準的な Linux 環境に付属 |
| テスト | **bats-core** | Bash 専用テストフレームワーク |
| 排他制御 | **flock** | 原子的なログ追記の保証 |
| AI ベンダー | **Claude 一択** | hooks API との完全互換 |

> テスト: 258 件（unit 197 件 + integration 61 件）

---

## Phase 2 Roadmap

Phase 1 MVP を安定稼働させた後の拡張候補:

| コンポーネント | 概要 |
|----------------|------|
| Self-Escalation Detector | 連続失敗・不確実性シグナルを検出し、上位ペルソナへ自動委譲 |
| Phase-Aware Trust Modifier | フェーズ連動での信頼閾値の動的変動 |
| Persona Prompt Templates | Architect / Analyst / Worker / Reporter の 4 ペルソナ |
| Retry-with-Feedback Loop | 失敗 → フィードバック → 再試行サイクル |

**Phase 3 以降**: Docker Sandbox Orchestrator、マルチエージェント信頼ネットワーク、Web ダッシュボード

---

## Summary: まとめ

oath-harness が解決すること:

1. **承認疲れの解消** — 実績を積むことで自動的に承認頻度が減る
2. **安全性の維持** — 実績ベースの信頼。失敗すれば自動的に制限に戻る
3. **透明性の確保** — 全操作を完全な JSONL で記録。なぜ承認/ブロックされたか常に追跡可能
4. **フェーズに応じた適切な制約** — PLANNING では書込禁止、AUDITING では実行禁止

---

**"Default is safe. Trust is earned."**

---

## Links

- **Repository**: [TBD]
- **Documentation**: `docs/specs/requirements.md`, `docs/specs/design.md`
- **ADR**: `docs/adr/`
- **Tests**: 258 tests（unit 197 + integration 61）

---

*oath-harness — Phase 1 (MVP)*
*Earned Autonomy for Claude Code*
