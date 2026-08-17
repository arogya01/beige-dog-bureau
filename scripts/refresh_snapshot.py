#!/usr/bin/env python3
"""Rebuild out/census.snapshot.json from the live SHELTER.AAC warehouse."""
from __future__ import annotations

import json
import sys
from datetime import date, datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from load_snowflake import env, sql, sql_all

ADULT_BULLY = "Bully-type label (adults only)"
ADULT_BLACK = "All-black coat (adults only)"


def split_from(row: list[str]) -> dict:
    return {
        "label": row[1],
        "n_yes": int(row[7]),
        "med_yes": float(row[3]),
        "n_no": int(row[8]),
        "med_no": float(row[4]),
        "delta": float(row[5]),
        "p": float(row[6]),
    }


def dog_from(r: list[str]) -> dict:
    band = r[13] or "unknown"
    return {
        "stay_id": r[0],
        "animal_id": r[1],
        "intake_date": r[2],
        "outcome_date": None,
        "outcome_status": None,
        "open": True,
        "days_in_care": int(float(r[3])),
        "name": r[4] or "",
        "name_raw": r[5] or "",
        "unnamed": str(r[6]).lower() in ("true", "1"),
        "breed": r[7] or "",
        "color": r[8] or "",
        "sex": r[9] or "",
        "source_name": r[10] or "",
        "found_address": r[11] or "",
        "age_years": float(r[12]) if r[12] not in (None, "") else None,
        "age_band": band,
        "bully_label": str(r[14]).lower() in ("true", "1"),
        "senior": band == "senior",
        "adult": band == "adult",
        "index": int(float(r[15])),
    }


def main() -> None:
    e = env()
    finding_rows = sql(e, "SELECT * FROM FINDINGS ORDER BY SPLIT_ID")["data"]
    by_label = {r[1]: r for r in finding_rows}
    cohort_n = int(finding_rows[0][2])

    census_rows = sql_all(e, """
        SELECT stay_id, animal_id, TO_VARCHAR(intake_date), days_in_care,
               name, name_raw, unnamed, breed, color, sex, source_name,
               found_address, age_years, age_band, bully_label, index
        FROM CENSUS
        ORDER BY index DESC, days_in_care DESC
        LIMIT 800
    """)
    stay_count = int(sql(e, "SELECT COUNT(*) FROM DT_STAYS")["data"][0][0])
    dogs = [dog_from(r) for r in census_rows]

    payload = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "as_of": date.today().isoformat(),
        "source": "snapshot",
        "open_count": len(dogs),
        "stay_count": stay_count,
        "findings": {
            "cohort_n": cohort_n,
            "splits": [split_from(r) for r in finding_rows],
            "bully_adult": split_from(by_label[ADULT_BULLY]),
            "black_adult": split_from(by_label[ADULT_BLACK]),
        },
        "dogs": dogs,
    }
    out = ROOT / "out" / "census.snapshot.json"
    out.write_text(json.dumps(payload, indent=2))
    print(f"wrote {out} open={len(dogs)} stays={stay_count} cohort={cohort_n}")
    print("bully_adult", payload["findings"]["bully_adult"])
    print("black_adult", payload["findings"]["black_adult"])


if __name__ == "__main__":
    main()
