# ShortCircuit OCI Bootstrap Guide

## Prerequisites
1. **Oracle Cloud Account**: Sign up at [cloud.oracle.com](https://www.oracle.com/cloud/free/).
2. **Region**: Select **Tokyo (ap-osaka-1)** as your home region during signup.
3. **API Key**: 
   - Go to **User Settings** -> **API Keys**.
   - Click **Add API Key**.
   - Download the Private Key and save it to '~/.oci/oci_api_key.pem'.
   - Copy the 'tenancy_ocid', 'user_ocid', 'fingerprint', and 'region' from the configuration snippet displayed after adding the key.

## Bootstrap
1. Copy the example vars:
   'cp terraform.tfvars.example terraform.tfvars'
2. Populate 'terraform.tfvars' with your OCI and Cloudflare credentials.
3. Initialize and Apply:
   'terraform init'
   'terraform apply'

## Post-Provisioning
The script will automatically:
- Install **Headscale** (Tailscale-compatible control plane).
- Configure **Litestream** to replicate the SQLite DB to Cloudflare R2.
- Open ports for **Nebula** (UDP 4242) and **MASQUE/QUIC** (UDP 443).
- Setup **DDNS** to update your Cloudflare records with the new VM IP.

## Networking Note
The Nebula mesh will be configured with **MTU 1200** to ensure 0-RTT traffic traverses the trans-Pacific Tailscale/Flannel layers without fragmentation.
