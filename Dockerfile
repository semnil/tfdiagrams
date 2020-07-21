FROM hashicorp/terraform:0.12.26

RUN apk update && apk add \
  ca-certificates \
  font-noto \
  graphviz \
  python3
RUN pip3 install tfdiagrams

ENTRYPOINT []
