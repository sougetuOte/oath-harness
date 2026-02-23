# 次回タスク（2026-02-23 更新）

## 現在のフォーカス: Theme B（ガードレール+ハーネス次世代FW）

### 次のステップ: ミニマム設計 → プロトタイプ実装

ユーザー要件メモ:
- **AIベンダー制限**: Claude一択（リソース制約）
- **ペルソナ設計**: アシモフ的な行動原則 + 役割分担（意思決定/分析/ワーカー/レポート）
  - Opus: 複雑な考察のみ、それ以外は全部 Sonnet/Haiku に振り分け
- **コンテキスト管理**: save/clear/再起動のタイミング設計
- **LAM資産の活用**: ultimate-think、save/load系コマンド
- **知識継承**: Obsidian型（人間が把握しやすい、RAGではなくAI検索）
- **実行環境**: Linux優先 → Windows対応は後回し、Mac非対応

## Theme A（RPG大規模化）

**ステータス**: 保留。Theme B が十分に形になってから着手検討。

## 完了済み成果物

### Theme B 調査・レポート（2026-02-23 完了）
- `research-b/01` ~ `06` — 業界動向・FW比較・信頼ベース監視・GitHub調査（150+ソース）
- `research-b/07-ownpilot-code-analysis.md` — OwnPilot コード解析
- `research-b/08-agentsh-code-analysis.md` — agentsh コード解析
- `theme-b-report.md` — 統合レポート
- `theme-b-deep-analysis.md` — 深掘り考察
- `theme-b-integration.md` — 最終統合（note.com 3記事 + 裏付け調査）

### 核心的結論（調査フェーズで確立）
- Earned Autonomy（動的信頼蓄積→自律度調整）の実装はOSSにゼロ
- Trust Engine はドメイン依存が強くベンダーが汎用化しにくい → 個人が攻められる
- Claude Code hooks 上に最小 Trust Engine を載せるのが最小構成
- LAM の Three Agents Model は100+プロジェクト中ユニーク
