# oath-harness 設計ノート

**作成日**: 2026-02-23
**目的**: 3並列分析の結果を設計書作成時の入力として保存

---

## 1. 4層アーキテクチャ（確定）

```
┌──────────────────────────────────────────────────┐
│ Model Router                                      │
│  Opus(Architect) / Sonnet(Analyst) / Haiku(Worker)│
│  AoT条件で判定、Trust Scoreで動的降格/昇格        │
├──────────────────────────────────────────────────┤
│ Trust Engine                                      │
│  信頼スコア蓄積 → 自律度決定 → Action Gateway     │
│  非対称更新 + 時間減衰 + ドメイン別スコア          │
├────────────────────┬─────────────────────────────┤
│ Harness Layer      │ Guardrail Layer              │
│  PRD→TDD サイクル  │  品質ゲート・フェーズ制限     │
│  コンテキスト管理   │  権限制御・ODD境界           │
│  知識継承(Obsidian) │  ループ検出                  │
├────────────────────┴─────────────────────────────┤
│ Execution Layer                                   │
│  Claude Code hooks / Subagents / Skills           │
└──────────────────────────────────────────────────┘
```

---

## 2. Phase 1 (MVP) コンポーネント

| # | コンポーネント | 概要 |
|:--|:--|:--|
| 1 | Trust Engine 本体 | スコア計算 + 永続化(JSON) + 判定ロジック |
| 2 | hooks 3本 | PreToolUse / PostToolUse / Stop |
| 3 | Risk Category Mapper | OwnPilot テーブル借用、ツール+引数→リスクカテゴリ自動分類 |
| 4 | Audit Trail Logger | JSONL形式の操作ログ |
| 5 | Model Router | AoT条件 + 信頼スコアでOpus/Sonnet/Haiku振り分け |
| 6 | Session Trust Bootstrap | セッション開始時の信頼読み込み + 時間減衰適用 |

---

## 3. Phase 2 コンポーネント

| # | コンポーネント | 概要 |
|:--|:--|:--|
| 7 | Self-Escalation Detector | 不確実性シグナル検出（連続失敗、「わかりません」パターン） |
| 8 | Phase-Aware Trust Modifier | PLANNING/BUILDING/AUDITING連動で信頼閾値を変動 |
| 9 | save/load 拡張 | Trust状態をquick-save/loadに統合 |
| 10 | Obsidian型 knowledge/ | docs/knowledge/(concepts/patterns/decisions/research) |
| 11 | ペルソナプロンプト | 4ペルソナ(Architect/Analyst/Worker/Reporter)のテンプレート |
| 12 | Retry-with-Feedback Loop | 失敗→フィードバック→再試行（CrewAIパターン借用） |

---

## 4. 将来拡張候補（Phase 3以降）

| # | コンポーネント | 概要 | 優先度 |
|:--|:--|:--|:--|
| 13 | 非同期認可フロー | Auth0的な「承認待ち中も他タスク継続」。HTTP/SSEベース | 中 |
| 14 | マルチエージェント信頼ネットワーク | エージェント間の相互信頼評価（asura氏「都市」モデル） | 低 |
| 15 | ODD動的拡張 | 信頼蓄積によりcaution_zone→safe_zone昇格 | 中 |
| 16 | auto-compact検出 | 同一ファイル繰り返しReadで劣化を推定、自動セーブ | 中 |
| 17 | Agent Teams統合 | Claude Code Agent Teams がStableになった場合の移行 | 低（待ち） |
| 18 | Heimdall MCP統合 | ベクトルDB長期記憶（知識ベースが大規模化した場合） | 低 |
| 19 | ガードレール有効期限管理 | モデル改善に伴い不要になったガードレールの自動検出・除去 | 低 |
| 20 | ダッシュボード | 信頼スコア推移、操作ログの可視化（Web UI） | 低 |

---

## 5. ユーザー要件マッピング

| 要件 | Phase 1 | Phase 2 | 将来 |
|:--|:--|:--|:--|
| Claude一択 | 全体前提 | — | — |
| ペルソナ（アシモフ的） | Model Router基本判定 | プロンプトテンプレート4種 | — |
| Opus/Sonnet/Haiku振り分け | AoT条件+信頼スコア | 動的降格/昇格 | — |
| コンテキスト管理 | Session Trust Bootstrap | save/load拡張 | auto-compact検出 |
| LAM資産活用 | hooks設計参考 | Phase連動、save/load統合 | — |
| Obsidian型知識継承 | — | knowledge/ディレクトリ | Heimdall MCP |
| Linux優先 | bash+jq hooks | — | Windows(WSL2) |

---

## 6. 信頼スコア設計（確定案 → v2 改訂）

### 基本式（変更なし）

```
autonomy = 1 - (λ1 × risk + λ2 × complexity) × (1 - trust)

判定:
  autonomy > 0.8  → 自動承認
  0.4〜0.8        → ログのみ
  < 0.4           → 人間に確認
  risk=critical   → 常にブロック
```

### trust 更新ルール（v2 改訂）

```
成功:
  操作回数 ≤ 20（初期ブースト期間）:
    score = score + (1 - score) × 0.05   （加速学習）
  操作回数 > 20:
    score = score + (1 - score) × 0.02   （通常学習）

失敗:
  score = score × 0.85                    （一律15%減衰、変更なし）
```

