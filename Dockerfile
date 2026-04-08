FROM hashicorp/terraform:1.14

ARG TFDIAGRAMS_VERSION=0.5.1

RUN apk update && apk add \
  ca-certificates \
  font-noto \
  gcc \
  graphviz \
  musl-dev \
  python3 \
  python3-dev \
  py3-pip

RUN pip3 install tfdiagrams==${TFDIAGRAMS_VERSION} --break-system-packages

WORKDIR /app

ENTRYPOINT []
