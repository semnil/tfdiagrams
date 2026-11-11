# Release flow decisions

> 日本語版は [release-flow.ja.md](release-flow.ja.md) を参照してください.

Closed decisions about how a version of tfdiagrams is released, with the alternatives that were turned down. The flow itself is in [README.md](../../README.md) "Release"; this document holds why it has that shape.

## Publishing the draft Release is the release gate

- **Decision** (2026-10-20): merging a version bump only tags the commit and creates a draft GitHub Release. Publishing that draft by hand is the step that uploads to PyPI and pushes the Docker images.
- **Alternatives turned down**: publishing as soon as the version bump is merged.
- **What depends on it**:
  - `release.yml` keeps its file name and its `release` environment, because the PyPI trusted publisher names both. Renaming either stops the upload.
  - A re-run of `tag-release.yml` with the tag already on the tested commit looks for the draft with `gh release list`, and relies on that list holding draft Releases for the workflow's token, which has `contents: write`.

## A version bump also sets the Dockerfile default

- **Decision** (2026-10-20): the pull request that bumps `version` in `pyproject.toml` also sets the `TFDIAGRAMS_VERSION` default in `Dockerfile` to the new version. `tests/test_tfdiagrams.py::test_dockerfile_default_version` fails when the two differ.
- **Alternatives turned down**: removing the default, so that every build passes the version; installing the local source in the default stage instead of a version from PyPI.
- **Accepted cost**: between merging a version bump and publishing its draft, a `docker build .` without a build argument fails, because the default stage installs a version PyPI does not have yet.

## The Example workflow builds the image from the pull request's source

- **Decision** (2026-10-20): the Example workflow builds a wheel from the pull request's checkout (`poetry build -f wheel`) and builds the `source` stage of `Dockerfile` with it, so the graph is rendered with the pull request's code.
- **Reason**: once the Dockerfile default moves in the version bump pull request, the default stage asks PyPI for a version that is not published yet, and the Example job would fail on every version bump pull request.
- **Alternatives turned down**: passing the latest version on PyPI as the build argument; leaving the Dockerfile default alone in the version bump and raising it in a separate pull request after the release.
- **Background**: the order of the two steps changed with this flow. Before it, a tag pushed by hand started the upload straight away (0.5.2), and the releases up to 0.5.1 are older than `release.yml`. Now the version is merged first and stays unpublished until the draft is published, so a pull request can name a version PyPI does not have.

## Rebase merging is disabled

- **Decision** (2026-10-20): rebase merging is off in the repository settings (`allow_rebase_merge: false`), so that a merged version bump is not missed.
- **Reason**: `tag-release.yml` finds a version bump by comparing the commit CI tested with that commit's first parent. With rebase merging off, the first parent of a commit on master is the previous tip of master.
- **Alternatives turned down**: leaving the setting as it was; making `tag-release.yml` fail when the current version has no tag.

## A draft published as a pre-release is released the same way

- **Decision** (2026-10-20): `release.yml` does not turn down a Release that is published as a pre-release. It uploads to PyPI and pushes the Docker images as it does for any published Release.
