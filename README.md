# tfdiagrams

Generate Diagram from terraform output.

## Required packaging tool:

[Poetry](https://python-poetry.org)

## Usage:

```bash
tdot [ flags ] [ input file path ]
```

If no input files are supplied, the program reads from **stdin**.

### Install packages

```bash
$ poetry install
Invoke commands

$ poetry run tdot ...
or

$ poetry shell
$ tdot
```

### Flags

**-T***format*  
Set output language to one of the supported formats. By default, attributed dot is produced.

**-o***outfile*  
Write output to file outfile.

**-e***keyword,comma,separated*  
Exclude keywords separated by commas

## Usage (docker):
```bash
docker run --rm -it \
  --workdir=/app \
  -v "$PWD:/app" \
  semnil/tfdiagrams sh -c "terraform init && terraform graph | tfdot -ograph.png"
```