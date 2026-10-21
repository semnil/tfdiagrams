FROM hashicorp/terraform:1.16 AS base

RUN apk update && apk upgrade && apk add \
  ca-certificates \
  font-noto \
  gcc \
  graphviz \
  musl-dev \
  python3 \
  python3-dev \
  py3-pip

WORKDIR /app

ENTRYPOINT []

# Installs the wheel that `poetry build -f wheel` wrote to dist/ from this checkout. The Example workflow builds this
# target.
FROM base AS source

COPY dist/ /tmp/dist/

RUN pip3 install /tmp/dist/*.whl --break-system-packages

# The default target installs TFDIAGRAMS_VERSION from PyPI. release.yml passes the tag as TFDIAGRAMS_VERSION.
FROM base

ARG TFDIAGRAMS_VERSION=0.5.3

RUN pip3 install tfdiagrams==${TFDIAGRAMS_VERSION} --break-system-packages
