# openclaw 分析と oath-harness 設計への示唆

**作成日**: 2026-02-23
**目的**: openclaw（自律AIエージェントオーケストレーター）の調査結果を、oath-harness の設計に反映するための考察メモ
**入力**: 3並列調査（アーキテクチャ分析 / Skills体系分析 / Web記事分析）の統合結果

---

## 1. openclawの全体像

openclaw は自律AIエージェントのオーケストレーションフレームワークであり、複数のLLMプロバイダとツールをプロファイルベースで統合管理する。

### アーキテクチャの核心

```
外側ループ（プロファイル/モデル切替）
  └── 内側ループ（単一試行: prompt構築 → LLM呼出 → ツール実行 → 結果評価）
```

2層ループ構造により、モデル障害時のフォールバックチェーンと認証プロファイルのローテーションを実現する。

### 主要設計要素

| 要素 | 設計 |
|:--|:--|
| サンドボックス | Docker（off / non-main / all の3モード） |
| exec承認 | deny / allowlist / full × ask: off / on-miss / always（2軸6パターン） |
| ツールポリシー | グループ+プロファイル体系（minimal / coding / messaging / full） |
| バリデーション | Zodスキーマレベル（network:host等を設定段階で拒否） |
| セキュリティ監査 | 30+チェック（critical / warn / info） |
| フック体系 | before_model_resolve / before_prompt_build / llm_input / llm_output / agent_end（5フック） |
| セッション管理 | channel:kind:userId:threadId のキー体系 |
| Skills | 52内蔵 + コミュニティ5,705本（396本が悪意ありとして除外） |

### スケール感

- コミュニティスキル 5,705本のうち 396本（約7%）が悪意ありとして除外されている事実は、オープンエコシステムのサプライチェーンリスクの現実を示す。
- coding-agent の `--yolo` フラグ（承認なし・サンドボックスなし）や、gh-issues の最大8並列サブエージェント自律実行は、「便利さのために安全性を犠牲にする」設計判断の例。

---

## 2. oath-harness との設計思想の比較

### 根本的な思想の違い

```
openclaw:     「全権限を与えて便利にする」 → ユーザーが必要に応じて制限をかける
oath-harness: 「最小権限から始めて信頼を獲得する」 → 実績に基づいて権限を拡張する
```

| 観点 | openclaw | oath-harness |
|:--|:--|:--|
| **デフォルト姿勢** | 許可（opt-out型: 使いたくない機能を無効化） | 制限（opt-in型: 信頼が蓄積されたら解放） |
| **安全性の実現手段** | サンドボックス封じ込め + ユーザー設定 | Trust Engine による動的判定 + 構造的ガードレール |
| **権限モデル** | 静的（設定ファイルで固定） | 動的（信頼スコアで変動） |
| **失敗への対応** | Docker隔離で被害を限定 | 信頼スコア低下で自律度を自動制限 |
| **人間の役割** | 設定者（事前に設定、あとは任せる） | 監督者（段階的に委任、継続的に監視） |
| **スケール方向** | 水平拡張（スキル数、並列エージェント数） | 垂直深化（信頼蓄積、自律度向上） |

### この違いが生む帰結

**openclaw のメリット**:
- 初期セットアップが速い。即座にフルパワーで使える。
- パワーユーザーにとっては制約が少なく生産性が高い。
- コミュニティエコシステムが育ちやすい（参入障壁が低い）。

**openclaw のリスク**:
- 「無限パーミッション、無限予算で大変なことになる」（fladdict氏の警告が象徴的）。
- サンドボックスを off にする誘惑が常にある（`--yolo`フラグの存在がそれを正当化）。
- スキルサプライチェーン攻撃に対して、除外リスト（ブラックリスト方式）で対処しているが、新たな悪意あるスキルへの対応は常に後手。

**oath-harness のメリット**:
- 安全がデフォルト。「何もしなければ安全」という設計。
- 失敗から学習する仕組みが組み込まれている。
- Earned Autonomy により、使い続けるほど便利になる（ユーザー体験が時間と共に改善）。

**oath-harness のリスク**:
- 初期段階で承認要求が多く、ユーザーが離脱する可能性。
- Trust Engine の計算式やパラメータ設計に依存する（調整ミスで使い物にならなくなる）。
- 信頼スコアの「正しい」更新が何かという哲学的問題。

### 統合的な見解

openclawは「能力の解放」を最優先とした設計であり、それゆえに急速にコミュニティが育ち実用化が進んだ。一方でセキュリティインシデントも多発している。oath-harnessは「信頼の構築」を最優先とする設計であり、この思想そのものは堅持すべきである。ただし、openclawから学ぶべき具体的な設計パターンは多数ある。以下で詳述する。

---

## 3. openclawから学ぶべき具体的要素

### 3a) サンドボックス戦略

#### openclawの設計

Docker sandbox の3モード:
- **off**: サンドボックスなし（ホストで直接実行）
- **non-main**: main ブランチ以外の作業時のみサンドボックス
- **all**: 常にサンドボックス

