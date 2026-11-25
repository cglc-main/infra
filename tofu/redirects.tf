# bulbashenko.dev and cglc.eu answer at Cloudflare's edge with a permanent redirect to bulbashenko.com (path and query
# kept). The records are proxied placeholders: the request never reaches the cluster.
locals {
  redirect_zones = toset(["bulbashenko.dev", "cglc.eu"])
}

data "cloudflare_zone" "redirect" {
  for_each = local.redirect_zones
  filter   = { name = each.key }
}

resource "cloudflare_dns_record" "redirect" {
  for_each = { for pair in setproduct(local.redirect_zones, ["@", "*"]) : "${pair[0]}/${pair[1]}" => pair }
  zone_id  = data.cloudflare_zone.redirect[each.value[0]].zone_id
  name     = each.value[1] == "@" ? each.value[0] : "*.${each.value[0]}"
  type     = "A"
  content  = "192.0.2.1"
  ttl      = 1
  proxied  = true
}

resource "cloudflare_ruleset" "redirect" {
  for_each = local.redirect_zones
  zone_id  = data.cloudflare_zone.redirect[each.key].zone_id
  name     = "redirect to bulbashenko.com"
  kind     = "zone"
  phase    = "http_request_dynamic_redirect"
  rules = [{
    description = "everything to bulbashenko.com"
    expression  = "true"
    action      = "redirect"
    action_parameters = {
      from_value = {
        status_code           = 301
        preserve_query_string = true
        target_url = {
          expression = "concat(\"https://bulbashenko.com\", http.request.uri.path)"
        }
      }
    }
  }]
}
