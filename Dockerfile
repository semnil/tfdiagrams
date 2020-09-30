FROM hashicorp/terraform:0.13.3

RUN apk update && apk add \
  ca-certificates \
  font-noto \
  graphviz \
  python3 \
  py3-pip
RUN pip3 install tfdiagrams==0.2.2

ENTRYPOINT []
