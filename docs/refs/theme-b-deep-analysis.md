# Theme B 深掘り考察: 先行実装の地図と個人が踏み込める領域

**作成日**: 2026-02-23
**取材ソース**: research-b/01〜06（計100+プロジェクト・75+文献）
**前提**: theme-b-report.md の統合レポートを踏まえた深掘り

---

## 1. 地図: 誰が何をどこまで作っているか

### 1.1 ベンダーの本気度マップ

| ベンダー | プロジェクト | Stars | 方向性 | 本気度 |
|:--|:--|:--|:--|:--|
| **LangChain** | DeepAgents | 9,484 | ハーネス（計画・サブエージェント・コンテキスト管理） | ★★★★★ |
| **Anthropic** | Claude Code + Agent SDK | 68,911 | ランタイム + hooks + プラグインエコシステム | ★★★★★ |
| **Microsoft** | Agent Framework + Control Plane | — | エンタープライズガバナンス、プラットフォーム層 | ★★★★ |
| **NVIDIA** | NeMo Guardrails | 5,682 | 会話AIガードレール（Colang DSL） | ★★★ |
| **OpenAI** | Codex + Agents SDK | — | サンドボックス封じ込め + 並列ガードレール | ★★★★ |
| **GitHub** | Agentic Workflows | ~3,400 | CI/CD統合、read-onlyデフォルト | ★★★ |

**結論: ベンダーは「本気で来ている」。だが方向がそれぞれ違う。**

- LangChain → ハーネスに全賭け（「ガードレールは一時的」と公言）
- Anthropic → ランタイム支配（Claude Code が GitHub 全 public commit の4%）
- Microsoft → ガバナンスのプラットフォーム化
- OpenAI → 封じ込め（サンドボックスが防壁）

### 1.2 個人・小チームの活動マップ

| プロジェクト | Stars | 特徴 | 生存理由 |
|:--|:--|:--|:--|
| **Pi** (badlogic) | — | 4ツール+300語プロンプト | 極端なミニマリズム |
| **agentsh** | 35 | SELinux的ポリシー強制 | OS思想の移植という独自性 |
| **agent-os** | 55 | POSIX的プリミティブ | 「カーネルが決める」哲学 |
| **mcp-human-loop** | 16 | 多次元スコアリング | 数理的アプローチ |
| **OwnPilot** | 95 | 5段階自律度+リスクスコア | 最も完成度が高い可変自律 |
| **OpenAgentsControl** | 2,162 | 計画先行+承認ゲート | 速度より安全を優先する層 |
| **MoAI-ADK** | — | 仕様先行+TDD+28エージェント | ニッチ（Go単一バイナリ） |
| **Copilot Orchestra** | — | TDDオーケストレーション | VSCode公式が取り上げ |
| **Claudekit** | — | Claude Code用ツールキット | エコシステム拡張 |

**生存している個人プロジェクトの共通点: ベンダーが「万人向け」にしようとしない思想的ニッチを攻めている。**

---

## 2. 決定的な空白地帯

### 2.1 誰も実装していないもの: Earned Autonomy

**Supervised Autonomy**（静的チェックポイント）は多数存在する。
**Earned Autonomy**（実績に基づいてチェックポイント頻度が動的に変化する）は **ゼロ**。

```
現状の風景:

[完全手動] ← 多数のプロジェクト → [静的チェックポイント] ← 多数 → [完全自律(Ralph)]
                                                          ↑
                                                     ここに空白
                                                  「動的信頼蓄積」
                                                   誰もいない
```

Anthropicの実証データ（Claude Code 750セッション）は Earned Autonomy が
**ユーザー行動として自然に起きている**ことを示している。
だが、それを**システムとして実装した**プロジェクトはない。

### 2.2 誰も統合していないもの: 5要素の結合

調査した100+プロジェクト全てを横断した結果:

```
            ハーネス  ガードレール  Trust    段階的    カーネル
            パターン  by-Constr.  Engine   HITL     強制
            -------  ----------  ------   -----    ------
Deep Agents   +++       -          -        +        -
Parlant        +       +++         -        +        -
LangGraph      +        -          -       +++       -
Agno          ++        +          -        +       +++
agentsh        -        +          +        ++       +++
Claude Code  +++        +          -        +        ++

→ 5列全てに「+++」が入るプロジェクトは存在しない
```

