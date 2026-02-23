# OwnPilot コード解析レポート

**作成日**: 2026-02-23
**ソース**: https://github.com/ownpilot/OwnPilot (shallow clone)
**ローカル**: `vendor-src/OwnPilot/`
**規模**: 871 TS ファイル / 437K行

---

## 1. アーキテクチャ概要

### パッケージ構成

pnpm + Turborepo の TypeScript モノリポ、5パッケージ:

```
packages/
  core/     - AIエンジン・ツール・プラグイン・サンドボックス・暗号 (~62K LOC)
  gateway/  - Hono製HTTPサーバ・ルート・DB・WebSocket (~72K LOC)
  ui/       - React 19 + Vite + Tailwind CSS (~36K LOC)
  channels/ - Telegram bot (Grammy)
  cli/      - Commander.js CLI
```

### 主要コンポーネントの関係

```
Web UI ←→ Gateway (Port 8080)
              ├── MessageBus (ミドルウェアパイプライン)
              │     └── Request → Audit → Persistence → Post-Processing
              │                → Context-Injection → Agent-Execution → Response
              ├── autonomy/     ← 自律度・リスク・承認の核心
              ├── services/execution-approval.ts  ← コード実行承認
              ├── routes/autonomy.ts
              ├── routes/execution-permissions.ts
              └── assistant/orchestrator.ts
                    └── checkToolCallApproval()
```

### データフロー（承認を含む場合）

```
LLMツール呼び出し
  → checkToolCallApproval() [orchestrator.ts]
      → assessRisk() [risk.ts]
          → requiresApproval: true の場合
               → SSE: approval_required イベント送信
               → createApprovalRequest() で Promise ブロック
               → UI の ExecutionApprovalDialog が表示 (120秒タイムアウト)
               → ユーザーが POST /approvals/{id}/resolve
               → resolveApproval() が Promise を解決
               → 実行継続 or キャンセル
```

---

## 2. 自律度制御の実装詳細

### 5段階の定義

ファイル: `packages/gateway/src/autonomy/types.ts`

```typescript
export enum AutonomyLevel {
  MANUAL     = 0,  // 常に承認を要求
  ASSISTED   = 1,  // 提案して承認を待つ
  SUPERVISED = 2,  // 低リスクは自動実行、高リスクは承認要求（デフォルト）
  AUTONOMOUS = 3,  // 全て実行、ユーザーに通知
  FULL       = 4,  // 完全自律、最小限の通知
}
```

### 切り替えロジック

`checkApprovalRequired()` 関数（`risk.ts`）:

| Level | 承認が必要なリスクレベル |
|:--|:--|
| MANUAL (0) | 常に |
| ASSISTED (1) | 常に |
| SUPERVISED (2) | medium 以上 (score >= 25) |
| AUTONOMOUS (3) | critical のみ (score >= 75) |
| FULL (4) | 決して不要（blocked 除く） |

**Config Override の優先順位**（最も重要な設計判断）:
1. `blockedTools` → 常に承認要求（レベル無視）
2. `blockedCategories` → 常に承認要求
3. `confirmationRequired` → 常に承認要求
4. `allowedTools` → 承認不要（レベル無視）
5. `allowedCategories` → 承認不要
6. 最後にレベルに基づく判定

### デフォルト設定

```typescript
DEFAULT_AUTONOMY_CONFIG = {
  level: AutonomyLevel.SUPERVISED,
  blockedCategories: ['system_command', 'code_execution'],
  confirmationRequired: ['delete_data', 'send_email', 'make_payment', 'modify_system'],
  maxCostPerAction: 1000,
  dailyBudget: 10000,
  auditEnabled: true,
}
```

---

## 3. リスクスコアリングの実装詳細

ファイル: `packages/gateway/src/autonomy/risk.ts`

### 計算式

```
score = min(100, round((categoryBaseRisk + factorScore) / 2))
factorScore = (presentWeight / totalWeight) * 100
```

### カテゴリ基底リスク

| カテゴリ | スコア | | カテゴリ | スコア |
|:--|:--|:--|:--|:--|
| notification | 15 | | api_call | 35 |
| tool_execution | 20 | | external_communication | 40 |
| goal_modification | 20 | | plan_execution | 45 |
| file_operation | 25 | | code_execution | 70 |
| memory_modification | 25 | | system_command | 80 |
| data_modification | 30 | | financial | 90 |

### リスクファクターと重み

```
financial_transaction: 1.0   system_command: 0.95   code_execution: 0.9
data_deletion: 0.8           file_delete: 0.8       system_wide: 0.8
sensitive_data: 0.7          irreversible: 0.7
email_send: 0.6              file_write: 0.6        high_cost: 0.6
data_modification: 0.5       external_api: 0.5      affects_others: 0.5
bulk_operation: 0.4          notification_send: 0.3
```

### リスクレベル閾値

```
score >= 75 → critical
score >= 50 → high
score >= 25 → medium
score  < 25 → low
```

