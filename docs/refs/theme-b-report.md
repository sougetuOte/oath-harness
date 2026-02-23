# Theme B 統合レポート: ガードレール + ハーネス = 次世代フレームワーク

**作成日**: 2026-02-23
**起源**: X20実験レポート → 今後の方向性議論
**取材ソース**: research-b/01〜03（計75+ソース）

---

## Executive Summary

2025-2026年のAIエージェント業界で、**ガードレールとハーネスの統合**が急速に主流化している。
LAMプロジェクトの「品質ゲート + 自律ハーネスの両方を備えたものが主流になるはず」という仮説は、
業界の動向と完全に一致する。ただし、その実現形態は当初の想定より明確な形で結晶化しつつある。

**3つの決定的発見**:

1. **ガードレールは一時的、ハーネスエンジニアリングは恒久的**（LangChain）
   - ガードレールはモデル改善で不要になる制約。ハーネスは永続的な構造投資。
2. **信頼は蓄積される — Earned Autonomy は実証済み**（Anthropic）
   - Claude Code で auto-approve が 20%→40%+ に上昇。経験者は監視頻度を上げつつ承認頻度を下げる。
3. **自律度と能力は独立した軸**（Knight/Columbia）
   - 高能力なエージェントを低自律度で運用することは設計上正しい。自律度はデザインチョイス。

---

## 1. 業界の現在地

### 1.1 3層エージェントスタック（LangChain定義）

```
+------------------------------------------+
|             AGENT HARNESS                |
|  （DeepAgents, Claude Agent SDK）         |
|  計画・サブエージェント・コンテキスト管理   |
+------------------------------------------+
|            AGENT FRAMEWORK               |
|  （LangChain, CrewAI, OpenAI Agents SDK）|
|  抽象化・ツール定義・エージェントループ     |
+------------------------------------------+
|             AGENT RUNTIME                |
|  （LangGraph, Temporal, Inngest）        |
|  永続実行・状態保存・HITL基盤             |
+------------------------------------------+
```

LAMはこの3層で言えば**ハーネス層**に位置する。フレームワークやランタイムではなく、
「エージェントが生産的に動ける構造を提供するもの」がLAMの本質。

### 1.2 Safety-by-Prompt → Guardrails-by-Construction

2026年初頭、業界全体で「プロンプトで安全性を指示する」から「アーキテクチャで安全性を強制する」への転換が文書化された。

根拠となったセキュリティベンチマーク:
- **PropensityBench（ICLR 2026）**: モデルは理論上99%以上「危険なツールは使わない」と言うが、実運用圧力下では使用する
- **Agent Security Bench**: 現行防御に対する攻撃成功率 **84.3%**
- **WASP**: トップモデルでも低コストインジェクションに **86%** 騙される

→ プロンプトベースの安全策は運用圧力下で崩壊する。構造的な安全策が必須。

### 1.3 主要フレームワークの自律制御パターン

| フレームワーク | 主要メカニズム | 粒度 | 特徴 |
|:--|:--|:--|:--|
| **LangGraph** | チェックポイント + interrupt | グラフノード | 静的/動的中断、approve/edit/reject |
| **CrewAI** | タスクガードレール + リトライ | タスク出力 | 自己修復ループ、LLM-as-Judge |
| **MS Agent Framework** | Control Plane | エージェント（プラットフォーム） | ガバナンスを外部化 |
| **Claude Code** | Deny/Allow/Ask + hooks | ツールコール | 14イベント・3ハンドラ型 |
| **OpenAI Agents SDK** | 並列ガードレール + サンドボックス | 入出力/ツール | fail-fast、封じ込め |

---

## 2. ガードレールとハーネスの関係性

### 2.1 従来の理解（対立構造）

```
ガードレール（制限）  ←対立→  ハーネス（自律）
```

### 2.2 現在の理解（階層構造）

```
ハーネス = 構造を与えて能力を引き出す（恒久的投資）
  └── ガードレール = 現時点の弱点を補う制約（一時的措置）
```

**LangChainの定式化**: ガードレールは「今日の欠点」への対処。ループ検出ミドルウェアはモデルが doom loop しなくなれば不要になる。ハーネスエンジニアリングは、モデルがどれだけ改善しても必要な構造的投資。

**Anthropicの発見**: 構造化された成果物（フィーチャーファイル、進捗ログ、gitヒストリー）は行動ガードレールとして機能する。ハーネスは制限ではなく構造を通じてエージェントの行動を導く。

→ **ハーネスそのものがガードレールの役割を果たす**。両者の境界は溶解しつつある。

### 2.3 Constitutional AI が体現するパターン

