# Theme B 最終統合レポート: note.com取材 + 裏付け調査 + 既存レポートの突き合わせ

**作成日**: 2026-02-23
**前提文書**: theme-b-report.md, theme-b-deep-analysis.md, research-b/01-06
**新規ソース**: note.com 3記事（asura氏）、裏付け追加調査（30+ソース）

---

## Executive Summary

既存レポートの5つの主要論点を、note.com記事の実践事例と追加調査で検証した結果、**全5論点が裏付けられた**。特に asura 氏の YouTube 自律運営エージェント「スラ」の設計は、ガードレール+ハーネスのハイブリッド仮説の**生きた実装例**であり、Theme B の理論的枠組みに最も直接的な実践的裏付けを与える。

追加調査では、OpenAI・Martin Fowler・Salesforce がハーネスエンジニアリングを正式に採用したこと、OWASP が Agentic AI Top 10 を公開したこと、Auth0/Permit.io が Action Gateway パターンを実装したこと等、2026年2月時点の最新動向を補完した。

**最も重要な発見**: 「Earned Autonomy をシステムとして実装したプロジェクトはゼロ」という主張は依然として有効。部品レベルでは近いもの（Action Gateway、Guardian Agents Protectors）が登場しているが、統合的な Trust Engine は確認できなかった。

---

## 1. note.com 3記事の取材結果

### 1.1 記事概要

| # | タイトル | 公開日 | 焦点 |
|:--|:--|:--|:--|
| 1 | なぜ今流行りのOpenClawやManusを使わずに、汎用AIエージェントを自作するのか | 2/14 | Why（戦略）: ハーネスの密度が競争優位 |
| 2 | 僕がAIエージェントの "都市" を作る理由 | 2/17 | What（構想）: 中央集権→自律分散への転換 |
| 3 | スラの脳内 \| 人間ゼロで動画が出てくる設計 | 2/20 | How（設計）: 5原則によるハイブリッド実装 |

**著者 asura 氏**: 非エンジニアの個人開発者。YouTube自律運営エージェント「スラ」、X分析エージェント「クマラ」を運用中。

### 1.2 記事1: 自作する理由 — ハーネスの密度が勝負を分ける

**核心主張**: モデル性能は民主化される。差がつくのは「ハーネスの密度」。

**根拠として挙げられたデータ**:
- OpenClaw: BitSight レポートで 42,900件の認証なし公開インスタンス、512件の脆弱性（8件クリティカル）、CVE-2026-25253（CVSS 8.8）
- Manus: Meta による20億ドル買収後のデータプライバシー懸念
- ベンチマーク飽和: MMLU 90%超え、スタンフォード HAI がベンチマーク飽和を明言

**Theme B との接続**: 「ハーネスの密度」は theme-b-report.md で定式化した「ハーネスエンジニアリングは恒久的投資」と同義。asura 氏は実践の中から同じ結論に独立に到達している。

### 1.3 記事2: 都市構想 — オーケストレーターの限界

**核心主張**: 「チーム」モデル（中央指揮者が全体を統括）はスケールしない。「都市」モデル（各エージェントが自律判断し、結果として全体が機能する）へ転換すべき。

**実体験に基づく課題**:
- スラ（YouTube担当）とクマラ（X担当）の間で情報が流れない
- 著者が手動でハブとなって橋渡し → スケール不可能
- Google A2A、Anthropic MCP への期待

**Theme B との接続**: 中央集権的ガードレール（オーケストレーターによる指揮）→分散型ハーネス設計（各エージェントの自律判断）への移行。Earned Autonomy の実践的パターンが見える: 単体確立→実績獲得→新エージェント追加→都市へ拡大。

### 1.4 記事3: スラの脳内 — 5原則のハイブリッド設計

**5つの設計原則**:

