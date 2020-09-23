FROM hashicorp/terraform:0.13.3

RUN apk update && apk add \
  ca-certificates \
  font-noto \
  graphviz \
  python3
RUN pip3 install tfdiagrams

ENTRYPOINT []
