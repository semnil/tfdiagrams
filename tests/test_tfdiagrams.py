import re
from importlib.metadata import version
from pathlib import Path


def test_version():
    assert version('tfdiagrams')


def test_dockerfile_default_version():
    dockerfile = (Path(__file__).resolve().parent.parent / 'Dockerfile').read_text()
    defaults = re.findall(r'^ARG TFDIAGRAMS_VERSION=(\S+)$', dockerfile, re.MULTILINE)
    assert defaults == [version('tfdiagrams')]
