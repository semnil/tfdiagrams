# English-base decisions

> 日本語版は [english-base.ja.md](english-base.ja.md) を参照してください.

Closed decisions from making English the base language of this repository's documents (#97), with the alternatives that were turned down.

## CLAUDE.md is a tracked file with the language override line

- **Decision** (2026-10-20): `CLAUDE.md` is a tracked file of the repository, and its "Conventions" section carries the line that overrides the language rule.
- **Alternatives turned down**: an untracked `CLAUDE.md` under `.claude/`, which applies only on the machine that holds it; having no `CLAUDE.md`.

## The example README has a Japanese version

- **Decision** (2026-10-20): `example/count/README.md` has a Japanese version beside it, `example/count/README.ja.md`, as the root README does.
- **Alternatives turned down**: leaving that README in English only.

## The probe pull requests are in English, comments included

- **Decision** (2026-10-20): the titles and bodies of the closed probe pull requests (#42 to #93) were rewritten in English, and so were their conversation comments.
- **Alternatives turned down**: leaving the comments in Japanese.