| 要素 | 役割 | LAMでの対応 |
|:--|:--|:--|
| 憲法（principles） | ガードレール（何が許されるか） | CLAUDE.md + phase-rules.md |
| 自己評価ループ | ハーネス（自律的に品質を維持） | Three Agents Model |
| 人間の関与削減 | Earned Autonomy | 承認ゲートの頻度調整 |

---

## 3. Earned Autonomy — 信頼の蓄積は実証されている

### 3.1 Anthropic の実証データ（2026年2月公開）

Claude Code 750セッション超のデータから:

| 指標 | 初心者（<50セッション） | 熟練者（~750セッション） |
|:--|:--|:--|
| フル auto-approve | ~20% | ~40%+ |
| interrupt率 | ~5% | ~9%（増加） |
| 99.9th セッション時間 | <25分 | >45分 |

**決定的な洞察**: 熟練者は承認頻度を下げるが、監視・介入頻度は上げる。
Sheridan-Verplank で言えば Level 5（承認して実行）→ Level 7（実行して報告）への移行。

**監視は消えない、進化する。**

### 3.2 信頼度の数理モデル（SOC研究）

```
自律度 A = 1 - (λ₁ × 複雑さ + λ₂ × リスク) × (1 - 信頼度)
信頼度 T = α₁ × 説明可能性 + α₂ × 実績 + α₃ × (1 - 不確実性)
人間関与 H = 1 - A
```

| シナリオ | 自律度 | 必要な信頼度 | 人間の役割 |
|:--|:--|:--|:--|
| 新規・高リスク | 0.1-0.3 | 低 | 完全制御 |
| 中程度の複雑さ | 0.4-0.7 | 中 | バランス監視 |
| ルーチン・低リスク | 0.8-1.0 | 高 | 最小限の監視 |

### 3.3 異分野に共通する信頼パターン

```
境界を定義 → 制約から始める → 成功を実証 → 拡張を獲得 → 継続的に監視
```

| 分野 | 境界定義 | 信頼シグナル | 拡張メカニズム |
|:--|:--|:--|:--|
| 自動運転 | ODD（運用設計領域） | 無事故走行距離 | ODD境界の拡大 |
| CI/CD | カナリア% | エラー率 | ロールアウト%増加 |
| コードレビュー | リスク分類 | 過去の精度 | 自動マージ対象拡大 |
| AIエージェント | 権限スコープ | タスク完了率 | ツールアクセス拡大 |

---

## 4. 新フレームワーク構想への示唆

### 4.1 LAMの既存構造は業界方向と整合している

| LAMの既存要素 | 業界の対応概念 |
|:--|:--|
| フェーズゲート（PLANNING/BUILDING/AUDITING） | ODD境界、Supervised Autonomy のチェックポイント |
| Three Agents Model | AI-AI debate（スケーラブルオーバーサイト） |
| CLAUDE.md | 憲法（Constitutional AI） |
| Allow/Deny リスト | Claude Code の3層パーミッション |
| 承認ゲート | LangGraph の interrupt_before/after |
| 仕様先行（Spec-before-code） | Bounded Autonomy の運用制限 |

### 4.2 LAMに足りないもの

| 不足要素 | 業界のベストプラクティス | 影響 |
|:--|:--|:--|
| **適応的自律度** | タスクのリスク/複雑さに応じて監視レベルを動的変更 | 現状は全フェーズで固定 |
| **リトライ付き自己修復** | CrewAI的な失敗→フィードバック→再試行ループ | 現状は失敗で停止 |
| **並列品質検証** | 実行と同時にガードレールを走らせる | 現状は逐次 |
| **構造化された監査証跡** | OpenTelemetry的なトレーシング | セッション状態ファイルのみ |
| **自己エスカレーション** | エージェントが自身の限界を認識して人間にエスカレート | 暗黙的 |

### 4.3 新フレームの骨格

```
+--------------------------------------------------+
|              TRUST ENGINE                        |
|  信頼スコア計算・自律度決定・エスカレーション判定    |
+--------------------------------------------------+
         |                    |
+------------------+  +-------------------+
|   HARNESS LAYER  |  |  GUARDRAIL LAYER  |
|  計画構造         |  |  品質ゲート       |
|  PRD → TDD サイクル|  |  フェーズ制限     |
|  コンテキスト管理  |  |  権限制御        |
|  サブエージェント  |  |  ループ検出       |
+------------------+  +-------------------+
         |                    |
+--------------------------------------------------+
|              EXECUTION LAYER                     |
|  Claude Code / Ralph Loop / 対話モード            |
+--------------------------------------------------+
```

**Trust Engine が新しい層**。タスクの性質と蓄積された信頼に基づいて、
ハーネス（自律度）とガードレール（制約度）のバランスをリアルタイムに調整する。

### 4.4 モード切替の具体像

