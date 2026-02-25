# oath-harness Phase 2a 設計書

**文書種別**: 設計書 (Design Specification)
**フェーズ**: Phase 2a (Phase 1 改良 + Phase 2 準備)
**作成日**: 2026-02-24
**ステータス**: DRAFT
**参照要件定義書**: `docs/specs/phase2a-requirements.md`
**前提設計書**: `docs/specs/design.md` (Phase 1)

---

## 1. 設計方針

Phase 2a は Phase 1 の **差分設計** である。アーキテクチャの四層構造、コンポーネント境界、フォールセーフ原則は変更しない。

**変更の原則**:
- 既存の公開インターフェース（関数シグネチャ）は維持し、新引数はデフォルト値付きで追加
- jq フィルタの拡張は既存フィールドとの後方互換性を保証する
- Phase 1 の全304テストは回帰テストとして維持する

---

## 2. 変更概要

### 2.1 ファイル変更マトリクス

| ファイル | 変更種別 | 対応要件 |
|:--|:--|:--|
| `lib/trust-engine.sh` | 修正 | 2a-1, 2a-2, 2a-4 |
| `lib/jq/trust-update.jq` | 修正 | 2a-1, 2a-2 |
| `lib/bootstrap.sh` | 修正 | 2a-1 |
| `lib/risk-mapper.sh` | 修正 | 2a-4 |
| `hooks/pre-tool-use.sh` | 修正 | 2a-4, 2a-5 |
| `hooks/post-tool-use.sh` | 修正 | 2a-5 |
| `hooks/post-tool-use-failure.sh` | **新規** | 2a-1, 2a-5 |
| `install/install.sh` | 修正 | 2a-5 |
| `install/uninstall.sh` | 修正 | 2a-5 |
| `bin/lib/cmd-demo.sh` | 修正 | 2a-6 |
| `bin/lib/cmd-status.sh` | 修正 | 2a-1 |
| `.claude/commands/quick-save.md` | 修正 | 2a-3 |
| `.claude/commands/quick-load.md` | 修正 | 2a-3 |
| `config/settings.json` | 修正 | 2a-2 |

### 2.2 新規ファイル

| ファイル | 説明 |
|:--|:--|
| `hooks/post-tool-use-failure.sh` | PostToolUseFailure フック |

### 2.3 新規テストファイル

| ファイル | 対象 |
|:--|:--|
| `tests/unit/recovery-boost.bats` | 失敗回復ブースト |
| `tests/unit/complexity-dynamic.bats` | complexity 動的化 |
| `tests/unit/post-tool-use-failure.bats` | PostToolUseFailure フック |
| `tests/integration/failure-recovery.bats` | 失敗→回復の統合フロー |

---

## 3. コンポーネント詳細設計

### 3.1 Trust Engine 拡張 (lib/trust-engine.sh)

**対応要件**: FR-DM-001〜005, FR-RB-001〜005, FR-CX-001〜002

#### 3.1.1 新規関数

```bash
# risk_category から complexity を導出する
# 引数: risk_category (string: low|medium|high|critical)
# 出力: complexity (float, stdout)
te_get_complexity() {
    local risk_category="$1"
    case "${risk_category}" in
        low)      echo "0.2" ;;
        medium)   echo "0.5" ;;
        high)     echo "0.7" ;;
        critical) echo "1.0" ;;
        *)        echo "0.5" ;;  # フォールバック
    esac
}
```

#### 3.1.2 既存関数の変更

**te_calc_autonomy**: 変更なし（第3引数 complexity は既にオプショナル）。呼び出し側が `te_get_complexity` の結果を渡す。

**te_record_success**: 回復ブースト対応を追加。

```
変更前:
  rate = (warmup ? boost_rate × 2 : boost_rate)

変更後:
  base_rate = (warmup ? boost_rate × 2 : boost_rate)
  rate = (is_recovering ? base_rate × recovery_boost_multiplier : base_rate)

  # 回復完了判定
  if is_recovering AND new_score >= pre_failure_score:
    is_recovering = false
    pre_failure_score = null

  # 連続失敗リセット
  consecutive_failures = 0
```

