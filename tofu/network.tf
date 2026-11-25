resource "hcloud_network" "private" {
  name     = "cluster"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "nodes" {
  network_id   = hcloud_network.private.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

# Three VMs on three different physical hosts. A server joins it only while stopped, which the rebuild does
# (docs operations/rebuild-node.md): this resource does not attach servers itself.
resource "hcloud_placement_group" "nodes" {
  name = "cluster"
  type = "spread"
}

# Open to the internet: web, mail, the tailnet's direct connections. The private network is not filtered.
resource "hcloud_firewall" "nodes" {
  name = "cluster"

  dynamic "rule" {
    for_each = {
      http        = "80"
      https       = "443"
      smtp        = "25"
      submissions = "465"
      submission  = "587"
      imaps       = "993"
    }
    content {
      description = rule.key
      direction   = "in"
      protocol    = "tcp"
      port        = rule.value
      source_ips  = ["0.0.0.0/0", "::/0"]
    }
  }

  rule {
    description = "tailscale"
    direction   = "in"
    protocol    = "udp"
    port        = "41641"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    description = "icmp"
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  dynamic "rule" {
    for_each = var.ssh_from_mesh_only ? [] : [1]
    content {
      description = "ssh from the administrator (until the mesh replaces it)"
      direction   = "in"
      protocol    = "tcp"
      port        = "22"
      source_ips  = ["${var.admin_ipv4}/32"]
    }
  }
}

resource "hcloud_firewall_attachment" "nodes" {
  firewall_id = hcloud_firewall.nodes.id
  server_ids  = [for s in data.hcloud_server.node : s.id]
}
