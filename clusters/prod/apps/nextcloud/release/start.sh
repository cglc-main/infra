#!/bin/sh
# Runs as www-data before Apache starts, on every start (the image's hook before-starting). Makes this Nextcloud
# match the repo, then saves config.php to the Storage Box. Every step is idempotent.
set -eu
occ() { php /var/www/html/occ "$@"; }

# A newer image: migrate the database (a no-op otherwise). The code is already the image's (`prepare`).
occ upgrade --no-interaction
occ maintenance:update:htaccess >/dev/null
occ db:add-missing-indices >/dev/null

# Apps: custom_apps is empty on every start, so install from the app store what the instance uses.
for app in user_oidc groupfolders; do
  occ app:getpath "$app" >/dev/null 2>&1 || occ app:install --keep-disabled "$app"
  occ app:enable "$app" >/dev/null
done

# Sign-in through the SSO (cglc-main/auth, client `nextcloud`; the provider's name `auth` is part of the back-channel
# logout URL registered there). The login page goes straight to it; the local admin uses /login?direct=1.
occ user_oidc:provider auth \
  --clientid=nextcloud --clientsecret-env=OIDC_CLIENT_SECRET \
  --discoveryuri=https://auth.bulbashenko.com/.well-known/openid-configuration \
  --scope="openid offline_access profile email groups" \
  --unique-uid=0 --mapping-uid=preferred_username --mapping-display-name=name --mapping-email=email \
  --mapping-groups=groups --group-provisioning=1 --group-whitelist-regex='/^(cloud-users|site-admins)$/' \
  --send-id-token-hint=1 >/dev/null
occ config:app:set --type=string --value=0 user_oidc allow_multiple_user_backends >/dev/null

# The site's media (docs contracts/site.md): Team folder Site with Gallery/ and Files/. The SSO group site-admins
# writes; the local user `site` (the app) only reads.
occ group:info site-admins >/dev/null 2>&1 || occ group:add site-admins >/dev/null
occ group:info site-reader >/dev/null 2>&1 || occ group:add site-reader >/dev/null
export OC_PASS="$SITE_PASSWORD"
if occ user:info site >/dev/null 2>&1; then
  occ user:resetpassword --password-from-env site >/dev/null
else
  occ user:add --password-from-env --display-name bulbashenko.com --group site-reader site >/dev/null
fi
unset OC_PASS
id=$(occ groupfolders:list --output=json | php -r '
  foreach (json_decode(stream_get_contents(STDIN), true) as $f) if ($f["mountPoint"] === "Site") { echo $f["id"]; break; }')
[ -n "$id" ] || id=$(occ groupfolders:create Site)
occ groupfolders:group "$id" site-admins read write share delete >/dev/null
occ groupfolders:group "$id" site-reader read >/dev/null
for dir in Gallery Files; do mkdir -p "/var/www/html/data/__groupfolders/$id/$dir"; done
occ groupfolders:scan "$id" >/dev/null

# config.php to the Storage Box (written beside it, then renamed: a failed copy never replaces the last good one).
cp /var/www/html/config/config.php /srv/state/.config.php.new
mv /srv/state/.config.php.new /srv/state/config.php
echo "start: done"
