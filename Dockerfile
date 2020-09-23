FROM hashicorp/terraform:0.13.03

RUN apk update && apk add \
  ca-certificates \
  font-noto \
  graphviz \
  python3
RUN pip3 install tfdiagrams

ENTRYPOINT []