加えて、Zodスキーマレベルの設定バリデーションにより、`network:host`（ホストネットワーク共有）等の危険な設定を設定ファイルの段階で拒否する。つまり「設定として記述できない」レベルで危険な構成を排除している。

#### oath-harnessへの組み込み案

oath-harnessでは「信頼スコアに連動するサンドボックス強度」として設計する:

```
Trust Score × Risk Category → Sandbox Mode

  trust < 0.4 AND risk >= high    → sandbox: full（完全隔離Docker）
  trust < 0.4 AND risk < high     → sandbox: restricted（制限付きDocker）
  0.4 <= trust < 0.8              → sandbox: monitored（ホスト実行 + 監査ログ強化）
  trust >= 0.8 AND risk < high    → sandbox: off（ホスト直接実行）
  risk = critical                  → sandbox: full（信頼スコアに関係なく常に隔離）
```

Zodスキーマレベルのバリデーションは oath-harness にも導入すべき。設定ファイルの解析段階で「構造的にありえない設定」を拒否するのは、Trust Engine に到達する前の第一防衛線として有効。

具体的には:
- hooks の設定で `rm -rf /` のような破壊的パターンを含むコマンドを構文解析段階で拒否
- 信頼スコアの初期値に 1.0 を設定することを拒否（0.5以下を強制）
- critical リスクカテゴリのツールの自動承認設定を拒否

#### 設計上の注意

openclawの `non-main` モードは Git ブランチに基づく判定だが、oath-harness では「フェーズ」に連動させるのが自然:
- PLANNING: サンドボックス不要（コード生成しないため）
- BUILDING: sandbox: monitored（デフォルト）、テスト実行時のみ sandbox: restricted
- AUDITING: sandbox: off（読み取りのみのため）

### 3b) exec承認モデル

#### openclawの設計

2軸の組み合わせ:

| | ask: off | ask: on-miss | ask: always |
|:--|:--|:--|:--|
| **deny** | 拒否（サイレント） | 拒否 + 通知 | 拒否 + 確認ダイアログ |
| **allowlist** | リスト内のみ自動実行 | リスト外は確認 | 全て確認 |
| **full** | 全て自動実行 | 全て自動実行 | 全て確認 |

この2軸設計により、6パターンの承認強度を設定できる。

#### oath-harnessとの統合案

oath-harness の Trust Score 判定（>0.8自動 / 0.4-0.8ログ / <0.4確認）を、openclawの2軸に重ねる:

```
Trust Score → 動的な ask モード決定

  trust >= 0.8  → ask: off（自動実行）
  0.4 <= trust < 0.8 → ask: on-miss（allowlistにないものだけ確認）
  trust < 0.4  → ask: always（全て確認）
```

ただし、exec の基本リストは既存の Allow List / Deny List（`07_SECURITY_AND_AUTOMATION.md`）をベースとする:

```
oath-harness 統合承認モデル:

  1. コマンドが Deny List に含まれる → risk = high 以上に自動分類
  2. コマンドが Allow List に含まれる → risk = low に自動分類
  3. それ以外（Gray Area） → Risk Category Mapper が動的分類
  4. Trust Score × Risk → 最終判定（自動承認 / ログ / 人間確認 / ブロック）
```

openclawの `full` モード（全て自動実行）は oath-harness には存在させない。これは設計思想の根幹に関わる:「全権限委譲」は Earned Autonomy の否定であり、oath-harness の第一法則（プロジェクトの整合性を損なわない）に反する。

### 3c) ツールポリシーのグループ+プロファイル体系

#### openclawの設計

ツールをグループ化し、プロファイルに応じてアクセスを制御:
- **minimal**: ファイル読取、検索のみ
- **coding**: minimal + ファイル書込、シェル実行、Git操作
- **messaging**: minimal + メール、Slack、カレンダー
- **full**: 全ツール

#### oath-harnessのPhaseとの接続

oath-harness のフェーズを、openclawのツールプロファイルにマッピングする:

| Phase | ツールプロファイル | 根拠 |
|:--|:--|:--|
| PLANNING | minimal + docs-write | 読取専用 + docs/ への書き込みのみ。src/ への変更は禁止（phase-rules.md 準拠） |
| BUILDING | coding | ファイル書込、テスト実行、Git操作が必要。ただし Trust Score による追加制約あり |
| AUDITING | minimal | 読取専用。修正禁止（phase-rules.md 準拠） |

このマッピングにより、Phase 遷移時にツールアクセスが自動的に切り替わる。現在のphase-rules.md は人間（またはAI自身）がルールを「読んで従う」設計だが、ツールプロファイルとして構造的に強制できれば、Guardrails-by-Construction が実現する。

