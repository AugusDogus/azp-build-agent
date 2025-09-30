FROM python:3-alpine

ENV TARGETARCH="linux-musl-x64"
ENV AGENT_ALLOW_RUNASROOT="true"

RUN apk update && apk upgrade && apk add --no-cache \
    bash curl git jq icu-libs docker docker-cli \
    python3-dev libffi-dev openssl-dev gcc musl-dev make cargo

RUN mkdir -p /usr/libexec/docker/cli-plugins && \
    curl -sSL https://github.com/docker/buildx/releases/download/v0.11.2/buildx-v0.11.2.linux-amd64 \
      -o /usr/libexec/docker/cli-plugins/docker-buildx && \
    chmod +x /usr/libexec/docker/cli-plugins/docker-buildx

RUN pip install --upgrade pip azure-cli

WORKDIR /azp
COPY start.sh .
RUN chmod +x start.sh

ENTRYPOINT ["./start.sh"]
