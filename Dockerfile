ARG PG_MAJOR_VERSION=18

FROM ghcr.io/astral-sh/uv:0.13.8@sha256:5cc1805e2426484abca4ad46ea783bab281fdb225fd82d8ce6d66a81254bac85 AS uv

# Pin each supported major to a multi-platform manifest index. BuildKit selects
# only the stage requested by PG_MAJOR_VERSION; Renovate updates these digests.
FROM postgres:14-trixie@sha256:980b7cb415aa0f812f65bdec8f6f599be408d8ed9c83ffcaa12650eac397b264 AS postgres14
FROM postgres:15-trixie@sha256:5a407822929c3789ff5154d3d35bd7e2090318149344c8a3d4ca942b035822ed AS postgres15
FROM postgres:16-trixie@sha256:63e83b5a3dc36a917dccb76fe1bd2ac51f1ec9c1deb47ff20d4f04233bf6eae9 AS postgres16
FROM postgres:17-trixie@sha256:846a7ddaa67a4b354ae1d21087b683901aa6113a4ed626d3787cfbf6c85e3e07 AS postgres17
FROM postgres:18-trixie@sha256:b9f6b8ff03b62f3cfd9d9ba3fe56226a9991c79d3fb46fd46536263bf02be553 AS postgres18

FROM postgres${PG_MAJOR_VERSION} AS build

# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION=4.54.3
ARG TARGETOS
ARG TARGETARCH

ENV LC_ALL=C.UTF-8 LANG=C.UTF-8
# Keep the disposable cluster under the directory owned by PGP_OS_USER.
ENV PGDATA="/var/lib/pgpartix/data"

# Install OS dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends wget git ca-certificates python3 \
    # Install GitHub CLI
    && mkdir -p -m 755 /etc/apt/keyrings \
    && wget --quiet -O- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    # Install yq
    && yq_binary="yq_${TARGETOS}_${TARGETARCH}" \
    && wget --quiet "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/${yq_binary}" --output-document=/usr/bin/yq \
    && wget --quiet "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/checksums" --output-document=/tmp/yq-checksums \
    && yq_sha256="$(awk -v binary="${yq_binary}" '$1 == binary {print $19}' /tmp/yq-checksums)" \
    && test -n "${yq_sha256}" \
    && echo "${yq_sha256}  /usr/bin/yq" | sha256sum --check --strict \
    && rm /tmp/yq-checksums \
    && chmod +x /usr/bin/yq \
    # Configure git, ensure it can operate on the mounted working directory,
    # and exclude the local formatting cache globally from commits.
    && git config --system --add safe.directory '*' \
    && echo '.pgrubic_cache/' > /etc/gitexclude \
    && git config --system core.excludesFile /etc/gitexclude \
    && apt-get purge -y --auto-remove wget \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies in an isolated environment.
COPY src/requirements.txt ./
RUN --mount=type=bind,from=uv,source=/uv,target=/usr/local/bin/uv \
    uv venv --python python3 /opt/pgpartix \
    && uv pip install --python /opt/pgpartix/bin/python --no-cache -r requirements.txt \
    && ln -s /opt/pgpartix/bin/check-jsonschema /usr/local/bin/check-jsonschema \
    && ln -s /opt/pgpartix/bin/pgrubic /usr/local/bin/pgrubic

ENV PATH="/opt/pgpartix/bin:${PATH}"

# Run pgpartix and its disposable PostgreSQL cluster as an unprivileged user.
ARG PGP_OS_USER=pgpuser

RUN useradd --uid 10001 --home-dir /src --create-home --shell /bin/bash ${PGP_OS_USER} \
    && chown -R "${PGP_OS_USER}:${PGP_OS_USER}" /src \
    && mkdir -p /var/lib/pgpartix \
    && chown -R "${PGP_OS_USER}:${PGP_OS_USER}" /var/lib/pgpartix

COPY src/bin/* /usr/local/bin/

WORKDIR /src

COPY src/sql sql

COPY src/schema.json ./

ENTRYPOINT []

CMD ["/bin/bash"]

FROM build AS test

ARG BATS_VERSION=1.14.0
ARG BATS_SHA256=bb537b70b15b732f6d8827dd6578e3d8ce166636ce1f18ea9a074184fcce9177

# Install test dependencies and create the tablespace fixture root.
RUN apt-get update \
    && apt-get install -y --no-install-recommends kcov wget \
    && wget --quiet \
        "https://github.com/bats-core/bats-core/archive/refs/tags/v${BATS_VERSION}.tar.gz" \
        --output-document=/tmp/bats-core.tar.gz \
    && echo "${BATS_SHA256}  /tmp/bats-core.tar.gz" | sha256sum --check --strict \
    && tar -xzf /tmp/bats-core.tar.gz \
    && rm /tmp/bats-core.tar.gz \
    && bats-core-${BATS_VERSION}/install.sh /usr/local \
    && rm -rf bats-core-${BATS_VERSION} \
    && mkdir -p /var/lib/pgpartix/tablespaces \
    && chown "${PGP_OS_USER}:${PGP_OS_USER}" /var/lib/pgpartix/tablespaces \
    && apt-get purge -y --auto-remove wget \
    && rm -rf /var/lib/apt/lists/*

# Test changes should not invalidate the dependency-installation layer.
COPY --chown=${PGP_OS_USER}:${PGP_OS_USER} tests tests

USER ${PGP_OS_USER}

FROM build AS runtime

USER ${PGP_OS_USER}
