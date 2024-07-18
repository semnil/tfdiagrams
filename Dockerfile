FROM hashicorp/terraform:1.9.2

RUN apk update && apk add \
  ca-certificates \
  font-noto \
  graphviz \
  python3 \
  py3-pip
RUN pip3 install tfdiagrams==0.2.4

ENTRYPOINT []
