# ADR-0004: bats-core 採用

**Status**: Accepted
**Date**: 2026-02-23
**Context**: oath-harness Phase 1 (MVP)

## Context

oath-harness は bash で実装されるため、テストフレームワークも bash を対象としたものを選定する必要がある。
テストの実行・CI 統合・アサーション表現力を軸に以下の選択肢を検討した。

| フレームワーク | 特徴 | 評価 |
|--------------|------|------|
| **bats-core** | bash 専用、TAP 出力、活発なメンテナンス | 最適 |
| shunit2 | 古典的、xUnit スタイル、機能が限定的 | 古い |
| shellspec | BDD スタイル、多機能、モック機構あり | オーバースペック |
| pytest (+ bash-language) | Python 依存、bash テストは間接的 | 不適 |

## Decision

**bats-core を git submodule として採用する。**

合わせて以下の公式拡張も submodule として導入する:

- `bats-support`: ヘルパー関数（`run`、`flunk` 等）
- `bats-assert`: アサーション関数（`assert_output`、`assert_success` 等）

ディレクトリ構成:

```
tests/
  bats-core/        # git submodule
  bats-support/     # git submodule
  bats-assert/      # git submodule
  unit/             # ユニットテスト (*.bats)
  integration/      # 統合テスト (*.bats)
  helpers.sh        # 共通ヘルパー
```

テスト実行コマンド:

```bash
tests/bats-core/bin/bats tests/unit/
tests/bats-core/bin/bats tests/integration/
```

## Consequences

### Positive

- bash スクリプト専用として最も成熟したフレームワークであり、実績が豊富
- TAP（Test Anything Protocol）出力により、CI ツール（GitHub Actions 等）と容易に統合できる
- `bats-assert` の `assert_output`、`assert_line` 等により、
  シェル出力のアサーションを宣言的に記述できる
- `setup` / `teardown` フックにより、テスト間の状態分離が容易
- git submodule のため、バージョンを固定でき、再現性が保証される

### Negative

- git submodule の管理が必要（`git submodule update --init --recursive` の実行が必須）
- 新規クローン時に submodule の初期化を忘れるとテストが実行できない
- bats-core のバージョンアップに追従するメンテナンスコストが発生する

### Risks

- git submodule の参照先が廃止・移動した場合にビルドが壊れるリスクがある
  - 緩和策: bats-core の公式リポジトリ（`bats-core/bats-core`）を参照しており、
    廃止リスクは低い。念のため fork を検討する
- CI 環境で submodule の初期化が行われない場合にテストが失敗するリスクがある
  - 緩和策: CI 設定に `git submodule update --init --recursive` を明示的に追加する
