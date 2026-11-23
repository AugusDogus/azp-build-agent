# Azure Pipelines Docker Agent

Self-hosted Azure Pipelines agents in a container, with Docker available to your jobs either from the host or inside the container (Docker-in-Docker). Ubuntu is the default; Alpine is a smaller alternative.

## Quick Start

```bash
docker run -d --restart unless-stopped \
  --name azp-agent-01 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e AZP_URL="https://dev.azure.com/YOUR_ORG" \
  -e AZP_TOKEN="YOUR_PAT" \
  -e AZP_POOL="Default" \
  -e AZP_AGENT_NAME="azp-agent-01" \
  ghcr.io/augusdogus/azp-build-agent:ubuntu
```

The agent registers itself in the pool, downloads the latest agent release for your organization, and starts taking jobs.

### Run several agents

```bash
for i in 01 02 03; do
  docker run -d --restart unless-stopped \
    --name azp-agent-$i \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e AZP_URL="https://dev.azure.com/YOUR_ORG" \
    -e AZP_TOKEN="YOUR_PAT" \
    -e AZP_POOL="Default" \
    -e AZP_AGENT_NAME="azp-agent-$i" \
    ghcr.io/augusdogus/azp-build-agent:ubuntu
done
```

## Images

| Tag | Base | Use it for |
|-----|------|------------|
| `ubuntu`, `latest` | Ubuntu 26.04 LTS | Default. glibc, so Playwright and most prebuilt tools work |
| `alpine` | Alpine 3.24 (`python:3-alpine3.24`) | Smaller image when your toolchain works on musl |

To pin a version, use a release tag:

| Tag | Changes when |
|-----|--------------|
| `2.0.0-ubuntu`, `2.0.0-alpine` (and `2.0.0` for Ubuntu) | Never |
| `2.0-ubuntu`, `2-ubuntu`, ... | A newer 2.0.x / 2.x release comes out |
| `ubuntu`, `alpine`, `latest` | Every push to `main`, and every Monday's rebuild with security updates |
| `ubuntu-<sha>`, `alpine-<sha>` | Never (one per commit) |

See [Releases](https://github.com/AugusDogus/azp-build-agent/releases) for what changed in each version.

**Both:** Docker Engine and CLI, Buildx, Compose, Git, Azure CLI, jq, curl
**Alpine also has:** Python 3, gcc, make, cargo

## Docker for your jobs

Pick one with `AZP_DOCKER_MODE`:

| Mode | How | Notes |
|------|-----|-------|
| Host daemon | `-v /var/run/docker.sock:/var/run/docker.sock` | Simplest and fastest. Jobs share the host's images, build cache and disk, so clean up on the host (see below). Anyone who can run a pipeline on this pool effectively has root on the host. |
| Docker-in-Docker | `--privileged -v azp-docker-01:/var/lib/docker` | Each agent has its own daemon. Use one volume per agent. Without the volume the daemon falls back to the `vfs` storage driver, which copies every image layer in full and fills disks quickly. |
| None | `-e AZP_DOCKER_MODE=none` | For agents that never need Docker. |

The default, `auto`, uses a mounted host socket if there is one, otherwise starts Docker-in-Docker, and if that isn't possible (no `--privileged`) starts the agent without Docker and logs a warning. Set `host` or `dind` to fail at startup instead.

### Disk space

Build agents fill disks: images built by jobs, build cache, and each pipeline's `_work` folder. Plan for it:

- **Host daemon:** schedule `docker system prune -af --filter "until=48h"` on the host (a systemd timer or cron job), and alert on free space.
- **Docker-in-Docker:** run the same prune inside each agent: `docker exec azp-agent-01 docker system prune -af --filter "until=48h"`.
- **Pipeline folders:** turn on *Agent pools > your pool > Settings > Maintenance jobs* in Azure DevOps to delete old `_work` folders.

## Sign-in options

The agent needs a credential that can register agents in the pool (Agent Pools: Read & manage). Use one of:

| Variables | Credential |
|-----------|------------|
| `AZP_TOKEN` or `AZP_TOKEN_FILE` | Personal access token |
| `AZP_AUTH_CLIENTID` | User-assigned managed identity (Azure VMs, Container Apps). The identity must be added to the Azure DevOps organization with access to the pool. |
| `AZP_CLIENTID`, `AZP_CLIENTSECRET`, `AZP_TENANTID` | Service principal, added to the organization the same way |

## Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `AZP_URL` | Yes | Organization URL, e.g. `https://dev.azure.com/yourorg` |
| `AZP_TOKEN` / `AZP_TOKEN_FILE` / `AZP_AUTH_CLIENTID` / `AZP_CLIENTID` | One of these | See [Sign-in options](#sign-in-options) |
| `AZP_POOL` | No | Agent pool (default `Default`) |
| `AZP_AGENT_NAME` | No | Agent name (default: container hostname) |
| `AZP_WORK` | No | Work folder (default `_work`) |
| `AZP_DOCKER_MODE` | No | `auto` (default), `host`, `dind` or `none` |
| `DOCKER_STORAGE_DRIVER` | No | Force a Docker-in-Docker storage driver |
| `DOCKERD_EXTRA_ARGS` | No | Extra `dockerd` flags for Docker-in-Docker |
| `DOCKERD_START_TIMEOUT` | No | Seconds to wait for Docker-in-Docker (default 120) |
| `AZP_AGENT_PLATFORM` | No | Agent package platform; detected automatically (`linux-x64`, `linux-arm64`, `linux-musl-x64`, ...) |

## Build it yourself

```bash
docker build -f Dockerfile.ubuntu -t azp-agent:ubuntu .
docker build -f Dockerfile.alpine -t azp-agent:alpine .
```

Builds work on amd64 and arm64 hosts; the agent package for the right CPU is picked at startup.

## Managing agents

```bash
docker logs -f azp-agent-01        # follow logs
docker stop azp-agent-01           # stop gracefully (the agent finishes shutting down)
docker rm -f azp-agent-01          # remove the container
```

Removing a container does not remove the agent from the pool. Delete it under *Agent pools > your pool > Agents*, or start a new container with the same `AZP_AGENT_NAME` to replace it.

## Troubleshooting

**Agent doesn't appear in the pool:** check `AZP_URL`, the credential's permissions and that the pool exists. Startup errors are in `docker logs`.

**`Cannot connect to the Docker daemon`:** with the host socket, check the host's Docker service is running (an OS update can restart or replace it, so restart the agents after Docker updates). With Docker-in-Docker, check the container runs with `--privileged`.

**`No space left on device`:** see [Disk space](#disk-space).

**`start.sh: not found` or `bad interpreter` after cloning on Windows:** the image strips Windows line endings at build time, and `.gitattributes` keeps them out of checkouts.

## CI

Every pull request, push to `main` and a weekly schedule build both images and check that the tools are installed, that the latest Azure Pipelines agent runs on them, and that Docker works in each mode. Pushes to `main` and the weekly run then publish to `ghcr.io`.

To release, tag a commit on `main` and push the tag:

```bash
git tag v2.1.0 && git push origin v2.1.0
```

That runs the same tests, publishes the version tags above and creates a GitHub release with notes from the merged PRs. A tag with a suffix (`v2.1.0-rc.1`) becomes a pre-release.

## Security

- Docker-in-Docker needs `--privileged`; mounting the host socket gives jobs root on the host. Only run pipelines you trust on these agents.
- Pass tokens with your secret manager or `AZP_TOKEN_FILE`, never in the image or the repo.
- Keep agents off the public internet; they only need outbound HTTPS to Azure DevOps.
