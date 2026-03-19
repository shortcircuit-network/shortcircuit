terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# Availability Domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Ubuntu 22.04 ARM64 image (newest first)
data "oci_core_images" "ubuntu_arm64" {
  compartment_id           = var.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# VCN
resource "oci_core_vcn" "headscale_vcn" {
  compartment_id = var.compartment_id
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "${var.vm_name}-vcn"
  is_ipv6enabled = true
}

# Internet Gateway
resource "oci_core_internet_gateway" "headscale_igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.headscale_vcn.id
  display_name   = "${var.vm_name}-igw"
  enabled        = true
}

# Route Table
resource "oci_core_route_table" "headscale_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.headscale_vcn.id
  display_name   = "${var.vm_name}-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.headscale_igw.id
  }
}

# Security List
resource "oci_core_security_list" "headscale_sl" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.headscale_vcn.id
  display_name   = "${var.vm_name}-sl"

  # Allow all outbound traffic
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # SSH
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  # Headscale control plane (HTTPS)
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 443
      max = 443
    }
  }

  # STUN (Tailscale coordination)
  ingress_security_rules {
    protocol  = "17" # UDP
    source    = "0.0.0.0/0"
    stateless = false
    udp_options {
      min = 3478
      max = 3478
    }
  }
}

# Public Subnet
resource "oci_core_subnet" "headscale_subnet" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.headscale_vcn.id
  cidr_block        = "10.0.0.0/24"
  display_name      = "${var.vm_name}-subnet"
  route_table_id    = oci_core_route_table.headscale_rt.id
  security_list_ids = [oci_core_security_list.headscale_sl.id]
  ipv6cidr_block    = cidrsubnet(oci_core_vcn.headscale_vcn.ipv6cidr_blocks[0], 8, 0)
}

# Headscale Compute Instance (Ampere A1 — ARM64)
resource "oci_core_instance" "headscale" {
  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = var.vm_name
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_gb
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu_arm64.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.headscale_subnet.id
    assign_public_ip = true
    display_name     = "${var.vm_name}-vnic"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
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
    }))
  }
}
