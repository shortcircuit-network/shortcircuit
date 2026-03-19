#!/bin/bash
# bootstrap.sh — DigitalOcean amd64 Shortcircuit lighthouse
# Rendered by Terraform templatefile(). $${var} = Terraform; $VAR = bash.
#
# Service architecture:
#   litestream-restore (oneshot) → headscale (localhost:8443) → litestream-replicate (continuous)
#   certbot (oneshot, CF DNS challenge) → haproxy (SNI router, :443 TCP) → ocserv (localhost:4443)
#   ddns-update.timer (both FQDNs every 5min)
#
# Port routing:
#   TCP :443 → HAProxy SNI:
#     ${headscale_domain} → localhost:8443 (Headscale)
#     ${ocserv_domain}    → localhost:4443 (ocserv TCP)
#   UDP :443 → ocserv directly (DTLS, no HAProxy needed)
#   UDP :3478 → Headscale STUN coordination
set -euo pipefail
exec > /var/log/bootstrap.log 2>&1

echo "==> Bootstrap started: $(date -u)"

# 1. Create non-root admin user, install SSH key, disable root login
useradd -m -s /bin/bash admin
mkdir -p /home/admin/.ssh
echo "${ssh_public_key}" > /home/admin/.ssh/authorized_keys
chown -R admin:admin /home/admin/.ssh
chmod 700 /home/admin/.ssh
chmod 600 /home/admin/.ssh/authorized_keys
echo "admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/admin
chmod 440 /etc/sudoers.d/admin

# Disable root SSH login — admin user is the only entry point
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl reload ssh

# 2. Install packages
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl jq git golang-go \
  haproxy \
  ocserv \
  certbot python3-certbot-dns-cloudflare

# 2. Kernel settings
cat > /etc/sysctl.d/99-shortcircuit.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
fs.file-max = 100000
EOF
sysctl --system

# 3. Create directories
mkdir -p /var/lib/headscale /etc/headscale /var/run/headscale \
         /var/log/ddns /var/state/ddns \
         /etc/ocserv

# 4. Build ddns-ipv4 binary from source
git clone https://github.com/shortcircuit-network/shortcircuit.git /opt/shortcircuit
cd /opt/shortcircuit
go build -o /usr/local/bin/ddns-ipv4 ./cmd/ddns-ipv4/
echo "==> ddns-ipv4 built: $(ddns-ipv4 2>&1 | head -1 || true)"

# 5. Write DDNS env file
cat > /etc/ddns.env <<EOF
CF_TOKEN=${cf_token}
CF_EMAIL=${cf_email}
DDNS_RECORDS_JSON='${ddns_records_json}'
LOG_PATH=/var/log/ddns/ddns.log
STATE_PATH=/var/state/ddns/ip.txt
EOF
chmod 600 /etc/ddns.env

# 6. Install Headscale (amd64 .deb)
HEADSCALE_DEB="headscale_${headscale_version}_linux_amd64.deb"
curl -fsSL -o /tmp/$HEADSCALE_DEB \
  "https://github.com/juanfont/headscale/releases/download/v${headscale_version}/$HEADSCALE_DEB"
dpkg -i /tmp/$HEADSCALE_DEB
rm /tmp/$HEADSCALE_DEB

# 7. Write Headscale config — listens on localhost:8443, HAProxy terminates TLS on :443
cat > /etc/headscale/config.yaml <<EOF
server_url: ${headscale_server_url}
listen_addr: 127.0.0.1:8443
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

# 8. Install Litestream (amd64)
LITESTREAM_VERSION="${litestream_version}"
curl -fsSL -o /tmp/litestream.tar.gz \
  "https://github.com/benbjohnson/litestream/releases/download/v$LITESTREAM_VERSION/litestream-v$LITESTREAM_VERSION-linux-amd64.tar.gz"
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

# 10. Cloudflare credentials for certbot DNS challenge
# Uses scoped API token (DNS:Zone:Edit) — NOT the legacy global API key.
cat > /etc/cloudflare.ini <<EOF
dns_cloudflare_api_token = ${cf_token}
EOF
chmod 600 /etc/cloudflare.ini

# 11. Obtain TLS certificates via Cloudflare DNS challenge (no port 80 needed)
# Both FQDNs in one cert avoids HAProxy needing two cert paths.
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 30 \
  -d "${headscale_domain}" \
  -d "${ocserv_domain}" \
  --non-interactive --agree-tos \
  --email "${letsencrypt_email}" \
  --cert-name shortcircuit

