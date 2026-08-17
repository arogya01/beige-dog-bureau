# Beige Dog Bureau — design

Date: 2026-08-16
Challenge: DEV Weekend Challenge, Dog Days Edition
Prize lane: Best Use of Snowflake
Repo: `/Users/arogyabichpuria/Documents/beige-dog-bureau`
Analysis source: `/Users/arogyabichpuria/Documents/57-days`

## What this is not

This is **not** a find-and-adopt marketplace.

There is no “adopt” checkout, no user accounts, no Petfinder listings, no “dogs near me.”
Austin Animal Center already publishes outcomes. We do not become a shelter CRM.

Judges who think they are looking at Tinder-for-dogs will bounce. The product is a **public bulletin** that uses the warehouse to answer one question.

## What this is

**Thesis:** Adoption sites show the photogenic ones. In Austin’s own open data, the coat is not the wait. The label is.

The existing local analysis (`scripts/analyze.py` → `out/findings.json`) already shows:

| Split | Median days to adoption | p |
|---|---:|---:|
| All-black coat vs not | 28 vs 28 | 1.00 |
| Bully-label adult vs other adult | **91 vs 32** | 0.0002 |
| Unnamed at intake vs named | 38.5 vs 27 | 0.0002 |
| Small breed vs not | 10 vs 33 | 0.0002 |

The web app is the public face of that finding: a dated **bulletin**, a **slice chart**, and **case files** for dogs still in care. Cortex may speak only from a warehouse row or a published finding. It may not invent a personality or a medical story.

Names, locked: the institution on the masthead is **Beige Dog Bureau**. The story title (hero line and DEV post) is **It's Not the Coat**. Do not invent a third.

## Who it is for

1. DEV judges (20-second demo, no Snowflake login).
2. Anyone who has heard “black dogs don’t get adopted” and has never seen the table.

Not for: people trying to take a dog home tonight.

## Surfaces

### 1. Bulletin (`/`)

- Dated header: “Austin Animal Center · census as of {as_of}.”
- Lead stat: black coat Δ = 0; bully-label adults +59 days.
- Ranked list of dogs **currently in care** (unmatched intakes), sorted by overlooked index.
- Filters: still waiting / unnamed / bully-label / senior. Not “cute / good with kids.”

### 2. Case file (`/dog/:stay_id`)

- Name or “Unnamed · {animal_id}.”
- Intake date, days waiting, color, age band, breed label, found location, named?
- The source row, visible. Every Cortex sentence must be licensed by a field here.
- Link to AAC’s public data, not an adopt button.

### 3. Ask (`POST /ask`)

- Input: stay_id + one question, or “write the letter.”
- Cortex (Snowflake REST) receives **only** that row plus the published findings table.
- Output: letter or answer + citations (`days_in_care`, `primary_color`, …).
- If the question needs a fact not in the row, refuse.

## Architecture

```
Socrata AAC intakes + outcomes
        │
        ▼
scripts/pull.py  →  data/*.csv
        │
        ▼
Snowflake
  RAW.INTAKES_RAW / OUTCOMES_RAW     (already sketched in sql/01_setup.sql)
  STAGING.STAYS                      (intake paired to earliest later outcome)
  MARTS.CENSUS                       (open stays + overlooked index)
  MARTS.FINDINGS                     (the published splits, not recomputed in the request)
        │
        ├─ live SQL          (list, case file)
        └─ Cortex REST       (letter / NLQ, grounded)
        │
        ▼
Public web app  (beige-dog-bureau/app)
  snapshot JSON fallback so the demo works if the warehouse is asleep
```

Judge-facing URL is the public app. Snowsight worksheets and table screenshots go in the DEV post to prove the DAG.

## Stay pairing (the warehouse work)

`animal_id` is not unique. Repeat visitors break `JOIN ON animal_id`.

For each intake row I, the stay’s outcome is the earliest outcome O where
`O.animal_id = I.animal_id AND O.outcome_date >= I.intake_date`.

- If no such O exists, the stay is **open** (still in care).
- Days in care = `DATEDIFF(day, intake_date, COALESCE(outcome_date, CURRENT_DATE))`.
- Cohort for the *finding* remains **adopted dogs only** (see README: including “Reclaimed” manufactures a fake stray effect).
- Cohort for the *bulletin list* is **open dog stays**.

## Overlooked index (bulletin sort only)

Explainable. Not a black-box ranker.

```
index = days_in_care
      + 20 if unnamed
      + 20 if bully_label
      + 10 if adult (not puppy, not senior)
```

Coat color does **not** add points. That is the thesis.

`bully_label` matches the existing analyzer: pit / staffordshire / bully-type tokens in `primary_breed`. Document the token list in one file and use it in both Python and SQL.

## Cortex contract

- Model via Cortex REST (`/api/v2/cortex/v1/chat/completions` or `inference:complete`), PAT auth.
- System rule: use only supplied JSON. If a field is null, say it is unknown. No veterinary advice. No “this dog would love a yard.”
- Show the JSON next to the letter.
- Cache letters by `(stay_id, prompt_version)`.
- On 429 / timeout: show the cached letter or a template built from the row in the client. Never a blank page.

## Error handling

| Failure | Behavior |
|---|---|
| Snowflake unreachable | Serve `out/census.snapshot.json` + `out/findings.json`. Banner: “census snapshot, {generated_at}.” |
| Cortex 429 / no PAT | Disable “write the letter”; keep bulletin + case file. |
| Non-dog in feed | Filtered in `STAGING.STAYS` (`type = 'Dog'`). |
| Repeat visitor | Stay pairing rule above. Case file is a stay, not an animal-for-life. |
| Name is `*Foo` or an ID | Reuse `clean_name()` from `scripts/analyze.py`. |

## Testing

- SQL or Python fixture: animal A intake Jan 1, outcome Jan 10, intake Feb 1, no outcome → two stays, second open, days from Feb 1.
- Finding fixture: black-coat median delta is 0 on the checked-in `findings.json` (regression: do not “fix” it).
- Cortex unit: prompt + row without a name → letter must not invent a name.
- App: `/` renders with only snapshot files, no env vars.

## Out of scope

Petfinder, Dallas, maps, adopt checkout, user accounts, Solana, ElevenLabs in the judge demo (audio can stay in `out/audio` for the writeup, not the critical path), live camera, “AI vet.”

## Keys

```
SNOWFLAKE_ACCOUNT
SNOWFLAKE_USER
SNOWFLAKE_PAT
SNOWFLAKE_WAREHOUSE   # auto-suspend ≤ 5 min
```

Gemini is already used offline for name archetypes. It is not required to open the site.

## Submission

DEV post thesis in the first sentence. Embed repo. Deployed bulletin. Screenshot of `MARTS.CENSUS` in Snowsight. Prize category: Snowflake only.
