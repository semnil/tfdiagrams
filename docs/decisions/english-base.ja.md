# 英語基本化の決定

> For the English version, see [english-base.md](english-base.md).

このリポジトリの文書を英語基本にしたとき (#97) に閉じた判断と、却下した案を持つ。

## CLAUDE.md を追跡するファイルにして、言語の上書き行を置く

- **決定** (2026-10-20): `CLAUDE.md` をリポジトリの追跡するファイルにし、その「Conventions」に、言語の規則を上書きする行を置く。
- **却下した案**: 追跡しない `CLAUDE.md` を `.claude/` に置く (それを持つマシンでしか効かない)。`CLAUDE.md` を作らない。

## 例の README に日本語版を作る

- **決定** (2026-10-20): `example/count/README.md` の隣に、日本語版 `example/count/README.ja.md` を置く。ルートの README と同じ形にする。
- **却下した案**: その README を英語だけのままにする。

## probe の pull request は、コメントも含めて英語にする

- **決定** (2026-10-20): クローズ済みの probe の pull request (#42 から #93) のタイトルと本文を英語に書き換え、会話のコメントも英語にする。
- **却下した案**: コメントを日本語のまま残す。
