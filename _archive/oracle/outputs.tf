output "instance_public_ip" {
  description = "Public IPv4 address of the Headscale instance (use for SSH and DNS verification)"
  value       = oci_core_instance.headscale.public_ip
}

output "instance_id" {
  description = "OCID of the Headscale instance"
  value       = oci_core_instance.headscale.id
}

output "headscale_url" {
  description = "Headscale server URL (value of headscale_server_url variable)"
  value       = var.headscale_server_url
}
