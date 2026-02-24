# oath-status 設計書

**文書種別**: 詳細設計書 (Design Specification)
**機能**: oath-status CLI
**作成日**: 2026-02-24
**ステータス**: APPROVED
**参照要件定義書**: `docs/specs/oath-status/requirements.md`

---

## 1. アーキテクチャ概要

oath-status は oath-harness の **読み取り専用** CLI ツールである。既存の lib/ モジュールを source して再利用し、新規ロジックは最小限にとどめる。

```
bin/oath              ← エントリポイント（サブコマンドディスパッチ）
bin/lib/
├── cmd-status.sh     ← oath status の実装
├── cmd-audit.sh      ← oath audit の実装
├── cmd-config.sh     ← oath config の実装
├── cmd-phase.sh      ← oath phase の実装
└── format.sh         ← 色付け・テーブル描画ヘルパー
```

### 依存関係

```
bin/oath
  ├── source lib/common.sh     (パス定数、ログ)
  ├── source lib/config.sh     (設定読み込み)
  ├── source lib/trust-engine.sh (autonomy 計算)
  ├── source lib/tool-profile.sh (フェーズ取得)
  └── source bin/lib/*.sh      (各サブコマンド)
```

**設計原則**: oath-status は状態を **読むだけ** で **書かない**。trust-scores.json の変更、audit ログへの追記、フェーズの変更は一切行わない。

---

## 2. エントリポイント: `bin/oath`

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="${HARNESS_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

OATH_VERSION="0.1.0"

# Check jq dependency
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required but not installed." >&2; exit 1; }

# Source oath-harness lib modules
source "${HARNESS_ROOT}/lib/common.sh"
source "${HARNESS_ROOT}/lib/config.sh"
source "${HARNESS_ROOT}/lib/trust-engine.sh"
source "${HARNESS_ROOT}/lib/tool-profile.sh"

# Source oath-status modules
source "${SCRIPT_DIR}/lib/format.sh"
source "${SCRIPT_DIR}/lib/cmd-status.sh"
source "${SCRIPT_DIR}/lib/cmd-audit.sh"
source "${SCRIPT_DIR}/lib/cmd-config.sh"
source "${SCRIPT_DIR}/lib/cmd-phase.sh"

# Load config (non-fatal on missing settings.json)
config_load

case "${1:-status}" in
    status)  shift || true; cmd_status "$@" ;;
    audit)   shift || true; cmd_audit "$@" ;;
    config)  cmd_config ;;
    phase)   cmd_phase ;;
    help|-h|--help)  cmd_help ;;
    version|--version|-v)  cmd_version ;;
    *)
        echo "Unknown command: $1" >&2
        cmd_help >&2
        exit 1
        ;;
esac
```

**デフォルトサブコマンド**: 引数なしで `oath` を実行した場合は `oath status` と同等。

---

## 3. コンポーネント詳細設計

### 3.1 format.sh — 表示ヘルパー

#### 色定義

```bash
# 端末色サポート判定
_fmt_has_color() {
    [[ -t 1 ]] && [[ "${TERM:-dumb}" != "dumb" ]]
}

# 色コード (ANSI escape)
if _fmt_has_color; then
    FMT_GREEN='\033[0;32m'
    FMT_YELLOW='\033[0;33m'
    FMT_RED='\033[0;31m'
    FMT_CYAN='\033[0;36m'
    FMT_BOLD='\033[1m'
    FMT_DIM='\033[2m'
    FMT_RESET='\033[0m'
else
    FMT_GREEN='' FMT_YELLOW='' FMT_RED=''
    FMT_CYAN='' FMT_BOLD='' FMT_DIM='' FMT_RESET=''
fi
```

#### スコア色付け関数

```bash
# スコア値に応じた色を返す
# Args: score (float)
# Output: 色付きスコア文字列 (stdout)
fmt_score() {
    local score="$1"
    if _float_cmp "${score} >= 0.7"; then
        printf "${FMT_GREEN}%s${FMT_RESET}" "${score}"
    elif _float_cmp "${score} >= 0.4"; then
        printf "${FMT_YELLOW}%s${FMT_RESET}" "${score}"
    else
        printf "${FMT_RED}%s${FMT_RESET}" "${score}"
    fi
}
```

#### テーブル描画

```bash
# 固定幅テーブル行を出力
# Args: col1 col2 col3 col4 (各カラムの値)
fmt_table_row() {
    printf "%-16s %-8s %-6s %s\n" "$1" "$2" "$3" "$4"
}
```

### 3.2 cmd-status.sh — 信頼スコア表示

#### `cmd_status()` — メインロジック

```bash
cmd_status() {
    local domain="${1:-}"

    if [[ -n "${domain}" ]]; then
        _cmd_status_detail "${domain}"
    else
        _cmd_status_summary
    fi
}
```

#### `_cmd_status_summary()` — サマリー表示

1. trust-scores.json の存在確認
2. 存在しない場合: 「No trust data yet. Start a Claude Code session to begin building trust.」を表示して終了
3. ヘッダー行: バージョン、フェーズ、global_operation_count を表示
4. 各ドメインを jq でイテレート:
   - score を読み取り
   - total_operations を読み取り
   - `te_calc_autonomy "${score}" 2` (risk=medium想定) で autonomy を計算
   - `te_decide "${autonomy}" "medium"` で判定を取得
   - `fmt_table_row` で1行出力
5. ドメインは score の降順でソート

**jq フィルタ** (インライン、3行以内):
```jq
.domains | to_entries | sort_by(-.value.score) |
  .[] | [.key, .value.score, .value.total_operations]
