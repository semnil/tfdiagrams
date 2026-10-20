"""Release version rules shared by tag-release.yml and release.yml.

python3 .github/scripts/release_version.py read < pyproject.toml
    Prints the [tool.poetry] version of the pyproject.toml on stdin. Exits 1 when it holds none or is not TOML.
python3 .github/scripts/release_version.py check <version>
    Exits 0 when <version> is a release version (X.Y.Z), which is also the release tag, and exits 1 with an
    ::error:: line otherwise.
"""

import re
import sys
import tomllib


def read():
    try:
        version = tomllib.load(sys.stdin.buffer)["tool"]["poetry"]["version"]
    except (tomllib.TOMLDecodeError, KeyError, TypeError) as err:
        print(f"no [tool.poetry] version: {err!r}", file=sys.stderr)
        return 1
    print(version)
    return 0


def check(version):
    if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        return 0
    shown = " ".join(version.splitlines())
    print(f"::error::version {shown} is not a release version (X.Y.Z)")
    return 1


def main(argv):
    if argv == ["read"]:
        return read()
    if len(argv) == 2 and argv[0] == "check":
        return check(argv[1])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
