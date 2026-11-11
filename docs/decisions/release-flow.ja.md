# リリースの流れの決定

> For the English version, see [release-flow.md](release-flow.md).

tfdiagrams の版をどうリリースするかについて閉じた判断と、却下した案を持つ。流れそのものは [README.ja.md](../../README.ja.md) の「リリース」にある。この文書は、その形にした理由を持つ。

## 版上げで Dockerfile の既定値も上げる

- **決定** (2026-10-20): `pyproject.toml` の `version` を上げる pull request で、`Dockerfile` の `TFDIAGRAMS_VERSION` の既定値も新しい版にする。2 つが違うと `tests/test_tfdiagrams.py::test_dockerfile_default_version` が失敗する。
- **却下した案**: 既定値を消して、どのビルドでも版を渡す。既定のステージで、PyPI の版ではなくローカルのソースを入れる。
- **受け入れた代償**: 版上げをマージしてから下書きを公開するまでのあいだ、ビルド引数を付けない `docker build .` は失敗する。既定のステージが、PyPI にまだ無い版を入れようとするため。

## Example ワークフローは pull request のソースからイメージを作る

- **決定** (2026-10-20): Example ワークフローは、pull request のチェックアウトから wheel を作り (`poetry build -f wheel`)、それを使って `Dockerfile` の `source` ステージをビルドする。グラフは pull request のコードで描かれる。
- **理由**: 版上げの pull request で Dockerfile の既定値が動くと、既定のステージはまだ公開されていない版を PyPI に求める。Example のジョブは、版上げの pull request のたびに失敗することになる。
- **却下した案**: PyPI の最新の版をビルド引数で渡す。版上げでは Dockerfile の既定値を動かさず、リリースの後に別の pull request で上げる。
- **経緯**: この流れで 2 つの手順の順序が変わった。以前は、手で push したタグがすぐにアップロードを始めていた (0.5.2)。0.5.1 までのリリースは `release.yml` より前のもの。今は版を先にマージし、下書きを公開するまで未公開のままなので、pull request が PyPI に無い版を名指しすることがある。

## rebase マージを無効にする

- **決定** (2026-10-20): リポジトリの設定で rebase マージを無効にする (`allow_rebase_merge: false`)。マージした版上げを取りこぼさないため。
- **理由**: `tag-release.yml` は、CI が検査したコミットとその第 1 親を比べて版上げを見つける。rebase マージが無効なら、master 上のコミットの第 1 親は、その前の master の先端になる。
- **却下した案**: 設定をそのままにする。今の版のタグが無いときに `tag-release.yml` を失敗させる。

## pre-release として公開した下書きも同じようにリリースする

- **決定** (2026-10-20): `release.yml` は、pre-release として公開された Release を拒まない。公開されたほかの Release と同じように、PyPI へアップロードし、Docker イメージを push する。
