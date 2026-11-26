# bulbashenko.com. Everything public points at the Floating IP. Stalwart manages its own mail records through the
# Cloudflare API (DKIM with key rotation, MTA-STS, TLS-RPT, SRV, autoconfig: apps/stalwart/plan.ndjson), so they are
# not here; the ones that depend on the network are.
data "cloudflare_zone" "main" {
  filter = { name = local.domain }
}

locals {
  zone_id = data.cloudflare_zone.main.zone_id
  fip     = data.hcloud_floating_ip.main.ip_address
}

resource "cloudflare_dns_record" "apex" {
  zone_id = local.zone_id
  name    = local.domain
  type    = "A"
  content = local.fip
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "wildcard" {
  zone_id = local.zone_id
  name    = "*.${local.domain}"
  type    = "A"
  content = local.fip
  ttl     = 300
  proxied = false
}

# The admin UIs on *.int resolve to the nodes' tailnet addresses: reachable only from the mesh, and a new UI needs no
# DNS change. Traefik still lets only tailnet sources through (component int-route, middleware mesh-only).
resource "cloudflare_dns_record" "int" {
  for_each = toset(local.tailnet_ips)
  zone_id  = local.zone_id
  name     = "*.int.${local.domain}"
  type     = "A"
  content  = each.value
  ttl      = 300
  proxied  = false
}

# Each node by name: the target of its reverse DNS (nodes.tf).
resource "cloudflare_dns_record" "node" {
  for_each = local.nodes
  zone_id  = local.zone_id
  name     = "${each.key}.${local.domain}"
  type     = "A"
  content  = data.hcloud_server.node[each.key].ipv4_address
  ttl      = 300
  proxied  = false
}

resource "cloudflare_dns_record" "mx" {
  zone_id  = local.zone_id
  name     = local.domain
  type     = "MX"
  content  = "mail.${local.domain}"
  priority = 10
  ttl      = 300
}

# Mail leaves from any node's address.
resource "cloudflare_dns_record" "spf" {
  zone_id = local.zone_id
  name    = local.domain
  type    = "TXT"
  content = "\"v=spf1 ${join(" ", [for s in data.hcloud_server.node : "ip4:${s.ipv4_address}"])} ip4:${local.fip} -all\""
  ttl     = 300
}

resource "cloudflare_dns_record" "dmarc" {
  zone_id = local.zone_id
  name    = "_dmarc.${local.domain}"
  type    = "TXT"
  content = "\"v=DMARC1; p=quarantine; adkim=s; aspf=s; rua=mailto:postmaster@${local.domain}\""
  ttl     = 300
}

# Only Let's Encrypt may issue certificates for the domain.
resource "cloudflare_dns_record" "caa" {
  for_each = { issue = "letsencrypt.org", issuewild = "letsencrypt.org", iodef = "mailto:postmaster@${local.domain}" }
  zone_id  = local.zone_id
  name     = local.domain
  type     = "CAA"
  data     = { flags = 0, tag = each.key, value = each.value }
  ttl      = 300
}
