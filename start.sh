#!/bin/bash
set -e

if ! docker info >/dev/null 2>&1; then
  # Clean up stale containerd state that can prevent startup
  rm -rf /var/run/docker/containerd/containerd.sock.ttrpc /var/run/docker/containerd/containerd.sock
  rm -rf /run/containerd/containerd.sock.ttrpc /run/containerd/containerd.sock
  
  dockerd >/tmp/dockerd.log 2>&1 &
  
  # Wait up to 60 seconds for docker to start
  WAIT_TIME=0
  until docker info >/dev/null 2>&1 || [ $WAIT_TIME -eq 60 ]; do
    sleep 1
    WAIT_TIME=$((WAIT_TIME + 1))
  done
  
  # If docker still isn't running, log error and exit to trigger container restart
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon failed to start within 60 seconds" >&2
    cat /tmp/dockerd.log >&2
    exit 1
  fi
fi

if [ -z "${AZP_URL}" ]; then
  echo "error: missing AZP_URL" >&2
  exit 1
fi

if [ -n "$AZP_CLIENTID" ]; then
  az login --allow-no-subscriptions --service-principal --username "$AZP_CLIENTID" --password "$AZP_CLIENTSECRET" --tenant "$AZP_TENANTID"
  AZP_TOKEN=$(az account get-access-token --query accessToken --output tsv)
fi

if [ -z "${AZP_TOKEN_FILE}" ]; then
  if [ -z "${AZP_TOKEN}" ]; then
    echo "error: missing AZP_TOKEN" >&2
    exit 1
  fi
  AZP_TOKEN_FILE="/azp/.token"
  echo -n "${AZP_TOKEN}" > "${AZP_TOKEN_FILE}"
fi

unset AZP_CLIENTSECRET AZP_TOKEN

[ -n "${AZP_WORK}" ] && mkdir -p "${AZP_WORK}"

export VSO_AGENT_IGNORE="AZP_TOKEN,AZP_TOKEN_FILE"

AZP_AGENT_PACKAGES=$(curl -LsS -u user:$(cat "${AZP_TOKEN_FILE}") -H "Accept:application/json" \
  "${AZP_URL}/_apis/distributedtask/packages/agent?platform=${TARGETARCH:-linux-x64}&top=1")
AZP_AGENT_PACKAGE_LATEST_URL=$(echo "${AZP_AGENT_PACKAGES}" | jq -r ".value[0].downloadUrl")

[ -z "${AZP_AGENT_PACKAGE_LATEST_URL}" -o "${AZP_AGENT_PACKAGE_LATEST_URL}" = "null" ] && exit 1

curl -LsS "${AZP_AGENT_PACKAGE_LATEST_URL}" | tar -xz
./bin/installdependencies.sh
source ./env.sh

# Only configure if not already configured
if [ ! -f ".agent" ]; then
  ./config.sh --unattended \
    --agent "${AZP_AGENT_NAME:-$(hostname)}" \
    --url "${AZP_URL}" \
    --auth PAT \
    --token $(cat "${AZP_TOKEN_FILE}") \
    --pool "${AZP_POOL:-Default}" \
    --work "${AZP_WORK:-_work}" \
    --replace \
    --acceptTeeEula
else
  echo "Agent already configured. Skipping config."
fi

chmod +x ./run.sh
./run.sh "$@"
