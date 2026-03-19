variable "project_id" {}
variable "region" { default = "us-central1" }
variable "zone" { default = "us-central1-a" }

provider "google" {
  project = "your-project-id"
  region  = "us-central1" # Stay in us-central1, us-east1, or us-west1 for free tier
}

# 1. Dual-Stack Network (IPv4 internal + IPv6 external)
resource "google_compute_network" "headscale_net" {
  name                    = "headscale-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "headscale_sub" {
  name             = "headscale-ipv6-sub"
  ip_cidr_range    = "10.0.0.0/24"
  network          = google_compute_network.headscale_net.id
  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "EXTERNAL"
}

# 2. IPv6 Firewall (Zero IPv4 external range)
resource "google_compute_firewall" "headscale_fw_v6" {
  name    = "allow-headscale-v6"
  network = google_compute_network.headscale_net.name

  allow {
    protocol = "tcp"
    ports    = ["22", "443"]
  }
  allow {
    protocol = "udp"
    ports    = ["3478"] # Critical for STUN/Tailscale
  }

  source_ranges = ["::/0"] # IPv6 only
}

# 3. The Always Free Debian VM
resource "google_compute_instance" "headscale_vm" {
  name         = "headscale-free-node"
  machine_type = "e2-micro"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30 # Max free tier disk size
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.headscale_sub.name
    stack_type = "IPV4_IPV6"
    
    # NO access_config block = No Public IPv4 = No $3.60/mo bill.
    ipv6_access_config {
      network_tier = "PREMIUM"
    }
  }

  metadata = {
    # 4. The "DHH-style" Automator
    startup-script = <<-EOT
      #!/bin/bash
      # Install Go and build your DDNS tool
      apt-get update && apt-get install -y golang-go git
      git clone https://github.com /opt/ddns
      cd /opt/ddns && go build -o /usr/local/bin/ddns-ipv6
      
      # Setup Headscale
      wget https://github.com
      dpkg -i headscale_STALE_VERSION_linux_amd64.deb
      systemctl enable --now headscale
    EOT
  }
}