**te_record_failure**: 連続失敗追跡と回復開始を追加。

```
変更前:
  score = score × failure_decay

変更後:
  # 初回失敗時に回復目標を記録
  if consecutive_failures == 0 AND NOT is_recovering:
    pre_failure_score = score（減衰前の値）
    is_recovering = true

  score = score × failure_decay
  consecutive_failures += 1
```

#### 3.1.3 設計判断

**Q: 回復中に再度失敗した場合の pre_failure_score は？**
A: 最初の値を維持する（FR-RB-003）。`is_recovering == true` の場合は pre_failure_score を上書きしない。

**Q: warmup と recovery の同時発動は？**
A: 両方の倍率を適用する（FR-RB-005）。`base_rate × 2（warmup）× 1.5（recovery）= base_rate × 3`。回復目標で自動停止するため、無制限にはならない。

---

### 3.2 trust-update.jq 拡張

**対応要件**: FR-DM-001〜003, FR-RB-001〜003

現在の trust-update.jq に以下のロジックを追加する。

#### 3.2.1 success アクション拡張

```jq
# 既存の rate 計算の後に追加:

# Recovery boost
(if ($dom.is_recovering // false) then
    $rate * ($rb // 1.5)
else
    $rate
end) as $final_rate |

# Score update with final_rate
(($dom.score + (1 - $dom.score) * $final_rate) ...) as $new_score |

# Recovery completion check
(if ($dom.is_recovering // false) and
    $new_score >= ($dom.pre_failure_score // 1.0) then
    false
else
    ($dom.is_recovering // false)
end) as $still_recovering |

(if $still_recovering == false and ($dom.is_recovering // false) then
    null
else
    ($dom.pre_failure_score // null)
end) as $pfs |

# Apply all updates
.domains[$d].is_recovering = $still_recovering |
.domains[$d].pre_failure_score = $pfs |
.domains[$d].consecutive_failures = 0
```

#### 3.2.2 failure アクション拡張

```jq
# 既存の failure 処理の前に追加:

# Record pre-failure score (only on first failure in sequence)
(if ($dom.consecutive_failures // 0) == 0 and
    ($dom.is_recovering // false | not) then
    $dom.score
else
    ($dom.pre_failure_score // null)
end) as $pfs |

(if ($dom.consecutive_failures // 0) == 0 and
    ($dom.is_recovering // false | not) then
    true
else
    ($dom.is_recovering // false)
end) as $recovering |

# 既存の score 減衰を適用後:
.domains[$d].consecutive_failures = (($dom.consecutive_failures // 0) + 1) |
.domains[$d].pre_failure_score = $pfs |
.domains[$d].is_recovering = $recovering
```

#### 3.2.3 新規パラメータ

trust-update.jq への追加入力変数:

| 変数 | 用途 | 渡し方 |
|:--|:--|:--|
| `$rb` | recovery_boost_multiplier | `--argjson rb 1.5` |

#### 3.2.4 後方互換性

既存フィールドがないドメインに対して `// 0`、`// false`、`// null` でデフォルト値を適用する。Phase 1 形式のデータでもエラーなく動作する。

---

### 3.3 Bootstrap 拡張 (lib/bootstrap.sh)

**対応要件**: FR-DM-004

`sb_ensure_initialized` 内で、各ドメインに新フィールドが存在しない場合に補完する。

```bash
# _sb_ensure_phase2a_fields()
# Phase 2a で追加されたフィールドを既存ドメインに補完する
_sb_ensure_phase2a_fields() {
    if [[ ! -f "${TRUST_SCORES_FILE}" ]]; then
        return 0
    fi

    local tmp
    tmp="$(jq '
        .domains |= with_entries(
            .value += {
                consecutive_failures: (.value.consecutive_failures // 0),
                pre_failure_score: (.value.pre_failure_score // null),
                is_recovering: (.value.is_recovering // false)
            }
        )
    ' "${TRUST_SCORES_FILE}")"
    printf '%s\n' "${tmp}" | atomic_write "${TRUST_SCORES_FILE}"
}
```

