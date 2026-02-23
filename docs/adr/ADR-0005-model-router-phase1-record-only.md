# ADR-0005: Model Router Phase 1 実装（記録のみ）

**Status**: Accepted
**Date**: 2026-02-23
**Context**: oath-harness Phase 1 (MVP)

## Context

oath-harness のアーキテクチャには Model Router（タスクの性質に応じて Opus / Sonnet / Haiku を
動的に振り分けるコンポーネント）が含まれる。

Phase 1 において Model Router をどこまで実装するかを決定する必要がある。

現時点での制約:

- Claude Code の hooks API には `before_model_resolve` 相当のフックが存在しない
  （モデル切替を API レベルで行う手段がない）
- 実際のモデル切替機能を実装しても、Phase 1 の実行環境では発動しない

## Decision

**Phase 1 の Model Router は推奨モデル情報の生成・記録のみを行い、実際のモデル切替は行わない。**

具体的な実装スコープ:

| 機能 | Phase 1 | Phase 2 |
|------|---------|---------|
| タスク分類（推奨モデルの判定） | 実装する | 維持 |
| 推奨情報のログ記録 | 実装する | 維持 |
| 実際のモデル切替 | 実装しない | `before_model_resolve` フック実装時に有効化 |

Phase 1 では以下のデータを audit ログに記録する:

```json
{
  "timestamp": "...",
  "event": "model_recommendation",
  "recommended_model": "sonnet",
  "reason": "building_phase_code_generation",
  "actual_model": null
}
```

## Consequences

### Positive

- Phase 1 のスコープを過剰拡大することなく、将来の実装基盤を整備できる
- 実データの蓄積により、Phase 2 での振り分けロジックの最適化に使える根拠が得られる
- `before_model_resolve` フック実装前から Model Router のロジックをテスト・検証できる

### Negative

- Phase 1 では Model Router が実際の動作に影響を与えないため、価値が限定的に見える
- 将来の有効化を忘れると、記録だけが蓄積されて実効性のないままになるリスクがある

### Risks

- Claude Code API の将来のバージョンでモデル切替フックの仕様が変わる可能性がある
  - 緩和策: Phase 2 での実装時に API 仕様を再確認する。現時点の実装は抽象化レイヤーを設けて
    フック仕様の変更に対応しやすい設計とする
- 「記録のみ」の状態が長期間続くと、Model Router モジュールの保守優先度が低下するリスクがある
  - 緩和策: `docs/tasks/phase2-tasks.md` に Model Router 有効化タスクを明示的に記録する
