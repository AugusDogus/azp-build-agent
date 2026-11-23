#!/bin/bash
set -euo pipefail

log() { echo "[start] $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Docker
#
# AZP_DOCKER_MODE:
#   auto (default) use the host's daemon if /var/run/docker.sock is mounted,
#                  otherwise start one inside the container (needs --privileged).
#                  If that fails, the agent still starts, without Docker.
#   host           require a mounted host socket.
#   dind           always start a daemon inside the container; fail if it can't.
#   none           don't touch Docker.
# ---------------------------------------------------------------------------
: "${AZP_DOCKER_MODE:=auto}"
: "${DOCKER_STORAGE_DRIVER:=}"
: "${DOCKERD_EXTRA_ARGS:=}"
: "${DOCKERD_START_TIMEOUT:=120}"

is_mountpoint() { awk -v p="$1" '$5 == p { found = 1 } END { exit !found }' /proc/self/mountinfo; }

start_dockerd() {
  # Stale sockets from an earlier run of this container stop containerd starting.
  rm -f /var/run/docker/containerd/containerd.sock /var/run/docker/containerd/containerd.sock.ttrpc \
        /run/containerd/containerd.sock /run/containerd/containerd.sock.ttrpc /var/run/docker.pid

  local driver="${DOCKER_STORAGE_DRIVER}"
  if [ -z "$driver" ] && ! is_mountpoint /var/lib/docker; then
    # overlay on top of the container's own overlay root fails on many hosts.
    # vfs always works but copies every layer in full and fills disks fast, so
    # mount a volume at /var/lib/docker to get overlay2 instead.
    driver=vfs
    log "WARNING: /var/lib/docker is not a volume, using the vfs storage driver (slow, disk hungry)."
    log "         Add '-v azp-docker:/var/lib/docker' to use overlay2."
  fi

  local args=(--host=unix:///var/run/docker.sock)
  [ -n "$driver" ] && args+=(--storage-driver="$driver")
  # shellcheck disable=SC2206 # word splitting is intended for extra args
  args+=(${DOCKERD_EXTRA_ARGS})

  log "Starting dockerd ${args[*]}"
  dockerd "${args[@]}" >/tmp/dockerd.log 2>&1 &

  local waited=0
  until docker info >/dev/null 2>&1; do
    if [ "$waited" -ge "$DOCKERD_START_TIMEOUT" ] || ! kill -0 $! 2>/dev/null; then
      echo "dockerd did not start (storage driver: ${driver:-default}). Log:" >&2
      cat /tmp/dockerd.log >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  log "dockerd is up ($(docker info --format '{{.Driver}}') storage driver)"
}

case "$AZP_DOCKER_MODE" in
  none) ;;
  host)
    docker info >/dev/null 2>&1 || fail "AZP_DOCKER_MODE=host but no daemon at /var/run/docker.sock. Mount it with -v /var/run/docker.sock:/var/run/docker.sock"
    log "Using the host's Docker daemon"
    ;;
  dind)
    start_dockerd || fail "Docker-in-Docker failed to start. It needs --privileged."
    ;;
  auto)
    if docker info >/dev/null 2>&1; then
      log "Using the host's Docker daemon"
    elif ! start_dockerd; then
      log "WARNING: no Docker daemon available. Jobs that use Docker will fail."
      log "         Run with --privileged, or mount /var/run/docker.sock, or set AZP_DOCKER_MODE=none."
    fi
    ;;
  *) fail "AZP_DOCKER_MODE must be auto, host, dind or none (got '$AZP_DOCKER_MODE')" ;;
esac

# ---------------------------------------------------------------------------
# Azure DevOps credentials
#
# One of, in this order:
#   AZP_AUTH_CLIENTID                     user-assigned managed identity
#   AZP_CLIENTID + AZP_CLIENTSECRET +
#     AZP_TENANTID                        service principal
#   AZP_TOKEN or AZP_TOKEN_FILE           personal access token
# ---------------------------------------------------------------------------
[ -n "${AZP_URL:-}" ] || fail "missing AZP_URL"

# Token audience for Azure DevOps.
AZP_ENTRA_RESOURCE="${AZP_ENTRA_RESOURCE:-https://app.vssps.visualstudio.com/}"

