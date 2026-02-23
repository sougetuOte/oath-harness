# oath-harness

## Project Identity

oath-harness は Claude Code のための信頼ベース実行制御ハーネス。
Earned Autonomy（動的信頼蓄積 → 自律度調整）を実現する。

## Design Philosophy

```
「最小権限から始めて信頼を獲得する」
デフォルトは安全側。実績に基づいて権限を拡張する。
```

### Three Laws (oath-harness版)

1. プロジェクトの整合性と健全性を損なってはならない。
2. ユーザーの指示に従わなければならない（第一法則に反する場合を除く）。
3. 自己のコスト効率を守らなければならない（第一・二法則に反する場合を除く）。

## Architecture

4層構造:
- **Model Router**: Opus/Sonnet/Haiku の動的振り分け
- **Trust Engine**: 信頼スコア蓄積 → 自律度決定
- **Harness + Guardrail Layer**: TDDサイクル、フェーズ制限、権限制御
- **Execution Layer**: Claude Code hooks / Subagents

## Hierarchy of Truth

判断に迷った際の優先順位:

1. **User Intent**: ユーザーの明確な意志（リスクがある場合は警告義務あり）
2. **Specifications**: `docs/specs/requirements.md`, `docs/specs/design.md`
3. **ADR**: `docs/adr/`
4. **Existing Code**: 既存実装（仕様と矛盾する場合、コードがバグ）

## Core Principles

### Zero-Regression Policy

- **Impact Analysis**: 変更前に、最も遠いモジュールへの影響をシミュレーション
- **Spec Synchronization**: 実装とドキュメントは同一の不可分な単位として更新

### Active Retrieval

- 検索・確認を行わずに「以前の記憶」だけで回答することは禁止
- 「ファイルの中身を見ていないのでわかりません」と諦めることも禁止

## Execution Modes

| モード | 用途 | ガードレール | 推奨モデル |
|--------|------|-------------|-----------|
| `/planning` | 設計・タスク分解 | コード生成禁止 | Opus / Sonnet |
| `/building` | TDD 実装 | 仕様確認必須 | Sonnet |
| `/auditing` | レビュー・監査 | 修正禁止（指摘のみ） | Opus |

詳細は `.claude/rules/phase-rules.md` を参照。

## References

| カテゴリ | 場所 |
|---------|------|
| 行動規範 | `.claude/rules/` |
| 設計仕様 | `docs/specs/` |
| ADR | `docs/adr/` |
| タスク | `docs/tasks/` |
| 設定 | `config/` |
| テスト | `tests/` |

## Tech Stack

- **言語**: Bash (POSIX互換 + bashism)
- **テスト**: bats-core
- **JSON処理**: jq
- **排他制御**: flock
- **統合先**: Claude Code hooks API

## Context Management

コンテキスト残量が **20% を下回った** と判断したら、現在のタスクの区切りの良いところで
ユーザーに「残り少ないので `/quick-save` を推奨します」と提案すること。

### セーブ/ロードの使い分け
- `/quick-save`: SESSION_STATE.md のみ記録（軽量）
- `/quick-load`: SESSION_STATE.md のみ読込（日常の再開）
- `/full-save`: SESSION_STATE.md + git commit + push + daily（一日の終わり）
- `/full-load`: 詳細な状態確認 + 復帰報告（数日ぶりの復帰）

## Implementation Guide

### Module Structure

```
lib/
├── common.sh        # パス定数、ログ、jqラッパー、flock
├── config.sh        # settings.json ロード・バリデーション
├── trust-engine.sh  # スコア取得・計算・判定・更新
├── risk-mapper.sh   # リスク分類（low/medium/high/critical）
├── tool-profile.sh  # フェーズ別アクセス制御
├── bootstrap.sh     # セッション初期化・v1→v2マイグレーション
├── model-router.sh  # Opus/Sonnet/Haiku推奨（Phase 1は記録のみ）
├── audit.sh         # 監査証跡JSONL記録
└── jq/
    ├── audit-entry.jq   # 監査エントリ構築フィルタ
    └── trust-update.jq  # 信頼スコア更新フィルタ

hooks/
├── pre-tool-use.sh  # ツール実行前の判定（allow/block）
├── post-tool-use.sh # ツール実行後の信頼更新
└── stop.sh          # セッション終了時の永続化
```

### Prohibited Actions

- `--yolo` 相当の全自動承認機能は設計上存在しない
- `trust-scores.json` の直接スコア変更（バリデーションで拒否される）
- `initial_score > 0.5` の設定（安全側デフォルトの強制）
- `risk = critical` ツールの自動承認設定

### Technical Constraints

- **外部依存なし**: bash + jq + flock（標準Linuxツール）のみ
- **オフライン動作**: インターネット接続不要
- **排他制御**: trust-scores.json と audit ログは flock で原子性保証
- **フォールセーフ**: エラー時は安全側（ブロック）に倒す。フォールオープン禁止

### Testing

```bash
bash tests/run-all-tests.sh    # 全テスト（258件）
bash tests/run-unit-tests.sh   # 単体テスト（197件）
bash tests/run-integration-tests.sh  # 統合テスト（61件）
```

- フレームワーク: bats-core（git submodule）
- テストヘルパー: `tests/helpers.sh`
- フィクスチャ: `tests/fixtures/`

### Key Formulas

```
# 自律度計算
autonomy = 1 - (λ1 × risk_norm + λ2 × complexity) × (1 - trust)
  λ1 = 0.6, λ2 = 0.4, complexity = 0.5（Phase 1固定）

# 判定
risk = critical       → blocked（常時）
autonomy > 0.8        → auto_approved
0.4 ≤ autonomy ≤ 0.8  → logged_only
autonomy < 0.4        → human_required

# 信頼スコア更新
成功時（初期ブースト ≤20操作）: score += (1 - score) × 0.05
成功時（通常 >20操作）:        score += (1 - score) × 0.02
失敗時:                       score × 0.85
```

## Development Status

Phase 1 (MVP) — BUILDING Wave 5（ドキュメント・完成）
全258テスト Green（単体197 + 統合61）
