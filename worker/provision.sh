#!/usr/bin/env bash
# Provision the Rooted Abroad lead store. Idempotent: safe to re-run.
#
# Requires: a Cloudflare account reachable by wrangler, either via
#   `wrangler login`, or CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID.
#
# Usage: ./provision.sh [location-hint]     # default: weur (EU West)
#   EU residency is confirmed (MOD-6). D1 location is fixed at creation time,
#   so only override this argument on a deliberate, signed-off decision.
set -euo pipefail

cd "$(dirname "$0")"

DB_NAME="rooted-abroad-leads"
LOCATION="${1:-weur}"
SITE_HTML="../site/public/index.html"
BUILD_HTML="../build/index.html"

if [[ "$LOCATION" != weur && "$LOCATION" != eeur && "${ALLOW_NON_EU:-}" != 1 ]]; then
  echo "refusing to create the lead DB outside the EU ($LOCATION)." >&2
  echo "EU residency is a signed-off requirement; set ALLOW_NON_EU=1 to override." >&2
  exit 1
fi

db_id() {
  wrangler d1 info "$DB_NAME" --json 2>/dev/null | python3 -c \
    'import json,sys; print(json.load(sys.stdin).get("uuid",""))' 2>/dev/null || true
}

ID="$(db_id)"
if [[ -z "$ID" ]]; then
  echo "==> Creating D1 database $DB_NAME in $LOCATION"
  wrangler d1 create "$DB_NAME" --location "$LOCATION"
  ID="$(db_id)"
  [[ -n "$ID" ]] || { echo "could not resolve database id after create" >&2; exit 1; }
else
  echo "==> D1 database $DB_NAME already exists ($ID)"
fi

echo "==> Pinning database_id in wrangler.toml"
python3 - "$ID" <<'PY'
import re, sys
id = sys.argv[1]
p = 'wrangler.toml'
s = open(p).read()
s = re.sub(r'^database_id = ".*"$', f'database_id = "{id}"', s, flags=re.M)
open(p, 'w').write(s)
PY

echo "==> Applying schema (CREATE TABLE IF NOT EXISTS)"
wrangler d1 execute "$DB_NAME" --remote --file=schema.sql --yes

echo "==> Deploying Worker"
wrangler deploy 2>&1 | tee /tmp/wrangler-deploy.log

URL="$(grep -oE 'https://[a-z0-9.-]+\.workers\.dev' /tmp/wrangler-deploy.log | head -1)"
[[ -n "$URL" ]] || { echo "could not parse workers.dev URL from deploy output" >&2; exit 1; }

echo "==> Pointing the form at $URL/leads"
for f in "$SITE_HTML" "$BUILD_HTML"; do
  [[ -f "$f" ]] && python3 - "$f" "$URL" <<'PY'
import sys
f, url = sys.argv[1], sys.argv[2]
s = open(f).read()
old = "var LEAD_ENDPOINT = 'https://rooted-abroad-leads.__CF_SUBDOMAIN__.workers.dev/leads';"
new = f"var LEAD_ENDPOINT = '{url}/leads';"
if old in s:
    open(f, 'w').write(s.replace(old, new))
    print(f"  patched {f}")
else:
    print(f"  {f}: endpoint already set or markup changed — check manually")
PY
done

cat <<EOF

Provisioned. Remaining manual steps (no API for these):
  1. Commit + push ../build and let GitHub Pages redeploy.
  2. Smoke-test a real submission, then:
       wrangler d1 execute $DB_NAME --remote --command "SELECT * FROM leads ORDER BY id DESC LIMIT 5"
  3. Analytics: the page already counts traffic with no account (./analytics.sh
     reads it). To move to a real provider, set exactly one key in the
     ANALYTICS object in index.html and redeploy:
       - posthogKey       (EU cloud, free tier, gives traffic + conversion)
       - plausibleDomain
       - cfBeaconToken    (Cloudflare dashboard -> Web Analytics -> add site)
     Whichever is set wins; the account-free counters switch themselves off.

Rate limiting is already in the Worker (20 POST/min per IP, LEADS_LIMIT binding).
The lead DB is created in the EU ($LOCATION) — fixed at creation, per MOD-6.
EOF
