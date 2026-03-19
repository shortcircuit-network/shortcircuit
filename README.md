# shortcircuit — Headscale + DDNS Infrastructure

Self-hosted Tailscale control plane (Headscale) with Cloudflare DDNS, provisioned via Terraform.
Supports two deployment targets: Oracle Cloud (primary, free Ampere A1 ARM64) and GCP (legacy, free e2-micro IPv6).

## Deployments

| Target | Path | Instance | IP | DDNS |
|--------|------|----------|----|------|
| **Oracle Cloud** (primary) | `terraform/oracle/` | Ampere A1 Flex (1 OCPU / 6 GB) | Public IPv4 (free) | A record |
| GCP (legacy) | `terraform/gcp/` | e2-micro | IPv6 only | AAAA record |

---

## Oracle Cloud (Primary)

Ampere A1 Flex — ARM64, 4 OCPU / 24 GB available in the free tier. Uses 1 OCPU / 6 GB by default.

**What Terraform provisions:**
- VCN (10.0.0.0/16 + Oracle-assigned IPv6 /56), Internet Gateway, Route Table, Security List
- Public subnet with IPv4 + IPv6
- Ubuntu 22.04 ARM64 instance with cloud-init bootstrap
- Firewall: SSH (22), Headscale (443 TCP), STUN (3478 UDP)

**What cloud-init does on first boot:**
- Builds `ddns-ipv4` binary from source (native ARM64, ~seconds)
- Installs Headscale (arm64 .deb)
- Installs Litestream for SQLite → R2 replication
- Wires up systemd: `litestream-restore` → `headscale` → `litestream-replicate` + `ddns-update.timer`

### Litestream / R2 Setup

Headscale state survives instance destroy/recreate via Cloudflare R2:

1. Create an R2 bucket named `shortcircuit-headscale` (or set `r2_bucket` var)
2. Create an R2 API token with **Object Read & Write** on that bucket
3. Note your `r2_endpoint`: `https://ACCOUNT_ID.r2.cloudflarestorage.com`

On first boot, Litestream restores the DB from R2 (no-op if empty). On subsequent boots after destroy, Headscale picks up from where it left off — node registrations preserved.

### Quick Start

```bash
cd terraform/oracle

# Create terraform.tfvars from .env.example (Oracle section)
cp ../../.env.example .env.example   # reference only

cat > terraform.tfvars <<EOF
tenancy_ocid         = "ocid1.tenancy.oc1.."
user_ocid            = "ocid1.user.oc1.."
fingerprint          = "aa:bb:..."
private_key_path     = "~/.oci/oci_api_key.pem"
region               = "us-phoenix-1"
compartment_id       = "ocid1.compartment.oc1.."
ssh_public_key       = "ssh-ed25519 AAAA..."
cf_token             = "your_token"
cf_email             = "you@example.com"
ddns_records_json    = "[{\"name\":\"headscale.example.com\",\"zone\":\"ZONE_ID\",\"record\":\"RECORD_ID\"}]"
r2_access_key_id     = "your_r2_key_id"
r2_secret_access_key = "your_r2_secret"
r2_endpoint          = "https://ACCOUNT_ID.r2.cloudflarestorage.com"
headscale_server_url = "https://headscale.example.com"
EOF

terraform init
terraform plan -var-file=terraform.tfvars   # review
terraform apply -var-file=terraform.tfvars
```

### Verify (after ~3 min for cloud-init)

```bash
ssh ubuntu@$(terraform output -raw instance_public_ip)

sudo systemctl status headscale litestream-replicate ddns-update.timer
sudo journalctl -u litestream-restore    # confirm R2 restore ran
sudo journalctl -u headscale             # confirm started
sudo headscale nodes list
tail -f /var/log/ddns/ddns.log           # confirm A record updated
cat /var/log/bootstrap.log               # full cloud-init output
```

R2 verification: objects appear under `headscale/db` in your bucket within ~30 seconds.

---

## GCP (Legacy)

IPv6-only e2-micro — stays in free tier by omitting public IPv4.

```bash
cd terraform/gcp
terraform init
terraform apply -var "project_id=YOUR_GCP_PROJECT"
```

Check logs:
```bash
tail -f /var/log/ddns/ddns.log
```

**Notes:**
- IPv6-only ensures free-tier eligibility (no $3.60/mo IPv4 charge)
- 2 GB swap helps Go DDNS + Headscale on 1 GB RAM e2-micro
- DDNS updater: `ddns-ipv6` binary (AAAA records)

---

## DDNS Binaries

| Binary | Path | Record | Provider |
|--------|------|--------|----------|
| `ddns-ipv4` | `cmd/ddns-ipv4/` | A | `api4.ipify.org`, `4.ifconfig.me` |
| `ddns-ipv6` | `cmd/ddns-ipv6/` | AAAA | `6.ifconfig.me`, `api64.ipify.org` |

Both binaries: retry with exponential backoff, state file caching (skip update if IP unchanged), multiple records via `DDNS_RECORDS_JSON`.

Build manually:
```bash
go build -o ddns-ipv4 ./cmd/ddns-ipv4/
go build -o ddns-ipv6 ./cmd/ddns-ipv6/
```

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `CF_TOKEN` | Yes | Cloudflare API token (DNS edit) |
| `CF_EMAIL` | Yes | Cloudflare account email |
| `DDNS_RECORDS_JSON` | Yes | Single-line JSON array of records |
| `LOG_PATH` | No | Log file path (stdout if unset) |
| `STATE_PATH` | No | State file for IP caching |
| `TTL` | No | DNS TTL in seconds (default: 120) |

See `.env.example` for all Oracle Terraform variables.
