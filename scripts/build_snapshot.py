#!/usr/bin/env python3
"""Build out/census.snapshot.json from 57-days Socrata dumps."""
from __future__ import annotations

import json
import sys
from datetime import date, datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from lib.domain import open_census, pair_stays

ANALYSIS = Path("/Users/arogyabichpuria/Documents/57-days")


def main() -> None:
    intakes = json.loads((ANALYSIS / "data" / "intakes.json").read_text())
    outcomes = json.loads((ANALYSIS / "data" / "outcomes.json").read_text())
    findings = json.loads((ROOT / "out" / "findings.json").read_text())
    as_of = date.today()
    stays = pair_stays(intakes, outcomes, as_of=as_of)
    census = open_census(stays)
    payload = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "as_of": as_of.isoformat(),
        "source": "snapshot",
        "open_count": len(census),
        "stay_count": len(stays),
        "findings": {
            "cohort_n": findings["cohort_n"],
            "splits": findings["splits"],
            "bully_adult": findings["bully_within_band"]["adult"],
            "black_adult": findings["black_within_band"]["adult"],
        },
        "dogs": census,
    }
    out = ROOT / "out" / "census.snapshot.json"
    out.write_text(json.dumps(payload, indent=2))
    print(f"wrote {out} open={len(census)} stays={len(stays)}")


if __name__ == "__main__":
    main()
