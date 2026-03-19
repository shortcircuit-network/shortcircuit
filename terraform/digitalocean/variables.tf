variable "do_token" {
  description = "DigitalOcean API token — minimum scopes: Droplets (create/read/delete), SSH Keys (create/read/delete), Firewalls (create/read/update/delete)"
  sensitive   = true
}

variable "do_region" {
  description = "DigitalOcean region slug (e.g. sfo3, nyc3, ams3, sgp1, fra1)"
  default     = "sfo3"
}

variable "droplet_name" {
  description = "Name for the lighthouse droplet"
  default     = "shortcircuit-lighthouse"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key to install on the droplet (e.g. ~/.ssh/id_ed25519.pub)"
}

variable "pvt_key" {
  description = "Path to SSH private key for droplet access (e.g. ~/.ssh/id_ed25519)"
}

# Headscale
variable "headscale_domain" {
  description = "Headscale control plane FQDN (e.g. mesh.shortcircuit.network)"
}

variable "headscale_server_url" {
  description = "Public HTTPS URL for the Headscale control plane (e.g. https://mesh.shortcircuit.network)"
}

variable "headscale_version" {
  description = "Headscale release version to install"
  default     = "0.25.1"
}

variable "litestream_version" {
  description = "Litestream release version to install"
  default     = "0.3.13"
}

# ocserv / OpenConnect VPN
variable "ocserv_domain" {
  description = "OpenConnect VPN FQDN (e.g. vpn.shortcircuit.network)"
}

# TLS / Certbot
variable "letsencrypt_email" {
  description = "Email for Let's Encrypt certificate registration"
}

# Cloudflare (DDNS + certbot DNS challenge)
variable "cf_token" {
  description = "Cloudflare API token with DNS edit permissions"
  sensitive   = true
}

variable "cf_email" {
  description = "Cloudflare account email"
}

variable "ddns_records_json" {
  description = "Single-line JSON array of A records to update. Example: [{\"name\":\"mesh.shortcircuit.network\",\"zone\":\"ZONE_ID\",\"record\":\"RECORD_ID\"},{\"name\":\"vpn.shortcircuit.network\",\"zone\":\"ZONE_ID\",\"record\":\"RECORD_ID\"}]"
}

# Litestream / Cloudflare R2
variable "r2_access_key_id" {
  description = "Cloudflare R2 access key ID for Litestream SQLite replication"
  sensitive   = true
}

variable "r2_secret_access_key" {
  description = "Cloudflare R2 secret access key for Litestream SQLite replication"
  sensitive   = true
}

variable "r2_endpoint" {
  description = "Cloudflare R2 S3-compatible endpoint (https://ACCOUNT_ID.r2.cloudflarestorage.com)"
}

variable "r2_bucket" {
  description = "R2 bucket name for Headscale SQLite replication"
  default     = "shortcircuit-headscale"
}
