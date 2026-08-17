"""Stay pairing, overlooked index, and name cleaning.

Shared by the snapshot builder and tests. Keep in lockstep with sql/02_stays.sql.
"""
from __future__ import annotations

import re
from datetime import datetime, date
from typing import Any

BULLY_TOKENS = ("Pit Bull", "Staffordshire", "American Bully")

def clean_name(raw: str | None) -> str:
    if not raw:
        return ""
    n = raw.strip().strip("*").strip()
    n = re.split(r"[(/]", n)[0]
    n = re.sub(r"\b(aka|AKA)\b.*", "", n)
    n = n.replace('"', "").replace("’", "'").strip(" .-'")
    n = re.sub(r"\s+", " ", n)
    if not n or n.isdigit():
        return ""
    if not re.match(r"^[A-Za-z]", n):
        return ""
    return n.title()


def parse_ts(ts: str | None) -> datetime | None:
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts[:19])
    except (TypeError, ValueError):
        return None


def is_bully(breed: str | None) -> bool:
    b = breed or ""
    return any(tok in b for tok in BULLY_TOKENS)


def age_years(dob: datetime | None, as_of: date) -> float | None:
    if not dob:
        return None
    days = (as_of - dob.date()).days
    if days < 0 or days > 25 * 365:
        return None
    return days / 365.25


def age_band(years: float | None) -> str:
    if years is None:
        return "unknown"
    if years < 0.5:
        return "puppy"
    if years < 2:
        return "young"
    if years < 7:
        return "adult"
    return "senior"


def overlooked_index(days_in_care: int, unnamed: bool, bully: bool, band: str) -> int:
    score = days_in_care
    if unnamed:
        score += 20
    if bully:
        score += 20
    if band == "adult":
        score += 10
    return score


def pair_stays(
    intakes: list[dict[str, Any]],
    outcomes: list[dict[str, Any]],
    *,
    as_of: date | None = None,
) -> list[dict[str, Any]]:
    """Each dog intake pairs to the earliest later outcome on the same animal_id.

    Unmatched intakes are open stays (still in care).
    """
    today = as_of or date.today()
    dog_intakes = [r for r in intakes if r.get("type") == "Dog"]
    by_animal: dict[str, list[dict[str, Any]]] = {}
    for o in outcomes:
        if o.get("type") != "Dog":
            continue
        by_animal.setdefault(str(o.get("animal_id")), []).append(o)
    for lst in by_animal.values():
        lst.sort(key=lambda r: parse_ts(r.get("outcome_date")) or datetime.max)

    stays: list[dict[str, Any]] = []
    for inc in dog_intakes:
        animal_id = str(inc.get("animal_id") or "")
        intake_dt = parse_ts(inc.get("source_date"))
        if not animal_id or not intake_dt:
            continue
        match = None
        for o in by_animal.get(animal_id, []):
            od = parse_ts(o.get("outcome_date"))
            if od and od >= intake_dt:
                match = o
                break
        end_dt = parse_ts(match.get("outcome_date")) if match else datetime.combine(today, datetime.min.time())
        days = (end_dt.date() - intake_dt.date()).days
        if days < 0:
            continue
        name_at_intake = (inc.get("name_at_intake") or "").strip()
        display_raw = (match.get("name") if match else None) or name_at_intake
        name = clean_name(display_raw)
        unnamed = clean_name(name_at_intake) == ""
        breed = inc.get("primary_breed") or (match.get("primary_breed") if match else "") or ""
        color = inc.get("primary_color") or (match.get("primary_color") if match else "") or ""
        years = age_years(parse_ts(inc.get("date_of_birth")), today)
        band = age_band(years)
        bully = is_bully(breed)
        stay_id = f"{animal_id}-{intake_dt.date().isoformat()}"
        stays.append({
            "stay_id": stay_id,
            "animal_id": animal_id,
            "intake_date": intake_dt.date().isoformat(),
            "outcome_date": parse_ts(match.get("outcome_date")).date().isoformat() if match and parse_ts(match.get("outcome_date")) else None,
            "outcome_status": (match.get("outcome_status") if match else None),
            "open": match is None,
            "days_in_care": days,
            "name": name,
            "name_raw": (display_raw or "").strip(),
            "unnamed": unnamed,
            "breed": breed,
            "color": color,
            "sex": inc.get("sex") or "",
            "source_name": inc.get("source_name") or "",
            "found_address": inc.get("found_address") or "",
            "age_years": None if years is None else round(years, 2),
            "age_band": band,
            "bully_label": bully,
            "senior": band == "senior",
            "adult": band == "adult",
            "index": overlooked_index(days, unnamed, bully, band),
        })
    return stays


def open_census(stays: list[dict[str, Any]]) -> list[dict[str, Any]]:
    open_stays = [s for s in stays if s["open"]]
    open_stays.sort(key=lambda s: (-s["index"], -s["days_in_care"], s["stay_id"]))
    return open_stays
