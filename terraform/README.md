# Shortcircuit — Self-Host Your Own Node

Deploy a Shortcircuit lighthouse on DigitalOcean in ~5 minutes.

**What you get:**
- [Headscale](https://headscale.net) mesh control plane (`mesh.YOUR_DOMAIN`)
- [ocserv](https://ocserv.gitlab.io/www-ocserv/) OpenConnect VPN (`vpn.YOUR_DOMAIN`) — iOS/Android/macOS native via GlobalProtect-compatible clients
- HAProxy SNI routing — both services share port 443, no port conflicts
- Let's Encrypt TLS via Cloudflare DNS challenge
- SQLite replicated to Cloudflare R2 via [Litestream](https://litestream.io) — survive droplet loss with zero data loss
- Cloudflare DDNS — A records kept current if the IP changes

---

## Prerequisites

| Requirement | Notes |
|---|---|
| [DigitalOcean account](https://digitalocean.com) | $6/mo for s-1vcpu-1gb |
| [Cloudflare account](https://cloudflare.com) | Free plan. Your domain's DNS must be on Cloudflare. |
| [Cloudflare R2](https://dash.cloudflare.com/r2) | Free tier (10GB). Create a bucket named `shortcircuit-headscale` (or your own name). |
| [OpenTofu](https://opentofu.org/docs/intro/install/) or [Terraform](https://developer.hashicorp.com/terraform/install) | Either works |
| SSH key pair | For droplet access |

---

## Setup

### 1. Create Cloudflare A records

In Cloudflare DNS, add two A records pointing to any IP (DDNS will update them):

```
mesh.YOUR_DOMAIN   A   1.2.3.4   (proxied: OFF)
vpn.YOUR_DOMAIN    A   1.2.3.4   (proxied: OFF)
```

Then get the Zone ID and Record IDs:

```bash
# Zone ID — visible in Cloudflare dashboard sidebar, or:
curl -s -H "Authorization: Bearer YOUR_CF_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones?name=YOUR_DOMAIN" \
  | jq -r '.result[0].id'

# Record IDs
CF_ZONE_ID="<zone-id-from-above>"
curl -s -H "Authorization: Bearer YOUR_CF_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=A" \
  | jq -r '.result[] | "\(.name)  \(.id)"'
```

### 2. Create Cloudflare API token

Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens) → Create Token → use the **"Edit zone DNS"** template. Scope it to your domain.

### 3. Create Cloudflare R2 credentials

In [Cloudflare R2 settings](https://dash.cloudflare.com/r2/api-tokens), create an API token with **Object Read & Write** on your bucket. Note the Access Key ID, Secret Access Key, and endpoint URL (`https://ACCOUNT_ID.r2.cloudflarestorage.com`).

### 4. Generate an SSH key for the droplet

```bash
ssh-keygen -t ed25519 -f ~/.ssh/shortcircuit_ed25519 -C "shortcircuit"
```

### 5. Create a DigitalOcean API token

Go to [DO API Tokens](https://cloud.digitalocean.com/account/api/tokens) → **Generate New Token** → enable **"Restrict token scopes"**.

Grant only these scopes — nothing else:

| Resource | Permissions |
|---|---|
| Droplets | Read, Create, Delete |
| SSH Keys | Read, Create, Delete |
| Firewalls | Read, Create, Update, Delete |

Do **not** grant console access, Volumes, Domains, Spaces, Kubernetes, or account-level scopes. A leaked token with these scopes can only manage compute resources — it cannot access your account, billing, or other services.

Set **no expiry** — Terraform needs this token to work on-demand indefinitely for reprovisioning.

### 6. Configure Terraform

```bash
cd terraform/digitalocean
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in all values
```

### 6. Deploy

```bash
tofu init    # or: terraform init
tofu plan
tofu apply
```

Outputs the droplet IP, Headscale URL, and VPN URL when done.

---

## After Deploy

Bootstrap logs are at `/var/log/bootstrap.log` on the droplet.

**Check services:**
```bash
ssh admin@<DROPLET_IP> 'systemctl status headscale haproxy ocserv litestream-replicate'
```

**Add a Headscale user and get an auth key:**
```bash
ssh admin@<DROPLET_IP>
sudo headscale users create myuser
sudo headscale preauthkeys create --user myuser --expiration 24h
```

**Connect a device:**
```bash
# Linux/macOS
tailscale up --login-server https://mesh.YOUR_DOMAIN --auth-key <key>

# iOS/Android: install Tailscale app → Settings → Account → Use custom coordination server
```

**Add OpenConnect VPN user:**
```bash
ssh admin@<DROPLET_IP>
sudo ocpasswd -c /etc/ocserv/users.passwd myuser
# Connect via GlobalProtect / Cisco AnyConnect / OpenConnect client to vpn.YOUR_DOMAIN
```

---

## Backup & Recovery

Headscale's SQLite database replicates continuously to R2 via Litestream. On a new droplet, `terraform apply` bootstraps and Litestream restores the database automatically before Headscale starts.

**Manual restore:**
```bash
sudo litestream restore -config /etc/litestream.yml /var/lib/headscale/db.sqlite
```

---

## Sizing

| Droplet | Cost | Suitable for |
|---|---|---|
| s-1vcpu-1gb | $6/mo | Personal use, <20 devices, light VPN |
| s-1vcpu-2gb | $12/mo | Small team, moderate VPN throughput |

---

## Architecture

```
Client (port 443 TCP/UDP)
    │
    ├── TCP 443 → HAProxy (SNI)
    │       ├── mesh.YOUR_DOMAIN → Headscale (127.0.0.1:8443)
    │       └── vpn.YOUR_DOMAIN  → ocserv TCP (127.0.0.1:4443)
    │
    └── UDP 443 → ocserv DTLS (direct, no HAProxy needed)
```
