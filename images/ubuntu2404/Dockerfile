# syntax=docker/dockerfile:1.7
# FollyFactory CI runner image - Ubuntu 24.04.
#
# Modelled on actions/runner-images (hosted ubuntu-24.04) for the toolchain and
# on actions/runner's own container image for the agent, so the same image can be
# used as a plain job container, a standalone self-hosted runner, or an
# actions-runner-controller (ARC) scale-set runner.
#
# Toolchain: Node.js 22 + 24 (in the hosted tool cache), the four .NET 10 SDK
# bands side by side, PostgreSQL 18 (stopped by default), the Railway CLI, and
# docker CLI + buildx + compose.

ARG UBUNTU_VERSION=24.04

# ---------------------------------------------------------------------------
# Downloads: everything fetched from a release URL, so the final image carries
# no curl/unzip scratch space and the layers rebuild independently.
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS downloads

ARG TARGETOS
ARG TARGETARCH
ARG RUNNER_VERSION=2.338.2
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.8.1
ARG DOCKER_VERSION=29.9.2
ARG BUILDX_VERSION=0.38.1
ARG COMPOSE_VERSION=5.6.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /downloads

# actions/runner. ARC's scale-set controller execs /home/runner/run.sh from this.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) runner_arch=x64 ;; \
        arm64) runner_arch=arm64 ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    mkdir -p actions-runner; \
    curl -fsSL -o runner.tar.gz \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${TARGETOS}-${runner_arch}-${RUNNER_VERSION}.tar.gz"; \
    tar xzf runner.tar.gz -C actions-runner; \
    rm runner.tar.gz

# Container hooks: k8s hooks drive ARC's containerMode=kubernetes, docker hooks
# drive container jobs/services when a docker daemon is reachable.
RUN set -eux; \
    for flavour in k8s docker; do \
        curl -fsSL -o hooks.zip \
            "https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-${flavour}-${RUNNER_CONTAINER_HOOKS_VERSION}.zip"; \
        unzip -q hooks.zip -d "actions-runner/${flavour}"; \
        rm hooks.zip; \
    done

# docker CLI (static), buildx and compose plugins. No daemon: jobs talk to a
# dind sidecar (ARC containerMode=dind) or a mounted socket.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) docker_arch=x86_64 ;; \
        arm64) docker_arch=aarch64 ;; \
    esac; \
    curl -fsSL -o docker.tgz \
        "https://download.docker.com/${TARGETOS}/static/stable/${docker_arch}/docker-${DOCKER_VERSION}.tgz"; \
    tar xzf docker.tgz --strip-components=1 -C /usr/local/bin docker/docker; \
    rm docker.tgz; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-buildx \
        "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.${TARGETOS}-${TARGETARCH}"; \
    curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
        "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-${TARGETOS}-${docker_arch}"; \
    chmod 0755 /usr/local/lib/docker/cli-plugins/docker-buildx /usr/local/lib/docker/cli-plugins/docker-compose

# Railway CLI. The release binary rather than `npm install --global @railway/cli`,
# so it survives a job switching Node versions with actions/setup-node.
ARG RAILWAY_CLI_VERSION=5.71.0
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) railway_target=x86_64-unknown-linux-musl ;; \
        arm64) railway_target=aarch64-unknown-linux-musl ;; \
    esac; \
    curl -fsSL "https://github.com/railwayapp/cli/releases/download/v${RAILWAY_CLI_VERSION}/railway-v${RAILWAY_CLI_VERSION}-${railway_target}.tar.gz" \
        | tar -xz -C /usr/local/bin railway; \
    chmod 0755 /usr/local/bin/railway

# ---------------------------------------------------------------------------
# Runner image
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION}

ARG TARGETARCH
# Space-separated so a thinner image is a --build-arg away.
ARG NODE_VERSIONS="22.23.4 24.22.1"
ARG DOTNET_SDK_VERSIONS="10.0.112 10.0.204 10.0.303 10.0.401"
ARG POSTGRES_MAJOR=18

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    TZ=Etc/UTC
# ImageOS is what actions/*-versions lookups key off; the other two are what
# actions/runner expects when it is PID 1 in a container.
ENV ImageOS=ubuntu24 \
    RUNNER_MANUALLY_TRAP_SIG=1 \
    ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1
ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache \
    AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
ENV DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    NUGET_XMLDOC_MODE=skip \
    POSTGRES_MAJOR=${POSTGRES_MAJOR}
ENV PATH=/opt/node/bin:/usr/share/dotnet:/home/runner/.dotnet/tools:$PATH

