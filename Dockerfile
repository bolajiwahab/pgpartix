ARG PG_MAJOR_VERSION=18

FROM ghcr.io/astral-sh/uv:0.13.8@sha256:5cc1805e2426484abca4ad46ea783bab281fdb225fd82d8ce6d66a81254bac85 AS uv

FROM kcov/kcov:latest-alpine@sha256:6e6f3f62461100d789ae5b91e0534b65ff1b88f47564ee8edc845096835cd99f AS kcov

# Pin each supported major to a multi-platform manifest index. BuildKit selects
# only the stage requested by PG_MAJOR_VERSION; Renovate updates the pins.
FROM postgres:14-alpine@sha256:0e6cd607ed90b858005f39da5931dad42ff1ea4be37a897ffe325414b0bab029 AS postgres14-alpine
FROM postgres:15-alpine@sha256:fc41cfa8a90c09e84dd723ee764be4b2f59ba6c98b1e5b3fca540adddf68a5ba AS postgres15-alpine
FROM postgres:16-alpine@sha256:f377d590e5474681d4d7838635031a2b50647923b7abfa803ce9b5ff35d5c663 AS postgres16-alpine
FROM postgres:17-alpine@sha256:d3244e8ce3f165ee3c93d9c4a4b1d0fe48b3a89e2287b717fdcbbde92d405065 AS postgres17-alpine
FROM postgres:18-alpine@sha256:1018733457011bf88d81db98cf43aac6d5150afc18787dbe204771fedf80ff95 AS postgres18-alpine

FROM postgres${PG_MAJOR_VERSION}-alpine AS build

# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION=4.54.3
ARG TARGETOS
ARG TARGETARCH

ENV LC_ALL=C.UTF-8 LANG=C.UTF-8
# Keep the disposable cluster under the directory owned by PGP_OS_USER.
ENV PGDATA="/var/lib/pgpartix/data"

# Install OS dependencies
RUN apk add --no-cache bash ca-certificates coreutils findutils git github-cli grep python3 sed wget \
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
    && apk del wget

# Install Python dependencies in an isolated environment.
COPY pyproject.toml uv.lock /opt/pgpartix-project/
RUN --mount=type=bind,from=uv,source=/uv,target=/usr/local/bin/uv \
    UV_PROJECT_ENVIRONMENT=/opt/pgpartix uv sync \
        --project /opt/pgpartix-project --python python3 --no-managed-python \
        --locked --no-dev --no-cache \
    && ln -s /opt/pgpartix/bin/check-jsonschema /usr/local/bin/check-jsonschema \
    && ln -s /opt/pgpartix/bin/pgrubic /usr/local/bin/pgrubic

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

ARG BATS_VERSION=1.14.0
ARG BATS_SHA256=bb537b70b15b732f6d8827dd6578e3d8ce166636ce1f18ea9a074184fcce9177

# Keep coverage tooling and its shared libraries in the test image only.
COPY --from=kcov /usr/local/bin/kcov* /usr/local/bin/

# Install test dependencies and create the tablespace fixture root.
RUN apk add --no-cache libcurl libdw libstdc++ wget zlib \
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
    && apk del wget

# Test changes should not invalidate the dependency-installation layer.
COPY --chown=${PGP_OS_USER}:${PGP_OS_USER} tests tests

USER ${PGP_OS_USER}

FROM build AS runtime

USER ${PGP_OS_USER}
