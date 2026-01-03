FROM hashicorp/terraform:1.14

RUN apk update && apk add \
  ca-certificates \
  font-noto \
  gcc \
  graphviz \
  musl-dev \
  python3 \
  python3-dev \
  py3-pip

RUN pip3 install tfdiagrams==0.5.0 --break-system-packages

WORKDIR /app

ENTRYPOINT []