| 原則 | 内容 | Theme B 対応 |
|:--|:--|:--|
| パイプライン | 工程を分けて独立（テーマ→構成→台本→…→投稿） | **ハーネス**: 構造的誘導 |
| スキーマ契約 | フェーズ間のデータを型で厳密定義 | **ガードレール**: 静的制約 |
| 品質関門 | ゼロエラーまで次に進めない門番 | **ガードレール**: 品質ゲート |
| フォールバック | 多層設計、第一候補失敗→代替経路 | **ハーネス**: 動的誘導 |
| ペルソナ制約 | 口調・禁止表現・感情パターン定義 | **ハーネス**: 出力方向の安定化 |

**実例**: ある日、画像生成の第一候補がエラーを返し続けたが、スラはフォールバックで自動的に第二候補に切り替え、著者が気づいた時には投稿済み。

**著者が自覚する課題**: フィードバックループが人間を経由しており閉じていない。外部情報を取り込む手段がない。スラは「孤独」。

**Theme B との接続**: この5原則はガードレール+ハーネスのハイブリッドの**具体的な実装例**。そして著者が課題として認識する「フィードバックループの未完成」は、まさに Trust Engine が解決すべき問題領域。

### 1.5 3記事の横断分析

**共通する主張**:
1. ハーネス設計こそが競争優位の源泉（3記事一貫）
2. 自律と制御の両立（「人間ゼロ」を目指しつつ厳格な制約）
3. 段階的な自律拡大の思想（単体→マルチ→都市）
4. 検証と改善のサイクル重視（ブラックボックスの拒絶）

**最大の示唆**: 著者は自らを「住人ではなく設計者」と位置づけている。人間の役割は個々のタスクへの介入から、「自律が健全に機能する環境の設計」へ移行する。これは Trust Engine の人間側の役割定義に直結する。

---

## 2. 裏付け調査: 5論点の検証結果

### 2.1 論点1: Earned Autonomy（システム実装ゼロ）

| 裏付けソース | 内容 |
|:--|:--|
| Anthropic 公式（2026/2月） | 750セッションデータでフル auto-approve 20%→40%+、セッション時間 <25分→>45分。行動変化は漸進的 |
| Knight/Columbia（arXiv: 2506.12469） | 5段階自律度レベル + Autonomy Certificate（第三者認証）の構想。ただし静的設計 |
| AWS Security Scoping Matrix（2025/11） | Agency と Autonomy を分離した4スコープ分類。静的分類であり動的制御ではない |

**判定**: ユーザー行動としての Earned Autonomy は Anthropic データで強く裏付け。システム実装の不在も追加調査で確認。**裏付け: 高**。

### 2.2 論点2: ガードレール一時的 / ハーネス恒久的

| 裏付けソース | 内容 |
|:--|:--|
| LangChain 公式ブログ | 明文で記述。ハーネス変更のみで Terminal Bench 2.0 で +13.7pt |
| OpenAI 公式（Codex） | 3人のエンジニアが5ヶ月で約100万行。ハーネスの3要素を定義 |
| Martin Fowler | OpenAI のハーネスエンジニアリングを分析・支持 |
| Salesforce | エージェントハーネスを「運用システム」と正式定義 |
| Phil Schmid（Hugging Face） | ハーネスを AI ラボの新たなモート（競争優位性の源泉）と位置づけ |
| asura 氏（note.com） | 実践から独立に「ハーネスの密度が勝負を分ける」と同一結論に到達 |

**判定**: 業界主要プレイヤー + 実践者の双方から支持。2026年のコンセンサスとして成立。**裏付け: 非常に高**。

### 2.3 論点3: Trust Engine 未実装

| 裏付けソース | 内容 |
|:--|:--|
| Auth0 | Async Authorization（非同期認可）。アクション単位の承認であり、信頼蓄積に基づく動的調整ではない |
| Permit.io | Action Gateway パターン。低リスク自動承認/高リスク人間ルーティング。静的リスク分類 |
| Gartner Guardian Agents（2025/6） | Protectors（行動・権限の動的調整/ブロック）を予測。2030年までに市場10-15%。具体実装は未確認 |
| Dynatrace | Observability をリアルタイムコントロールプレーンに。信頼の阻害要因は可視性不足 |
| Google Cloud | Bounded autonomy 導入中。動的信頼スコアについては言及なし |

