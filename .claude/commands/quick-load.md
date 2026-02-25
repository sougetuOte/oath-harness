# クイックロード

プロジェクトルートの `SESSION_STATE.md` を読み、以下の形式で簡潔に報告:

```
Phase: [フェーズ] | 次: [最優先ステップ] | 未解決: [あれば/なし]
Trust: [domain]=[score] [domain]=[score][R] ...
```

Trust 行の書式:
- SESSION_STATE.md の Trust State セクションからドメインとスコアを読み取る
- 回復中のドメイン（is_recovering == true）には `[R]` を付与する
- Trust State が「未初期化」の場合は `Trust: 未初期化` と表示する
- Trust State セクション自体が存在しない場合は Trust 行を省略する

報告後、ユーザーの指示を待つ。先回りしてファイルを読み込まない。
