# oath-status タスク分解

**参照設計書**: `docs/specs/oath-status/design.md`
**参照要件定義**: `docs/specs/oath-status/requirements.md`
**作成日**: 2026-02-24

---

## PR 構成

1PR で完結（新規ファイルのみ、既存コードへの変更なし）

---

## タスク一覧

### Task 1: format.sh — 表示ヘルパー

**ファイル**: `bin/lib/format.sh`
**依存**: なし（最初に実装）
**対応要件**: FR-OS-008

**実装内容**:
- `_fmt_has_color()` — 端末色サポート判定
- 色コード定数（FMT_GREEN, FMT_YELLOW, FMT_RED, FMT_CYAN, FMT_BOLD, FMT_DIM, FMT_RESET）
- `fmt_score()` — スコア値に応じた色付き文字列
- `fmt_table_row()` — 固定幅テーブル行出力
- `_fmt_relative_time()` — ISO時刻→相対時間変換

**テスト** (tests/unit/oath-status.bats 内):
- 色なし環境で FMT_* が空文字列
- fmt_score の閾値判定（0.7以上=緑, 0.4以上=黄, 未満=赤）
- _fmt_relative_time の変換（秒→min ago, 時間→hours ago, 日→days ago）

---

### Task 2: cmd-status.sh — 信頼スコア表示

**ファイル**: `bin/lib/cmd-status.sh`
**依存**: Task 1 (format.sh)
**対応要件**: FR-OS-001, FR-OS-002, FR-OS-003, FR-OS-009

**実装内容**:
- `cmd_status()` — ディスパッチ（引数なし→サマリー、あり→詳細）
- `_cmd_status_summary()` — 全ドメインのスコア降順テーブル
- `_cmd_status_detail()` — 指定ドメインの全フィールド + 4段階 autonomy 推定

**テスト**:
- サマリーに全ドメインが表示される（テスト #1）
- サマリーがスコア降順（テスト #2）
- ドメイン詳細が全フィールドを表示（テスト #3）
- ドメイン詳細で autonomy 推定が4段階（テスト #4）
- 存在しないドメインにエラーメッセージ（テスト #5）
- trust-scores.json 不在時に初期メッセージ（テスト #6）

---

### Task 3: cmd-audit.sh — 監査ログ表示

**ファイル**: `bin/lib/cmd-audit.sh`
**依存**: Task 1 (format.sh)
**対応要件**: FR-OS-004, FR-OS-005

**実装内容**:
- `cmd_audit()` — `--tail N` オプション解析、デフォルト N=10
- `_cmd_audit_entries()` — outcome=pending エントリのみ抽出・表形式出力

**テスト**:
- audit サマリーが表示される（テスト #7）
- audit --tail 5 で5件表示（テスト #8）
- audit ファイル不在時にメッセージ（テスト #9）

---

### Task 4: cmd-config.sh + cmd-phase.sh — 設定・フェーズ表示

**ファイル**: `bin/lib/cmd-config.sh`, `bin/lib/cmd-phase.sh`
**依存**: なし（lib/ の config.sh, tool-profile.sh を利用）
**対応要件**: FR-OS-006, FR-OS-007

**実装内容**:
- `cmd_config()` — 全設定値の整形表示、デフォルト値との差異に「(custom)」マーク
- `cmd_phase()` — 現在のフェーズを大文字で表示

**テスト**:
- config で全設定値が表示される（テスト #10）
- phase で現在のフェーズが表示される（テスト #11）

---

### Task 5: bin/oath エントリポイント + help/version

**ファイル**: `bin/oath`
**依存**: Task 1〜4（全サブコマンド）
**対応要件**: FR-OS-010

**実装内容**:
- エントリポイントスクリプト（設計書 §2 のコード）
- `cmd_help()` — Usage 表示
- `cmd_version()` — バージョン表示
- サブコマンドディスパッチ（デフォルト: status）
- `chmod +x bin/oath`

**テスト**:
- help でヘルプが表示される（テスト #12）
- 不明コマンドでエラー exit 1（テスト #13）
- 引数なしで status が実行される（テスト #14）

---

## 実装順序と依存関係

```
Task 1 (format.sh)
  ├── Task 2 (cmd-status.sh) ← 依存
  ├── Task 3 (cmd-audit.sh)  ← 依存
  └── Task 4 (cmd-config.sh + cmd-phase.sh) ← 独立だが同Wave
Task 5 (bin/oath) ← Task 1〜4 完了後
```

**Wave 1**: Task 1 → テスト Red/Green
**Wave 2**: Task 2, 3, 4 → 並行可、各テスト Red/Green
**Wave 3**: Task 5 → 結合、全テスト Green

---

## 完了基準

- [ ] 全14テストケースが Green
- [ ] `bin/oath` が実行可能（chmod +x）
- [ ] 既存テスト（272件）に影響なし
- [ ] 読み取り専用であること（trust-scores.json, audit ログへの書き込みなし）

---

*本文書は oath-status CLI のタスク分解である。*
