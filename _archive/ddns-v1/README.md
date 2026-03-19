# IPv6 DDNS for Headscale / Free GCE

This repo provides a **Cloudflare AAAA DDNS updater** for IPv6-only instances.

## Features
- IPv6-only, free on GCP
- Multiple records configurable via `.env`
- State caching prevents API abuse
- Modular, systemd-ready

## Quick Start
1. Copy `.env.example` → `.env` and fill in your tokens & record IDs.
2. Build Go binary:
```bash
go build -o /usr/local/bin/ddns-ipv6 ./cmd/ddns-ipv6.go
```
3. Create systemd user:
```bash
sudo useradd -r -s /bin/false ddns
```
4. Copy service & timer:
```
sudo cp systemd/ddns-update.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ddns-update.timer
```
5. Check logs
```
tail -f ./logs/ddns.log
```