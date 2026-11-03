#!/usr/bin/env bash
# Read the interim traffic counters off the live page's instrumentation.
#
# No account, no credentials. Prints "today / total" per bucket plus the
# conversion rate. Reading a counter also increments it by one, so every run
# of this script inflates each bucket it reads by exactly 1 — subtract the
# number of times you've looked if you need an exact figure.
#
# Replace this the moment a real analytics provider key is in index.html;
# this exists so that no day of traffic goes unmeasured in the meantime.
set -euo pipefail

BASE="https://hits.sh/rooted-abroad.k7m2/"
BUCKETS=(
  pageview
  device/mobile device/desktop
  source/direct source/li source/linkedin-com
  form/start form/submit form/stored form/fallback
  role/partner role/buyer role/other
)

read_bucket() {
  curl -sf -m 10 "${BASE}${1}.svg?view=today-total" \
    | grep -oE 'aria-label="hits: [0-9]+ / [0-9]+"' \
    | grep -oE '[0-9]+ / [0-9]+' || echo "0 / 0"
}

declare -A TOTAL
printf '%-22s %10s %10s\n' bucket today total
printf '%-22s %10s %10s\n' ---------------------- ---------- ----------
for b in "${BUCKETS[@]}"; do
  v="$(read_bucket "$b")"
  today="${v%% / *}"; total="${v##* / }"
  TOTAL[$b]="$total"
  printf '%-22s %10s %10s\n' "$b" "$today" "$total"
done

views="${TOTAL[pageview]:-0}"
subs="${TOTAL[form/submit]:-0}"
if [[ "$views" -gt 0 ]]; then
  printf '\nconversion (submit/pageview): %s%%\n' \
    "$(python3 -c "print(round(100*$subs/$views, 1))")"
fi