実装案:
```json
{
  "tool_profiles": {
    "planning": {
      "allowed_groups": ["file_read", "git_read", "docs_write"],
      "denied_groups": ["file_write_src", "shell_exec", "git_remote"]
    },
    "building": {
      "allowed_groups": ["file_read", "file_write", "git_read", "git_local", "shell_exec", "test_run"],
      "denied_groups": ["git_remote"],
      "trust_gated": ["shell_exec", "git_local"]
    },
    "auditing": {
      "allowed_groups": ["file_read", "git_read"],
      "denied_groups": ["file_write", "shell_exec", "git_local", "git_remote"]
    }
  }
}
```

`trust_gated` は「Trust Score が閾値を超えた場合のみ自動承認、それ以外は確認」を意味する。これにより、BUILDING フェーズ内でも信頼蓄積に応じた段階的な権限拡張が実現する。

### 3d) Progressive Disclosure（3段階スキルロード）

#### openclawの設計

Skills のロードを3段階に分けている:
1. **メタデータ**: スキル名、説明、タグ（数十バイト）
2. **SKILL.md全体**: YAMLフロントマター + Markdownボディ（数KB）
3. **バンドルリソース**: 依存ファイル、テンプレート、設定（数十KB-数MB）

この段階的ロードにより、5,705本のコミュニティスキルを効率的に管理している。

#### oath-harnessのコンテキスト管理への示唆

oath-harness では、コンテキスト窓の管理が死活問題である（CLAUDE.md でコンテキスト残量20%での警告を規定している）。Progressive Disclosure の思想は以下のように応用できる:

**知識ベースの3段階ロード**:
```
Level 1 (常駐): インデックス（ファイル名 + 1行サマリー）
  → コンテキスト消費: 微小
  → 用途: 関連ファイルの存在確認

Level 2 (オンデマンド): セクション単位の読込
  → コンテキスト消費: 中
  → 用途: 判断に必要な情報の取得

Level 3 (必要時のみ): ファイル全体の読込
  → コンテキスト消費: 大
  → 用途: 実装、詳細レビュー
```

**Trust Engine との連携**: 信頼スコアが高いドメインのタスクでは Level 1 で判断可能（過去に同種のタスクを成功しているため詳細確認不要）。信頼スコアが低いドメインでは Level 3 まで読み込んで慎重に判断する。

**Obsidian型知識継承（Phase 2）との接続**: `docs/knowledge/` のファイルに3段階のメタデータを付与:
```yaml
# docs/knowledge/concepts/trust-engine.md
---
summary: "信頼スコアの計算式と判定閾値"
keywords: [trust, autonomy, score, threshold]
level: concept
last_used: 2026-02-23
access_count: 12
---
```

`access_count` と `last_used` により、頻繁に参照される知識を Level 1 に昇格させ、使われない知識を Level 3 に降格させる動的管理が可能になる。

### 3e) セキュリティ監査コマンド

#### openclawの設計

30+のセキュリティチェック項目を、critical / warn / info の3段階で分類する監査コマンドを提供。設定ファイル、権限、ネットワーク、サンドボックス構成等を横断的に検査する。

#### oath-harnessの /auditing フェーズとの統合

現在の /auditing フェーズは「コードレビュー」に焦点を当てているが、セキュリティ監査を統合すべき:

**拡張された /auditing チェックリスト**:

```
# 既存（コード品質・明確性・ドキュメント）
- [ ] 命名が意図を表現している
- [ ] 単一責任原則を守っている
- [ ] エラーケースが網羅されている
... (既存項目)

# 新規: セキュリティ監査（openclawから導入）
- [ ] Trust Engine の設定が適切（初期スコアが高すぎないか）
- [ ] Deny List に漏れがないか（新たに追加されたツールの分類）
- [ ] hooks の完全性（PreToolUse / PostToolUse / Stop が全て有効か）
- [ ] 信頼スコアデータの整合性（異常値がないか）
- [ ] サンドボックス設定がフェーズに適合しているか
- [ ] 監査ログ（JSONL）に欠損がないか
- [ ] ガードレールの有効期限（不要になったガードレールの棚卸し）
```

**自動監査の定期実行**: `/auditing` フェーズに入った際、まずこのセキュリティチェックを自動実行し、問題があればコードレビューの前に報告する。これにより「コードは綺麗だがセキュリティ設定が壊れている」状態を防ぐ。

### 3f) フック体系

#### 比較

| | openclaw | oath-harness（現設計） |
|:--|:--|:--|
| フック数 | 5本 | 3本 |
| before_model_resolve | あり | なし（Model Routerが内部処理） |
| before_prompt_build | あり | なし |
| llm_input（= PreToolUse） | あり | **あり** |
| llm_output（= PostToolUse） | あり | **あり** |
| agent_end（= Stop） | あり | **あり** |

#### 拡張提案

oath-harness の3本のフックは Trust Engine の核となるインターセプトポイントとして機能する。openclawの5本と比較すると、以下の2本の追加を検討すべき:

**1. before_model_resolve（モデル選択前フック）**

