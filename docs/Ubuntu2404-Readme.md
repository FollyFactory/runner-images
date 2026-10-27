# ubuntu2404

`ghcr.io/follyfactory/runner-images/ubuntu2404`

Ubuntu 24.04 (noble), `linux/amd64` and `linux/arm64`. Built from
[`images/ubuntu2404/Dockerfile`](../images/ubuntu2404/Dockerfile); the versions
below are that Dockerfile's build-arg defaults, and
`docker run --rm <image> verify-image` re-checks them inside a built image.

## Runner agent

| Component | Version | Path |
|-----------|---------|------|
| actions/runner | 2.338.2 | `/home/runner` |
| Container hooks (k8s) | 0.8.1 | `/home/runner/k8s/index.js` |
| Container hooks (docker) | 0.8.1 | `/home/runner/docker/index.js` |

The runner user is `runner` (uid 1001), in `sudo` (passwordless) and `docker`
(gid 123). `ImageOS=ubuntu24`, `RUNNER_MANUALLY_TRAP_SIG=1` and
`ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1` are set, as in the official image.

## Language and runtime

### Node.js

Installed into the hosted tool cache, so `actions/setup-node` resolves them
without a download. `/opt/node` symlinks the newest and is on `PATH`.

| Version | Tool cache path |
|---------|-----------------|
| 22.23.4 | `/opt/hostedtoolcache/node/22.23.4/<arch>` |
| 24.22.1 | `/opt/hostedtoolcache/node/24.22.1/<arch>` |

### .NET SDK

All in `/usr/share/dotnet` (`DOTNET_ROOT`), side by side, owned by `runner` so
`actions/setup-dotnet` can add more. Pick one per repo with `global.json`.

| Band | SDK | Runtime |
|------|-----|---------|
| 9.0.1xx | 9.0.121 | 9.0.20 |
| 9.0.2xx | 9.0.205 | 9.0.6 |
| 9.0.3xx | 9.0.318 | 9.0.20 |
| 10.0.1xx | 10.0.112 | 10.0.12 |
| 10.0.2xx | 10.0.204 | 10.0.8 |
| 10.0.3xx | 10.0.303 | 10.0.11 |
| 10.0.4xx | 10.0.401 | 10.0.12 |

`DOTNET_CLI_TELEMETRY_OPTOUT=1`, `DOTNET_NOLOGO=1`,
`DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1` and `NUGET_XMLDOC_MODE=skip` are set.
`~/.dotnet/tools` is on `PATH`, for `dotnet tool restore`/`dotnet tool install`.

### Python

| Name | Version |
|------|---------|
| python3 (`python` → `python3`) | 3.12 (noble) |
| pip, venv | from the distro |

## Databases

### PostgreSQL

| Name | Version |
|------|---------|
| PostgreSQL server + client (PGDG) | 18.x |

```
Host: 127.0.0.1    Port: 5432
User: postgres     Password: postgres
```

The service is **stopped by default**, like the hosted images. Start it from a
job with `start-postgres` (it waits for readiness) and stop it with
`stop-postgres`; neither needs an explicit `sudo`. `START_POSTGRES=1` in the
container environment starts it before the runner comes up.

Local auth is `trust` for the `postgres` superuser over the unix socket and
`scram-sha-256` over `127.0.0.1`; `listen_addresses` is `localhost`.

### SQLite

| Name | Version |
|------|---------|
| sqlite3 | from the distro |

## Container tooling

No daemon ships in the image. Jobs reach one through an ARC dind sidecar or a
mounted `/var/run/docker.sock`.

| Name | Version |
|------|---------|
| docker CLI (static) | 29.9.2 |
| docker buildx plugin | 0.38.1 |
| docker compose plugin | 5.6.1 |

## CLI tools

| Name | Version / source |
|------|------------------|
| railway (Railway CLI) | 5.71.0, release binary in `/usr/local/bin` |
| git | `ppa:git-core/ppa` |
| git-lfs | distro |
| gh (GitHub CLI) | cli.github.com apt repo |
| jq | distro |
| curl, wget | distro |
| rsync, zip, unzip, tar, xz-utils, zstd, bzip2, pigz | distro |
| openssh-client, gnupg | distro |
| dnsutils, iproute2, iputils-ping, netcat-openbsd, net-tools | distro |
| shellcheck | distro |
| parallel, tree, file, less, time, procps | distro |

## Build tooling

| Name | Source |
|------|--------|
| build-essential (gcc, g++, make) | distro |
| pkg-config, libtool via build-essential deps | distro |
| libicu-dev, libssl-dev, libkrb5-dev, libsqlite3-dev, libpq-dev | distro |

## Environment

| Variable | Value |
|----------|-------|
| `ImageOS` | `ubuntu24` |
| `RUNNER_TOOL_CACHE`, `AGENT_TOOLSDIRECTORY` | `/opt/hostedtoolcache` |
| `DOTNET_ROOT` | `/usr/share/dotnet` |
| `POSTGRES_MAJOR` | `18` |
| `LANG`, `LC_ALL` | `en_US.UTF-8` |
| `TZ` | `Etc/UTC` |
| `PATH` additions | `/opt/node/bin`, `/usr/share/dotnet`, `/home/runner/.dotnet/tools` |

## Shared-workflow coverage

What [cur-10/workflows](https://github.com/cur-10/workflows) needs from a
runner, and where it comes from:

| Workflow / action | Needs | Provided by |
|-------------------|-------|-------------|
| `dotnet-build-test` | `docker run`/`inspect` for `postgres:18`, `psql`, `actions/setup-dotnet` + `global.json`, `dotnet restore`/`format`/`build`/`test`, `dotnet tool restore` → `dotnet ef`, efbundle execution | docker CLI (+ dind), PostgreSQL 18 client, the seven SDKs |
| `node-build-test` | `actions/setup-node` with `.nvmrc`, `npm ci` and the lint/test/build scripts | Node 22 + 24 in the tool cache |
| `container-release`, `container-rollback` | `docker login`/`build`/`push`/`manifest inspect`, `docker buildx imagetools`, `git tag`, `gh api`, `gh release` | docker CLI + buildx, git, gh |
| `dotnet-api-release`, `dotnet-api-rollback` | the above plus `dotnet ef migrations bundle` and running the bundle | SDKs, docker CLI, gh |
| `railway-deploy` | `docker buildx imagetools`, `jq`, `npm install --global @railway/cli` then `railway` on `PATH` | buildx, jq, Node with a writable global prefix on `PATH`; `railway` 5.71.0 is also preinstalled for direct use |
| `verify-version`, `next-version` | `curl`, `jq`, `git log`/`tag`, `gh api`, bash with `sed -E`/`sort -V` | the CLI baseline |
| `docs-checks` | `actions/create-github-app-token`, `awk`, `diff` | Node, distro coreutils/diffutils |
| `tests` | `docker run rhysd/actionlint` | docker CLI (+ dind) |