呼び出し位置: `sb_ensure_initialized` の末尾（v1→v2 マイグレーションの後）。

---

### 3.4 Risk Mapper 拡張 (lib/risk-mapper.sh)

**対応要件**: FR-CX-003

complexity 値を audit ログに記録するため、`rcm_classify` の出力に complexity を追加する。

```
変更前の出力: "medium 2"  (risk_category risk_value)
変更後の出力: "medium 2 0.5"  (risk_category risk_value complexity)
```

**呼び出し側の影響**: hooks/pre-tool-use.sh の read コマンドに第3変数を追加。

---

### 3.5 PreToolUse フック拡張 (hooks/pre-tool-use.sh)

**対応要件**: FR-CX-002, FR-HK-008〜009

#### 3.5.1 complexity 動的化

```bash
# Step 7-9 変更:
risk_result="$(rcm_classify "${tool_name}" "${tool_input_json}")"
read -r risk_category risk_value complexity <<< "${risk_result}"

# Step 14 変更:
autonomy="$(te_calc_autonomy "${trust}" "${risk_value}" "${complexity}")"
```

#### 3.5.2 updatedInput 準備（Phase 2a では記録のみ）

```bash
# Step 16 の後に追加:
# Phase 2b で有効化予定: Task tool の model を動的に注入
# Phase 2a では推奨値を audit ログに記録するのみ
if [[ "${tool_name}" == "Task" ]]; then
    log_debug "pre-tool-use: model_recommendation for Task: ${recommended_model}"
    # Phase 2b: updatedInput.model = ${recommended_model}
fi
```

JSON 出力に `updatedInput` は Phase 2a では**含めない**（FR-HK-009）。Phase 2b で有効化する際にコメント解除する設計とする。

---

### 3.6 PostToolUseFailure フック (hooks/post-tool-use-failure.sh) — 新規

**対応要件**: FR-HK-006〜007

#### 3.6.1 責務

ツール実行失敗時の専用フック。`consecutive_failures` のインクリメントと失敗回復ブーストの開始を担当する。

#### 3.6.2 PostToolUse との重複回避（FR-HK-007）

Claude Code の仕様上、失敗時に `PostToolUse`（is_error=true）と `PostToolUseFailure` の**両方が発火する可能性がある**。

**戦略: PostToolUse 側で失敗処理を無効化する**

```bash
# hooks/post-tool-use.sh の変更:
# PostToolUseFailure が登録されている場合、失敗処理を PostToolUseFailure に委譲
if [[ "${outcome}" == "failure" ]]; then
    # Phase 2a: PostToolUseFailure が失敗処理を担当
    # ここでは audit の outcome 更新のみ行い、スコア更新はスキップ
    atl_update_outcome "${session_id}" "${tool_name}" "failure" "" || true
    exit 0
fi
```

PostToolUseFailure 側で完全な失敗処理を行う:

```bash
# hooks/post-tool-use-failure.sh:
# 1. スコア更新（te_record_failure）
# 2. audit の outcome + trust_score_after 更新
# 3. consecutive_failures は trust-update.jq 内で自動インクリメント
```

#### 3.6.3 実装スケルトン

