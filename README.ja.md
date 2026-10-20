# tfdiagrams

Terraform の出力からダイアグラムを生成する。

> For the English version, see [README.md](README.md).

![](example/count/graph.png)

## 使い方 (CLI):

```bash
tfdot [ flags ] [ input file path ]
# terraform graph | tfdot -ograph.png
```

入力ファイルを指定しない場合は **stdin** から読み込む。

### パッケージのインストール

```bash
$ pip install tfdiagrams
```

### フラグ

**-T***format*  
出力形式を対応する形式のいずれかに設定する。既定では png 画像を出力する。

**-o***outfile*  
出力をファイル outfile に書き込む。

**-e***keyword,comma,separated*  
カンマ区切りで指定したキーワードを除外する

## 使い方 (docker):
```bash
docker run --rm -it \
  --workdir=/app \
  -v "$PWD:/app" \
  semnil/tfdiagrams sh -c "terraform init && terraform graph | tfdot -ograph.png"
```

## リリース

1. 版だけを変更する pull request を作ってマージする。版とは `pyproject.toml` の `version` と、`Dockerfile` の `TFDIAGRAMS_VERSION` の既定値である。
2. master で CI が成功すると、`tag-release.yml` がマージされたコミットに版のタグ (例: `0.5.3`) を付け、自動生成のノート付きで GitHub Release の下書きを作る。
3. 必要ならノートを編集し、下書きを公開する。公開すると `release.yml` が起動し、タグが `pyproject.toml` の版と一致することを確かめてから、パッケージを PyPI にアップロードし、続いて Docker イメージを Docker Hub と GHCR に push する。

マージした版上げで CI が失敗したら、再実行する。成功すると `tag-release.yml` がもう一度走る。Release はパッケージより先に公開される。`release.yml` が失敗したら、失敗したジョブを再実行する。手で push したタグからは何も起動しない。
