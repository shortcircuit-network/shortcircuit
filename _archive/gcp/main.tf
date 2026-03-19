provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "headscale_net" {
  name                    = "headscale-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "headscale_sub" {
  name             = "headscale-ipv6-sub"
  ip_cidr_range    = "10.101.0.0/24"
  network          = google_compute_network.headscale_net.id
  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "EXTERNAL"
}

resource "google_compute_firewall" "headscale_fw_v6" {
  name    = "allow-headscale-v6"
  network = google_compute_network.headscale_net.name

  allow {
    protocol = "tcp"
    ports    = ["22","443"]
  }
  allow {
    protocol = "udp"
    ports    = ["3478"]
  }

  source_ranges = ["::/0"]
}

resource "google_compute_instance" "headscale_vm" {
  name         = var.vm_name
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30
    }
  }

  network_interface {
    subnetwork         = google_compute_subnetwork.headscale_sub.name
    stack_type         = "IPV4_IPV6"
    ipv6_access_config {
      network_tier = "PREMIUM"
    }
  }

  metadata_startup_script = file("${path.module}/scripts/bootstrap.sh")
}