**判定**: 部品レベル（Action Gateway、Protectors 概念）は存在するが、「タスク性質 × 信頼蓄積 → 自律度の連続的調整」という統合エンジンは未確認。**裏付け: 高**。

### 2.4 論点4: Safety-by-Prompt 崩壊

| 裏付けソース | 内容 |
|:--|:--|
| Agent Security Bench（ICLR 2025 採録） | Mixed Attack の ASR **84.30%**、拒否率 3.22% |
| arXiv 2504.11168 | Azure Prompt Shield 等6つの主要防御に対し**最大100%回避** |
| Anthropic ブラウザエージェント防御（2025/11） | 二層構造（RL訓練 + 分類器フィルタ）で攻撃成功率を**1%**に低減。プロンプトだけに依存しないアプローチの有効性を実証 |
| OWASP Agentic AI Top 10（2026） | 100人以上の専門家査読。上位4リスクの3つがアイデンティティ・ツール・信頼境界 |

**判定**: ICLR 採録の査読済み論文 + OWASP の専門家合意。学術的信頼性が最も高い論点。**裏付け: 非常に高**。

### 2.5 論点5: 5要素統合の空白

調査した全プロジェクトの中で、以下5要素を全て備えたものは依然として確認できなかった:

```
              ハーネス  Guardrails  Trust    段階的   カーネル
              パターン  by-Constr.  Engine   HITL    強制
              -------  ----------  ------   -----   ------
OpenAI Codex   +++       ++         -        +       +++
Deep Agents    +++        -         -        +        -
Claude Code    +++        +         -        +        ++
Auth0/Permit    -         +         △        ++       -
asura/スラ      ++       ++         -        +        -

→ 5列全てに「+++」は依然として不在
  (△ = 部品レベルで近い)
```

**判定**: **裏付け: 高**。

---

## 3. 新たに発見された重要な概念・ソース

### 3.1 OpenAI のハーネスエンジニアリング正式採用

既存レポート時点では LangChain が主導と整理していたが、OpenAI も Codex プロジェクトで「ハーネスエンジニアリング」を正式に採用し、公式ブログで詳細を公開。3人のエンジニアが5ヶ月で約100万行を生成。

ハーネスの3要素: **Context Engineering**、**Architectural Constraints**、**Garbage Collection**。

→ 既存レポートの「ハーネスエンジニアリングは恒久的投資」というLangChain主導の見方を、OpenAI が独立に裏付け。業界コンセンサスとしての確度が大幅に上昇。

### 3.2 Martin Fowler の分析参入

Martin Fowler（ThoughtWorks）がハーネスエンジニアリングを分析・文書化。ソフトウェアエンジニアリングの権威がこの概念を認知したことで、一過性のバズワードではなく持続的なパラダイムとしての位置づけが強化された。

### 3.3 OWASP Agentic AI Top 10（2026）

100人以上の専門家による査読済みフレームワーク。上位4リスクのうち3つがアイデンティティ、ツール、委任された信頼境界に関するもの。「Least Agency（最小権限）」の原則を強調。

→ 既存レポートの PropensityBench/ASB データに加え、業界標準としてのセキュリティフレームワークが確立。

### 3.4 Action Gateway パターン（Auth0/Permit.io）

Trust Engine の「部品」として最も近いもの:
- Auth0: エージェントが認可リクエスト発行→人間承認待ちの間も他タスク継続（非同期認可）
- Permit.io: リスクレベルに応じたルーティング（低リスク→自動承認、高リスク→人間）

→ 既存レポートでは「Trust Engine を誰も作っていない」と結論したが、より正確には「部品は存在するが統合されていない」。この精度の向上は設計方針に影響する。