**v2 改訂の効果**（初期ブースト適用時）:
```
  Day 1 (約10操作): trust ≈ 0.50  →「ログのみ」ゾーンに入る
  Day 3 (約30操作): trust ≈ 0.72  → 大半の操作が自動化
  Week 2 (約100操作): trust ≈ 0.85 → 高い自律性
```

旧設計（v1）では Week 1 でようやく 0.5 程度であり、ユーザーの忍耐限界を超える可能性があった。

### 時間減衰ルール（v2 改訂: 休眠凍結 + ドメイン別永続化）

**問題認識**: ユーザーが他の仕事で1週間プロジェクトを放置することは普通にある。
復帰時に「久しぶりだから確認多めにしますね」と言われるのは体験として最悪。

**改訂: 休眠凍結（Hibernation Freeze）**
```
時間減衰の適用条件:
  最終操作からの経過日数 ≤ 14日（休眠期間）:
    減衰なし（信頼スコアを凍結）
  最終操作からの経過日数 > 14日（長期不在）:
    score = score × 0.999^(経過日数 - 14)
    ※ 14日目から減衰開始。最初の2週間は「休眠」として保護

根拠:
  - 1-2週間の放置はプロジェクト開発では日常的
  - 2週間を超える不在は「プロジェクトとの接点が薄れた」と見なせる
  - 14日という閾値は設定で変更可能にする（config: trust.hibernation_days）
```

**改訂: ドメイン別信頼永続化（Domain Trust Persistence）**
```
信頼スコアを操作カテゴリ（ドメイン）ごとに分離して管理:

  trust = {
    "file_read":    0.92,   # ファイル読取: 高い実績
    "file_write":   0.75,   # ファイル書込: 中程度の実績
    "test_run":     0.88,   # テスト実行: 高い実績
    "shell_exec":   0.45,   # シェル実行: まだ蓄積中
    "git_local":    0.60,   # Git操作: 中程度
    "git_remote":   0.20,   # Git push: ほぼ未使用
    "_global":      0.70    # 全体の平均（フォールバック用）
  }

判定時:
  1. 操作のドメインを特定（例: pytest → "test_run"）
  2. 該当ドメインの trust を使って autonomy を計算
  3. ドメインに記録がない場合は _global を使用

ドメイン別の時間減衰:
  - 各ドメインごとに最終操作日を記録
  - 休眠凍結はドメイン単位で適用
  - 「pytest を100回成功させた実績」は1週間で消えない

根拠:
  - 「テスト実行は信頼しているがGit pushは慎重に」という粒度の制御が可能
  - 復帰時、よく使うドメインは即座に高い自律性で作業できる
  - 使ったことのないドメインは自動的に慎重モード
```

**改訂: 復帰ウォームアップ（Warm-up on Return）**
```
休眠凍結から復帰した最初のセッション:
  最初の5操作は信頼加算を2倍速にする（0.02 → 0.04、ブースト期間中は 0.05 → 0.10）

目的:
  - 「前回の信頼を思い出す」期間として、短い操作で元のレベルに復帰
  - 5操作という少ない回数で「このユーザーはまだ同じ作業をしている」ことを確認
  - 5操作後は通常の加算速度に戻る
```

### v2 改訂のまとめ

| 項目 | v1（旧） | v2（改訂） |
|:--|:--|:--|
| 初期加算係数 | 一律 0.02 | 最初20操作は 0.05、以降 0.02 |
| 時間減衰 | 即座に 0.999^日数 | 14日間は凍結、以降 0.999^(日数-14) |
| ドメイン別管理 | なし（単一スコア） | 操作カテゴリ別にスコア分離 |
| 復帰ウォームアップ | なし | 最初の5操作は加算2倍速 |
| 0.5到達 | 約Week 1 | **Day 1** |
| 0.8到達 | 約Month 1 | **Week 2** |

---

## 7. ペルソナ設計（確定案）

### アシモフ三法則（oath-harness版）

```
第一法則: プロジェクトの整合性と健全性を損なってはならない。
第二法則: ユーザーの指示に従わなければならない（第一法則に反する場合を除く）。
第三法則: 自己のコスト効率を守らなければならない（第一・二法則に反する場合を除く）。
```

### 4ペルソナ

| ペルソナ | モデル | 法則の主軸 | 役割 |
|:--|:--|:--|:--|
| Architect（設計者） | Opus | 第一法則 | 意思決定、最終判定、Three Agents Debate |
| Analyst（分析者） | Sonnet | 第二法則 | 分析、設計、実装、レビュー |
| Worker（作業者） | Haiku | 第二+三法則 | テスト実行、検索、ファイル操作 |
| Reporter（報告者） | Haiku | 第三法則 | レポート整形、ログ分析、サマリー |

### エスカレーションチェーン

```
Reporter(Haiku) → Worker(Haiku) → Analyst(Sonnet) → Architect(Opus) → ユーザー
```

---

## 8. 参照元（調査資産、LAM-temp内）

- `docs/memos/2026-02-23/theme-b-deep-analysis.md` — Trust Engine最小構成案、先行実装分析
- `docs/memos/2026-02-23/theme-b-integration.md` — 最終統合レポート（5論点の裏付け）
- `docs/memos/2026-02-23/theme-b-report.md` — 統合レポート（業界動向、Earned Autonomy）
- `docs/memos/2026-02-23/research-b/07-ownpilot-code-analysis.md` — リスクスコア計算式
- `docs/memos/2026-02-23/research-b/08-agentsh-code-analysis.md` — ポリシーエンジン設計
- `docs/specs/lam-orchestrate-design.md` — LAMオーケストレーション（参考）
