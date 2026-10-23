# CLAUDE.md

## Conventions

- **Override of the global CLAUDE.md's 「ドキュメント」 language rule**: this file is written entirely in English, and each document is maintained in English at its path with a Japanese version beside it as `<name>.ja.md`

## Commands

Poetry project (Python `^3.12`). The commands CI runs:

```bash
poetry install --no-interaction   # install deps into the Poetry venv
poetry run pytest -q              # run tests
poetry build                      # build sdist + wheel into dist/
```

Rendering a diagram also needs the Graphviz `dot` binary on PATH (pydot shells out to it); install it separately (e.g. `brew install graphviz`).

## Architecture

CLI `tfdot` turns `terraform graph` DOT output into an image:

- `tfdiagrams/console/__init__.py` — `main`, the `tfdot` entry point (argparse flags `-n -T -o -e`; reads a file argument, else stdin).
- `tfdiagrams/generate.py` — `Diagram` parses the DOT with pydot, swaps each node for a `diagrams` library icon, and writes the image through Graphviz (`prog='dot'`).
- `tfdiagrams/resources.py` — `RESOURCES_MAP`: a large static dict mapping a Terraform resource type (e.g. `aws_instance`) to a `diagrams` class path (e.g. `aws.compute.EC2Instance`), or `None` for no icon. `generate.py` resolves a value `v` as `eval('diagrams.' + v + '()')`, so a malformed value raises at render time.

## Gotchas

- The version lives in two files that must stay in sync: `version` in `pyproject.toml` and the `ARG TFDIAGRAMS_VERSION` default in `Dockerfile`. `tests/test_tfdiagrams.py::test_dockerfile_default_version` fails if they drift — bump both together. For the full release flow, see README.md "Release".
- Opening a PR triggers the `Example` workflow (`.github/workflows/workflow.yml`): it rebuilds `example/count/graph.png` from your branch and pushes the update back onto the branch (commit and push are skipped for Dependabot).