```bash
#!/bin/bash
# oath-harness PostToolUseFailure hook
# Handles tool execution failures: score decay + consecutive failure tracking
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# PostToolUseFailure errors should not block (side-effect only)
trap 'exit 0' ERR

source "${HARNESS_ROOT}/lib/common.sh"
source "${HARNESS_ROOT}/lib/config.sh"
source "${HARNESS_ROOT}/lib/trust-engine.sh"
source "${HARNESS_ROOT}/lib/bootstrap.sh"
source "${HARNESS_ROOT}/lib/risk-mapper.sh"
source "${HARNESS_ROOT}/lib/audit.sh"

# Step 1: Read stdin
raw_input="$(cat)"
[[ -z "${raw_input}" ]] && exit 0

tool_name="$(printf '%s' "${raw_input}" | jq -r '.tool_name // empty' 2>/dev/null)"
[[ -z "${tool_name}" ]] && exit 0

tool_input_json="$(printf '%s' "${raw_input}" | jq -c '.tool_input // {}' 2>/dev/null)"
[[ -z "${tool_input_json}" ]] && tool_input_json="{}"

# Step 2: Initialize
config_load
sb_ensure_initialized
session_id="$(sb_get_session_id)"

# Step 3: Get domain
domain="$(rcm_get_domain "${tool_name}" "${tool_input_json}")"

# Step 4: Record failure (includes consecutive_failures increment)
te_record_failure "${domain}" || true

# Step 5: Get updated trust score
trust_after="$(te_get_score "${domain}")"

# Step 6: Update audit trail
atl_update_outcome "${session_id}" "${tool_name}" "failure" "${trust_after}" || true

log_debug "post-tool-use-failure: tool=${tool_name} domain=${domain} trust_after=${trust_after}"

exit 0
```

---

### 3.7 install.sh / uninstall.sh 拡張

**対応要件**: FR-HK-010

install.sh に PostToolUseFailure フックの登録を追加:

```json
{
  "hooks": {
    "PreToolUse": [...],
    "PostToolUse": [...],
    "PostToolUseFailure": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "<path>/hooks/post-tool-use-failure.sh"
          }
        ]
      }
    ],
    "Stop": [...]
  }
}
```

uninstall.sh にも PostToolUseFailure の削除を追加。

---

### 3.8 save/load Trust 統合

**対応要件**: FR-SL-001〜004

#### 3.8.1 quick-save.md 変更

SESSION_STATE.md のテンプレートに Trust State セクションを追加:

```markdown
### Trust State
- trust-scores.json が存在する場合:
  - Global Operations: (global_operation_count)
  - ドメイン一覧: domain=score (successes/failures)
  - 回復中ドメイン: [RECOVERING → target] 表記
- trust-scores.json が存在しない場合:
  - 「未初期化」と記載
```

#### 3.8.2 quick-load.md 変更

ロード時の報告に Trust 概要を追加:

```
Phase: BUILDING | 次: ... | 未解決: なし
Trust: file_read=0.72 shell_exec=0.45[R] git_local=0.38
```

`[R]` は is_recovering == true のドメインを示す。

---

### 3.9 oath demo 拡張 (bin/lib/cmd-demo.sh)

**対応要件**: FR-DM-001〜003

既存の demo コマンドに Phase 2a シナリオを追加。

#### 3.9.1 シナリオ構成

```bash
# demo_phase2a_scenarios()
# 4つのシナリオを順番に実行・表示

demo_scenario_normal_growth()     # シナリオ1: 正常な信頼蓄積
demo_scenario_failure_recovery()  # シナリオ2: 失敗と回復ブースト
demo_scenario_complexity_compare() # シナリオ3: complexity 動的化の影響
demo_scenario_consecutive_fail()  # シナリオ4: consecutive_failures の蓄積
```

各シナリオは一時ディレクトリでシミュレーションを実行し、ステップごとのスコア推移をテーブル表示する。既存の `demo_generate_sample_data` は維持。

---

### 3.10 oath status 拡張 (bin/lib/cmd-status.sh)

**対応要件**: FR-DM-005

ドメイン詳細表示に新フィールドを追加:

```
Domain: shell_exec
  Score:       0.45  ████░░░░░░
  Successes:   8
  Failures:    3
  Consecutive: 2        ← 新規
  Recovering:  yes → 0.52  ← 新規
  Warmup:      no
```

---

## 4. データフロー変更

### 4.1 PreToolUse フロー（Phase 2a）

```
stdin → parse → config_load → sb_ensure_initialized
  → rcm_get_domain → rcm_classify (+ complexity)   ← 変更: complexity 追加
  → tpe_check
  → te_get_score
  → te_calc_autonomy(trust, risk, complexity)       ← 変更: complexity 動的
  → te_decide
  → mr_recommend
  → atl_append_pre (+ complexity)                   ← 変更: complexity 記録
  → exit code
```

