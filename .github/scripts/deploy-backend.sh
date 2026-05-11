#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?target is required}"
JAR_FILE="${2:?jar file is required}"

SSH_USER="${SSH_USER:-root}"
API_DOMAIN="${API_DOMAIN:-api.edgepulse.top}"
ANALYTICS_DOMAIN="${ANALYTICS_DOMAIN:-analytics.edgepulse.top}"
ADMIN_DOMAIN="${ADMIN_DOMAIN:-ads.299188.xyz}"

case "$TARGET" in
  api)
    HOST="${API_HOST:-}"
    PORT="${API_SSH_PORT:-22}"
    KEY="${API_SSH_PRIVATE_KEY:-}"
    SERVICE_NAME="ug-ads-api"
    REMOTE_JAR="/app/ug-ads-api.jar"
    SPRING_PROFILE="api"
    CADDY_KIND="api"
    ;;
  analytics)
    HOST="${ANALYTICS_HOST:-}"
    PORT="${ANALYTICS_SSH_PORT:-22}"
    KEY="${ANALYTICS_SSH_PRIVATE_KEY:-}"
    SERVICE_NAME="ug-ads-analytics"
    REMOTE_JAR="/app/ug-ads-analytics.jar"
    SPRING_PROFILE="analytics"
    CADDY_KIND="analytics"
    ;;
  *)
    echo "Unsupported target: $TARGET" >&2
    exit 1
    ;;
esac

if [ -z "$HOST" ]; then
  echo "Missing host for target: $TARGET" >&2
  exit 1
fi

if [ -z "$KEY" ]; then
  echo "Missing SSH private key for target: $TARGET" >&2
  exit 1
fi

if [ ! -f "$JAR_FILE" ]; then
  echo "Jar file does not exist: $JAR_FILE" >&2
  exit 1
fi

SSH_DIR="$RUNNER_TEMP/deploy_ssh_$TARGET"
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

REMOTE_TMP="/tmp/${SERVICE_NAME}.jar.new"

scp "${SCP_OPTS[@]}" "$JAR_FILE" "${SSH_USER}@${HOST}:${REMOTE_TMP}"

ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HOST}" \
  "SERVICE_NAME='$SERVICE_NAME' REMOTE_JAR='$REMOTE_JAR' REMOTE_TMP='$REMOTE_TMP' SPRING_PROFILE='$SPRING_PROFILE' CADDY_KIND='$CADDY_KIND' API_DOMAIN='$API_DOMAIN' ANALYTICS_DOMAIN='$ANALYTICS_DOMAIN' ADMIN_DOMAIN='$ADMIN_DOMAIN' bash -s" <<'REMOTE_SCRIPT'
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
  if [ "$CADDY_KIND" = "api" ]; then
    cat > /etc/caddy/Caddyfile <<EOF
http://${API_DOMAIN} {
    encode gzip
    rewrite * /ug-ads/api/open/dispatch
    reverse_proxy 127.0.0.1:8080
}
EOF
  else
    cat > /etc/caddy/Caddyfile <<EOF
http://${ANALYTICS_DOMAIN} {
    encode gzip
    rewrite * /ug-ads/api/open/dispatch
    reverse_proxy 127.0.0.1:8080
}

${ADMIN_DOMAIN} {
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
  fi
}

mkdir -p /app
mv "$REMOTE_TMP" "$REMOTE_JAR"
chmod 0644 "$REMOTE_JAR"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=${SERVICE_NAME}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/app
Environment=TZ=Asia/Shanghai
ExecStart=/usr/bin/env java -Xms128m -Xmx256m -jar ${REMOTE_JAR} --spring.profiles.active=${SPRING_PROFILE}
Restart=on-failure
RestartSec=5
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF

install_caddy_if_missing
write_caddyfile
caddy fmt --overwrite /etc/caddy/Caddyfile >/dev/null 2>&1 || true

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

systemctl enable --now caddy
systemctl reload caddy || systemctl restart caddy
REMOTE_SCRIPT

echo "Deployed $TARGET backend to $HOST"