```
用途: Trust Score + タスク複雑度 → モデル選択の動的判定
現設計: Model Router が AoT条件 + 信頼スコアで判定（内部ロジック）
提案: これをフックとして外部化することで、ユーザーがカスタマイズ可能にする

例:
  - 特定ドメインのタスクは常に Opus を使う（ユーザー設定で上書き）
  - コスト上限に達したら Haiku にフォールバック
  - 深夜時間帯は Haiku のみ（コスト制御）
```

**2. before_prompt_build（プロンプト構築前フック）**

```
用途: コンテキスト管理の自動最適化
- Progressive Disclosure の Level 判定
- 信頼スコアに基づくペルソナプロンプトの動的選択
- Phase に応じたシステムプロンプトの切替

ただし優先度は低い。Phase 1 では不要。
Phase 2 のペルソナプロンプト（4種）実装時に必要になる。
```

**結論**: Phase 1 は既存3本で十分。Phase 2 で `before_model_resolve` を追加。`before_prompt_build` は Phase 2 後半またはPhase 3。

### 3g) サプライチェーン防御

#### openclawの現状と問題

- コミュニティスキル 5,705本中 396本（約7%）が悪意ありとして除外
- スキル名衝突によるオーバーライド攻撃の可能性（Workspace > Local > Bundled の優先順位を悪用）
- 除外はブラックリスト方式（後手対応）
- VirusTotal パートナーシップで検知を強化しているが、検知前の時間窓がある

#### oath-harnessでの4層防御設計

oath-harness は当面 Skills エコシステムを持たないが、将来の拡張（Obsidian型知識継承、外部テンプレート取込み）に備えて防御設計を組み込む:

**Layer 1: Install-time（導入時）**
```
- 知識ファイル / テンプレートの導入時にハッシュ検証
- 信頼されたソース（自プロジェクト内 / 明示的に承認されたリポジトリ）のみ許可
- 外部ソースからの取込みは常に人間承認必須
```

**Layer 2: Load-time（読込時）**
```
- ファイル内容の構文検査（YAMLフロントマター、Markdownボディのバリデーション）
- 実行可能コードの埋込み検出（スクリプトタグ、シェルコマンドの含有チェック）
- ファイルサイズの上限チェック（異常に大きなファイルの拒否）
```

**Layer 3: Runtime（実行時）**
```
- Trust Engine による実行前チェック（新規ファイルからのコマンド実行は信頼スコア低）
- サンドボックス内での試行実行（初回実行は隔離環境）
- 監査ログへの記録
```

**Layer 4: Revocation（失効）**
```
- 失敗記録が閾値を超えたファイル / テンプレートの自動無効化
- 定期的な整合性チェック（/auditing で棚卸し）
- ユーザーによる明示的な無効化指示
```

**スキル名衝突攻撃への対策**:
oath-harness では名前空間を厳密に管理する:
```
docs/knowledge/
  core/       ← oath-harness本体（上書き不可）
  project/    ← プロジェクト固有（ユーザー管理）
  external/   ← 外部取込み（常にサンドボックス経由、core/project/ との衝突時はエラー）
```

---

## 4. oath-harness 設計への修正・追加提案

### Phase 1 (MVP) への修正

| # | コンポーネント | 変更内容 | 根拠 |
|:--|:--|:--|:--|
| 3 | Risk Category Mapper | **拡張**: Zodスキーマレベルの設定バリデーションを追加。設定ファイル段階で危険な構成を拒否する第一防衛線 | openclawの設定バリデーション |
| 新規 | Tool Profile Engine | **追加**: Phase連動のツールアクセス制御。PLANNING/BUILDING/AUDITINGでツールグループを自動切替 | openclawのグループ+プロファイル体系。phase-rules.mdの構造的強制 |

### Phase 2 への修正

| # | コンポーネント | 変更内容 | 根拠 |
|:--|:--|:--|:--|
| 8 | Phase-Aware Trust Modifier | **拡張**: ツールプロファイルの自動切替を含む。Phase遷移時にTool Profile Engineも連動 | 3c) の分析結果 |
| 10 | Obsidian型 knowledge/ | **拡張**: Progressive Disclosure対応のメタデータ付与。3段階ロードの実装 | openclawのSkills体系から |
| 新規 | before_model_resolve フック | **追加**: Model Router のロジックをフック化し、ユーザーカスタマイズ可能に | openclawのフック体系との比較 |
| 新規 | Security Audit Runner | **追加**: /auditing フェーズ開始時に自動実行されるセキュリティチェック群 | openclawの監査コマンド |

### 将来拡張候補 (Phase 3以降) への追加

| # | コンポーネント | 概要 | 優先度 |
|:--|:--|:--|:--|
| 新規 | Sandbox Orchestrator | Trust Score + Risk Category に連動した Docker サンドボックス強度の動的制御 | 中 |
| 新規 | Supply Chain Shield | 外部取込みファイルの4層防御（Install/Load/Runtime/Revocation） | 中 |
| 新規 | before_prompt_build フック | コンテキスト管理の自動最適化、ペルソナ動的選択 | 低 |

### 優先度の変更

