ARG PG_MAJOR_VERSION=18

FROM ghcr.io/astral-sh/uv:0.12.13@sha256:b485bd65cc2cf1c9a93b3554012c9c3778cf7b1b5fd3d3096ce9e1226c97e1e6 AS uv

FROM postgres:${PG_MAJOR_VERSION}-trixie AS build

# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION=4.53.6
ARG TARGETOS
ARG TARGETARCH

ENV LC_ALL=C.UTF-8 LANG=C.UTF-8
ENV PGDATA="/var/lib/postgresql/pgpartix"

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
