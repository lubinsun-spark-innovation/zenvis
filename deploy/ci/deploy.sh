#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <backend-directory> <zenvis-infra-directory>" >&2
  exit 2
fi

backend_dir=$(realpath "$1")
infra_dir=$(realpath "$2")

: "${SERVER_HOST:?SERVER_HOST is required}"
: "${SERVER_USER:?SERVER_USER is required}"
: "${SERVER_SSH_KEY:?SERVER_SSH_KEY is required}"
: "${ZENVIS_BOOTSTRAP_SUPER_ADMIN_PASSWORD:?ZENVIS_BOOTSTRAP_SUPER_ADMIN_PASSWORD is required}"
: "${ZENVIS_BOOTSTRAP_ADMIN_PASSWORD:?ZENVIS_BOOTSTRAP_ADMIN_PASSWORD is required}"

image_tag=${DEPLOY_IMAGE_TAG:-${GITHUB_SHA:-manual}}
image_tag=${image_tag//\//-}
image_name=zenvis-backend
remote_app_dir=${REMOTE_APP_DIR:-/root/lubinsun/zenvis}
remote_release_dir="/tmp/zenvis-${image_tag}"
work_dir=$(mktemp -d)
ssh_dir="$work_dir/ssh"
mkdir -p "$ssh_dir"

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

chmod 700 "$ssh_dir"
printf '%s\n' "$SERVER_SSH_KEY" > "$ssh_dir/id_ed25519"
chmod 600 "$ssh_dir/id_ed25519"

known_hosts="$ssh_dir/known_hosts"
if [[ -n "${SERVER_SSH_KNOWN_HOSTS:-}" ]]; then
  printf '%s\n' "$SERVER_SSH_KNOWN_HOSTS" > "$known_hosts"
else
  ssh-keyscan -H "$SERVER_HOST" > "$known_hosts"
fi
chmod 600 "$known_hosts"

ssh_options=(
  -i "$ssh_dir/id_ed25519"
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes
  -o UserKnownHostsFile="$known_hosts"
)

echo "Building ${image_name}:${image_tag}"
docker build \
  --build-arg BASE_IMAGE_ARCH=amd64 \
  --tag "${image_name}:${image_tag}" \
  "$backend_dir"
docker save "${image_name}:${image_tag}" | gzip -1 > "$work_dir/backend-image.tar.gz"

tar -C "$infra_dir" -czf "$work_dir/deploy-bundle.tar.gz" \
  deploy/.env.example \
  deploy/config \
  deploy/docker-compose.yml \
  deploy/docker-compose.production.yml \
  deploy/open_config \
  deploy/server/deploy.sh

umask 077
printf 'ZENVIS_BOOTSTRAP_SUPER_ADMIN_PASSWORD=%s\n' \
  "$ZENVIS_BOOTSTRAP_SUPER_ADMIN_PASSWORD" > "$work_dir/runtime.env"
printf 'ZENVIS_BOOTSTRAP_ADMIN_PASSWORD=%s\n' \
  "$ZENVIS_BOOTSTRAP_ADMIN_PASSWORD" >> "$work_dir/runtime.env"

ssh "${ssh_options[@]}" "${SERVER_USER}@${SERVER_HOST}" \
  "mkdir -p '$remote_release_dir' && chmod 700 '$remote_release_dir'"

scp "${ssh_options[@]}" \
  "$work_dir/backend-image.tar.gz" \
  "$work_dir/deploy-bundle.tar.gz" \
  "$work_dir/runtime.env" \
  "${SERVER_USER}@${SERVER_HOST}:${remote_release_dir}/"

ssh "${ssh_options[@]}" "${SERVER_USER}@${SERVER_HOST}" \
  "APP_DIR='$remote_app_dir' IMAGE_NAME='$image_name' IMAGE_TAG='$image_tag' \
   IMAGE_ARCHIVE='${remote_release_dir}/backend-image.tar.gz' \
   DEPLOY_ARCHIVE='${remote_release_dir}/deploy-bundle.tar.gz' \
   RUNTIME_ENV='${remote_release_dir}/runtime.env' \
   bash -s" < "$infra_dir/deploy/server/deploy.sh"

for attempt in {1..24}; do
  if curl -fsS --max-time 15 \
    "https://apisoc.lubinsun.2333123.xyz/actuator/health/readiness" >/dev/null; then
    echo "Public backend readiness check passed."
    exit 0
  fi
  echo "Waiting for the public backend endpoint (${attempt}/24)..."
  sleep 5
done

echo "The server deployment succeeded, but the public backend endpoint is not ready." >&2
exit 1