---

## 3. ベンダーに潰されるか？ の分析

### 3.1 潰される領域（手を出すべきでない）

| 領域 | 理由 | ベンダー |
|:--|:--|:--|
| 汎用エージェントループ | 規模の経済が効く | LangGraph, CrewAI |
| IDE統合 | プラットフォーム優位性 | Copilot, Cursor, Claude Code |
| クラウドデプロイ | インフラ投資が必要 | AWS, Azure, GCP |
| エンタープライズガバナンス | 営業力が必要 | Microsoft, Forrester |

### 3.2 潰されない領域（個人が攻められる）

| 領域 | なぜ潰されないか | 根拠 |
|:--|:--|:--|
| **思想的にユニークなフレームワーク** | ベンダーは中庸を目指す | Pi(4ツール)が14.5万stars、agentsh(SELinux思想)が独自路線 |
| **Constitutional governance** | プロジェクト固有すぎて汎用化不可 | Spec-Kit, CLAUDE.md パターン |
| **TDD強制ワークフロー** | ベンダーは速度を優先する | tddGPT, MoAI-ADK |
| **Trust Engine / Earned Autonomy** | **まだ誰も作っていない** | 空白地帯（3.1参照） |
| **Claude Code エコシステム拡張** | Anthropicはプラグインを歓迎 | 24,632 stars の awesome-claude-code |
| **ドメイン特化オーケストレーター** | 万人向けFWでは不十分 | ゲーム開発、セキュリティ等 |

### 3.3 判定

**Trust Engine / Earned Autonomy は「まだ誰もいない」+「ベンダーが汎用化しにくい」の二重条件を満たす。**

理由:
- 信頼スコアの計算式はドメイン/プロジェクト依存（汎用化しにくい）
- 人間との信頼構築は個人の行動パターンに依存（万人向け不可）
- ベンダーの関心は「安全なデフォルト設定」であり「動的な信頼蓄積」ではない
- Anthropic自身が「ユーザーの監視パターンは進化する」と観測しているが、それを自動化するプロダクトは出していない

---

## 4. 自作するなら何を作るか

### 4.1 最小構成: Trust-Aware Hook Layer

Claude Code の hooks システムの上に、Trust Engine を載せる。

```
Claude Code (既存)
  │
  ├── PreToolUse hook ──→ Trust Engine が自律度を判定
  │                          ├── 高信頼 + 低リスク → 自動承認
  │                          ├── 中信頼 or 中リスク → ログのみ
  │                          └── 低信頼 or 高リスク → 人間に確認
  │
  ├── PostToolUse hook ──→ 結果を記録、信頼スコア更新
  │
  └── Stop hook ──────→ セッション終了時に信頼データ永続化
```

**これだけなら1ファイル+設定で実装できる。**

### 4.2 信頼スコアの最小実装

```
trust_score = {
  "tool_category": {
    "file_read":     { "score": 0.9, "successes": 47, "failures": 1 },
    "file_write":    { "score": 0.7, "successes": 23, "failures": 3 },
    "bash_command":  { "score": 0.5, "successes": 12, "failures": 4 },
    "git_push":      { "score": 0.3, "successes": 2,  "failures": 1 }
  }
}

// ツールカテゴリごとに信頼度が違う（file_read は安全、git_push は危険）
// 成功/失敗の履歴で信頼度が変動
// 非対称更新: 成功 → +0.01、失敗 → -0.1（信頼は築くのに時間がかかり、失うのは一瞬）
```

### 4.3 学習として何が得られるか

| 実装すること | 学べること |
|:--|:--|
| Trust Engine の数式設計 | 信頼の数理モデル、非対称ダイナミクス |
| hooks でのインターセプト | Claude Code の内部構造、イベント駆動設計 |
| 信頼データの永続化 | セッションを超えた状態管理 |
| 自律度の判定ロジック | リスク評価、ODD（運用設計領域）の概念 |
| 自己エスカレーション | エージェントが「自分には無理」と判断する条件設計 |

---

## 5. 先行者との位置関係

### 5.1 最も近い先行者

