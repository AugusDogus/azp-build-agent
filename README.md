# Azure Pipelines Build Agent (Docker)

A self-hosted Azure Pipelines agent running in Docker with Docker-in-Docker support, based on Alpine Linux.

## Features

- **Lightweight**: Built on Python 3 Alpine image
- **Docker-in-Docker**: Run Docker commands within your pipelines
- **Docker Buildx**: Multi-platform build support included
- **Azure CLI**: Pre-installed for Azure resource management
- **Auto-configuration**: Automatically downloads and configures the latest Azure Pipelines agent
- **Multiple authentication methods**: Supports PAT tokens or Azure service principal authentication

## Prerequisites

- Docker installed on your host machine
- Azure DevOps organization URL
- Personal Access Token (PAT) with **Agent Pools (Read & Manage)** permission, or Azure service principal credentials

## Quick Start

### 1. Build the Docker Image

```bash
docker build -t azp-agent:linux .
```

### 2. Run a Single Agent

```bash
docker run -d --privileged \
  --name azp-agent-01 \
  -e AZP_URL="https://dev.azure.com/YOUR_ORGANIZATION" \
  -e AZP_TOKEN="YOUR_PAT_TOKEN" \
  -e AZP_POOL="Default" \
  -e AZP_AGENT_NAME="azp-agent-01" \
  azp-agent:linux
```

### 3. Run Multiple Agents in the Same Pool

```bash
for i in 01 02 03; do
  docker run -d --privileged \
    --name azp-agent-$i \
    -e AZP_URL="https://dev.azure.com/YOUR_ORGANIZATION" \
    -e AZP_TOKEN="YOUR_PAT_TOKEN" \
    -e AZP_POOL="Default" \
    -e AZP_AGENT_NAME="azp-agent-$i" \
    azp-agent:linux
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

- **Bash** - Shell scripting
- **Git** - Version control
- **Docker** & **Docker CLI** - Container operations
- **Docker Buildx** (v0.11.2) - Multi-platform builds
- **Azure CLI** - Azure resource management
- **Python 3** - Python runtime and pip
- **jq** - JSON processing
- **curl** - HTTP requests
- Development tools: gcc, make, cargo, etc.

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
3. Optionally authenticates via Azure service principal
4. Downloads the latest Azure Pipelines agent package
5. Configures the agent with your organization and pool
6. Starts the agent and begins accepting jobs

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

## License

This project is provided as-is for use with Azure DevOps self-hosted agents.
