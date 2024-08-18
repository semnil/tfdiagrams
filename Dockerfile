FROM hashicorp/terraform:1.9.4

RUN apk update && apk add \
  ca-certificates \
  font-noto \
  gcc \
  graphviz \
  musl-dev \
  python3 \
  python3-dev \
  py3-pip

RUN pip3 install tfdiagrams==0.3.0 --break-system-packages

ENTRYPOINT []
