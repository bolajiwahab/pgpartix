ARG PG_MAJOR_VERSION=18

FROM ghcr.io/astral-sh/uv:0.13.9@sha256:d3b601f0c7b118bc1753febf7c41cc80981df678445e0254284eecf84db79a7d AS uv

FROM kcov/kcov:latest-alpine@sha256:6e6f3f62461100d789ae5b91e0534b65ff1b88f47564ee8edc845096835cd99f AS kcov

# Pin each supported major to a multi-platform manifest index. BuildKit selects
# only the stage requested by PG_MAJOR_VERSION; Renovate updates the pins.
FROM postgres:14-alpine@sha256:e7d9e6aac7fe3232f7661da103aebc0ce38b04105b46af5e9edd5ef6bc343f20 AS postgres14
FROM postgres:15-alpine@sha256:e18480a22d6e48f4d816a6696769b1ec09ac73a824c5649e49c7d8b684913f3d AS postgres15
FROM postgres:16-alpine@sha256:1d5b02d3a9941fbd52437db4107f8c52d6297dac553ca1e5c299ebb3756b4857 AS postgres16
FROM postgres:17-alpine@sha256:526f86d93c6ea08fd3f1fe5605650cacc781b2c6013169a0ad8f42c7d3d84f32 AS postgres17
FROM postgres:18-alpine@sha256:ff64c9e3bdf8e2120107d3559de8db314e8305f7e38c5105903c6295876738ff AS postgres18

# Select one of the digest-pinned stages above.
# hadolint ignore=DL3006
FROM postgres${PG_MAJOR_VERSION} AS build

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION=4.54.3
ARG TARGETOS
ARG TARGETARCH

ENV LC_ALL=C.UTF-8 LANG=C.UTF-8
# Keep the disposable cluster under the directory owned by PGP_OS_USER.
ENV PGDATA="/var/lib/pgpartix/data"

# Install OS dependencies
RUN apk add --no-cache \
        'bash~5.3' \
        'ca-certificates~20261020' \
        'coreutils~9.11' \
        'findutils~4.10' \
        'git~2.54' \
        'github-cli~2.97' \
        'python3~3.14' \
    && apk add --no-cache --virtual .download-deps 'wget~1.25' \
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
    && apk del .download-deps \
    && rm -f /usr/bin/wget

# Install Python dependencies in an isolated environment.
COPY pyproject.toml uv.lock /opt/pgpartix-project/
RUN --mount=type=bind,from=uv,source=/uv,target=/usr/local/bin/uv \
    UV_PROJECT_ENVIRONMENT=/opt/pgpartix uv sync \
        --project /opt/pgpartix-project --python python3 --no-managed-python \
        --locked --no-build --no-dev --no-cache \
    && ln -s /opt/pgpartix/bin/check-jsonschema /usr/local/bin/check-jsonschema \
    && ln -s /opt/pgpartix/bin/pgrubic /usr/local/bin/pgrubic \
    && rm -rf /opt/pgpartix-project

ENV PATH="/opt/pgpartix/bin:${PATH}"

# Run pgpartix and its disposable PostgreSQL cluster as an unprivileged user.
ARG PGP_OS_USER=pgpuser

RUN adduser -D -u 10001 -h /src -s /bin/bash ${PGP_OS_USER} \
    && chown -R "${PGP_OS_USER}:${PGP_OS_USER}" /src \
    && mkdir -p /var/lib/pgpartix \
    && chown -R "${PGP_OS_USER}:${PGP_OS_USER}" /var/lib/pgpartix \
    # pgpartix starts PostgreSQL directly as PGP_OS_USER, without gosu.
    && rm -f /usr/local/bin/gosu

COPY src/bin/* /usr/local/bin/

WORKDIR /src

COPY src/sql sql

COPY src/schema.json ./

ENTRYPOINT []

CMD ["/bin/bash"]

FROM build AS test

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

ARG BATS_VERSION=1.14.0
ARG BATS_SHA256=bb537b70b15b732f6d8827dd6578e3d8ce166636ce1f18ea9a074184fcce9177

# Install test dependencies and create the tablespace fixture root.
COPY --from=kcov /usr/local/bin/kcov* /usr/local/bin/

RUN apk add --no-cache \
        'libcurl~8.23' \
        'libdw~0.195' \
        'libstdc++~15.2' \
        'zlib~1.4' \
    && apk add --no-cache --virtual .download-deps 'wget~1.25' \
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
    && apk del .download-deps \
    && rm -f /usr/bin/wget

# Test changes should not invalidate the dependency-installation layer.
COPY --chown=${PGP_OS_USER}:${PGP_OS_USER} tests tests

USER ${PGP_OS_USER}

FROM build AS runtime

USER ${PGP_OS_USER}
