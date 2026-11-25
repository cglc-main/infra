# Secrets come from secrets.sops.json (TF_VAR_*) locally and from GitHub secrets in CI.
variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_token" {
  description = "Cloudflare API token: DNS edit and redirect rules on the three zones"
  type        = string
  sensitive   = true
}

variable "state_passphrase" {
  type      = string
  sensitive = true
}

variable "keepalived_hcloud_token" {
  description = "Hetzner API token the nodes use to move the Floating IP (keepalived)"
  type        = string
  sensitive   = true
}

variable "k3s_token" {
  description = "Shared secret of the k3s servers"
  type        = string
  sensitive   = true
}

variable "etcd_s3_access_key" {
  type      = string
  sensitive = true
}

variable "etcd_s3_secret_key" {
  type      = string
  sensitive = true
}

variable "admin_ipv4" {
  description = "The administrator's address: SSH stays open to it until the mesh replaces it (ssh_from_mesh_only)"
  type        = string
}

variable "ssh_from_mesh_only" {
  description = "true once the nodes are in the tailnet: SSH is then closed to the internet"
  type        = bool
  default     = false
}