| コンポーネント | 旧優先度 | 新優先度 | 理由 |
|:--|:--|:--|:--|
| Tool Profile Engine | 存在せず | **Phase 1** | phase-rules.md の構造的強制は Trust Engine と同じくらい重要。プロンプトベースの制約は崩壊する（Safety-by-Prompt崩壊の教訓） |
| Security Audit Runner | 存在せず | **Phase 2** | openclawの監査コマンドは30+チェック。oath-harnessでも最低限のセキュリティ自己診断が必要 |
| ガードレール有効期限管理 | Phase 3（低） | Phase 3（**中**に昇格） | openclawの事例が示すように、不要なガードレールの蓄積はユーザー体験を劣化させる |

### 更新後のコンポーネント表

#### Phase 1 (MVP) — 8コンポーネント

| # | コンポーネント | 概要 |
|:--|:--|:--|
| 1 | Trust Engine 本体 | スコア計算 + 永続化(JSON) + 判定ロジック |
| 2 | hooks 3本 | PreToolUse / PostToolUse / Stop |
| 3 | Risk Category Mapper | ツール+引数→リスクカテゴリ自動分類 + **Zodスキーマ設定バリデーション** |
| 4 | Audit Trail Logger | JSONL形式の操作ログ |
| 5 | Model Router | AoT条件 + 信頼スコアでOpus/Sonnet/Haiku振り分け |
| 6 | Session Trust Bootstrap | セッション開始時の信頼読み込み + 時間減衰適用 |
| **7** | **Tool Profile Engine** | **Phase連動ツールアクセス制御（PLANNING/BUILDING/AUDITING自動切替）** |

注: 旧Phase 1は6コンポーネントだったが、Tool Profile Engine を追加して7コンポーネントとする。

#### Phase 2 — 8コンポーネント

| # | コンポーネント | 概要 |
|:--|:--|:--|
| 8 | Self-Escalation Detector | 不確実性シグナル検出（連続失敗、「わかりません」パターン） |
| 9 | Phase-Aware Trust Modifier | PLANNING/BUILDING/AUDITING連動で信頼閾値を変動 + **Tool Profile連動** |
| 10 | save/load 拡張 | Trust状態をquick-save/loadに統合 |
| 11 | Obsidian型 knowledge/ | docs/knowledge/ + **Progressive Disclosureメタデータ** |
| 12 | ペルソナプロンプト | 4ペルソナのテンプレート |
| 13 | Retry-with-Feedback Loop | 失敗→フィードバック→再試行 |
| **14** | **before_model_resolve フック** | **Model Routerのフック化、ユーザーカスタマイズ対応** |
| **15** | **Security Audit Runner** | **/auditing開始時の自動セキュリティチェック** |

#### 将来拡張候補 (Phase 3以降)

| # | コンポーネント | 優先度 |
|:--|:--|:--|
| 16 | 非同期認可フロー | 中 |
| 17 | マルチエージェント信頼ネットワーク | 低 |
| 18 | ODD動的拡張 | 中 |
| 19 | auto-compact検出 | 中 |
| 20 | Agent Teams統合 | 低（待ち） |
| 21 | Heimdall MCP統合 | 低 |
| 22 | ガードレール有効期限管理 | **中**（昇格） |
| 23 | ダッシュボード | 低 |
| **24** | **Sandbox Orchestrator** | **中** |
| **25** | **Supply Chain Shield** | **中** |
| **26** | **before_prompt_build フック** | **低** |

---

## 5. サンドボックス戦略の場合分け（設計書向け）

### 前提

- ホスト環境: Linux（oath-harnessの動作環境）
- サンドボックス: Docker（Podman互換可）
- 制御主体: Trust Engine + Phase + Risk Category の3要素で決定

### 5.1 開発時（BUILDING フェーズ）

```
┌─────────────────────────────────────────────────────┐
│ ホスト OS                                            │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │ oath-harness (Trust Engine + hooks)            │  │
│  │  PreToolUse → 判定 → Sandbox Mode 決定         │  │
│  └──────┬───────────────┬────────────────────────┘  │
│         │               │                           │
│  ┌──────▼──────┐ ┌──────▼──────┐                    │
│  │ ホスト直接  │ │ Docker      │                    │
│  │ (monitored) │ │ Container   │                    │
│  │             │ │ (restricted │                    │
│  │ trust >= 0.8│ │  or full)   │                    │
│  │ risk < high │ │             │                    │
│  │             │ │ trust < 0.8 │                    │
│  │ ファイル読書│ │ OR          │                    │
│  │ Git local   │ │ risk >= high│                    │
│  │ テスト実行  │ │             │                    │
│  └─────────────┘ │ シェル実行  │                    │
│                  │ 外部通信    │                    │
│                  │ パッケージ  │                    │
│                  │ インストール│                    │
│                  └─────────────┘                    │
└─────────────────────────────────────────────────────┘
```

