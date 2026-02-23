# ADR-0001: bash モジュール分割

**Status**: Accepted
**Date**: 2026-02-23
**Context**: oath-harness Phase 1 (MVP)

## Context

oath-harness の実装を1ファイルに集約するか、`lib/*.sh` に分割するかを決定する必要がある。
単一ファイルにすれば `source` のパス管理が単純になる一方、コードベースが肥大化するにつれて
保守性・テスト容易性が低下するリスクがある。

## Decision

`lib/*.sh` によるモジュール分割を採用し、7〜8 モジュールに責務を分散する。

想定するモジュール構成:

| モジュール | 責務 |
|-----------|------|
| `lib/common.sh` | パス定数、ログ、jqラッパー、flock ユーティリティ |
| `lib/config.sh` | settings.json ロード・バリデーション |
| `lib/trust-engine.sh` | 信頼スコア取得・計算・判定・更新 |
| `lib/risk-mapper.sh` | リスク分類（low/medium/high/critical） |
| `lib/tool-profile.sh` | フェーズ別アクセス制御 |
| `lib/bootstrap.sh` | セッション初期化・v1→v2マイグレーション |
| `lib/model-router.sh` | Opus/Sonnet/Haiku推奨情報の生成・記録 |
| `lib/audit.sh` | 監査証跡JSONL記録・センシティブ値マスク |

エントリポイント（`hooks/` 配下のスクリプト）は必要なモジュールのみを `source` する。

## Consequences

### Positive

- 各モジュールの依存関係が明確になり、循環依存を防止しやすい
- テストを関心事ごとに分割でき、bats ファイルとの 1:1 対応が可能
- Phase 2 以降の機能追加時に影響範囲を限定できる
- コードレビューの粒度が適切になる

### Negative

- `source` のパス管理が複雑になる（絶対パス参照か `BASH_SOURCE` 相対解決が必要）
- モジュール読み込み順序が重要になる（依存関係を意識した順序で `source` する必要がある）
- ファイル数が増えることで、初見のコントリビューターが全体像を把握しにくい

### Risks

- 読み込み順序の誤りによる「未定義関数」エラーが実行時まで検出されないリスクがある
  - 緩和策: `tests/unit/` で各モジュールを独立してロードするテストを整備する
- パスの解決方法を統一しないと、環境差異（CI vs ローカル）で動作が変わる可能性がある
  - 緩和策: `OATH_HARNESS_ROOT` 環境変数を定義し、全モジュールで参照する規約を設ける
