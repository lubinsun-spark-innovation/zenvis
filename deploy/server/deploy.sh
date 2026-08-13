#!/usr/bin/env bash

set -Eeuo pipefail

: "${APP_DIR:?APP_DIR is required}"
: "${IMAGE_NAME:?IMAGE_NAME is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${IMAGE_ARCHIVE:?IMAGE_ARCHIVE is required}"
: "${DEPLOY_ARCHIVE:?DEPLOY_ARCHIVE is required}"
: "${RUNTIME_ENV:?RUNTIME_ENV is required}"

services=(
  kafka-service
  redis-service
  redis-stack-service
  mysql-service
  clickhouse-service
  zenvis-backend
  vectum-service
)
containers=(
  kafka-service
  redis-signal
  redis-stack-signal
  mysql8
  clickhouse-service
  zenvis-backend
  vectum-service
)
stage_dir=$(mktemp -d)
backup_file=""

cleanup() {
  rm -rf "$stage_dir" "$IMAGE_ARCHIVE" "$DEPLOY_ARCHIVE" "$RUNTIME_ENV"
  rmdir "$(dirname "$IMAGE_ARCHIVE")" 2>/dev/null || true
}
trap cleanup EXIT

upsert_env() {
  local key=$1
  local value=$2
  local env_file="$APP_DIR/.env"
  local temp_file
  temp_file=$(mktemp)

  awk -v key="$key" -v value="$value" '
    BEGIN { found = 0 }
    index($0, key "=") == 1 {
      if (!found) {
        print key "=" value
        found = 1
      }
      next
    }
    { print }
    END {
      if (!found) print key "=" value
    }
  ' "$env_file" > "$temp_file"
  mv "$temp_file" "$env_file"
}

random_hex() {
  openssl rand -hex "${1:-24}"
}

rollback() {
  local exit_code=$?
  echo "Deployment failed; collecting bounded diagnostics and restoring the previous release." >&2
  timeout 10s docker compose \
    --project-directory "$APP_DIR" \
    -f "$APP_DIR/docker-compose.yml" \
    -f "$APP_DIR/docker-compose.production.yml" \
    ps >&2 || true

  for container in "${containers[@]}"; do
    echo "=== ${container} state ===" >&2
    timeout 5s docker inspect --format \
      'status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} restarts={{.RestartCount}} error={{.State.Error}}' \
      "$container" >&2 || true
    echo "=== ${container} logs (tail 80) ===" >&2
    timeout 8s docker logs --tail=80 "$container" >&2 || true
  done

  if [[ -n "$backup_file" && -f "$backup_file" ]]; then
    tar -C "$APP_DIR" -xzf "$backup_file" || true
    docker compose \
      --project-directory "$APP_DIR" \
      -f "$APP_DIR/docker-compose.yml" \
      -f "$APP_DIR/docker-compose.production.yml" \
      up -d zenvis-backend || true
  fi
  exit "$exit_code"
}

mkdir -p "$APP_DIR" "$APP_DIR/backups"
tar -C "$stage_dir" -xzf "$DEPLOY_ARCHIVE"

backup_items=()
for item in .env docker-compose.yml docker-compose.production.yml config open_config .deployed-backend-sha; do
  [[ -e "$APP_DIR/$item" ]] && backup_items+=("$item")
done
if (( ${#backup_items[@]} > 0 )); then
  backup_file="$APP_DIR/backups/release-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -C "$APP_DIR" -czf "$backup_file" "${backup_items[@]}"
  chmod 600 "$backup_file"
fi

install -m 644 "$stage_dir/deploy/docker-compose.yml" "$APP_DIR/docker-compose.yml"
install -m 644 "$stage_dir/deploy/docker-compose.production.yml" "$APP_DIR/docker-compose.production.yml"
rm -rf "$APP_DIR/config.next"
cp -a "$stage_dir/deploy/config" "$APP_DIR/config.next"
rm -rf "$APP_DIR/config"
mv "$APP_DIR/config.next" "$APP_DIR/config"
mkdir -p "$APP_DIR/open_config"
cp -a "$stage_dir/deploy/open_config/." "$APP_DIR/open_config/"

if [[ ! -f "$APP_DIR/.env" ]]; then
  install -m 600 "$stage_dir/deploy/.env.example" "$APP_DIR/.env"
  set -a
  # shellcheck disable=SC1090
  source "$RUNTIME_ENV"
  set +a
  : "${ZENVIS_BOOTSTRAP_SUPER_ADMIN_PASSWORD:?bootstrap super-admin password is required}"
  : "${ZENVIS_BOOTSTRAP_ADMIN_PASSWORD:?bootstrap admin password is required}"

  upsert_env MYSQL_ROOT_PASSWORD "Zenvis$(random_hex 24)"
  upsert_env MYSQL_PASSWORD "Zenvis$(random_hex 24)"
  upsert_env CLICKHOUSE_PASSWORD "Zenvis$(random_hex 24)"
  upsert_env REDIS_PASSWORD "Zenvis$(random_hex 24)"
  upsert_env KAFKA_CLUSTER_ID "$(openssl rand -hex 11)"
  upsert_env API_BEARER_TOKEN "$(random_hex 32)"
  upsert_env MCP_BEARER_TOKEN "$(random_hex 32)"
  upsert_env VECTUM_AUTH_TOKEN "$(random_hex 32)"
  upsert_env ZENVIS_BOOTSTRAP_SUPER_ADMIN_PASSWORD "$ZENVIS_BOOTSTRAP_SUPER_ADMIN_PASSWORD"
  upsert_env ZENVIS_BOOTSTRAP_ADMIN_PASSWORD "$ZENVIS_BOOTSTRAP_ADMIN_PASSWORD"
fi

chmod 600 "$APP_DIR/.env"
upsert_env ARCH amd64
upsert_env ZENVIS_API_BIND_ADDRESS 127.0.0.1
upsert_env ZENVIS_API_PORT 11001
upsert_env ZENVIS_INFRA_BIND_ADDRESS 127.0.0.1
upsert_env ZENVIS_WEB_BIND_ADDRESS 127.0.0.1
upsert_env MYSQL_PORT 23306
upsert_env LUBINSUN_BASE_URL https://api.lubinsun.2333123.xyz/api
upsert_env ZENVIS_BACKEND_IMAGE "${IMAGE_NAME}:${IMAGE_TAG}"

trap rollback ERR
docker load < "$IMAGE_ARCHIVE"

compose=(
  docker compose
  --project-directory "$APP_DIR"
  -f "$APP_DIR/docker-compose.yml"
  -f "$APP_DIR/docker-compose.production.yml"
)

"${compose[@]}" config --quiet
"${compose[@]}" pull \
  kafka-service \
  redis-service \
  redis-stack-service \
  mysql-service \
  clickhouse-service \
  vectum-service
"${compose[@]}" up -d --remove-orphans "${services[@]}"

for attempt in {1..36}; do
  if timeout 5s curl -fsS --connect-timeout 2 --max-time 3 \
    http://127.0.0.1:11001/actuator/health/readiness >/dev/null; then
    printf '%s\n' "$IMAGE_TAG" > "$APP_DIR/.deployed-backend-sha"
    trap - ERR
    echo "Zenvis backend ${IMAGE_TAG} is ready on 127.0.0.1:11001."
    exit 0
  fi
  echo "Waiting for Zenvis backend readiness (${attempt}/36)..."
  sleep 5
done

echo "Zenvis backend did not become ready in time." >&2
false