### 4.2 PostToolUseFailure フロー（新規）

```
stdin → parse → config_load → sb_ensure_initialized
  → rcm_get_domain
  → te_record_failure (+ consecutive_failures, pre_failure_score, is_recovering)
  → te_get_score
  → atl_update_outcome
  → exit 0
```

### 4.3 PostToolUse フロー（Phase 2a 変更）

```
stdin → parse → config_load → sb_ensure_initialized
  → outcome 判定
  → if failure: audit 更新のみ（スコア更新は PostToolUseFailure に委譲） ← 変更
  → if success: te_record_success (+ recovery boost)                      ← 変更
  → te_get_score
  → atl_update_outcome
  → exit 0
```

---

## 5. JSON スキーマ変更

### 5.1 trust-scores.json ドメインスキーマ（Phase 2a）

```json
{
  "version": "2",
  "updated_at": "<ISO 8601>",
  "global_operation_count": 47,
  "domains": {
    "file_read": {
      "score": 0.72,
      "successes": 35,
      "failures": 1,
      "total_operations": 36,
      "last_operated_at": "2026-02-24T10:00:00Z",
      "is_warming_up": false,
      "warmup_remaining": 0,
      "consecutive_failures": 0,
      "pre_failure_score": null,
      "is_recovering": false
    }
  }
}
```

### 5.2 settings.json 追加項目

```json
{
  "trust": {
    "recovery_boost_multiplier": 1.5
  }
}
```

### 5.3 audit エントリ追加フィールド

```json
{
  "complexity": 0.5
}
```

---

## 6. エラー処理

Phase 1 のエラー処理戦略を踏襲する。追加分:

| エラー条件 | 処理 |
|:--|:--|
| `pre_failure_score` が null の状態で回復判定 | 回復しない（is_recovering = false として扱う） |
| `consecutive_failures` が undefined | 0 として扱う（jq の `// 0`） |
| PostToolUseFailure と PostToolUse が二重発火 | PostToolUse 側で失敗スコア更新をスキップ（audit 更新のみ） |
| `recovery_boost_multiplier` が設定未定義 | デフォルト値 1.5 を使用 |

---

## 7. テスト戦略

### 7.1 新規テスト

| テストファイル | テスト項目 | 推定件数 |
|:--|:--|:--|
| `tests/unit/recovery-boost.bats` | 回復ブースト発動・終了・再失敗・warmup 同時発動 | 15 |
| `tests/unit/complexity-dynamic.bats` | risk→complexity 導出、自律度への影響 | 10 |
| `tests/unit/post-tool-use-failure.bats` | PostToolUseFailure フック単体 | 8 |
| `tests/integration/failure-recovery.bats` | 失敗→回復→完了の統合フロー、二重発火防止 | 12 |

### 7.2 既存テストへの影響

| テストファイル | 影響 |
|:--|:--|
| `tests/unit/trust-engine.bats` | te_get_complexity のテスト追加。既存テストは変更なし |
| `tests/unit/risk-mapper.bats` | rcm_classify の出力形式変更に合わせて修正 |
| `tests/unit/pre-tool-use.bats` | complexity 第3変数の read に合わせて修正 |
| `tests/unit/post-tool-use.bats` | 失敗時のスコア更新スキップに合わせて修正 |
| `tests/integration/hooks-flow.bats` | PostToolUseFailure を含むフロー追加 |

### 7.3 回帰テスト

Phase 1 の全304テストを `tests/run-all-tests.sh` で実行し、パスを確認する。

---

## 8. ADR 更新

| ADR | 変更 |
|:--|:--|
| ADR-0006 (complexity-fixed-value) | Status を `Superseded` に変更。Phase 2a での risk→complexity 導出を記録 |
| ADR-0007 (新規) | PostToolUseFailure 採用と PostToolUse との責務分割の判断を記録 |

---

*本文書は oath-harness Phase 2a の設計書である。*
*Phase 1 設計書 (docs/specs/design.md) の全設計判断は、本文書で明示的に変更されない限り有効である。*