### 3.5 asura 氏の5原則（実践からの独立検証）

asura 氏は学術文献や業界レポートを参照せず、実践の中からガードレール+ハーネスのハイブリッド設計に独立に到達している。これは理論の実践的妥当性を示す強い傍証。

特に「品質関門（バリデーションゲート）」は LAM の承認ゲートと同構造であり、「スキーマ契約」は LAM の仕様先行（Spec-before-code）と同一原則。

### 3.6 日本語圏の動向

| ソース | 内容 |
|:--|:--|
| NTTデータ | 企業向けガードレール概念解説 |
| Future Architect | ガードレール構築の技術記事 |
| トレンドマイクロ | エージェンティックAI のアーキテクチャ・脅威・対策 |
| シスコ日本 | AI Defense の大幅強化（2026/2） |
| 大和総研 | 日本企業の AIエージェント導入は「がっかりしない手法」の模索段階 |
| UiPath/EnterpriseZine | 2026年は「実行」の年。AI推進法に基づく監査ログ・HITL設計が必須 |

**特徴**: 日本語圏では Earned Autonomy や Trust Engine に相当する議論は直接的にはなく、HITL設計とコンプライアンス対応が主な関心事。asura 氏の連載は日本語圏で最も先進的な実践報告の一つ。

---

## 4. 突き合わせ: 既存レポートの修正・補強

### 4.1 修正が必要な点

| 既存記述 | 修正 |
|:--|:--|
| 「Trust Engine を誰も実装していない」 | → 「統合的な Trust Engine はゼロだが、部品レベル（Action Gateway）は登場している」に精度向上 |
| ハーネスエンジニアリングの主導は LangChain | → LangChain + OpenAI + Martin Fowler + Salesforce + HuggingFace の業界横断コンセンサスに拡大 |

### 4.2 補強された点

| 既存論点 | 補強内容 |
|:--|:--|
| ハーネスは恒久的投資 | OpenAI（100万行生成）、Martin Fowler の分析、asura 氏の実践が独立に裏付け |
| Safety-by-Prompt 崩壊 | OWASP Agentic AI Top 10 が業界標準として確立 |
| LAM の既存構造は業界方向と整合 | asura 氏の品質関門≒承認ゲート、スキーマ契約≒仕様先行で実践的にも裏付け |
| Three Agents Model はユニーク | 追加調査でも類似プロジェクトは発見されず |

### 4.3 新たに追加すべき視座

**1. 「設計者」としての人間の役割**

asura 氏の「住人ではなく設計者」という自己定義は、Trust Engine 設計の重要な示唆。人間は個々のタスクに介入するのではなく、「自律が健全に機能する環境」を設計する。LAM の Living Architect のアイデンティティとも整合する。

**2. 分散型ハーネスの方向性**

asura 氏の「チーム→都市」転換は、中央集権的 Trust Engine から分散的信頼ネットワークへの発展を示唆。Phase 1（単体エージェント）では中央 Trust Engine が適切だが、Phase 2（マルチエージェント）では各エージェントが相互に信頼を評価する仕組みが必要になる。

**3. Action Gateway は Trust Engine の部品として取り込める**

Auth0/Permit.io の Action Gateway パターン（リスクベースルーティング）は、Trust Engine の「判定→ルーティング」部分にそのまま使える。足りないのは「信頼蓄積→閾値の動的変更」部分。

---

## 5. 統合結論

### 5.1 裏付け状況サマリー

