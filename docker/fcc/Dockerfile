# syntax=docker/dockerfile:1.7
FROM python:3.14-slim-bookworm

ARG FCC_VERSION
ARG VCS_REF=unknown
ARG SOURCE_URL=https://github.com/Soatrix/FCC-Docker

LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.title="Free Claude Code (FCC)" \
      org.opencontainers.image.description="Free Claude Code API gateway for EasyPanel" \
      org.opencontainers.image.revision="${VCS_REF}"

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/root \
    HOST=0.0.0.0 \
    PORT=8082 \
    FCC_OPEN_BROWSER=false \
    PROXY_AUTH_ENABLED=false \
    UV_INSTALL_DIR=/usr/local/bin \
    UV_NO_MODIFY_PATH=1 \
    UV_TOOL_DIR=/opt/fcc-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    PYTHONUNBUFFERED=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl tini \
 && rm -rf /var/lib/apt/lists/*

# Build context is the repository root. The version manifest is authoritative
# unless an explicit FCC_VERSION build argument is supplied.
COPY config/fcc-version.json /opt/fcc-version.json
RUN set -eu; \
    version="${FCC_VERSION:-$(python -c 'import json; print(json.load(open("/opt/fcc-version.json"))["version"])')}"; \
    curl -LsSf https://astral.sh/uv/install.sh | sh; \
    uv python install 3.14.10; \
    uv tool install --python "$(uv python find 3.14.10)" "free-claude-code==${version}"; \
    fcc-server --version; \
    test -x /usr/local/bin/fcc-claude; \
    test -x /usr/local/bin/fcc-doctor; \
    mkdir -p /root/.fcc

COPY docker/fcc/entrypoint.py /usr/local/lib/fcc-entrypoint.py
EXPOSE 8082

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
  CMD python -c 'import os, urllib.request; urllib.request.urlopen("http://127.0.0.1:"+os.environ.get("PORT","8082")+"/health", timeout=4).close()'

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/fcc-tools/free-claude-code/bin/python", "/usr/local/lib/fcc-entrypoint.py"]
CMD ["fcc-server"]
