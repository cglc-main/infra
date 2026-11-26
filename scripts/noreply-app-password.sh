#!/usr/bin/env bash
# Creates an app password for noreply@bulbashenko.com in Stalwart and writes it into the SOPS secrets of its users
# (auth: SMTP_CONNECTION_URI, nextcloud: smtp-password). The secret is never printed. Also for rotation: delete the
# old app password afterwards (Stalwart admin UI, account noreply). Docs: operations/secrets.md.
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/cglc.yaml}"
cd "$(dirname "$0")/.."
[[ -f clusters/prod/apps/auth/secret.sops.yaml ]] || { echo "run from the infra repository" >&2; exit 1; }

get() { kubectl -n stalwart get secret stalwart -o jsonpath="{.data.$1}" | base64 -d; }
export STALWART_USER STALWART_PASSWORD
STALWART_USER=$(get RECOVERY_ADMIN_USER)
STALWART_PASSWORD=$(get RECOVERY_ADMIN_PASSWORD)

# Through a port-forward: the server sees loopback, which auto-ban never blocks.
kubectl -n stalwart port-forward deploy/stalwart 18080:8080 >/dev/null &
pf=$!
trap 'kill $pf 2>/dev/null' EXIT
until curl -sf -o /dev/null http://127.0.0.1:18080/healthz/ready; do sleep 1; done

id=$(docker run --rm --network host -e STALWART_URL=http://127.0.0.1:18080 -e STALWART_USER -e STALWART_PASSWORD \
  ghcr.io/stalwartlabs/cli:2.0.0 query Account --where name=noreply | awk 'NR>1 && $1!="" {print $1; exit}')
[[ -n "$id" ]] || { echo "account noreply not found" >&2; exit 1; }

export APP_PASSWORD
APP_PASSWORD=$(curl -sf -u "$STALWART_USER:$STALWART_PASSWORD" -H 'Content-Type: application/json' \
  http://127.0.0.1:18080/jmap/ -d "$(jq -n -c --arg a "$id" '{
    using: ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"],
    methodCalls: [["x:AppPassword/set", {accountId: $a, create: {p1: {
      description: "SMTP for Ory and Nextcloud (SOPS: auth SMTP_CONNECTION_URI, nextcloud smtp-password)",
      permissions: {"@type": "Inherit"}, allowedIps: {}}}}, "0"]]}')" \
  | jq -r '.methodResponses[0][1].created.p1.secret // empty')
[[ -n "$APP_PASSWORD" ]] || { echo "app password not created" >&2; exit 1; }

editor=$(mktemp)
trap 'kill $pf 2>/dev/null; rm -f "$editor"' EXIT
cat > "$editor" <<'EOF'
import json, os, re, sys, urllib.parse
p = sys.argv[1]; s = open(p).read(); pw = os.environ["APP_PASSWORD"]
s = re.sub(r"(SMTP_CONNECTION_URI: smtps://[^:]+:)[^@]*(@)", lambda m: m.group(1) + urllib.parse.quote(pw, safe="") + m.group(2), s)
s = re.sub(r"(\n\s+smtp-password: ).*", lambda m: m.group(1) + json.dumps(pw), s)
open(p, "w").write(s)
EOF
for f in clusters/prod/apps/auth/secret.sops.yaml clusters/prod/apps/nextcloud/namespace/secret.sops.yaml; do
  EDITOR="python3 -I $editor" sops edit "$f"
done
echo "app password created for noreply ($id) and written to the auth and nextcloud secrets"
git status -s clusters/prod/apps/auth clusters/prod/apps/nextcloud
