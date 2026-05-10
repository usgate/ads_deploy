#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="${1:?frontend archive is required}"

SSH_USER="${SSH_USER:-root}"
HOST="${ANALYTICS_HOST:-}"
PORT="${ANALYTICS_SSH_PORT:-22}"
KEY="${ANALYTICS_SSH_PRIVATE_KEY:-}"
ANALYTICS_DOMAIN="${ANALYTICS_DOMAIN:-analytics.edgepulse.top}"
ADMIN_DOMAIN="${ADMIN_DOMAIN:-ad.520531.xyz}"

if [ -z "$HOST" ]; then
  echo "ANALYTICS_HOST is required." >&2
  exit 1
fi

if [ -z "$KEY" ]; then
  echo "ANALYTICS_SSH_PRIVATE_KEY is required." >&2
  exit 1
fi

if [ ! -f "$ARCHIVE" ]; then
  echo "Frontend archive does not exist: $ARCHIVE" >&2
  exit 1
fi

SSH_DIR="$RUNNER_TEMP/deploy_ssh_frontend"
mkdir -p "$SSH_DIR"
KEY_FILE="$SSH_DIR/id_key"
printf '%s\n' "$KEY" > "$KEY_FILE"
chmod 600 "$KEY_FILE"

SSH_OPTS=(
  -i "$KEY_FILE"
  -p "$PORT"
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
)

SCP_OPTS=(
  -i "$KEY_FILE"
  -P "$PORT"
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
)

REMOTE_TMP="/tmp/ug-ads-vue-dist.tar.gz"

scp "${SCP_OPTS[@]}" "$ARCHIVE" "${SSH_USER}@${HOST}:${REMOTE_TMP}"

ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HOST}" \
  "REMOTE_TMP='$REMOTE_TMP' ANALYTICS_DOMAIN='$ANALYTICS_DOMAIN' ADMIN_DOMAIN='$ADMIN_DOMAIN' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

install_caddy_if_missing() {
  if command -v caddy >/dev/null 2>&1; then
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gpg
    install -d -m 0755 /usr/share/keyrings
    rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
      | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    chmod 0644 /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
      > /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    apt-get install -y caddy
    return
  fi

  echo "Caddy is not installed and automatic install only supports Debian/Ubuntu with apt-get." >&2
  exit 1
}

write_caddyfile() {
  mkdir -p /etc/caddy
  cat > /etc/caddy/Caddyfile <<EOF
http://${ANALYTICS_DOMAIN} {
    encode gzip
    rewrite * /ug-ads/api/open/dispatch
    reverse_proxy 127.0.0.1:8080
}

http://${ADMIN_DOMAIN} {
    root * /app/ug-ads-vue
    encode gzip

    handle /ug-ads/* {
        reverse_proxy 127.0.0.1:8080
    }

    handle {
        try_files {path} /index.html
        file_server
    }
}
EOF
}

mkdir -p /app
rm -rf /app/ug-ads-vue.new
mkdir -p /app/ug-ads-vue.new
tar -xzf "$REMOTE_TMP" -C /app/ug-ads-vue.new
rm -f "$REMOTE_TMP"

rm -rf /app/ug-ads-vue.prev
if [ -d /app/ug-ads-vue ]; then
  mv /app/ug-ads-vue /app/ug-ads-vue.prev
fi
mv /app/ug-ads-vue.new /app/ug-ads-vue

install_caddy_if_missing
write_caddyfile
caddy fmt --overwrite /etc/caddy/Caddyfile >/dev/null 2>&1 || true
systemctl enable --now caddy
systemctl reload caddy || systemctl restart caddy
REMOTE_SCRIPT

echo "Deployed frontend to $HOST"
