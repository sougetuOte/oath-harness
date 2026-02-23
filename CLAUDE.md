# oath-harness

## Project Identity

oath-harness は Claude Code のための信頼ベース実行制御ハーネス。
Earned Autonomy（動的信頼蓄積 → 自律度調整）を実現する。

## Design Philosophy

```
「最小権限から始めて信頼を獲得する」
デフォルトは安全側。実績に基づいて権限を拡張する。
```

### Three Laws (oath-harness版)

1. プロジェクトの整合性と健全性を損なってはならない。
2. ユーザーの指示に従わなければならない（第一法則に反する場合を除く）。
3. 自己のコスト効率を守らなければならない（第一・二法則に反する場合を除く）。

## Architecture

4層構造:
- **Model Router**: Opus/Sonnet/Haiku の動的振り分け
- **Trust Engine**: 信頼スコア蓄積 → 自律度決定
- **Harness + Guardrail Layer**: TDDサイクル、フェーズ制限、権限制御
- **Execution Layer**: Claude Code hooks / Subagents

## References

| カテゴリ | 場所 |
|---------|------|
| 設計仕様 | `docs/specs/` |
| ADR | `docs/adr/` |
| 設定 | `config/` |
| テスト | `tests/` |

## Development Status

Phase 1 (MVP) 設計中
