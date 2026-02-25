# クイックセーブ（軽量版）

プロジェクトルートの `SESSION_STATE.md` への記録のみ。git commit は行わない。
コンテキスト消費を最小限に抑えるため、簡潔に実行すること。

## 1. SESSION_STATE.md を書き出す（プロジェクトルート直下）

以下の内容を **簡潔に** 記録（各項目は箇条書き数行で十分）:

### 完了タスク
- 今回のセッションで完了した作業を箇条書き

### 進行中タスク
- 作業途中のものとその現在の状態
- 次に何をすべきか

### 次のステップ
- 次セッションで最初にやるべきこと（優先順位付き）

### 変更ファイル一覧
- 今回変更したファイルのパス一覧

### 未解決の問題
- 残っている課題、確認事項（なければ「なし」）

### コンテキスト情報
- 現在のフェーズ (PLANNING / BUILDING / AUDITING)
- 現在のgitブランチ
- 関連するSPEC/ADR/設計書ファイル名

### Trust State
- `config/trust-scores.json` が存在する場合:
  - Global Operations: (global_operation_count の値)
  - Session Operations: (session_operation_count の値)
  - Domains: 各ドメインを以下の形式で列挙
    - (domain_name): (score) (successes: N, failures: N)
    - 回復中の場合は末尾に `[RECOVERING → (recovery_target)]` を追加
  - 回復中ドメインがある場合: Recovering セクションにドメイン名・target・consecutive_failures を記載
- `config/trust-scores.json` が存在しない場合:
  - 「未初期化」と記載

## 2. 完了報告

以下を表示:

```
--- quick-save 完了 ---
再開方法:
  claude -c  （直前セッション続行）
  claude     （新規セッション）

再開後: 「SESSION_STATE.md を読んで前回の続きから」
---
```
