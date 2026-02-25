# ADR-0007: PostToolUseFailure フックの採用と責務分割

**Status**: Accepted
**Date**: 2026-02-25
**Context**: oath-harness Phase 2a

## Context

Phase 1 では `PostToolUse` フック単体で成功・失敗の両方を処理していた。
フック受信時の JSON ペイロードに含まれる `is_error` フィールドを参照することで、
失敗時には信頼スコアを減衰させる実装となっていた。

Phase 2a では `consecutive_failures`（連続失敗カウント）の追跡と、
一定回数の成功後に発動する回復ブーストを導入する。
これに伴い、失敗処理の専用化が設計上の課題として浮上した。

Claude Code の hooks API に `PostToolUseFailure` フック（失敗時のみ発火する専用フック）が
追加されたことで、失敗処理を独立したフックとして実装する選択肢が利用可能となった。

検討した選択肢:

| 手法 | 説明 | 課題 |
|------|------|------|
| **PostToolUse のみ継続（Phase 1 方式）** | `is_error` で成否を分岐 | 責務が不明確、PostToolUseFailure の恩恵を得られない |
| **PostToolUseFailure のみに完全移行** | PostToolUse の失敗パスを削除 | 未サポート環境での後方互換性がなくなる |
| **audit タイムスタンプで重複検出** | 二重発火をタイムスタンプで識別 | 実装の複雑さが増す、競合状態のリスクがある |
| **責務分割（PostToolUse + PostToolUseFailure）** | フックを用途別に分担 | フックに失敗処理が分散するが責務は明確 |

## Decision

**PostToolUseFailure フックを新規追加し、失敗専用の処理を担当させる。**

各フックの責務を次のように分割する:

| フック | 責務 |
|--------|------|
| `PostToolUse` | 成功時: 信頼スコア更新、audit 記録。失敗時: audit の `outcome` 更新のみ（スコア更新はスキップ） |
| `PostToolUseFailure` | 信頼スコア減衰、`consecutive_failures` インクリメント、回復ブーストのトリガー判定、audit 記録 |

### 二重発火の保証

`PostToolUse` と `PostToolUseFailure` が同一の失敗イベントで両方発火した場合でも、
スコアが一度だけ減衰することを保証する。

具体的な制御: `PostToolUse` 側では `is_error == true` のときにスコア更新処理を呼び出さず、
audit の `outcome` フィールドを `"failure"` に設定するのみとする。
スコア減衰は `PostToolUseFailure` 側でのみ実行する。

### 後方互換性

`PostToolUseFailure` が未サポートの Claude Code バージョンでは、
`PostToolUse` の `is_error` フィールドを参照して audit の `outcome` 更新は維持される。
スコア更新は実行されないが、監査証跡の記録は継続する。

## Consequences

### Positive

- 失敗処理の専用化により、`consecutive_failures` 追跡と回復ブーストの実装が明確な責務のもとで行える
- `PostToolUseFailure` フックが発火しない環境でも、`PostToolUse` による audit 更新で最低限の記録が維持される
- スコア更新箇所が `PostToolUseFailure` に一本化されることで、信頼スコアの二重減衰リスクが排除される

### Negative

- 失敗時の処理が `PostToolUse`（audit 更新）と `PostToolUseFailure`（スコア更新）の2フックに分散し、コードの追跡が複雑になる
- 両フックの責務の境界をドキュメントおよびコードコメントで明示しないと、将来の開発者が混乱するリスクがある

### Risks

- Claude Code 側の仕様変更で `PostToolUseFailure` の発火タイミングや二重発火の挙動が変わった場合に、
  スコアの二重減衰または減衰スキップが発生するリスクがある
  - 緩和策: audit ログにフック種別を記録し、運用データから二重発火の異常を検出できるようにする。
    仕様変更が確認された際は本 ADR を改訂し実装を調整する
- `PostToolUseFailure` 未サポート環境ではスコア減衰が行われず、信頼スコアが過大評価されるリスクがある
  - 緩和策: インストール時に Claude Code のバージョンを確認し、未サポート環境ではユーザーに警告を表示する