---

## 4. 承認フローの実装詳細

### 2系統の独立した承認フロー

**系統A: コード実行承認（SSE-based、リアルタイム）**
- ファイル: `services/execution-approval.ts`
- タイムアウト: 120秒（自動却下）
- SSE `approval_required` → UI `ExecutionApprovalDialog` → REST resolve

**系統B: 一般アクション承認（ApprovalManager）**
- ファイル: `autonomy/approvals.ts`
- タイムアウト: 300秒（毎分クリーンアップ）
- EventEmitter `action:pending` → WebSocket通知 → REST decide
- **modify** オプション: パラメータ変更→再アセスメント可能
- **remember** フラグ: カテゴリ+タイプ単位で90日間記憶

---

## 5. 信頼蓄積の有無と限界

### 結論: **動的な信頼蓄積（Earned Autonomy）は存在しない**

| 概念 | 実装状況 |
|:--|:--|
| 固定5段階レベル | 完全実装 |
| リスクスコアリング | 完全実装 |
| 承認フロー | 完全実装（2系統） |
| 決定の記憶（手動 remember） | 実装あり（90日TTL） |
| **実績に基づく自動昇格** | **未実装** |
| **信頼スコアの動的計算** | **未実装** |
| **失敗時の自動降格** | **未実装** |

### 近いが不完全な仕組み

1. **rememberedDecisions**: `userId:category:type` 単位で承認/却下を90日記憶。ただしユーザーが明示的に `remember: true` を指定した場合のみ。自動蓄積ではない。
2. **dailySpend**: リスクスコアを累積するが予算管理用。信頼度の計算には使われない。
3. **allowedTools**: 手動ホワイトリスト。静的な信頼設定。

---

## 6. Theme B（Trust Engine）への示唆

### 借りられる実装

1. **リスク計算式**: `(categoryBaseRisk + factorScore) / 2` は明快で実装しやすい。ファクター重みテーブルはそのまま参考になる。
2. **Config Override 優先順位チェイン**: blocked > confirmation > allowed > level。どの条件が勝つかが一見して明確。
3. **ActionContext**: `conversationId`, `planId`, `previousActions` を渡せる設計は Trust Engine の実績ベース評価の土台になる。
4. **SSE + Promise の承認ブリッジ**: エージェント実行を一時停止→人間承認→再開のパターン。
5. **EventEmitter 承認ライフサイクル**: `action:pending/approved/rejected/expired/auto_approved` は監査・ログ・通知のフックポイント。

### 足りない部分

1. **実績に基づく自動レベル昇格**: 承認回数・却下回数・成功率のトラッキングがない
2. **信頼スコアの永続化**: `rememberedDecisions` はインメモリ。サーバ再起動でリセット
3. **コンテキスト活用**: `ActionContext` は型定義はあるが `_context` とアンダースコア付き。**実際にはリスク評価に使っていない**
4. **自律度レベルの降格トリガー**: 失敗時の自動降格メカニズムがない
5. **ツール間の相関リスク**: 連続アクションの文脈リスクは計算されない

### 設計上の教訓

- 静的な remember フラグは Earned Autonomy の第一歩。Trust Engine では「N回承認されたら自動 remember」にする自動化が必要
- `blockedCategories` に `system_command` と `code_execution` を入れる保守的デフォルトは重要
- dailyBudget は信頼上限の代替として使える: 信頼残高が尽きたら承認要求に切り替える設計

---

## 7. 注目すべきコードパターン

### Promise ブリッジによる非同期承認

```typescript
// execution-approval.ts
const pendingApprovals = new Map<string, { resolve: (approved: boolean) => void; timer: ... }>();

function createApprovalRequest(id: string): Promise<boolean> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => { pendingApprovals.delete(id); resolve(false); }, TIMEOUT);
    pendingApprovals.set(id, { resolve, timer });
  });
}

function resolveApproval(id: string, approved: boolean): boolean {
  const pending = pendingApprovals.get(id);
  if (!pending) return false;
  clearTimeout(pending.timer);
  pendingApprovals.delete(id);
  pending.resolve(approved);
  return true;
}
```

Promise の resolve 関数を Map に格納し、HTTP リクエストから呼び出す。エージェント実行ループを HTTP レイヤーから制御できる。

### ツールリスクマッピングの宣言的テーブル

```typescript
const TOOL_RISK_FACTORS: Record<string, string[]> = {
  delete_file: ['file_delete', 'data_deletion', 'irreversible'],
  send_email:  ['email_send', 'external_api', 'affects_others'],
  list_tasks:  [],  // 読み取りのみ = リスクなし
};
```

新ツール追加時にロジック変更不要、テーブルに1行追加するだけ。

### setInterval().unref() によるクリーンアップ

```typescript
this.cleanupInterval = setInterval(() => { ... }, 60000);
this.cleanupInterval.unref();  // テスト時・終了時にプロセスをブロックしない
```
