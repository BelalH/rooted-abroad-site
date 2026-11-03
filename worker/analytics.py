#!/usr/bin/env python3
"""Read the interim traffic counters off the live page's instrumentation.

No account, no credentials. Replaces this the moment a real provider key is
set in index.html; it exists so no day of traffic goes unmeasured first.

The counters are hit-counter badges: fetching one to read it also increments
it. Left uncorrected, this script's own reads are indistinguishable from
visitors — the first version of it reported a 25% form conversion rate on a
page that had never been submitted, because every bucket it read came back as
1. So it keeps a local ledger (.analytics-state.json) of a baseline taken on
first run plus every read since, and reports only counts it did not cause.

Caveats worth knowing before quoting a number from this:
  - The bucket URLs are public and in a public repo, so anyone can inflate
    them. Treat the output as directional, not as a system of record.
  - The ledger is local to this workspace. A read from anywhere else (another
    machine, a manual curl) lands in "unattributed" below, not in the ledger.

Usage: ./analytics.py [--reset-baseline]
"""
import json
import re
import sys
import urllib.error
import urllib.request
from datetime import date
from pathlib import Path

BASE = "https://hits.sh/rooted-abroad.k7m2/"
STATE = Path(__file__).with_name(".analytics-state.json")
LABEL = re.compile(r'aria-label="hits: (\d+) / (\d+)"')

BUCKETS = [
    "pageview",
    "device/mobile",
    "device/desktop",
    "source/direct",
    "source/li",
    "source/linkedin-com",
    "form/start",
    "form/submit",
    "form/stored",
    "form/fallback",
    "form/fallback-mailto",
    "form/fallback-copy",
    "role/partner",
    "role/buyer",
    "role/other",
]


def read_bucket(bucket):
    url = f"{BASE}{bucket}.svg?view=today-total"
    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            m = LABEL.search(r.read().decode("utf-8", "replace"))
    except (urllib.error.URLError, TimeoutError) as e:
        print(f"  ! {bucket}: {e}", file=sys.stderr)
        return None, None
    return (int(m.group(1)), int(m.group(2))) if m else (None, None)


def load_state():
    if STATE.exists():
        return json.loads(STATE.read_text())
    return {"baseline": {}, "baselineTakenOn": None, "reads": {}}


def main():
    state = load_state()
    if "--reset-baseline" in sys.argv:
        state = {"baseline": {}, "baselineTakenOn": None, "reads": {}}

    first_run = not state["baseline"]
    rows = []

    for b in BUCKETS:
        today, total = read_bucket(b)
        if total is None:
            rows.append((b, "?", "?", "?"))
            continue

        if first_run:
            # Everything up to and including this read is ours, not a visitor's.
            state["baseline"][b] = total
            state["reads"][b] = 0
        else:
            state["reads"][b] = state["reads"].get(b, 0) + 1

        reads = state["reads"][b]
        attributed = state["baseline"].get(b, 0) + reads
        rows.append((b, total, reads, max(total - attributed, 0)))

    if first_run:
        state["baselineTakenOn"] = date.today().isoformat()
    STATE.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")

    print(f"{'bucket':<22}{'raw':>8}{'our reads':>11}{'real':>8}")
    print(f"{'-' * 22:<22}{'-' * 8:>8}{'-' * 11:>11}{'-' * 8:>8}")
    for b, total, reads, real in rows:
        print(f"{b:<22}{total:>8}{reads:>11}{real:>8}")

    real = {r[0]: r[3] for r in rows if isinstance(r[3], int)}
    views, subs = real.get("pageview", 0), real.get("form/submit", 0)
    print()
    if first_run:
        print(
            f"Baseline set today ({state['baselineTakenOn']}); every count so far was "
            "our own verification. 'real' starts from zero here, not from launch."
        )
    if views:
        print(f"conversion (submit/pageview): {round(100 * subs / views, 1)}%")
    else:
        print("No visitor pageviews yet — nothing to compute a conversion rate from.")


if __name__ == "__main__":
    main()