# Baseline: the subset of the hosted ubuntu-24.04 apt set that build, test and
# packaging steps actually reach for, plus the .NET SDK's own dependencies.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        apt-transport-https \
        bash \
        bzip2 \
        ca-certificates \
        curl \
        dnsutils \
        file \
        findutils \
        gettext \
        gnupg \
        gpg-agent \
        iproute2 \
        iputils-ping \
        jq \
        less \
        libicu74 \
        libssl3t64 \
        locales \
        lsb-release \
        netcat-openbsd \
        openssh-client \
        parallel \
        pigz \
        procps \
        rsync \
        software-properties-common \
        sqlite3 \
        sudo \
        tar \
        time \
        tree \
        tzdata \
        unzip \
        wget \
        xz-utils \
        zip \
        zstd; \
    locale-gen en_US.UTF-8; \
    rm -rf /var/lib/apt/lists/*

# Build toolchain, kept in its own layer because it is the heaviest apt step.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        libicu-dev \
        libkrb5-dev \
        libsqlite3-dev \
        libssl-dev \
        pkg-config \
        python3 \
        python3-pip \
        python3-venv \
        python-is-python3 \
        shellcheck; \
    rm -rf /var/lib/apt/lists/*

# git from ppa:git-core (as the hosted images do - noble's git is older), and gh.
RUN set -eux; \
    add-apt-repository -y ppa:git-core/ppa; \
    mkdir -p -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    chmod 0644 /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=${TARGETARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends git git-lfs gh; \
    rm -rf /var/lib/apt/lists/*

# runner user: uid 1001 and gid 123 for the docker group are what ARC and the
# official runner image use, so volumes and hook-created pods line up.
RUN set -eux; \
    adduser --disabled-password --gecos "" --uid 1001 runner; \
    groupadd docker --gid 123; \
    usermod -aG sudo runner; \
    usermod -aG docker runner; \
    echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner; \
    echo 'Defaults env_keep += "DEBIAN_FRONTEND"' >> /etc/sudoers.d/runner; \
    chmod 0440 /etc/sudoers.d/runner; \
    chmod 0777 /home/runner; \
    install -d -o runner -g docker -m 0775 /opt/hostedtoolcache /home/runner/_work

# Node.js, laid into the hosted tool cache so actions/setup-node resolves these
# versions offline. /opt/node points at the newest and is on PATH, which also
# puts `npm install --global` binaries on PATH - railway-deploy installs its own
# pinned @railway/cli that way, over the release binary below.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) node_arch=x64 ;; \
        arm64) node_arch=arm64 ;; \
    esac; \
    for version in ${NODE_VERSIONS}; do \
        dest="/opt/hostedtoolcache/node/${version}/${node_arch}"; \
        mkdir -p "${dest}"; \
        curl -fsSL "https://nodejs.org/dist/v${version}/node-v${version}-linux-${node_arch}.tar.xz" \
            | tar -xJ --strip-components=1 -C "${dest}"; \
        touch "/opt/hostedtoolcache/node/${version}/${node_arch}.complete"; \
    done; \
    default_version="$(echo ${NODE_VERSIONS} | tr ' ' '\n' | sort -V | tail -1)"; \
    ln -sfn "/opt/hostedtoolcache/node/${default_version}/${node_arch}" /opt/node; \
    chown -R runner:docker /opt/hostedtoolcache/node; \
    node --version; \
    npm --version

# .NET SDKs, side by side in one root. Projects pick a band with global.json;
# `dotnet --list-sdks` shows them all.
RUN set -eux; \
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh; \
    chmod +x /tmp/dotnet-install.sh; \
    for version in ${DOTNET_SDK_VERSIONS}; do \
        /tmp/dotnet-install.sh --version "${version}" --install-dir "${DOTNET_ROOT}" --no-path; \
    done; \
    rm /tmp/dotnet-install.sh; \
    ln -sf "${DOTNET_ROOT}/dotnet" /usr/local/bin/dotnet; \
    chown -R runner:docker "${DOTNET_ROOT}"; \
    dotnet --list-sdks

# PostgreSQL, from PGDG so the major matches the server the workflows run
# (postgres:18) - a client older than the server breaks pg_dump. The package
# postinst creates the `main` cluster; we set the postgres password and local
# auth here and leave the server stopped, as the hosted images do. Jobs that
# want it bring it up with `start-postgres`.
COPY scripts/start-postgres.sh /usr/local/bin/start-postgres
COPY scripts/stop-postgres.sh /usr/local/bin/stop-postgres
RUN set -eux; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg; \
    chmod 0644 /etc/apt/keyrings/postgresql.gpg; \
    echo "deb [arch=${TARGETARCH} signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt noble-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        "postgresql-${POSTGRES_MAJOR}" \
        "postgresql-client-${POSTGRES_MAJOR}" \
        libpq-dev; \
    rm -rf /var/lib/apt/lists/*; \
    conf="/etc/postgresql/${POSTGRES_MAJOR}/main"; \
    sed -i "s/^#\?listen_addresses.*/listen_addresses = 'localhost'/" "${conf}/postgresql.conf"; \
    { \
        echo "local   all   postgres            trust"; \
        echo "local   all   all                 scram-sha-256"; \
        echo "host    all   all   127.0.0.1/32  scram-sha-256"; \
        echo "host    all   all   ::1/128       scram-sha-256"; \
    } > "${conf}/pg_hba.conf"; \
    pg_ctlcluster --skip-systemctl-redirect "${POSTGRES_MAJOR}" main start; \
    su postgres -c "psql -q -c \"ALTER USER postgres WITH PASSWORD 'postgres'\""; \
    pg_ctlcluster --skip-systemctl-redirect "${POSTGRES_MAJOR}" main stop; \
    chmod 0755 /usr/local/bin/start-postgres /usr/local/bin/stop-postgres

COPY --from=downloads /usr/local/bin/docker /usr/local/bin/docker
COPY --from=downloads /usr/local/bin/railway /usr/local/bin/railway
COPY --from=downloads /usr/local/lib/docker/cli-plugins /usr/local/lib/docker/cli-plugins
COPY --from=downloads --chown=runner:docker /downloads/actions-runner /home/runner
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY verify.sh /usr/local/bin/verify-image
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/verify-image

LABEL org.opencontainers.image.title="FollyFactory runner image (Ubuntu 24.04)" \
      org.opencontainers.image.description="Self-hosted/ARC Actions runner with Node.js 22+24, four .NET 10 SDKs, PostgreSQL 18 and the Railway CLI" \
      org.opencontainers.image.source="https://github.com/FollyFactory/runner-images" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /home/runner
USER runner

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/home/runner/run.sh"]
