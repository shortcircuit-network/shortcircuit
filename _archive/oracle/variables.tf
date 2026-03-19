# OCI Authentication
variable "tenancy_ocid" {
  description = "OCID of the OCI tenancy"
}

variable "user_ocid" {
  description = "OCID of the OCI user"
}

variable "fingerprint" {
  description = "Fingerprint of the OCI API key"
}

variable "private_key_path" {
  description = "Path to the OCI API private key file (.pem)"
}

variable "region" {
  description = "OCI region (e.g. us-phoenix-1, us-ashburn-1, ap-tokyo-1)"
  default     = "us-phoenix-1"
}

variable "compartment_id" {
  description = "OCID of the compartment to deploy resources in (use tenancy_ocid for root)"
}

# Instance
variable "ssh_public_key" {
  description = "SSH public key content for instance access"
}

variable "vm_name" {
  description = "Display name for the Headscale instance"
  default     = "headscale-node"
}

variable "ocpus" {
  description = "Number of Ampere A1 OCPUs (free tier: up to 4 total across all A1 instances)"
  default     = 1
}

variable "memory_gb" {
  description = "Memory in GB (free tier: up to 24 GB total across all A1 instances)"
  default     = 6
}

# DDNS (Cloudflare)
variable "cf_token" {
  description = "Cloudflare API token with DNS edit permissions"
  sensitive   = true
}

variable "cf_email" {
  description = "Cloudflare account email"
}

variable "ddns_records_json" {
  description = "Single-line JSON array of A records to update. Example: [{\"name\":\"headscale.example.com\",\"zone\":\"ZONE_ID\",\"record\":\"RECORD_ID\"}]"
}

# Litestream / R2
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

# Headscale
variable "headscale_server_url" {
  description = "Public HTTPS URL for the Headscale control plane (e.g. https://headscale.example.com)"
}

variable "headscale_version" {
  description = "Headscale release version to install (arm64 .deb)"
  default     = "0.25.1"
}
