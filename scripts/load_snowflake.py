#!/usr/bin/env python3
"""Create SHELTER.AAC tables and load 57-days CSVs through the SQL API."""
from __future__ import annotations

import csv
import gzip
import json
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANALYSIS = Path("/Users/arogyabichpuria/Documents/57-days")


def env() -> dict[str, str]:
    out: dict[str, str] = {}
    for line in (ROOT / ".env.local").read_text().splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def sql(e: dict[str, str], statement: str) -> dict:
    account = e["SNOWFLAKE_ACCOUNT"].replace("_", "-")
    url = f"https://{account}.snowflakecomputing.com/api/v2/statements"
    payload = json.dumps({
        "statement": statement,
        "timeout": 120,
        "warehouse": e.get("SNOWFLAKE_WAREHOUSE", "COMPUTE_WH"),
        "database": e.get("SNOWFLAKE_DATABASE", "SHELTER"),
        "schema": e.get("SNOWFLAKE_SCHEMA", "AAC"),
        "role": e.get("SNOWFLAKE_ROLE", "ACCOUNTADMIN"),
    }).encode()
    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    req.add_header("Authorization", f"Bearer {e['SNOWFLAKE_PAT']}")
    req.add_header("X-Snowflake-Authorization-Token-Type", "PROGRAMMATIC_ACCESS_TOKEN")
    try:
        with urllib.request.urlopen(req, timeout=130) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as err:
        raise RuntimeError(err.read().decode()[:500]) from err


def sql_all(e: dict[str, str], statement: str) -> list[list[str]]:
    """Run a query and follow partition links; body.data is only partition 0."""
    body = sql(e, statement)
    rows = list(body.get("data") or [])
    meta = body.get("resultSetMetaData") or {}
    handle = body.get("statementHandle")
    account = e["SNOWFLAKE_ACCOUNT"].replace("_", "-")
    for p in range(1, len(meta.get("partitionInfo") or [])):
        url = (f"https://{account}.snowflakecomputing.com"
               f"/api/v2/statements/{handle}?partition={p}")
        req = urllib.request.Request(url, method="GET")
        req.add_header("Accept", "application/json")
        req.add_header("Authorization", f"Bearer {e['SNOWFLAKE_PAT']}")
        req.add_header("X-Snowflake-Authorization-Token-Type", "PROGRAMMATIC_ACCESS_TOKEN")
        with urllib.request.urlopen(req, timeout=130) as resp:
            raw = resp.read()
            if resp.headers.get("Content-Encoding") == "gzip":
                raw = gzip.decompress(raw)
            rows.extend(json.loads(raw.decode()).get("data") or [])
    return rows


def lit(v: str | None) -> str:
    if v is None or v == "":
        return "NULL"
    return "'" + str(v).replace("'", "''") + "'"


def load_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def main() -> None:
    e = env()
    for name in ("01_setup.sql", "02_stays.sql", "03_marts.sql"):
        text = (ROOT / "sql" / name).read_text()
        for stmt in [s.strip() for s in text.split(";") if s.strip() and not s.strip().startswith("--")]:
            # keep comments-only chunks out
            body = "\n".join(ln for ln in stmt.splitlines() if not ln.strip().startswith("--"))
            # SQL API has no session; USE is rejected. Context comes from the request body.
            if body.strip().upper().startswith("USE "):
                continue
            if body.strip():
                print("run", name, body.split()[0], body.split()[1] if len(body.split()) > 1 else "")
                sql(e, body)

    intakes = load_csv(ANALYSIS / "data" / "intakes.csv")
    outcomes = load_csv(ANALYSIS / "data" / "outcomes.csv")
    print("intakes", len(intakes), "outcomes", len(outcomes))

    def flush_intakes(batch: list[dict[str, str]]) -> None:
        values = []
        for r in batch:
            values.append(
                "("
                + ",".join([
                    lit(r.get("id")),
                    lit(r.get("source_date") or None),
                    lit(r.get("animal_id")),
                    lit(r.get("type")),
                    lit(r.get("source_name")),
                    lit(r.get("name_at_intake")),
                    "TRUE" if str(r.get("ispreviouslyspayedneutered")).lower() == "true" else "FALSE",
                    lit(r.get("sex")),
                    lit(r.get("primary_breed")),
                    lit(r.get("primary_color")),
                    lit(r.get("date_of_birth") or None),
                    lit(r.get("found_address")),
                    lit(r.get("timestamp") or None),
                ])
                + ")"
            )
        sql(e, "INSERT INTO INTAKES_RAW VALUES " + ",".join(values))

    def flush_outcomes(batch: list[dict[str, str]]) -> None:
        values = []
        for r in batch:
            days = r.get("days_in_shelter")
            values.append(
                "("
                + ",".join([
                    lit(r.get("id")),
                    lit(r.get("outcome_date") or None),
                    lit(r.get("animal_id")),
                    lit(r.get("name")),
                    lit(r.get("outcome_status")),
                    lit(r.get("euthanasia_reason")),
                    lit(r.get("type")),
                    lit(r.get("sex")),
                    lit(r.get("spayed_neutered")),
                    lit(r.get("primary_breed")),
                    lit(r.get("primary_color")),
                    lit(r.get("secondary_color")),
                    lit(r.get("date_of_birth") or None),
                    lit(r.get("intake_date") or None),
                    days if days not in (None, "") else "NULL",
                    lit(r.get("timestamp") or None),
                ])
                + ")"
            )
        sql(e, "INSERT INTO OUTCOMES_RAW VALUES " + ",".join(values))

    sql(e, "TRUNCATE TABLE INTAKES_RAW")
    sql(e, "TRUNCATE TABLE OUTCOMES_RAW")
    chunk = 80
    for i in range(0, len(intakes), chunk):
        flush_intakes(intakes[i : i + chunk])
        if i % 800 == 0:
            print("intakes loaded", min(i + chunk, len(intakes)))
    for i in range(0, len(outcomes), chunk):
        flush_outcomes(outcomes[i : i + chunk])
        if i % 800 == 0:
            print("outcomes loaded", min(i + chunk, len(outcomes)))
    n = sql(e, "SELECT COUNT(*) FROM CENSUS")
    print("census_rows", n.get("data"))


if __name__ == "__main__":
    main()
