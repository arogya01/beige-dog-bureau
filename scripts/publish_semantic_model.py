#!/usr/bin/env python3
"""Publish semantic/census.yaml to the Snowflake stage @SHELTER.AAC.SEMANTIC.

The repo file is the source of truth. The app (lib/analyst.ts) reads it from
disk and passes it to Cortex Analyst inline, so this script is OPTIONAL - it
exists so the semantic model is also visible as a warehouse object, and so the
app can be switched to stage mode by setting

    SNOWFLAKE_SEMANTIC_MODEL_FILE=@SHELTER.AAC.SEMANTIC/census.yaml

in .env.local.

The Snowflake SQL REST API cannot run PUT (PUT streams a local file from a
driver). We get the same result with COPY INTO <stage> FROM (SELECT <text>)
using a file format that writes the string out verbatim: no delimiters, no
quoting, no compression, one file.

Usage:
    python3 scripts/publish_semantic_model.py          # publish + verify
    python3 scripts/publish_semantic_model.py --check  # verify only
"""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
YAML_PATH = ROOT / "semantic" / "census.yaml"
STAGE = "SHELTER.AAC.SEMANTIC"
STAGE_FILE = "census.yaml"


def env() -> dict[str, str]:
    out: dict[str, str] = {}
    path = ROOT / ".env.local"
    if not path.exists():
        sys.exit("no .env.local; cannot reach Snowflake")
    for line in path.read_text().splitlines():
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def _request(e: dict[str, str], url: str, data: bytes | None) -> dict:
    req = urllib.request.Request(url, data=data, method="POST" if data else "GET")
    if data:
        req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    req.add_header("Authorization", f"Bearer {e['SNOWFLAKE_PAT']}")
    req.add_header("X-Snowflake-Authorization-Token-Type", "PROGRAMMATIC_ACCESS_TOKEN")
    try:
        with urllib.request.urlopen(req, timeout=200) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as err:
        return {"__error__": err.read().decode()[:1000]}


def sql(e: dict[str, str], statement: str) -> dict:
    account = e["SNOWFLAKE_ACCOUNT"].replace("_", "-")
    url = f"https://{account}.snowflakecomputing.com/api/v2/statements"
    payload = json.dumps(
        {
            "statement": statement,
            "timeout": 180,
            "warehouse": e.get("SNOWFLAKE_WAREHOUSE", "COMPUTE_WH"),
            "database": e.get("SNOWFLAKE_DATABASE", "SHELTER"),
            "schema": e.get("SNOWFLAKE_SCHEMA", "AAC"),
            "role": e.get("SNOWFLAKE_ROLE", "ACCOUNTADMIN"),
        }
    ).encode()
    body = _request(e, url, payload)
    # Long statements come back 202 with a handle; poll it or you silently
    # read an empty result set.
    handle = body.get("statementHandle")
    for _ in range(60):
        if body.get("data") is not None or "__error__" in body or not handle:
            return body
        time.sleep(3)
        body = _request(e, f"{url}/{handle}", None)
    return body


def main() -> int:
    check_only = "--check" in sys.argv
    e = env()
    model = YAML_PATH.read_text()
    if "$$" in model:
        sys.exit("semantic model contains '$$' and cannot be dollar-quoted")

    if not check_only:
        for stmt in (
            f"CREATE STAGE IF NOT EXISTS {STAGE} "
            "DIRECTORY = (ENABLE = TRUE) "
            "COMMENT = 'Cortex Analyst semantic models for the Beige Dog Bureau'",
            # verbatim text out: no field/record delimiters, no quoting, no gzip
            f"COPY INTO @{STAGE}/{STAGE_FILE} FROM (SELECT $${model}$$) "
            "FILE_FORMAT = (TYPE = CSV COMPRESSION = NONE FIELD_DELIMITER = NONE "
            "RECORD_DELIMITER = NONE ESCAPE_UNENCLOSED_FIELD = NONE "
            "FIELD_OPTIONALLY_ENCLOSED_BY = NONE) "
            "SINGLE = TRUE OVERWRITE = TRUE MAX_FILE_SIZE = 33554432",
        ):
            r = sql(e, stmt)
            if "__error__" in r:
                print("FAILED:", r["__error__"])
                return 1

    r = sql(e, f"LIST @{STAGE}")
    if "__error__" in r:
        print("FAILED:", r["__error__"])
        return 1
    rows = r.get("data") or []
    if not rows:
        print(f"@{STAGE} is empty")
        return 1
    for row in rows:
        print("staged:", row[0], row[1], "bytes")
    print(f"local:  {YAML_PATH} {len(model.encode())} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