```

#### `_cmd_status_detail()` — ドメイン詳細

1. ドメイン名で trust-scores.json を参照
2. ドメインが存在しない場合: 「Domain '<name>' not found.」を表示
3. 全フィールドを表示
4. 各リスクレベル (low=1, medium=2, high=3, critical=4) で autonomy を計算して判定結果を表示

**相対時間表示**: `last_operated_at` から現在までの経過を「X days ago」「X hours ago」等で表示する。

```bash
_fmt_relative_time() {
    local iso_time="$1"
    local then_epoch now_epoch diff_seconds
    then_epoch="$(date -d "${iso_time}" '+%s' 2>/dev/null)" || { echo "${iso_time}"; return; }
    now_epoch="$(date -u '+%s')"
    diff_seconds=$(( now_epoch - then_epoch ))

    if (( diff_seconds < 60 )); then echo "just now"
    elif (( diff_seconds < 3600 )); then echo "$(( diff_seconds / 60 )) min ago"
    elif (( diff_seconds < 86400 )); then echo "$(( diff_seconds / 3600 )) hours ago"
    else echo "$(( diff_seconds / 86400 )) days ago"
    fi
}
```

### 3.3 cmd-audit.sh — 監査ログ表示

#### `cmd_audit()`

1. 今日の audit ファイルパスを計算: `${AUDIT_DIR}/$(date -u '+%Y-%m-%d').jsonl`
2. ファイル存在確認。なければ「No audit entries for today.」
3. `--tail N` オプションの解析 (デフォルト N=10)
4. jq で JSONL を読み込み、直近 N 件を表形式で表示

**表示フォーマット**: outcome が "pending" のエントリ（PreToolUse 記録）のみ表示。outcome エントリは省略。

```bash
_cmd_audit_entries() {
    local file="$1" count="$2"
    # outcome=pending のエントリのみ（PreToolUse 時の完全エントリ）
    jq -r 'select(.outcome == "pending") |
        [.timestamp[11:19],
         (.tool_name + "(" + ((.tool_input.command // .tool_input.file_path // "...") | tostring)[0:20] + ")"),
         .domain, .risk_category, .decision] | @tsv' \
        "${file}" | tail -n "${count}"
}
```

### 3.4 cmd-config.sh — 設定表示

#### `cmd_config()`

1. `config_load` は既にエントリポイントで実行済み
2. `_OATH_CONFIG` のキャッシュから全値を取得して整形表示
3. デフォルト値と異なる場合は「(custom)」マークを付与

### 3.5 cmd-phase.sh — フェーズ表示

#### `cmd_phase()`

```bash
cmd_phase() {
    local phase
    phase="$(tpe_get_current_phase)"
    printf "Current phase: %s%s%s\n" "${FMT_BOLD}" "$(echo "${phase}" | tr '[:lower:]' '[:upper:]')" "${FMT_RESET}"
}
```

---

## 4. エラー処理方針

| エラー条件 | 処理 |
|:--|:--|
| trust-scores.json 不在 | 「No trust data yet」を表示、exit 0 |
| audit ファイル不在 | 「No audit entries for today」を表示、exit 0 |
| 不正な trust-scores.json | jq エラーをキャッチし「Corrupted trust data」を表示、exit 1 |
| 未知のサブコマンド | ヘルプを表示、exit 1 |
| jq 未インストール | 「jq is required」を表示、exit 1 |

**原則**: 読み取り専用ツールなので、エラー時はメッセージを出して終了。安全側に倒す必要はない（書き込みをしないため）。

---

## 5. テスト設計

### 5.1 ファイル構成

```
tests/unit/oath-status.bats    ← 全サブコマンドの単体テスト
```

### 5.2 テストケース一覧

| # | テスト | サブコマンド | 検証内容 |
|:--|:--|:--|:--|
| 1 | status サマリーに全ドメインが表示される | status | 各ドメインの行が存在 |
| 2 | status サマリーがスコア降順 | status | 出力行の順序 |
| 3 | status ドメイン詳細が全フィールドを表示 | status file_read | score, successes, failures 等 |
| 4 | status ドメイン詳細で autonomy 推定が4段階 | status file_read | low/medium/high/critical の行 |
| 5 | status で存在しないドメインにエラー | status nonexistent | 「not found」メッセージ |
| 6 | trust-scores.json 不在時に初期メッセージ | status | 「No trust data yet」 |
| 7 | audit サマリーが表示される | audit | エントリ数と一覧行 |
| 8 | audit --tail 5 で5件表示 | audit --tail 5 | 出力行数が5以下 |
| 9 | audit ファイル不在時にメッセージ | audit | 「No audit entries」 |
| 10 | config で全設定値が表示される | config | 主要キーが出力に含まれる |
| 11 | phase で現在のフェーズが表示される | phase | 「Current phase: BUILDING」等 |
| 12 | help でヘルプが表示される | help | Usage 行が含まれる |
| 13 | 不明コマンドでエラー | unknown | exit code 1 |
| 14 | 引数なしで status が実行される | (なし) | status サマリーと同じ出力 |

---

## 6. ADR

本機能で新規 ADR は不要。既存の設計原則（bash + jq、lib/ 再利用、読み取り専用）に従う。

---

*本文書は oath-status CLI の設計書である。*
