FROM hashicorp/terraform:0.12.21

RUN apk update && apk add \
  ca-certificates \
  graphviz \
  python3
RUN pip3 install tfdiagrams

ENTRYPOINT []
