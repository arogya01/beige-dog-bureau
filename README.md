# Beige Dog Bureau

Public bulletin for [DEV Weekend Challenge: Dog Days Edition](https://dev.to/challenges/weekend-2026-08-13).
Prize lane: **Best Use of Snowflake**.

This is **not** an adopt-a-dog marketplace. It is a civic gazette built on Austin Animal Center open data.

**Thesis:** In 2,821 closed stays, an all-black coat waits 24 days against 23 — a difference the permutation test cannot separate from noise (p = 0.69). A bully-type label on an adult waits **62.5 days against 26** (p = 0.0002).

- Masthead: Beige Dog Bureau
- Story: It's Not the Coat
- Spec: `docs/superpowers/specs/2026-08-16-beige-dog-bureau-design.md`

## Run

```bash
python3 -m unittest tests.test_domain -v
python3 scripts/build_snapshot.py
npm install
npm run dev
```

Open http://localhost:3456

The site renders from `out/census.snapshot.json` with no warehouse. When `.env.local` has a working PAT, `/` prefers `SHELTER.AAC.CENSUS` and `/api/ask` calls Cortex. If Cortex is down, a template letter is built only from the row.

## Load Snowflake (optional, prize-category path)

1. Confirm network policy + PAT (see `NEED-FROM-YOU.md`).
2. `python3 scripts/load_snowflake.py`  
   Creates `SHELTER.AAC` tables/views and inserts the 57-days CSVs.

Worksheets to screenshot for the DEV post: `sql/01_setup.sql`, `sql/02_stays.sql`, `sql/03_marts.sql`.

## What the warehouse does

`animal_id` is reused. Each intake pairs to the earliest later outcome. Unmatched = still in care. The overlooked index is `days + unnamed + bully label + adult`. **Coat color is not in the score.**