| プロジェクト | 距離 | 何が足りないか |
|:--|:--|:--|
| **OwnPilot** (95★) | 最も近い | フィードバックループがない（静的5段階） |
| **mcp-human-loop** (16★) | 概念は近い | 永続的学習がない、プロトタイプ品質 |
| **agentsh** (35★) | 思想は近い | Trust Engine がない、純粋にポリシー強制のみ |
| **Cline auto-approve** (58K★) | 部分的に近い | ユーザー手動設定、自動調整なし |

**→ 4つとも「あと一歩」で Earned Autonomy に届くが、その一歩を誰も踏み出していない。**

### 5.2 LAMの独自性

調査した100+プロジェクトの中で、LAMの **Three Agents Model（Affirmative/Critical/Mediator）** を
実装しているプロジェクトは**ゼロ**。構造化された議論モデルでの意思決定はLAMのユニーク要素。

---

## 6. 推奨アクション

### 6.1 今すぐ作れるもの（学習用プロトタイプ）

**「Trust-Aware Claude Code Hook」** — 1〜2日で作れる最小構成:

1. `PreToolUse` hook: ツールカテゴリとリスクを判定、信頼スコアに基づいて承認/ログ/ブロック
2. `PostToolUse` hook: 結果を記録、信頼スコア更新
3. JSON ファイルで信頼データを永続化
4. セッション開始時に信頼データを読み込み

**これを実際に自分で使いながら、OwnPilot/mcp-human-loop/agentsh のコードを読む。**

### 6.2 もう少し踏み込むなら

- OwnPilot のリスクスコアリングを fork して Trust Engine を追加する
- mcp-human-loop の多次元スコアリングを永続化対応に拡張する
- agentsh の SELinux 的ポリシーに信頼度レイヤーを追加する

### 6.3 LAMの次のステップとして

LAMの既存構造はそのままで、Trust Engine を CLAUDE.md + hooks で実装する。

```
CLAUDE.md（憲法）  ←── 既存
phase-rules.md     ←── 既存（静的ガードレール）
trust-engine.json  ←── 新規（動的信頼スコア）
hooks/trust.sh     ←── 新規（hook でインターセプト）
```

---

## 7. リスクと注意点

### 7.1 ベンダーが追いつくリスク

LangChainは「ハーネスエンジニアリングが恒久的投資」と明言している。
Anthropicは信頼の動態を既に観測している。
**1年以内にベンダーが Earned Autonomy を実装する可能性は高い。**

→ だからこそ**今**学習として自作する意味がある。ベンダーが出してからでは「使うだけの人」になる。先に概念を理解し、自分の設計判断で実装した経験があれば、ベンダー製が出ても「評価できる人」になれる。

### 7.2 過剰投資のリスク

自作は「学習目的」と割り切る。プロダクション品質を目指すと、1人では維持できない。
目標は「概念を体得する」であり「世界一のフレームワークを作る」ではない。

### 7.3 LangChainの警告を真剣に受け止める

> ガードレールは一時的。モデルが改善すれば溶ける。

→ 今作るガードレール部分は、モデルが賢くなれば不要になる。
**だからこそ、ガードレールの実装に時間をかけすぎない。**
Trust Engine（信頼蓄積の仕組み）こそが残る価値。

---

## 参考プロジェクト一覧（自作時に読むべきコード）

| 優先度 | プロジェクト | 何を学ぶか | URL |
|:--|:--|:--|:--|
| ★★★ | OwnPilot | 5段階自律度+リスクスコア | github.com/ownpilot/OwnPilot |
| ★★★ | mcp-human-loop | 多次元スコアリングゲート | github.com/boorich/mcp-human-loop |
| ★★★ | agentsh | SELinux的ポリシー強制 | github.com/canyonroad/agentsh |
| ★★ | agent-os | POSIX的「カーネルが決める」 | github.com/imran-siddique/agent-os |
| ★★ | Claude Code hooks-mastery | hook実装パターン | github.com/disler/claude-code-hooks-mastery |
| ★★ | Pi (badlogic) | 極端なミニマリズムの威力 | github.com/badlogic/pi-mono |
| ★ | Parlant | 宣言的ポリシー分離 | github.com/emcie-co/parlant |
| ★ | AURA (論文) | リスクスコアの数理モデル | arxiv.org/abs/2510.15739 |

---

**取材メモ全体**: `docs/memos/2026-02-23/research-b/01〜06`
**統合レポート**: `docs/memos/2026-02-23/theme-b-report.md`
**本考察**: 本ファイル
