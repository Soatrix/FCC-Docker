# syntax=docker/dockerfile:1.7
FROM python:3.14-slim-bookworm

ARG FCC_VERSION=6.19.57
ARG VCS_REF=unknown
ARG SOURCE_URL=https://github.com/soatrix/FCC-Docker

LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.title="Free Claude Code (FCC) sidecar" \
      org.opencontainers.image.description="Internal Free Claude Code sidecar for Paperclip on EasyPanel" \
      org.opencontainers.image.version="${FCC_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/root \
    HOST=0.0.0.0 \
    PORT=8082 \
    MODEL=nvidia_nim/nvidia/nemotron-3-ultra-550b-a55b \
    FCC_CONFIG_SCHEMA=2 \
    FCC_OPEN_BROWSER=false \
    PROXY_AUTH_ENABLED=false \
    UV_INSTALL_DIR=/usr/local/bin \
    UV_NO_MODIFY_PATH=1 \
    PATH="/root/.local/bin:/usr/local/bin:${PATH}"

# Runtime dependencies only. No credentials are copied or baked into the image.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# Install uv non-interactively, then install the exact Python and FCC release.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
 && uv python install 3.14.10 \
 && uv tool install --python "$(uv python find 3.14.10)" "free-claude-code==${FCC_VERSION}" \
 && test -x /root/.local/bin/fcc-server \
 && test -x /root/.local/bin/fcc-claude \
 && test -x /root/.local/bin/fcc-doctor \
 && mkdir -p /root/.fcc/logs

EXPOSE 8082

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["curl", "-fsS", "http://127.0.0.1:8082/v1/models?view=messages"]

CMD ["fcc-server"]