# 12. HAProxy config — SNI TCP routing on :443
# headscale_domain → localhost:8443 (Headscale, handles its own TLS)
# ocserv_domain    → localhost:4443 (ocserv TCP, handles its own TLS)
cat > /etc/haproxy/haproxy.cfg <<EOF
global
  log /dev/log local0
  maxconn 4096
  daemon

defaults
  log     global
  timeout connect 5s
  timeout client  30s
  timeout server  30s

frontend https_sni
  bind *:443
  mode tcp
  tcp-request inspect-delay 5s
  tcp-request content accept if { req_ssl_hello_type 1 }
  use_backend headscale if { req_ssl_sni -i ${headscale_domain} }
  use_backend ocserv    if { req_ssl_sni -i ${ocserv_domain} }
  default_backend headscale

backend headscale
  mode tcp
  server hs 127.0.0.1:8443

backend ocserv
  mode tcp
  server oc 127.0.0.1:4443
EOF

# 13. ocserv config — TCP on localhost:4443, UDP :443 direct (DTLS)
# Users managed via ocpasswd: ocpasswd -c /etc/ocserv/users.passwd <username>
cat > /etc/ocserv/ocserv.conf <<EOF
auth = "plain[/etc/ocserv/users.passwd]"
tcp-port = 4443
udp-port = 443
socket-file = /run/ocserv-socket

server-cert = /etc/letsencrypt/live/shortcircuit/fullchain.pem
server-key  = /etc/letsencrypt/live/shortcircuit/privkey.pem

ca-cert = /etc/ssl/certs/ca-certificates.crt

max-clients = 16
max-same-clients = 2
keepalive = 32400

try-mtu-discovery = true
mtu = 1420

ipv4-network = 192.168.90.0/24
ipv4-netmask = 255.255.255.0
dns = 1.1.1.1
dns = 9.9.9.9

route = default

log-level = 2
EOF

# Create empty passwd file so ocserv starts (users added manually via ocpasswd)
touch /etc/ocserv/users.passwd

# 14. Systemd units

# litestream-restore
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

# headscale
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

# litestream-replicate
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

# ddns-update.service
cat > /etc/systemd/system/ddns-update.service <<'UNIT'
[Unit]
Description=Cloudflare IPv4 A Record DDNS Update (mesh + vpn FQDNs)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/ddns.env
ExecStart=/usr/local/bin/ddns-ipv4
User=root

[Install]
WantedBy=multi-user.target
UNIT

# ddns-update.timer
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

# certbot renewal timer (Let's Encrypt auto-renew)
cat > /etc/systemd/system/certbot-renew.timer <<'UNIT'
[Unit]
Description=Certbot auto-renewal for shortcircuit TLS certificates

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
UNIT

cat > /etc/systemd/system/certbot-renew.service <<'UNIT'
[Unit]
Description=Certbot renewal — shortcircuit

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet
ExecStartPost=/bin/systemctl reload haproxy
ExecStartPost=/bin/systemctl reload ocserv

[Install]
WantedBy=multi-user.target
UNIT

# 15. Enable and start all services
systemctl daemon-reload
systemctl enable \
  litestream-restore.service \
  headscale.service \
  litestream-replicate.service \
  haproxy.service \
  ocserv.service \
  ddns-update.timer \
  certbot-renew.timer

systemctl start litestream-restore.service
systemctl start headscale.service
systemctl start litestream-replicate.service
systemctl start haproxy.service
systemctl start ocserv.service
systemctl start ddns-update.timer
systemctl start certbot-renew.timer

echo "==> Bootstrap complete: $(date -u)"
echo "==> Headscale:           $(systemctl is-active headscale)"
echo "==> HAProxy:             $(systemctl is-active haproxy)"
echo "==> ocserv:              $(systemctl is-active ocserv)"
echo "==> Litestream replicate: $(systemctl is-active litestream-replicate)"
echo "==> DDNS timer:          $(systemctl is-active ddns-update.timer)"
echo ""
echo "==> Verification:"
echo "    curl https://${headscale_domain}/health"
echo "    iOS: GlobalProtect → ${ocserv_domain}"
echo "    Add VPN user: ocpasswd -c /etc/ocserv/users.passwd <username>"