entra_token() {
  local token
  token=$(az account get-access-token --resource "$AZP_ENTRA_RESOURCE" --query accessToken -o tsv 2>&1) \
    || fail "az account get-access-token failed: $token"
  { [ -n "$token" ] && [ "$token" != "null" ]; } || fail "Azure DevOps token is empty"
  echo "$token"
}

if [ -n "${AZP_AUTH_CLIENTID:-}" ]; then
  log "Signing in with managed identity $AZP_AUTH_CLIENTID"
  az login --identity --client-id "$AZP_AUTH_CLIENTID" --allow-no-subscriptions >/dev/null \
    || fail "managed identity sign-in failed"
  AZP_TOKEN=$(entra_token)
elif [ -n "${AZP_CLIENTID:-}" ]; then
  log "Signing in with service principal $AZP_CLIENTID"
  az login --service-principal --allow-no-subscriptions \
    --username "$AZP_CLIENTID" --password "${AZP_CLIENTSECRET:?missing AZP_CLIENTSECRET}" \
    --tenant "${AZP_TENANTID:?missing AZP_TENANTID}" >/dev/null \
    || fail "service principal sign-in failed"
  AZP_TOKEN=$(entra_token)
fi

if [ -z "${AZP_TOKEN_FILE:-}" ]; then
  [ -n "${AZP_TOKEN:-}" ] || fail "missing AZP_TOKEN (or AZP_TOKEN_FILE, AZP_AUTH_CLIENTID, AZP_CLIENTID)"
  AZP_TOKEN_FILE=/azp/.token
  (umask 077 && printf '%s' "$AZP_TOKEN" > "$AZP_TOKEN_FILE")
fi
unset AZP_CLIENTSECRET AZP_TOKEN

export VSO_AGENT_IGNORE="AZP_TOKEN,AZP_TOKEN_FILE,AZP_CLIENTSECRET"

# ---------------------------------------------------------------------------
# Agent
# ---------------------------------------------------------------------------
AZP_WORK="${AZP_WORK:-_work}"
mkdir -p "$AZP_WORK"

# Platform of the agent package: linux-x64, linux-arm64, linux-musl-x64, ...
# TARGETARCH is the old name for this setting and still works.
if [ -z "${AZP_AGENT_PLATFORM:-${TARGETARCH:-}}" ]; then
  case "$(uname -m)" in
    x86_64) arch=x64 ;;
    aarch64 | arm64) arch=arm64 ;;
    armv7l) arch=arm ;;
    *) fail "unsupported CPU $(uname -m); set AZP_AGENT_PLATFORM" ;;
  esac
  if [ -f /etc/alpine-release ]; then AZP_AGENT_PLATFORM="linux-musl-$arch"; else AZP_AGENT_PLATFORM="linux-$arch"; fi
fi
AZP_AGENT_PLATFORM="${AZP_AGENT_PLATFORM:-$TARGETARCH}"

if [ ! -x ./run.sh ]; then
  log "Looking up the latest $AZP_AGENT_PLATFORM agent for $AZP_URL"
  packages=$(curl -LsS -u "user:$(cat "$AZP_TOKEN_FILE")" -H "Accept: application/json" \
    "${AZP_URL}/_apis/distributedtask/packages/agent?platform=${AZP_AGENT_PLATFORM}&top=1") \
    || fail "could not reach $AZP_URL"
  url=$(echo "$packages" | jq -r '.value[0].downloadUrl // empty' 2>/dev/null || true)
  [ -n "$url" ] || fail "no agent download URL in the Azure DevOps response (check AZP_URL and the token's Agent Pools permission): ${packages:0:300}"

  log "Downloading $url"
  curl -LsS "$url" | tar -xz
fi

./bin/installdependencies.sh
# shellcheck disable=SC1091
source ./env.sh

if [ ! -f .agent ]; then
  log "Registering agent ${AZP_AGENT_NAME:-$(hostname)} in pool ${AZP_POOL:-Default}"
  ./config.sh --unattended \
    --agent "${AZP_AGENT_NAME:-$(hostname)}" \
    --url "$AZP_URL" \
    --auth PAT \
    --token "$(cat "$AZP_TOKEN_FILE")" \
    --pool "${AZP_POOL:-Default}" \
    --work "$AZP_WORK" \
    --replace \
    --acceptTeeEula
else
  log "Agent already registered, skipping config"
fi

# exec so `docker stop` reaches the agent and it can finish shutting down cleanly.
exec ./run.sh "$@"
