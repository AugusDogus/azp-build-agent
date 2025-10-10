# Azure Pipelines Build Agent (Docker)

A self-hosted Azure Pipelines agent running in Docker with Docker-in-Docker support. Available in two variants: Alpine (lightweight) and Ubuntu (full compatibility).

## Variants

Both variants use rolling release base images (`python:3-alpine` and `ubuntu:latest`) and are automatically tested weekly via GitHub Actions to ensure compatibility.

### Alpine (`Dockerfile.alpine`)
- **Lightweight**: ~500MB base image
- **Fast**: Quick to build and deploy
- **Best for**: General CI/CD, Docker builds, Azure CLI tasks
- **Limitations**: musl libc - some precompiled binaries may not work

### Ubuntu (`Dockerfile.ubuntu`)
- **Compatible**: Full glibc support for maximum compatibility
- **Standard**: Uses standard Ubuntu packages and repositories
- **Best for**: Building containers that need glibc (e.g., Playwright apps)
- **Size**: ~1GB base image

## Features

- **Docker-in-Docker**: Run Docker commands within your pipelines
- **Docker Buildx & Compose**: Multi-platform build support included
- **Azure CLI**: Pre-installed for Azure resource management
- **Auto-configuration**: Automatically downloads and configures the latest Azure Pipelines agent

## Prerequisites

- Docker installed on your host machine
- Azure DevOps organization URL
- Personal Access Token (PAT) with **Agent Pools (Read & Manage)** permission, or Azure service principal credentials

## Quick Start

### Option 1: Use Pre-built Images (Recommended)

Pull pre-built images from GitHub Container Registry:

**Alpine (lightweight):**
```bash
docker pull ghcr.io/OWNER/REPO:alpine
# or
docker pull ghcr.io/OWNER/REPO:latest-alpine
```

**Ubuntu (with Playwright support):**
```bash
docker pull ghcr.io/OWNER/REPO:ubuntu
# or
docker pull ghcr.io/OWNER/REPO:latest-ubuntu
# or
docker pull ghcr.io/OWNER/REPO:latest
```

> **Note:** Replace `OWNER/REPO` with your GitHub username and repository name (lowercase).

### Option 2: Build Locally

**Alpine (lightweight):**
```bash
docker build -f Dockerfile.alpine -t azp-agent:alpine .
```

**Ubuntu (with Playwright support):**
```bash
docker build -f Dockerfile.ubuntu -t azp-agent:ubuntu .
```

### 2. Run a Single Agent

Replace `azp-agent:alpine` with `azp-agent:ubuntu` if using the Ubuntu variant.

```bash
docker run -d --privileged \
  --name azp-agent-01 \
  -e AZP_URL="https://dev.azure.com/YOUR_ORGANIZATION" \
  -e AZP_TOKEN="YOUR_PAT_TOKEN" \
  -e AZP_POOL="Default" \
  -e AZP_AGENT_NAME="azp-agent-01" \
  azp-agent:alpine
```

### 3. Run Multiple Agents in the Same Pool

```bash
# Alpine variant
for i in 01 02 03; do
  docker run -d --privileged \
    --name azp-agent-$i \
    -e AZP_URL="https://dev.azure.com/YOUR_ORGANIZATION" \
    -e AZP_TOKEN="YOUR_PAT_TOKEN" \
    -e AZP_POOL="Default" \
    -e AZP_AGENT_NAME="azp-agent-$i" \
    azp-agent:alpine
done

# Ubuntu variant (for Playwright)
for i in 01 02 03; do
  docker run -d --privileged \
    --name azp-playwright-$i \
    -e AZP_URL="https://dev.azure.com/YOUR_ORGANIZATION" \
    -e AZP_TOKEN="YOUR_PAT_TOKEN" \
    -e AZP_POOL="Default" \
    -e AZP_AGENT_NAME="azp-playwright-$i" \
    azp-agent:ubuntu
done
```

## Environment Variables

### Required Variables

| Variable | Description |
|----------|-------------|
| `AZP_URL` | The URL of your Azure DevOps organization (e.g., `https://dev.azure.com/yourorg`) |
| `AZP_TOKEN` | Personal Access Token with Agent Pools (Read & Manage) permission |
| `AZP_POOL` | The name of the agent pool (default: `Default`) |

