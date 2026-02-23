---
name: adr-template
description: |
  ADR（Architecture Decision Record）作成を支援するテンプレートスキル。
  docs/adr/ へのADR作成時に自動適用され、
  3 Agents Modelに準拠した構造を提案する。
  アーキテクチャ決定、技術選定、設計方針の記録時に活用される。
---

# ADRテンプレートスキル

## 目的

このスキルは、ADR（Architecture Decision Record）作成時に一貫した構造と3 Agents Modelによる多角的検証を確保するためのテンプレートを提供する。

## 適用条件

以下のいずれかに該当する場合、このスキルを適用する:

- `docs/adr/` への新規ファイル作成
- アーキテクチャ決定、技術選定の記録を求められた
- `/adr-create` コマンドの実行時

## ファイル命名規則

```
docs/adr/
├── 0001-initial-architecture.md
├── 0002-database-selection.md
├── 0003-api-design-pattern.md
└── ...
```

形式: `NNNN-kebab-case-title.md`
- NNNN: 4桁の連番（0001から）
- タイトル: ケバブケースで簡潔に

## ADRテンプレート

```markdown
# ADR-NNNN: [決定タイトル]

## メタ情報
| 項目 | 内容 |
|------|------|
| ステータス | Proposed / Accepted / Deprecated / Superseded |
| 日付 | YYYY-MM-DD |
| 意思決定者 | [名前/ロール] |
| 関連ADR | [ADR-XXXX](./XXXX-*.md) |

## コンテキスト

### 背景
[この決定が必要になった背景・状況を記述する。]

### 制約条件
- [技術的制約]
- [ビジネス制約]
- [リソース制約]

### 要求事項
- [満たすべき要件1]
- [満たすべき要件2]

## 検討した選択肢

### Option A: [選択肢名]
**概要**: [簡潔な説明]

**メリット**:
- [利点1]
- [利点2]

**デメリット**:
- [欠点1]
- [欠点2]

### Option B: [選択肢名]
...

## 3 Agents Analysis

### [Affirmative] 推進者の視点
> 最高の結果はどうなるか？どうすれば実現できるか？

- [採用時のメリット、可能性]

### [Critical] 批判者の視点
> 最悪の場合どうなるか？何が壊れるか？

- [リスク、懸念点]

### [Mediator] 調停者の視点
> 今、我々が取るべき最善のバランスは何か？

- [両視点の統合]

## 決定

**採用**: Option [X]

### 決定理由
[なぜこの選択肢を採用したか]

## 影響

### ポジティブな影響
- [良い影響]

### ネガティブな影響
- [悪い影響]（緩和策: [対策]）

## 検証方法
- [この決定が正しかったかを検証する方法]
```

## ADRステータスの遷移

```
Proposed → Accepted → [Deprecated | Superseded]
    ↓
  Rejected
```

## 参照ドキュメント

- `.claude/rules/decision-making.md`
- `/adr-create` コマンド