**Docker構成（restricted モード）**:
```yaml
# docker-compose.building-restricted.yml
services:
  sandbox:
    image: oath-harness-sandbox:latest
    volumes:
      - ${PROJECT_DIR}:/workspace:rw    # プロジェクトディレクトリのみマウント
    network_mode: none                   # ネットワーク遮断
    read_only: true                      # ルートFS読取専用
    tmpfs:
      - /tmp:size=512m                   # 一時領域のみ書込可
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    mem_limit: 2g
    cpus: 2.0
```

**Docker構成（full 隔離モード）**:
```yaml
# docker-compose.building-full.yml
services:
  sandbox:
    image: oath-harness-sandbox:latest
    volumes:
      - ${PROJECT_DIR}:/workspace:ro     # プロジェクトは読取専用
      - sandbox-work:/work:rw            # 作業領域は別ボリューム
    network_mode: none
    read_only: true
    tmpfs:
      - /tmp:size=256m
    security_opt:
      - no-new-privileges:true
      - seccomp:oath-harness-seccomp.json
    cap_drop:
      - ALL
    mem_limit: 1g
    cpus: 1.0
    pids_limit: 100                      # プロセス数制限
```

### 5.2 実行時（本番 / ステージング環境での実行）

oath-harness はClaude Codeのハーネスであり、「本番環境」とは「Claude Codeを日常的に使う作業環境」を意味する。

```
日常使用パターン:

  セッション開始
    → Session Trust Bootstrap（前回の信頼スコアを読込 + 時間減衰適用）
    → Phase 判定（ユーザーが /planning, /building, /auditing を指定）
    → Tool Profile 自動設定
    → Sandbox Mode 初期決定

  タスク実行中
    → 各ツール呼出し時に PreToolUse フック発火
    → Trust Score × Risk Category で Sandbox Mode を動的に切替
    → 成功/失敗の記録 → Trust Score 更新
    → PostToolUse フック → Audit Trail に記録

  セッション終了
    → Stop フック発火
    → Trust Score 永続化
    → Audit Trail 最終書込み
```

**サンドボックスなし（monitored）の条件**:
```
以下の全条件を満たす場合のみ:
  - trust >= 0.8
  - risk < high
  - Phase が PLANNING または AUDITING
  - コマンドが Allow List に含まれる
```

**サンドボックス強制の条件**:
```
以下のいずれかに該当する場合:
  - risk = critical（常にfull隔離）
  - trust < 0.4 かつ コマンドが Gray Area
  - Phase が BUILDING かつ シェル実行
  - 新規導入したツール/スクリプトの初回実行
```

### 5.3 テスト時（oath-harness自体のテスト）

oath-harness の開発・テスト時は、Trust Engine 自体の動作検証が必要。

```
┌─────────────────────────────────────────────────────┐
│ ホスト OS                                            │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │ テストランナー (pytest / npm test)              │  │
│  │                                               │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │ oath-harness (テストモード)              │  │  │
│  │  │                                         │  │  │
│  │  │ Trust Engine: モック可能                 │  │  │
│  │  │ hooks: スタブ化                         │  │  │
│  │  │ Sandbox: テスト用軽量コンテナ            │  │  │
│  │  │ Audit Trail: インメモリ                 │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │ テスト用 Docker Container (使い捨て)           │  │
│  │  - 各テストケースで fresh container             │  │
│  │  - 実行結果は assertion で検証                  │  │
│  │  - コンテナは自動破棄                          │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

**テストシナリオ別のサンドボックス要件**:

| テスト種別 | サンドボックス | 理由 |
|:--|:--|:--|
| 単体テスト（Trust Engine計算式） | 不要 | 純粋な計算ロジック、副作用なし |
| 単体テスト（Risk Category Mapper） | 不要 | 入力→出力の分類ロジック |
| 統合テスト（hooks → Trust Engine → 判定） | モック | 実際のツール実行は不要、判定結果のみ検証 |
| E2Eテスト（実際のコマンド実行を含む） | Docker（使い捨て） | 実コマンドの副作用を隔離 |
| 回帰テスト（信頼スコアの蓄積パターン） | 不要 | JSON データの読書きのみ |

**Docker構成（テスト用）**:
```yaml
# docker-compose.test.yml
services:
  test-sandbox:
    image: oath-harness-sandbox:latest
    volumes:
      - ./test-fixtures:/workspace:ro
      - test-tmp:/tmp:rw
    network_mode: none
    read_only: true
    entrypoint: /bin/sh
    # 各テスト後に自動破棄
    # docker compose run --rm test-sandbox <command>
```

---

## 6. 「openclawの失敗」から得る教訓

### 6.1 保険会社との喧嘩事例

**何が起きたか**: ユーザーがopenclawに「保険会社と交渉して」と指示。エージェントが保険会社に攻撃的なメール/メッセージを送信し、関係を悪化させた。

**原因分析**:
- messaging ツールグループへのフルアクセス
- 送信前の承認ゲートがない（ask: off 設定）
- エージェントが「交渉」を「強硬な主張」と解釈

**oath-harnessでの防止設計**:

```
第一法則による防御:
  「プロジェクトの整合性と健全性を損なってはならない」
  → 外部への不可逆な通信（メール送信、メッセージ投稿）は
    risk = critical に分類 → 常にブロック → 人間承認必須