### Optional Variables

| Variable | Description |
|----------|-------------|
| `AZP_AGENT_NAME` | Custom agent name (default: container hostname) |
| `AZP_WORK` | Working directory for the agent (default: `_work`) |
| `AZP_TOKEN_FILE` | Path to a file containing the PAT token (alternative to `AZP_TOKEN`) |

## Included Tools

### Both Variants
- **Git** - Version control
- **Docker** & **Docker CLI** - Container operations
- **Docker Buildx** - Multi-platform builds
- **Docker Compose** - Multi-container applications
- **Azure CLI** - Azure resource management
- **jq** - JSON processing
- **curl** - HTTP requests

### Alpine-Specific
- **Python 3** - Python runtime and pip
- **Bash** - Shell scripting
- Development tools: gcc, make, cargo, etc.

### Ubuntu-Specific
- **Full glibc support** - Compatible with standard Linux binaries
- **Standard Ubuntu tooling** - Familiar Debian/Ubuntu package ecosystem

## Docker Permissions

The container requires `--privileged` mode to run Docker-in-Docker. This allows the agent to:
- Build Docker images
- Run containers within pipelines
- Use Docker Compose
- Execute Docker commands

## Managing Agents

### View Running Agents

```bash
docker ps | grep azp-agent
```

### Stop an Agent

```bash
docker stop azp-agent-01
```

### Remove an Agent

```bash
docker rm -f azp-agent-01
```

### View Agent Logs

```bash
docker logs azp-agent-01
```

### Stop All Agents

```bash
docker stop $(docker ps -q --filter "name=azp-agent")
```

### Remove All Agents

```bash
docker rm -f $(docker ps -aq --filter "name=azp-agent")
```

## Architecture

The agent container:
1. Starts Docker daemon if not already running (for Docker-in-Docker)
2. Validates required environment variables
3. Downloads the latest Azure Pipelines agent package
4. Configures the agent with your organization and pool
5. Starts the agent and begins accepting jobs

## Choosing the Right Variant

**Use Alpine if:**
- You need lightweight, fast-starting agents
- You're doing Docker builds, API testing, or general CI/CD
- Image size and resource usage are important
- Your builds don't require glibc-specific binaries

**Use Ubuntu if:**
- You're building Docker images that require glibc (like Playwright apps)
- You need maximum compatibility with precompiled Linux binaries
- You prefer the standard Ubuntu/Debian ecosystem
- You need to install packages with apt from Ubuntu repositories

## Troubleshooting

### Agent not appearing in pool

- Verify your `AZP_URL` is correct
- Check that your PAT token has **Agent Pools (Read & Manage)** permission
- Ensure the specified pool exists in Azure DevOps
- Check container logs: `docker logs azp-agent-01`

### Docker commands failing in pipeline

- Ensure container is run with `--privileged` flag
- Check Docker daemon is running inside container: `docker exec azp-agent-01 docker info`

### Agent disconnects frequently

- Check host system resources (CPU, memory, disk)
- Review container logs for errors
- Verify network connectivity to Azure DevOps

## Security Considerations

- **Privileged mode**: Required for Docker-in-Docker but grants extensive permissions
- **Token security**: Never commit tokens to version control; use secrets management
- **Network isolation**: Consider running agents in isolated networks or VPCs

## Continuous Integration & Publishing

This project includes two GitHub Actions workflows:

### Testing (`.github/workflows/test-images.yml`)
- ✅ Tests both Docker variants automatically
- ✅ Runs weekly to catch breaking changes in base images
- ✅ Runs on every push/PR that modifies Dockerfiles
- ✅ Verifies basic functionality (Docker, Git, Azure CLI)

### Build & Publish (`.github/workflows/build-and-publish.yml`)
- ✅ Automatically builds and publishes images to GitHub Container Registry
- ✅ Runs on every push to `main` branch
- ✅ Tags images as `:alpine`, `:latest-alpine`, `:ubuntu`, `:latest-ubuntu`, and `:latest`

Every push to `main` automatically publishes the latest images - no manual tagging required!

## License

This project is provided as-is for use with Azure DevOps self-hosted agents.
