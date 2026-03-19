terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_ssh_key" "shortcircuit" {
  name       = "shortcircuit-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "digitalocean_droplet" "lighthouse" {
  image    = "ubuntu-24-04-x64"
  name     = var.droplet_name
  region   = var.do_region
  # s-1vcpu-1gb ($6/mo) — Headscale + HAProxy idle well within 1GB. ocserv not used often.
  # Upgrade to s-1vcpu-2gb if connection count grows or ocserv OOMs under load.
  size     = "s-1vcpu-1gb"
  ssh_keys = [digitalocean_ssh_key.shortcircuit.fingerprint]
  ipv6     = true
  tags     = ["shortcircuit", "lighthouse"]

  user_data = base64encode(templatefile("${path.module}/scripts/bootstrap.sh", {
    cf_token             = var.cf_token
    cf_email             = var.cf_email
    ddns_records_json    = var.ddns_records_json
    r2_access_key_id     = var.r2_access_key_id
    r2_secret_access_key = var.r2_secret_access_key
    r2_endpoint          = var.r2_endpoint
    r2_bucket            = var.r2_bucket
    headscale_server_url = var.headscale_server_url
    headscale_version    = var.headscale_version
    litestream_version   = var.litestream_version
    headscale_domain     = var.headscale_domain
    ocserv_domain        = var.ocserv_domain
    letsencrypt_email    = var.letsencrypt_email
    ssh_public_key       = file(pathexpand(var.ssh_public_key_path))
  }))

  connection {
    host        = self.ipv4_address
    user        = "admin"
    type        = "ssh"
    private_key = file(var.pvt_key)
    timeout     = "2m"
  }
}

resource "digitalocean_firewall" "shortcircuit_fw" {
  name = "shortcircuit-firewall"

  droplet_ids = [digitalocean_droplet.lighthouse.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "443"   # ocserv DTLS direct (not through HAProxy)
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "3478"  # STUN (Headscale coordination)
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

output "lighthouse_ip" {
  value       = digitalocean_droplet.lighthouse.ipv4_address
  description = "Public IPv4 of the Shortcircuit lighthouse"
}

output "headscale_url" {
  value       = "https://${var.headscale_domain}"
  description = "Headscale control plane URL"
}

output "vpn_url" {
  value       = "https://${var.ocserv_domain}"
  description = "OpenConnect VPN URL"
}
