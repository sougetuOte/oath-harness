# リリースコマンド

引数で渡されたバージョン（例: `v0.1.0`）でリリースを実行する。
引数がない場合はユーザーにバージョンを確認する。

## 前提チェック

1. `gh` CLI がインストールされていること
2. git remote が設定されていること
3. 未コミットの変更がある場合、リリースフローに含める

## ステップ 1: 汚染ファイル除去

以下のファイルを git 追跡から除外し `.gitignore` に追加する:

```
SESSION_STATE.md
.claude/states/
.claude/current-phase.md  ← 追跡は残すがリセット
data/
docs/refs/
docs/slides/
docs/tasks/
docs/memos/
```

具体的な操作:
- `git rm --cached` で追跡から外す（ローカルファイルは残す）
- `data/` ディレクトリは `rm -rf` で完全削除
- `.claude/current-phase.md` は `AUDITING` にリセット（追跡は残す）
- `.gitignore` に上記パターンを追加（重複しないよう確認）

## ステップ 2: ドキュメント整合性チェック

1. `bash tests/run-all-tests.sh` でテスト数をカウント
2. `CLAUDE.md` と `README.md` のテスト数表記を実テスト数に更新
3. `LICENSE` ファイルがなければ MIT License で作成（年と著作者はユーザーに確認）
4. `CHANGELOG.md` がなければテンプレートを作成し、リリース内容をユーザーと相談して記入
5. `README.md` の License セクションを `MIT` に更新
6. `README.md` の `file_write_src` ドメインが記載されているか確認、なければ追加

## ステップ 3: 全テスト実行

```bash
bash tests/run-all-tests.sh
```

**1件でも失敗したらリリースを中止する。** 修正を提案し、修正後に `/release` を再実行するよう案内。

## ステップ 4: リリース内容確認

ユーザーに以下を提示して確認を求める:

```
--- リリース確認 ---
バージョン: vX.Y.Z
テスト: XXX 件 GREEN
除外済みファイル: [リスト]
更新済みドキュメント: [リスト]
新規ファイル: [リスト]

この内容でリリースしますか？
---
```

ユーザーが「承認」するまで次へ進まない。

## ステップ 5: コミット・タグ・プッシュ

1. `git add` で変更をステージング
2. `git commit` — メッセージ: `release: vX.Y.Z`
3. `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
4. ユーザーに push 先を確認（ブランチ名、リモート名）
5. `git push origin <branch> --tags`

## ステップ 6: GitHub Release 作成

```bash
gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <CHANGELOG抜粋>
```

CHANGELOG.md の該当バージョンセクションをリリースノートとして使用。

## ステップ 7: 完了報告

```
--- リリース完了 ---
バージョン: vX.Y.Z
タグ: vX.Y.Z
リリースURL: <gh release URL>
テスト: XXX 件 GREEN

リリースおめでとうございます！🎉
---
```

## 安全装置

- テスト失敗時は即座に中止
- 各 git 操作前にユーザー確認を挟む
- `--force` 系のコマンドは一切使わない
- 失敗した場合のロールバック手順を提示する
