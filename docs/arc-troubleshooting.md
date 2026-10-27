# When the farm doesn't run your jobs

Every one of these was hit bringing up `mortis-farm-cur10` on a single-node
cluster, 27 Oct 2026. They present almost identically - a job sits in "Waiting
for a runner to pick up this job..." - and the fix is different each time, so
start by telling cluster problems and routing problems apart.

## First: which half is broken

```bash
kubectl logs -n arc-systems -l app.kubernetes.io/component=runner-scale-set-listener -f | grep "assigned job"
```

One line every ~50 seconds:

- **`"assigned job"=0`** while a job waits on GitHub - GitHub is offering this
  scale set nothing. The cluster is fine; the problem is routing. Skip to
  [Routing](#routing).
- **`"assigned job"=1`** and no pod appears - GitHub handed the work over and
  the cluster can't act on it. See [The cluster](#the-cluster).

Two things that look like health but aren't:

- **The scale set showing "Online"** only means the listener pod connected to
  GitHub. It says nothing about whether a runner pod can start.
- **`lastMessageID` not advancing** across polls means no new messages at all,
  which is the same signal as `assigned job=0`.

## Routing

### The job is an orphan

Symptom: the job log says `Job is about to start running on the runner:
<scale set>`, then nothing, while runners sit Idle and the listener reports
`assigned job=0`.

GitHub dispatched the job to an ephemeral runner that no longer exists -
usually one deleted by a `helm upgrade` while it was Pending. From GitHub's
side the job is assigned, not queued, so it is never offered again.

**Cancel the run** and start it fresh. Re-running failed jobs is not enough;
the dispatch has to be dropped.

### `runs-on` doesn't match

A scale set is matched by its **name**, as one exact string. Not combined with
`self-hosted` or anything else.

```yaml
runs-on: mortis-farm-cur10
```

The quoted form belongs only in a `with:` block, where a reusable workflow's
`runs-on` **input** is parsed with `fromJSON`:

```yaml
with:
  runs-on: '"mortis-farm-cur10"'
```

Put that quoted form on a job directly and the requested label becomes
`"mortis-farm-cur10"`, quotes included, which matches nothing. The job log's
`Requested labels:` line shows exactly what was asked for - compare it
character by character.

### The labels never reached GitHub

The Helm value is `scaleSetLabels`. `runnerScaleSetLabels` is the field on the
`AutoscalingRunnerSet` CR that it renders into, and the chart's
`values.schema.json` only validates `listenerConfig`, so the wrong key is
accepted and silently dropped.

Individual runners never show labels in the GitHub UI - only the scale set row
does. That is normal and not a symptom. If the scale set row shows only its own
name, `scaleSetLabels` did not take.

### Wrong org

Runners registered to one org cannot run another org's jobs. `githubConfigUrl`
has to name the org (or enterprise, or repo) the workflow lives in.

## The cluster

```bash
kubectl get pods -n arc-runners
```

### `Pending`

```
0/1 nodes are available: 1 Insufficient cpu.
```

`kubectl describe pod -n arc-runners <name> | sed -n '/Events:/,$p'` names the
resource. Requests are a **scheduling floor**, not a reservation: the scheduler
must find `minRunners × request` free before any job exists, and
`maxRunners × request` under load. Nothing is pulled and no error reaches
GitHub - the job simply waits.

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.allocatable.cpu,\
MEM:.status.allocatable.memory,EPH:.status.allocatable.ephemeral-storage
```

Size requests against that, not against what a build would like to have. A low
CPU request does not slow a build down - with no CPU *limit* it still uses
whatever the node has idle. An `ephemeral-storage` request is the quietest way
to make a pod unschedulable, because allocatable ephemeral storage is usually
far smaller than the disk.

### `ImagePullBackOff`

The package is private and the pods have no credentials. Either make it public
(see the README) or:

```bash
kubectl create secret docker-registry ghcr-pull \
  --namespace arc-runners \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USERNAME \
  --docker-password=YOUR_PAT_WITH_read:packages
```

and add `imagePullSecrets: [{name: ghcr-pull}]` under `template.spec`.

### `ContainerCreating` for several minutes

The first pull of a multi-GB image on that node. It caches afterwards; keeping
`minRunners` above zero keeps it warm.

### No runner pods at all

The container in your values must be named exactly `runner`.
`autoscalingrunnerset.yaml` hardcodes `- name: runner` and fills its body from
the values container of that name, and the dind wiring - `DOCKER_HOST`, the
work volume, the externals mount - and the `init-dind-externals` init container
are all gated on the same check. Under any other name the rendered runner
container has no image, and yours is left as a stray sidecar with no job
config.

A healthy dind-mode pod is `2/2`: `runner` and `dind`.
