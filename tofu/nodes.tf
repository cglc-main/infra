# The three servers already exist (bought, not managed here): they are read by name, so OpenTofu can never destroy or
# replace one. A node is rebuilt with `hcloud server rebuild` and the cloud-init below (docs operations/rebuild-node.md).
locals {
  domain = "bulbashenko.com"
  # name -> private address. The first is where the cluster was initialised (k3s cluster-init).
  nodes = {
    "cglc-1" = "10.0.1.1"
    "cglc-2" = "10.0.1.2"
    "cglc-3" = "10.0.1.3"
  }
  first_node = "cglc-1"
  # Headscale hands out addresses in order and the nodes join the tailnet first (apps/headscale/config.yaml).
  tailnet_ips = ["100.64.0.1", "100.64.0.2", "100.64.0.3"]
}

data "hcloud_server" "node" {
  for_each = local.nodes
  name     = each.key
}

data "hcloud_floating_ip" "main" {
  name = "ingress"
}

resource "hcloud_server_network" "node" {
  for_each   = local.nodes
  server_id  = data.hcloud_server.node[each.key].id
  network_id = hcloud_network.private.id
  ip         = each.value
}

# Outgoing mail leaves from the node Stalwart runs on: each node's address must resolve back to a name that resolves
# to it (forward-confirmed reverse DNS). The Floating IP is mail's address for incoming mail.
resource "hcloud_rdns" "node" {
  for_each   = local.nodes
  server_id  = data.hcloud_server.node[each.key].id
  ip_address = data.hcloud_server.node[each.key].ipv4_address
  dns_ptr    = "${each.key}.${local.domain}"
}

resource "hcloud_rdns" "floating" {
  floating_ip_id = data.hcloud_floating_ip.main.id
  ip_address     = data.hcloud_floating_ip.main.ip_address
  dns_ptr        = "mail.${local.domain}"
}

# What each node boots with after a rebuild (hosts/cloud-init.yaml).
output "cloud_init" {
  sensitive = true
  value = {
    for name, ip in local.nodes : name => templatefile("${path.module}/../hosts/cloud-init.yaml", {
      name           = name
      private_ip     = ip
      first          = name == local.first_node
      first_ip       = local.nodes[local.first_node]
      peers          = [for n, p in local.nodes : p if n != name]
      priority       = 100 - index(keys(local.nodes), name) * 10
      floating_ip    = data.hcloud_floating_ip.main.ip_address
      floating_id    = data.hcloud_floating_ip.main.id
      server_id      = data.hcloud_server.node[name].id
      tailnet_ip     = local.tailnet_ips[index(keys(local.nodes), name)]
      hcloud_token   = var.keepalived_hcloud_token
      k3s_token      = var.k3s_token
      etcd_s3_key    = var.etcd_s3_access_key
      etcd_s3_secret = var.etcd_s3_secret_key
      # renovate: datasource=github-releases depName=k3s-io/k3s
      k3s_version = "v1.37.2+k3s1"
    })
  }
}
