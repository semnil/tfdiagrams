FROM hashicorp/terraform:1.9.2

RUN apk update && apk add \
  ca-certificates \
  font-noto \
  gcc \
  graphviz \
  musl-dev \
  python3 \
  python3-dev \
  py3-pip

WORKDIR /app
COPY tfdiagrams/ ./tfdiagrams/
COPY poetry.lock .
COPY pyproject.toml .

RUN pip3 install poetry --break-system-packages \
  && pip3 install packaging==24.1 --break-system-packages \
  && poetry config virtualenvs.create false --local

RUN /usr/bin/poetry install

ENTRYPOINT []
