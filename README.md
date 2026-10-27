# runner-images

Container images for FollyFactory's self-hosted GitHub Actions runners.

One image per OS lives under [`images/`](images). They are modelled on
[actions/runner-images](https://github.com/actions/runner-images) for the
toolchain and on [actions/runner](https://github.com/actions/runner)'s own
container image for the agent, so the same image works three ways:

- an **ARC** runner, under
  [actions-runner-controller](https://github.com/actions/actions-runner-controller)
  scale sets;
- a **standalone** self-hosted runner (`docker run` + a registration token);
- a plain **job container** (`container:` in a workflow) on any runner.

| Image | Published as | Software |
|-------|--------------|----------|
| [`images/ubuntu2404`](images/ubuntu2404) | `ghcr.io/follyfactory/runner-images/ubuntu2404` | [manifest](docs/Ubuntu2404-Readme.md) |

Tags: `latest`, and `YYYYMMDD-<short sha>` for every build. Both are multi-arch
(`linux/amd64`, `linux/arm64`), so an ARC node pulls the right architecture from
either tag. [The build workflow](.github/workflows/build-ubuntu2404.yml) builds
each architecture on a native hosted runner - `ubuntu-24.04` and
`ubuntu-24.04-arm`, both free and unmetered on a public repo - and rebuilds on
every change to the image plus once a week for base-image and apt security
updates.

## Making the package public

The first push creates the package **private**, whatever the repo's visibility:
GHCR visibility is per package. Flip it once, by hand, at
`github.com/orgs/FollyFactory/packages/container/runner-images%2Fubuntu2404/settings`
→ *Danger Zone* → *Change visibility* → *Public*. That is a one-way change, and
every build after it stays public.

Worth doing while in there: *Inherit access from repository*, so this repo's
admins keep write access to the package. The image already carries
`org.opencontainers.image.source`, so the package links itself back here.

Once public, ARC pulls it anonymously - no `imagePullSecret`, no registry login
on the nodes.

## What's in ubuntu2404

Ubuntu 24.04, with the full list in [docs/Ubuntu2404-Readme.md](docs/Ubuntu2404-Readme.md):

- **Node.js 22 and 24**, in the hosted tool cache at `/opt/hostedtoolcache/node`,
  so `actions/setup-node` resolves either version without downloading. The newer
  one is on `PATH` via `/opt/node`, which is also where `npm install --global`
  puts binaries - how `railway-deploy` gets its pinned `@railway/cli` onto
  `PATH`.
- **.NET SDKs 9.0.121, 9.0.205, 9.0.318, 10.0.112, 10.0.204, 10.0.303 and
  10.0.401**, side by side in `/usr/share/dotnet`. A repo's `global.json` picks
  one; `actions/setup-dotnet` finds the band it asks for already installed, and
  can still add another because the runner user owns that directory.
- **PostgreSQL 18**, server and client, installed but **stopped** — the same
  deal as the hosted images. Start it from a job (see below).
- **docker CLI, buildx and compose**, but no daemon: jobs talk to a
  docker-in-docker sidecar or a mounted socket.
- **The Railway CLI** (`railway`), as the release binary, so it stays put when a
  job switches Node version. `railway-deploy` in the shared workflows still
  installs its own pinned `@railway/cli` globally, which takes precedence on
  `PATH` — the image's copy is for jobs that call `railway` directly.
- git (from `ppa:git-core`), git-lfs, gh, jq, build-essential, python3, and the
  rest of the hosted-image baseline that build and packaging steps reach for.

Every version is a `--build-arg`, so a thinner image is one argument away:

```bash
docker build --build-arg DOTNET_SDK_VERSIONS="10.0.401" \
  --build-arg NODE_VERSIONS="24.22.1" \
  -t runner:slim images/ubuntu2404
```

It is a big image — seven .NET SDKs is most of it. Keep a warm image cache on
the nodes that run it, or build a slimmer variant per repo as above.

## Using PostgreSQL

The cluster ships initialised and stopped. Bring it up in a step:

```yaml
- run: start-postgres    # then 127.0.0.1:5432, user postgres, password postgres
```

`stop-postgres` stops it again; both work without `sudo` (they re-exec
themselves). Setting `START_POSTGRES=1` in the container's environment starts it
before the runner comes up instead, for jobs that expect a database from their
first step.

Workflows that run their own `postgres:NN` container (as
[cur-10/workflows](https://github.com/cur-10/workflows)' `dotnet-build-test`
does) ignore all this and just use `psql` from the image — which is why the
client here is 18, matching the newest server those workflows start. A client
older than the server breaks `pg_dump`.

## Running it

### ARC scale set

The image needs no special template: ARC's default command is
`/home/runner/run.sh`, which is this image's default too. `runner` is uid 1001
and the `docker` group is gid 123, as in the official runner image, so volumes
and the container hooks line up. `/home/runner/k8s/index.js` (for
`containerMode: kubernetes`) and `/home/runner/docker/index.js` are both there.

```yaml
# values.yaml for gha-runner-scale-set
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/follyfactory/runner-images/ubuntu2404:latest
        command: ["/home/runner/run.sh"]
```

Workflows that run `docker` commands need `containerMode: dind`. The dind
sidecar shares the pod's network, so a container started with
`--publish 5432:5432` is reachable on `localhost` from the job, which is what
the shared workflows assume.

### Standalone

```bash
docker run --rm \
  -e RUNNER_NAME=local-1 \
  -e GITHUB_URL=https://github.com/FollyFactory \
  -e RUNNER_TOKEN=<registration token> \
  ghcr.io/follyfactory/runner-images/ubuntu2404:latest \
  bash -c './config.sh --unattended --url "$GITHUB_URL" --token "$RUNNER_TOKEN" --name "$RUNNER_NAME" --ephemeral && ./run.sh'
```

### Job container

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container: ghcr.io/follyfactory/runner-images/ubuntu2404:latest
```

## Building and checking it locally

```bash
docker build -t runner:local images/ubuntu2404
```

```bash
docker run --rm runner:local verify-image
```

`verify-image` is [`images/ubuntu2404/verify.sh`](images/ubuntu2404/verify.sh):
it asserts every expected Node and .NET version, starts and stops PostgreSQL,
and checks the runner agent, the hooks and the tool baseline. CI runs it against
both architectures before anything is published, and it is the quickest way to
see whether a version bump actually landed.

## License

MIT - see [LICENSE](LICENSE). The images bundle third-party software under its
own licences (Ubuntu packages, the .NET SDKs, Node.js, PostgreSQL, the docker
CLI, the Railway CLI); that software is redistributed, not relicensed.

## Conventions

The workspace conventions don't cover this repo yet. The build workflow runs on
both pushes to `main` and pull requests, so either the `feature/issue-N` + PR
flow or `voxcia-valhalla`'s trunk-based one works — Matt's call.
