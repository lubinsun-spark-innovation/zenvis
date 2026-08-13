#!/usr/bin/env bash

set -Eeuo pipefail

: "${SERVER_HOST:?SERVER_HOST is required}"
: "${SERVER_USER:?SERVER_USER is required}"
: "${SERVER_SSH_KEY:?SERVER_SSH_KEY is required}"

remote_app_dir=${REMOTE_APP_DIR:-/root/lubinsun/zenvis}
work_dir=$(mktemp -d)

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

chmod 700 "$work_dir"
printf '%s\n' "$SERVER_SSH_KEY" > "$work_dir/id_ed25519"
chmod 600 "$work_dir/id_ed25519"

if [[ -n "${SERVER_SSH_KNOWN_HOSTS:-}" ]]; then
  printf '%s\n' "$SERVER_SSH_KNOWN_HOSTS" > "$work_dir/known_hosts"
else
  for attempt in {1..3}; do
    if ssh-keyscan -T 15 -H "$SERVER_HOST" > "$work_dir/known_hosts"; then
      break
    fi
    echo "Waiting for the SSH endpoint (${attempt}/3)..." >&2
    sleep 5
  done
fi
[[ -s "$work_dir/known_hosts" ]] || {
  echo "Unable to collect the server SSH host key." >&2
  exit 1
}
chmod 600 "$work_dir/known_hosts"

ssh \
  -i "$work_dir/id_ed25519" \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o IdentitiesOnly=yes \
  -o ServerAliveInterval=5 \
  -o ServerAliveCountMax=3 \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$work_dir/known_hosts" \
  "${SERVER_USER}@${SERVER_HOST}" \
  "APP_DIR='$remote_app_dir' timeout 45s bash -s" <<'REMOTE_SCRIPT'
set -u

echo "=== Host ==="
uptime || true
free -h || true
df -h / || true

echo "=== Zenvis containers ==="
docker ps -a \
  --filter name=kafka-service \
  --filter name=redis-signal \
  --filter name=redis-stack-signal \
  --filter name=mysql8 \
  --filter name=clickhouse-service \
  --filter name=zenvis-backend \
  --filter name=vectum-service \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' || true

echo "=== Container resources ==="
timeout 10s docker stats --no-stream \
  kafka-service redis-signal redis-stack-signal mysql8 \
  clickhouse-service zenvis-backend vectum-service 2>/dev/null || true

for container in kafka-service redis-signal redis-stack-signal mysql8 \
  clickhouse-service zenvis-backend vectum-service; do
  if ! docker inspect "$container" >/dev/null 2>&1; then
    continue
  fi
  echo "=== ${container} state ==="
  docker inspect --format \
    'status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} restarts={{.RestartCount}} error={{.State.Error}}' \
    "$container" || true
  echo "=== ${container} logs (tail 80) ==="
  timeout 8s docker logs --tail=80 "$container" 2>&1 || true
done
REMOTE_SCRIPT
