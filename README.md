# Azure Pipelines Docker Agent

Self-hosted Azure Pipelines agents with Docker-in-Docker support. Choose Alpine (lightweight) or Ubuntu (full compatibility).

## Quick Start

### Pull Pre-built Images

```bash
# Alpine (lightweight, ~500MB)
docker pull ghcr.io/augustogus/azp-build-agent:alpine

# Ubuntu (full compatibility, ~1GB) 
docker pull ghcr.io/augustogus/azp-build-agent:ubuntu
```

### Run an Agent

```bash
docker run -d --privileged \
  --name azp-agent-01 \
  -e AZP_URL="https://dev.azure.com/YOUR_ORG" \
  -e AZP_TOKEN="YOUR_PAT_TOKEN" \
  -e AZP_POOL="Default" \
  -e AZP_AGENT_NAME="azp-agent-01" \
  ghcr.io/augustogus/azp-build-agent:alpine
```

### Run Multiple Agents

```bash
for i in 01 02 03; do
  docker run -d --privileged \
    --name azp-agent-$i \
    -e AZP_URL="https://dev.azure.com/YOUR_ORG" \
    -e AZP_TOKEN="YOUR_PAT_TOKEN" \
    -e AZP_POOL="Default" \
    -e AZP_AGENT_NAME="azp-agent-$i" \
    ghcr.io/augustogus/azp-build-agent:alpine
done
```

## Variants

| Variant | Size | Base Image | Use Case |
|---------|------|------------|----------|
| **Alpine** | ~500MB | `python:3-alpine` | General CI/CD, Docker builds, lightweight deployments |
| **Ubuntu** | ~1GB | `ubuntu:latest` | Playwright, browser testing, maximum compatibility |

**Choose Ubuntu if** you need glibc for tools like Playwright, otherwise use Alpine.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `AZP_URL` | ✅ | Azure DevOps org URL (e.g., `https://dev.azure.com/yourorg`) |
| `AZP_TOKEN` | ✅ | PAT with Agent Pools (Read & Manage) permission |
| `AZP_POOL` | ✅ | Agent pool name (default: `Default`) |
| `AZP_AGENT_NAME` | ❌ | Custom agent name (default: hostname) |
| `AZP_WORK` | ❌ | Working directory (default: `_work`) |
| `AZP_TOKEN_FILE` | ❌ | Path to token file (alternative to `AZP_TOKEN`) |

## Included Tools

**Both variants:** Docker, Docker Compose, Buildx, Git, Azure CLI, jq, curl  
**Alpine only:** Python 3, pip, bash, gcc, make, cargo  
**Ubuntu only:** glibc, standard apt packages

## Build Locally

```bash
# Alpine
docker build -f Dockerfile.alpine -t azp-agent:alpine .

# Ubuntu
docker build -f Dockerfile.ubuntu -t azp-agent:ubuntu .
```

## Managing Agents

```bash
# View logs
docker logs azp-agent-01

# Stop agent
docker stop azp-agent-01

# Remove agent
docker rm -f azp-agent-01

# Stop all
docker stop $(docker ps -q --filter "name=azp-agent")
```

## Troubleshooting

**Agent not appearing?** Check `AZP_URL`, PAT permissions, pool exists, and logs: `docker logs azp-agent-01`

**Docker commands failing?** Ensure `--privileged` flag is set

**Agent disconnecting?** Check host resources (CPU/memory/disk) and network connectivity

## CI/CD

- **Testing**: Weekly automated tests catch upstream breaking changes
- **Publishing**: Every push to `main` publishes `:alpine`, `:ubuntu`, and `:latest` tags to ghcr.io
- **Monitoring**: GitHub Actions verify both variants build and start correctly

## Security

⚠️ Requires `--privileged` mode for Docker-in-Docker  
🔒 Never commit tokens - use secrets management  
🌐 Consider network isolation for production agents
