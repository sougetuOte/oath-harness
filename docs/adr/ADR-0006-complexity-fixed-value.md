# ADR-0006: complexity = 0.5 固定値の採用

**Status**: Superseded by Phase 2a (2026-02-25)
**Date**: 2026-02-23
**Context**: oath-harness Phase 1 (MVP)

## Superseded

Phase 2a において、`complexity` を `risk_category` から動的に導出する方式を採用した。
これにより本 ADR は置き換えられる。

導出ルール:

| risk_category | complexity |
|---------------|------------|
| low           | 0.2        |
| medium        | 0.5        |
| high          | 0.7        |
| critical      | 1.0        |

Phase 1 で採用した固定値 0.5 は、medium カテゴリのデフォルト値として引き継がれる。

詳細は以下を参照:
- `docs/specs/phase2a-design.md` Section 3.1.1
- `docs/specs/phase2a-requirements.md` Section E

## Context

oath-harness の自律度計算式は以下の通り定義されている:

```
autonomy = 1 - (λ1 × risk + λ2 × complexity) × (1 - trust)
```

このうち `complexity`（タスク複雑度）の値をどのように決定するかを決定する必要がある。

検討した選択肢:

| 手法 | 説明 | 課題 |
|------|------|------|
| **固定値 0.5** | Phase 1 を通じて一定 | 動的でない |
| AoT 判断ポイント数から推定 | 判断ポイント数を 0〜1 にスケール | Phase 1 では実装コストが高い |
| ファイル行数・分岐数から計算 | 静的解析ベース | bash の静的解析ツールが限定的 |
| ユーザーが都度指定 | 最も柔軟 | 運用負担が高い |

## Decision

**Phase 1 では `complexity = 0.5`（固定値）を採用する。**

`λ1 = 0.6`、`λ2 = 0.4` とした場合の自律度式（complexity 固定後）:

```
autonomy = 1 - (0.6 × risk + 0.4 × 0.5) × (1 - trust)
         = 1 - (0.6 × risk + 0.2) × (1 - trust)
```

これにより、Phase 1 では `risk` と `trust` の 2 変数のみで自律度が決まる。

Phase 2 では AoT（Atom of Thought）の判断ポイント数から complexity を動的に推定する設計を検討する。
その際の推定式（案）:

```
complexity = min(1.0, aot_atom_count / 10)
```

## Consequences

### Positive

- 実装が単純になり、Phase 1 の開発速度が向上する
- テストケースが減少し（complexity のバリエーションを考慮不要）、テスト設計が容易
- `risk` と `trust` という最重要変数に集中することで、自律度判定の予測可能性が高まる
- complexity 計算ロジックのバグによる誤判定リスクがない

### Negative

- タスクの実際の複雑度が自律度計算に反映されない
- 単純なタスクも複雑なタスクも同じ complexity として扱われるため、
  最適な自律度が設定されないケースが生じる

### Risks

- 固定値が適切でなかった場合（0.5 が高すぎる・低すぎる）に、
  全タスクの自律度が一律にずれるリスクがある
  - 緩和策: Phase 1 の運用データを蓄積し、audit ログから実際の判定傾向を分析する。
    必要に応じて固定値を調整する（ADR の更新で対応）
- Phase 2 への移行時に、固定値から動的計算への変更が既存の信頼スコアデータに
  影響を与えるリスクがある
  - 緩和策: complexity 値は audit ログに記録しておき、移行時の影響分析を容易にする