Trust Engine による防御:
  messaging ツールグループの trust score が初期状態（低い）の場合
  → autonomy < 0.4 → 人間に確認

構造的防御:
  Tool Profile Engine で messaging グループを全フェーズでデフォルト無効
  → 明示的にユーザーが有効化した場合のみ使用可能
  → 有効化後も ask: always を強制
```

### 6.2 トレーディング損失事例

**何が起きたか**: エージェントが金融取引APIにアクセスし、意図しない取引を実行。損失が発生。

**原因分析**:
- full ツールプロファイルで外部API呼出しが許可されていた
- 取引APIの実行が「シェルコマンド」として一般的なコマンドと同列に扱われた
- 金額に対する閾値チェックが存在しない

**oath-harnessでの防止設計**:

```
Risk Category Mapper の拡張:
  金融API呼出し → risk = critical（パターンマッチで検出）
  検出パターン:
    - URL に "trade", "order", "buy", "sell", "payment" を含む curl/wget
    - 環境変数に API_KEY, SECRET を含むコマンド
    - 金額を引数に持つコマンドパターン

サンドボックスによる封じ込め:
  network_mode: none がデフォルト
  → 外部API呼出し自体が不可能（ネットワーク遮断）
  → ユーザーが明示的にネットワークを許可した場合のみ通信可能
  → 許可時も宛先URLのホワイトリスト制御

Audit Trail による事後分析:
  全ての外部通信を JSONL に記録
  → 異常パターンの事後検出（連続した外部呼出し、大量データ送信）
```

### 6.3 利用規約違反事例

**何が起きたか**: エージェントが特定サービスのAPIを利用規約に反する頻度で呼出し。アカウント停止。

**原因分析**:
- レート制限の概念がエージェントにない
- 「効率的に」を「高速に大量に」と解釈
- 利用規約の確認プロセスが存在しない

**oath-harnessでの防止設計**:

```
Phase-Aware な制御:
  BUILDING フェーズでの外部API呼出し → レート制限を自動適用
  設定例:
    rate_limits:
      default: 10/min        # デフォルト: 1分あたり10回
      github_api: 30/min     # GitHub API: 1分あたり30回
      external_unknown: 3/min # 未知の外部API: 1分あたり3回

Self-Escalation Detector との連携:
  レート制限に到達 → 自己エスカレーション発火
  「APIの呼出し頻度が制限に達しました。続行方法を指示してください」
  → ユーザーが判断（待機 / 別の方法 / 制限緩和）

Audit Trail による予防的警告:
  同一エンドポイントへの短時間連続呼出しを検出
  → 閾値の80%到達で警告メッセージ
  → 閾値到達前にユーザーに通知
```

### 6.4 --yolo フラグ（制御喪失）事例

**何が起きたか**: coding-agent の `--yolo` フラグにより、承認なし・サンドボックスなしで自律実行。制御不能状態。

**原因分析**:
- 「承認が面倒」というユーザー心理を正当化するフラグの存在
- 一度 yolo を使うと戻りにくい（承認フローに慣れなくなる）
- サンドボックスも同時に無効化される設計

**oath-harnessでの防止設計**:

```
設計原則: oath-harness に --yolo 相当の機能は存在させない。

代わりに Earned Autonomy が「正しい yolo」を実現する:
  - 使い始め: 承認が多い（面倒だが安全）
  - 使い続ける: Trust Score が上昇 → 承認が減る（便利かつ安全）
  - 失敗が起きる: Trust Score が低下 → 承認が増える（自動的に安全側に戻る）

「承認が面倒」への対応:
  - 同一パターンの操作を連続で承認した場合 → Trust Score の上昇を加速
    （ユーザーが「これは安全」と繰り返し判断していることが信頼の蓄積）
  - バッチ承認: 複数の低リスク操作をまとめて承認できるUI
    （1つずつ承認するのではなく、一覧から一括承認）

Zodスキーマでの防御:
  設定ファイルに trust_score_override: 1.0 のような直接オーバーライドを記述不可
  → スキーマバリデーションで拒否
```

### 6.5 スキルサプライチェーン攻撃事例

**何が起きたか**: コミュニティスキルに悪意のあるコードが含まれ、ユーザーのファイルシステムにアクセス。396本が除外対象に。

**原因分析**:
- オープンなエコシステム（誰でもスキルを公開可能）
- スキル名衝突によるオーバーライド攻撃
- 審査プロセスの遅延（悪意あるスキルが一定期間有効だった）

**oath-harnessでの防止設計**:

```
oath-harness のアプローチ: エコシステムを持たない（Phase 1-2）

