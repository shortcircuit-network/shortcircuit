#!/bin/bash
# ARCHIVED — do not use. Kept for reference only.
# Headscale version is stale (0.22.3). Use terraform/digitalocean/ instead.
set -e

# Install essentials
apt-get update
apt-get install -y golang-go git curl jq vim htop

# Create 2GB swap
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Sysctl tweaks
cat <<EOF >> /etc/sysctl.d/99-headscale.conf
fs.file-max = 100000
net.ipv6.neigh.default.gc_thresh1 = 128
net.ipv6.neigh.default.gc_thresh2 = 512
net.ipv6.neigh.default.gc_thresh3 = 1024
net.ipv6.conf.all.forwarding = 1
EOF
sysctl --system

# Setup directories
mkdir -p /opt/ddns /opt/headscale /var/log/ddns /var/state/ddns

# Pull Go DDNS
git clone https://github.com/jkubo/ddns-ipv6.git /opt/ddns
cd /opt/ddns/cmd
go build -o /usr/local/bin/ddns-ipv6

# Copy systemd units
cp /opt/ddns/systemd/ddns-update.service /etc/systemd/system/
cp /opt/ddns/systemd/ddns-update.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now ddns-update.timer

# Install Headscale
wget https://github.com/juanfont/headscale/releases/download/v${headscale_version}/headscale_${headscale_version}_linux_amd64.deb
dpkg -i headscale_${headscale_version}_linux_amd64.deb
systemctl enable --now headscale

echo "Bootstrap complete. Swap enabled, DDNS and Headscale running."