| 状況 | Trust Engine の判定 | 結果モード |
|:--|:--|:--|
| 明確なPRD + 低リスク + 高実績 | 自律度 HIGH | Ralph的自律ループ |
| 明確なPRD + 高リスク + 中実績 | 自律度 MEDIUM | 自律 + 定期チェックイン |
| 曖昧な要件 + 未知のドメイン | 自律度 LOW | LAM的承認ゲート |
| 過去に失敗した類似タスク | 自律度 LOW + 追加制約 | 強化監視モード |

### 4.5 LangChainの重要な警告

> ガードレールは一時的。モデルが改善すれば溶ける。
> ハーネスエンジニアリングが恒久的な長期投資。

→ 新フレームを設計するなら、**ガードレール側の設計に時間をかけすぎない**。
ガードレールは現時点の弱点を補うもので、寿命が短い。
**ハーネス構造（PRD品質、テスト設計、コンテキスト管理）が本体**。

---

## 5. LAMとは別フレームか？ LAMの進化か？

### 5.1 別フレーム説の根拠

- LAMの設計前提は「人間が常に近くにいる」。Trust Engine は「人間がいなくてもいい時間帯がある」を前提とする。
- LAMのフェーズは固定的。新フレームのフェーズ内自律度は可変。
- LAMの承認ゲートは全タスクに一律適用。新フレームはタスクのリスク/実績に応じて適応的。

### 5.2 LAM進化説の根拠

- LAMの既存構造（フェーズ、Three Agents、CLAUDE.md、仕様先行）は業界ベストプラクティスと一致
- 足りないのは Trust Engine と適応的自律度であり、これは既存構造の上に追加できる
- CNCF の4本柱（golden paths, guardrails, safety nets, manual review）は全てLAMに存在するか追加可能

### 5.3 結論

**LAMの進化として実現可能だが、名前は変えるべき。**

LAMの「Living Architect」としてのアイデンティティ（整合性の番人）は維持しつつ、
Trust Engine による自律度可変の仕組みを追加する。
「品質ゲートの番人」から「品質ゲート + 自律ハーネスの両方を調整するオーケストレーター」への進化。

---

## 6. 残された問い

1. **Trust Engine の具体的な実装**: hooks + 設定ファイルで実現できるか？ それとも独自の制御層が必要か？
2. **信頼スコアの永続化**: セッションを超えて信頼を蓄積する仕組みはどう設計するか？
3. **ガードレールの有効期限**: どのガードレールを「一時的」と判定し、いつ外すのか？
4. **自己エスカレーションの実装**: エージェントが「自分には難しい」と判断する基準は何か？
5. **検証**: この構想は実験で検証できるか？ X20実験の Phase 3 で試せるか？

---

## 参考文献（主要ソースのみ）

### ハーネスエンジニアリング
- [LangChain: Agent Frameworks, Runtimes, and Harnesses](https://blog.langchain.com/agent-frameworks-runtimes-and-harnesses-oh-my/)
- [LangChain: Improving Deep Agents with Harness Engineering](https://blog.langchain.com/improving-deep-agents-with-harness-engineering/)
- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [OpenAI: Harness Engineering](https://openai.com/index/harness-engineering/)

### ガードレール・安全性
- [NVIDIA NeMo Guardrails](https://developer.nvidia.com/nemo-guardrails)
- [Guardrails-by-Construction への移行](https://micheallanham.substack.com/p/transitioning-to-guardrails-by-construction)
- [CNCF: 4 Pillars of Platform Control](https://www.cncf.io/blog/2026/01/23/the-autonomous-enterprise-and-the-four-pillars-of-platform-control-2026-forecast/)

### 信頼とEarned Autonomy
- [Anthropic: Measuring AI Agent Autonomy in Practice](https://www.anthropic.com/research/measuring-agent-autonomy)
- [Knight/Columbia: Levels of Autonomy for AI Agents](https://knightcolumbia.org/content/levels-of-autonomy-for-ai-agents-1)
- [SOC Trust-Autonomy Framework](https://arxiv.org/abs/2505.23397)
- [Sheridan-Verplank LOA Taxonomy](https://www.researchgate.net/figure/Sheridan-and-Verplanks-original-levels-of-automation-2_tbl1_337253476)

### エージェントフレームワーク
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks)
- [LangGraph Human-in-the-Loop](https://docs.langchain.com/oss/python/langchain/human-in-the-loop)
- [Microsoft Agent Framework](https://learn.microsoft.com/en-us/agent-framework/overview/agent-framework-overview)
- [Supervised Autonomy Pattern](https://edge-case.medium.com/supervised-autonomy-the-ai-framework-everyone-will-be-talking-about-in-2026-fe6c1350ab76)

全取材メモ: `docs/memos/2026-02-23/research-b/01〜03`