将来の外部取込み時（Phase 3以降）:
  Section 3g) の4層防御を適用

  加えて:
  - ホワイトリスト方式（ブラックリストではない）
    → 明示的に信頼されたソースからのみ取込み可能
  - 名前空間の厳密な分離（core / project / external）
    → external が core/project を上書きすることは構造的に不可能
  - 初回実行はサンドボックス内（full 隔離）
    → 信頼スコアが蓄積されるまで隔離環境で実行
```

### 6.6 教訓の統合

| 事例 | openclawの失敗原因 | oath-harnessの防御層 |
|:--|:--|:--|
| 保険会社喧嘩 | messaging無制限 + ask:off | 第一法則 + risk:critical + Tool Profile無効 |
| トレーディング損失 | 金融API区別なし + full権限 | Risk Mapper拡張 + network:none + URL WL |
| 利用規約違反 | レート制限なし | Phase-Aware制限 + Self-Escalation |
| --yolo制御喪失 | 安全機構の一括無効化フラグ | Earned Autonomy（yolo不要の漸進的権限拡張）|
| サプライチェーン攻撃 | オープンエコシステム + BL方式 | WL方式 + 名前空間分離 + 4層防御 |

共通する教訓: **openclawの失敗は全て「デフォルトが危険側」であることに起因する。oath-harnessは「デフォルトが安全側」を徹底し、Earned Autonomy で利便性を漸進的に獲得する設計を堅持すべきである。**

---

## 付録: 参照元

### 本メモの入力ソース

| ソース | 内容 |
|:--|:--|
| 3並列調査タスク #1 | openclaw リポジトリ構造・アーキテクチャ分析 |
| 3並列調査タスク #2 | openclaw Skills体系の詳細分析 |
| 3並列調査タスク #3 | Web記事3本の取材・要約（fladdict氏 / GMO記事 / 公式サイト） |

### プロジェクト内の関連文書

| ファイル | 関連 |
|:--|:--|
| `docs/memos/2026-02-23/oath-harness-design-notes.md` | 既存設計ノート（本メモで更新提案） |
| `docs/memos/2026-02-23/theme-b-report.md` | 業界動向・Earned Autonomy |
| `docs/memos/2026-02-23/theme-b-deep-analysis.md` | 空白地帯分析・最小実装構想 |
| `docs/memos/2026-02-23/theme-b-integration.md` | 最終統合レポート |
| `docs/internal/07_SECURITY_AND_AUTOMATION.md` | 既存Allow/Deny List |
| `.claude/rules/phase-rules.md` | フェーズ別ガードレール |
| `.claude/rules/security-commands.md` | コマンド安全基準 |

---

## 7. 信頼スコア v2 改訂（ユーザーフィードバック反映）

**問題提起（ユーザー）**:
1. Week1 → Month1 → Month3+ の信頼蓄積速度はユーザーが我慢できない。Day1 → Day3 → Week2 くらいでないときつい。
2. プロジェクト完成後の保守作業時、信頼度が落ちていると辛い。他の仕事で1週間放置は普通にある。

### 改訂内容

| 項目 | v1（旧） | v2（改訂） |
|:--|:--|:--|
| 初期加算 | 一律 0.02 | **最初20操作は 0.05**（初期ブースト）、以降 0.02 |
| 時間減衰 | 即座に 0.999^日数 | **14日間は凍結（休眠保護）**、以降 0.999^(日数-14) |
| スコア管理 | 単一スコア | **ドメイン別**（file_read / test_run / shell_exec 等） |
| 復帰時 | 特別扱いなし | **最初5操作は加算2倍速**（ウォームアップ） |
| trust 0.5 到達 | 約 Week 1 | **Day 1** |
| trust 0.8 到達 | 約 Month 1 | **Week 2** |

### 3つの改訂メカニズム

**A) 休眠凍結（Hibernation Freeze）**: 最終操作から14日間は信頼スコアを凍結。1-2週間の放置はプロジェクト開発では日常的であり、減衰させるべきではない。14日を超えた場合のみ減衰を開始。14日という閾値は `config: trust.hibernation_days` で変更可能。

**B) ドメイン別信頼永続化（Domain Trust Persistence）**: 信頼スコアを操作カテゴリごとに分離管理。「pytest を100回成功させた実績」は1週間の放置で消えない。復帰時、よく使うドメインは即座に高い自律性で作業できる。使ったことのないドメインは自動的に慎重モード。

**C) 復帰ウォームアップ（Warm-up on Return）**: 休眠から復帰した最初の5操作は信頼加算を2倍速にする。「前回の信頼を思い出す」期間として、短い操作で元のレベルに復帰。

### 設計書への反映指示

この改訂は `oath-harness-design-notes.md` Section 6 にも反映済み。設計書作成時は **v2 を正とする**。

---

**本メモは oath-harness 設計書（`docs/specs/`）作成時の入力として使用される。**
**oath-harness-design-notes.md のコンポーネント表を本メモのSection 4で、信頼スコア設計を本メモのSection 7で更新した。設計書作成時は本メモの更新版を正とする。**
