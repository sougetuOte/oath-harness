# oath-status 要件定義書

**文書種別**: 要件定義書 (Requirements Specification)
**機能**: oath-status CLI
**作成日**: 2026-02-24
**ステータス**: DRAFT

---

## A. Core Value (Why & Who)

### A-1. ユーザーストーリー

```
As a oath-harness を使っている開発者、
I want 信頼スコア・監査ログ・セッション状態をコマンド一つで確認できるツール、
So that hooks の判定がなぜそうなったかを理解でき、
       信頼スコアの成長を実感できるから。
```

### A-2. Problem Statement

oath-harness v0.1.0 では、信頼スコアの確認に `cat state/trust-scores.json | jq .` が必要。
監査ログの確認にも `cat audit/YYYY-MM-DD.jsonl | jq .` が必要。
初心者ユーザーにとって jq の書式を覚えるのはハードルが高い。
ツールのブロック理由を素早く把握する手段がない。

### A-3. 想定ユーザー

| ユーザー像 | 詳細 |
|:--|:--|
| 主要対象 | oath-harness をインストール済みの Claude Code ユーザー |
| 技術背景 | bash コマンドの基本操作ができる。jq の知識は不要 |

---

## B. 機能要求

### B-1. サブコマンド一覧

| サブコマンド | 説明 | 優先度 |
|:--|:--|:--|
| `oath status` (引数なし) | 全ドメインの信頼スコアサマリーを表示 | Must |
| `oath status <domain>` | 指定ドメインの詳細情報を表示 | Must |
| `oath audit` | 今日の監査ログのサマリーを表示 | Must |
| `oath audit --tail N` | 直近N件の監査エントリを表示 | Should |
| `oath config` | 現在の設定値を表示 | Should |
| `oath phase` | 現在のフェーズを表示 | Must |

### B-2. `oath status` の出力仕様

#### 引数なし（サマリー表示）

```
oath-harness v0.1.0  |  Phase: BUILDING  |  Session: 47 ops

Domain          Score   Ops   Status
────────────────────────────────────────
file_read       0.82    35    auto_approved
shell_exec      0.51    11    logged_only
git_local       0.38     5    human_required
file_write      0.30     0    human_required
```

**表示項目**:

| 項目 | ソース | 説明 |
|:--|:--|:--|
| Domain | trust-scores.json `.domains` のキー | ドメイン名 |
| Score | `.domains[].score` | 現在の信頼スコア (0.0〜1.0) |
| Ops | `.domains[].total_operations` | 累積操作回数 |
| Status | score から autonomy を計算し te_decide で判定 | risk=medium 想定での判定結果 |

**色付け** (端末が対応している場合):

| Score 範囲 | 色 |
|:--|:--|
| >= 0.7 | 緑 |
| 0.4〜0.7 | 黄 |
| < 0.4 | 赤 |

#### ドメイン指定（詳細表示）

```
Domain: file_read
Score:            0.82
Successes:        34
Failures:         1
Total operations: 35
Last operated:    2026-02-23T09:55:00Z (1 day ago)
Warming up:       No
Warmup remaining: 0

Autonomy estimates:
  risk=low:      0.93 → auto_approved
  risk=medium:   0.86 → auto_approved
  risk=high:     0.79 → logged_only
  risk=critical: N/A  → blocked (always)
```

### B-3. `oath audit` の出力仕様

```
Audit log: 2026-02-24  |  47 entries

Recent decisions:
  09:55:00  Bash(ls -la)         file_read   low       auto_approved
  09:54:30  Write(src/main.sh)   file_write  medium    logged_only
  09:54:00  Bash(git push)       git_remote  high      blocked (phase)
  09:53:30  Bash(rm tmp/)        file_write  high      human_required
```

### B-4. `oath config` の出力仕様

```
oath-harness configuration (config/settings.json)

Trust:
  initial_score:      0.3
  hibernation_days:   14
  boost_threshold:    20
  warmup_operations:  5
  failure_decay:      0.85

Risk weights:
  lambda1:            0.6
  lambda2:            0.4

Autonomy thresholds:
  auto_approve:       0.8
  human_required:     0.4
```

### B-5. `oath phase` の出力仕様

```
Current phase: BUILDING
```

---

## C. 機能要求 ID 一覧

| ID | 要求 | 優先度 | 受け入れ条件 |
|:--|:--|:--|:--|
| FR-OS-001 | 全ドメインの信頼スコアサマリーを表形式で表示する | Must | ドメイン名、スコア、操作回数、判定ステータスが表示されること |
| FR-OS-002 | 指定ドメインの詳細情報を表示する | Must | スコア、成功/失敗回数、最終操作日時、ウォームアップ状態が表示されること |
| FR-OS-003 | ドメイン詳細で各リスクレベルでの autonomy 推定値を表示する | Must | low/medium/high/critical の 4段階の autonomy と判定が表示されること |
| FR-OS-004 | 今日の監査ログのサマリーを表示する | Must | エントリ数と直近の判定一覧が表示されること |
| FR-OS-005 | `--tail N` で直近N件を表示する | Should | 指定件数のエントリが逆時系列で表示されること |
| FR-OS-006 | 現在の設定値を一覧表示する | Should | settings.json の全キーとデフォルト値が表示されること |
| FR-OS-007 | 現在のフェーズを表示する | Must | .claude/current-phase.md の内容が表示されること |
| FR-OS-008 | 端末色対応時にスコアを色付けする | Should | TERM が色対応の場合に緑/黄/赤で表示されること |
| FR-OS-009 | trust-scores.json が存在しない場合にエラーではなく初期状態を表示する | Must | 「No trust data yet」のような表示になること |
| FR-OS-010 | jq 以外の外部依存なしで動作する | Must | bash + jq のみで実装されていること |

---

## D. Constraints (Limits)

### D-1. 技術的制約

| 制約 | 内容 | 理由 |
|:--|:--|:--|
| 言語 | bash + jq | oath-harness と同じスタック |
| 外部依存 | なし | oath-harness のポリシー準拠 |
| 配置場所 | `bin/oath` | oath-harness ルートからの相対パス |
| lib 再利用 | lib/ の関数を source して利用可 | DRY 原則、既存テスト資産の活用 |

### D-2. スコープ外

- インタラクティブ TUI（ncurses 等）
- Web ダッシュボード（Phase 3 のスコープ）
- trust-scores.json の直接編集機能
- 監査ログの削除・アーカイブ機能

---

## E. Perspective Check (3 Agents Model)

### Atom E1: CLI vs TUI vs Web

**[Affirmative]**
CLI は最もシンプルで oath-harness のスタック（bash + jq）と一貫している。初心者でも `oath status` を叩くだけで結果が見える。

**[Critical]**
CLI 出力は見た目が地味で、信頼スコアの「成長」を実感しにくい。Web ダッシュボードの方が視覚的なインパクトがある。

**[Mediator]**
Phase 1 では CLI で十分。Web ダッシュボードは Phase 3 候補に既にある。CLI の出力を丁寧に設計し、色付けとレイアウトで見やすくすれば十分な UX が得られる。

---

## F. テスト戦略

| テスト種別 | 対象 | ツール |
|:--|:--|:--|
| 単体テスト | 各サブコマンドの出力フォーマット | bats-core |
| 単体テスト | trust-scores.json 未存在時のフォールバック | bats-core |
| 単体テスト | 色付けの有無（TERM 変数） | bats-core |
| 統合テスト | oath status → oath audit の一連のフロー | bats-core |

---

*本文書は oath-status CLI の要件定義書である。*
