#!/bin/bash
# bootstrap.sh — Oracle Cloud Ampere A1 (ARM64) Headscale node
# Rendered by Terraform templatefile(). ${var} = Terraform; $VAR = bash.
set -euo pipefail
exec > /var/log/bootstrap.log 2>&1

echo "==> Bootstrap started: $(date -u)"

# 1. Install packages
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y curl jq git golang-go

# 2. Kernel settings
cat > /etc/sysctl.d/99-headscale.conf <<EOF
net.ipv4.ip_forward = 1
fs.file-max = 100000
EOF
sysctl --system

# 3. Create directories
mkdir -p /var/lib/headscale /etc/headscale /var/run/headscale \
         /var/log/ddns /var/state/ddns

# 4. Build ddns-ipv4 binary from source (native ARM64 compile, ~seconds)
git clone https://github.com/shortcircuit-network/shortcircuit.git /opt/shortcircuit
cd /opt/shortcircuit
go build -o /usr/local/bin/ddns-ipv4 ./cmd/ddns-ipv4/
echo "==> ddns-ipv4 built: $(ddns-ipv4 2>&1 | head -1 || true)"

# 5. Write DDNS env file (systemd EnvironmentFile)
# DDNS_RECORDS_JSON must be single-line JSON — see variables.tf description.
cat > /etc/ddns.env <<EOF
CF_TOKEN=${cf_token}
CF_EMAIL=${cf_email}
DDNS_RECORDS_JSON='${ddns_records_json}'
LOG_PATH=/var/log/ddns/ddns.log
STATE_PATH=/var/state/ddns/ip.txt
EOF
chmod 600 /etc/ddns.env

# 6. Install Headscale (arm64 .deb from GitHub releases)
HEADSCALE_DEB="headscale_${headscale_version}_linux_arm64.deb"
curl -fsSL -o /tmp/$HEADSCALE_DEB \
  "https://github.com/juanfont/headscale/releases/download/v${headscale_version}/$HEADSCALE_DEB"
dpkg -i /tmp/$HEADSCALE_DEB
rm /tmp/$HEADSCALE_DEB

# 7. Write Headscale config
cat > /etc/headscale/config.yaml <<EOF
server_url: ${headscale_server_url}
listen_addr: 0.0.0.0:443
metrics_listen_addr: 127.0.0.1:9090
grpc_listen_addr: 127.0.0.1:50443
grpc_allow_insecure: false

noise:
  private_key_path: /var/lib/headscale/noise_private.key

prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48

derp:
  server:
    enabled: false
  urls:
    - https://controlplane.tailscale.com/derpmap/default
  auto_update_enabled: true
  update_frequency: 24h

database:
  type: sqlite3
  sqlite:
    path: /var/lib/headscale/db.sqlite

log:
  level: info
  format: text

unix_socket: /var/run/headscale/headscale.sock
unix_socket_permission: "0770"

logtail:
  enabled: false

randomize_client_port: false
EOF

# 8. Install Litestream (arm64 binary)
LITESTREAM_VERSION="0.3.13"
curl -fsSL -o /tmp/litestream.tar.gz \
  "https://github.com/benbjohnson/litestream/releases/download/v$LITESTREAM_VERSION/litestream-v$LITESTREAM_VERSION-linux-arm64.tar.gz"
tar -xzf /tmp/litestream.tar.gz -C /usr/local/bin litestream
rm /tmp/litestream.tar.gz
chmod +x /usr/local/bin/litestream

# 9. Write Litestream replication config
cat > /etc/litestream.yml <<EOF
dbs:
  - path: /var/lib/headscale/db.sqlite
    replicas:
      - type: s3
        bucket: ${r2_bucket}
        path: headscale/db
        endpoint: ${r2_endpoint}
        access-key-id: ${r2_access_key_id}
        secret-access-key: ${r2_secret_access_key}
        force-path-style: true
EOF
chmod 600 /etc/litestream.yml

# 10. Systemd units

# litestream-restore: oneshot that restores the DB from R2 if not present locally.
# Runs before headscale on every boot — -if-db-not-exists is a no-op if DB exists.
cat > /etc/systemd/system/litestream-restore.service <<'UNIT'
[Unit]
Description=Litestream — restore Headscale SQLite from R2 on boot
Before=headscale.service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/litestream restore -if-db-not-exists -config /etc/litestream.yml /var/lib/headscale/db.sqlite

[Install]
WantedBy=multi-user.target
UNIT

# headscale: override to add litestream-restore dependency
cat > /etc/systemd/system/headscale.service <<'UNIT'
[Unit]
Description=Headscale VPN Control Plane
After=network-online.target litestream-restore.service
Wants=network-online.target
Requires=litestream-restore.service

[Service]
Type=simple
ExecStart=/usr/bin/headscale serve
Restart=always
RestartSec=5
User=root
Group=root

[Install]
WantedBy=multi-user.target
UNIT

# litestream-replicate: continuous replication to R2 while headscale runs
cat > /etc/systemd/system/litestream-replicate.service <<'UNIT'
[Unit]
Description=Litestream — continuous replication of Headscale SQLite to R2
After=headscale.service
Requires=headscale.service

[Service]
Type=simple
ExecStart=/usr/local/bin/litestream replicate -config /etc/litestream.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

# ddns-update: IPv4 A record updater (one-shot, triggered by timer)
cat > /etc/systemd/system/ddns-update.service <<'UNIT'
[Unit]
Description=Cloudflare IPv4 A Record DDNS Update
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/ddns.env
ExecStart=/usr/local/bin/ddns-ipv4
User=root
Group=root

[Install]
WantedBy=multi-user.target
UNIT

# ddns-update timer: run every 5 minutes
cat > /etc/systemd/system/ddns-update.timer <<'UNIT'
[Unit]
Description=Run Cloudflare IPv4 DDNS update every 5 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
AccuracySec=1s

[Install]
WantedBy=timers.target
UNIT

# 11. Enable and start all services
systemctl daemon-reload
systemctl enable litestream-restore.service headscale.service litestream-replicate.service ddns-update.timer

systemctl start litestream-restore.service
systemctl start headscale.service
systemctl start litestream-replicate.service
systemctl start ddns-update.timer

echo "==> Bootstrap complete: $(date -u)"
echo "==> Headscale: $(systemctl is-active headscale)"
echo "==> Litestream replicate: $(systemctl is-active litestream-replicate)"
echo "==> DDNS timer: $(systemctl is-active ddns-update.timer)"
