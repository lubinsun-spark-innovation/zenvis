#!/usr/bin/env bash

set -Eeuo pipefail

: "${SERVER_HOST:?SERVER_HOST is required}"
: "${SERVER_USER:?SERVER_USER is required}"
: "${SERVER_SSH_KEY:?SERVER_SSH_KEY is required}"

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
  for attempt in {1..6}; do
    if ssh-keyscan -T 20 -H "$SERVER_HOST" > "$work_dir/known_hosts"; then
      break
    fi
    echo "Waiting for the overloaded SSH endpoint (${attempt}/6)..." >&2
    sleep 10
  done
fi
[[ -s "$work_dir/known_hosts" ]] || {
  echo "Unable to collect the server SSH host key." >&2
  exit 1
}
chmod 600 "$work_dir/known_hosts"

cat > "$work_dir/stop-zenvis.sh" <<'REMOTE_SCRIPT'
set -Eeuo pipefail

containers=(
  zenvis-backend
  vectum-service
  clickhouse-service
  kafka-service
  redis-stack-signal
  mysql8
  redis-signal
)

for container in "${containers[@]}"; do
  docker update --restart=no "$container" >/dev/null 2>&1 || true
done

timeout 90s docker stop -t 15 "${containers[@]}" 2>/dev/null || true
for container in "${containers[@]}"; do
  docker update --restart=no "$container" >/dev/null 2>&1 || true
  docker stop -t 5 "$container" >/dev/null 2>&1 || true
  docker rm "$container" >/dev/null 2>&1 || true
done

echo "=== Remaining Zenvis containers ==="
docker ps -a \
  --filter name=kafka-service \
  --filter name=redis-signal \
  --filter name=redis-stack-signal \
  --filter name=mysql8 \
  --filter name=clickhouse-service \
  --filter name=zenvis-backend \
  --filter name=vectum-service \
  --format 'table {{.Names}}\t{{.Status}}' || true

echo "=== Host after stopping Zenvis ==="
uptime || true
free -h || true
df -h / || true
REMOTE_SCRIPT

ssh_options=(
  -i "$work_dir/id_ed25519"
  -o BatchMode=yes
  -o ConnectTimeout=30
  -o IdentitiesOnly=yes
  -o ServerAliveInterval=10
  -o ServerAliveCountMax=12
  -o StrictHostKeyChecking=yes
  -o UserKnownHostsFile="$work_dir/known_hosts"
)

for attempt in {1..12}; do
  if timeout 180s ssh "${ssh_options[@]}" "${SERVER_USER}@${SERVER_HOST}" \
    "timeout 150s bash -s" < "$work_dir/stop-zenvis.sh"; then
    echo "Zenvis VPS containers were stopped and removed; persistent data was preserved."
    exit 0
  fi
  echo "Waiting for an SSH maintenance slot (${attempt}/12)..." >&2
  sleep 15
done

echo "Unable to stop Zenvis because the server remained unavailable over SSH." >&2
exit 1