| # | 論点 | 裏付け | 信頼度 | 新規ソースの貢献 |
|:--|:--|:--|:--|:--|
| 1 | Earned Autonomy 実装ゼロ | Anthropic公式 + 追加調査で確認 | **高** | Auth0/Permit.io は部品のみと精度向上 |
| 2 | ハーネス恒久的/ガードレール一時的 | LangChain + OpenAI + Martin Fowler + Salesforce + asura | **非常に高** | OpenAI正式採用、asura独立検証 |
| 3 | Trust Engine 未実装 | 部品レベルは存在、統合は不在 | **高** | Action Gateway パターンの発見 |
| 4 | Safety-by-Prompt 崩壊 | ICLR 2025 + OWASP 2026 | **非常に高** | OWASP Agentic AI Top 10 |
| 5 | 5要素統合の空白 | 追加プロジェクト含め確認 | **高** | asura/スラを含めても空白は維持 |

### 5.2 Theme B の核心主張の最終評価

**「品質ゲート（ガードレール）と自律（ハーネス）を備えたものが主流になるはず」**

→ 2026年2月時点で、この仮説は**業界コンセンサスとして成立**している。LangChain/OpenAI/Anthropic/Salesforce/Martin Fowler がそれぞれの言葉でこれを支持し、asura 氏が実践で独立に検証している。

**「Trust Engine（動的信頼蓄積→自律度調整）は誰も作っていない」**

→ **依然として有効**。ただし「部品は登場している」に精度を上げるべき。Action Gateway + 信頼蓄積層 の組み合わせが実装の最短経路。

### 5.3 次のアクションへの示唆

1. **Trust Engine の最小実装設計**を更新: Auth0/Permit.io の Action Gateway パターンを取り込む
2. **asura 氏の5原則**を LAM の既存構造とのマッピングとして整理（品質関門≒承認ゲート等）
3. **分散型信頼の方向性**を中長期ビジョンに追加（単体→マルチエージェントへの発展パス）
4. **OwnPilot/agentsh のコード読み**は引き続き有効（既存レポートの推奨から変更なし）

---

## 参考文献（本レポートで新規追加分のみ）

### note.com 記事
- asura「なぜ今流行りのOpenClawやManusを使わずに、汎用AIエージェントを自作するのか」(2026/2/14)
- asura「僕がAIエージェントの "都市" を作る理由」(2026/2/17)
- asura「スラの脳内｜人間ゼロで動画が出てくる設計」(2026/2/20)

### ハーネスエンジニアリング
- OpenAI: Harness engineering (https://openai.com/index/harness-engineering/)
- OpenAI: Unlocking the Codex harness (https://openai.com/index/unlocking-the-codex-harness/)
- Martin Fowler: Harness Engineering (https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html)
- Salesforce: What Is an Agent Harness? (https://www.salesforce.com/agentforce/ai-agents/agent-harness/)
- Phil Schmid: The importance of Agent Harness in 2026 (https://www.philschmid.de/agent-harness-2026)

### セキュリティ・ガバナンス
- OWASP Agentic AI Top 10 (https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)
- arXiv 2504.11168: Bypassing LLM Guardrails
- Anthropic: Mitigating prompt injection risks in browser use (2025/11)

### Trust / Authorization
- Auth0: Secure HITL Interactions for AI Agents (https://auth0.com/blog/secure-human-in-the-loop-interactions-for-ai-agents/)
- Permit.io: HITL for AI Agents Best Practices (https://www.permit.io/blog/human-in-the-loop-for-ai-agents-best-practices-frameworks-use-cases-and-demo)
- Gartner: Guardian Agents 予測 (2025/6)
- Dynatrace: Agentic AI Observability Report
- Google Cloud: Lessons from 2025 on agents and trust

### 日本語圏
- NTTデータ: AIガードレールとは (https://www.nttdata.com/jp/ja/trends/data-insight/2025/1203/)
- Future Architect: AIエージェントのガードレールの作り方
- トレンドマイクロ: エージェンティックAIの実現
- シスコ日本: AI Defenseの大幅強化 (2026/2)
- 大和総研: AIエージェント元年を振り返る (2026/1)
- UiPath/EnterpriseZine: 2026年はAIエージェント実行の年へ

---

**本レポートは theme-b-report.md, theme-b-deep-analysis.md と合わせて Theme B の完全な調査記録を構成する。**
