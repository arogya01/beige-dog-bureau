# It's Not the Coat — Beige Dog Bureau

*This is a submission for [Weekend Challenge: Dog Days Edition](https://dev.to/challenges/weekend-2026-08-13)*

## What I Built

A public bulletin, not an adoption desk. Austin Animal Center already lists dogs. I wanted the file the marketing photo skips.

Everyone knows the black dog myth: dark coats sit in shelters longer. I built the warehouse to measure it, and the data would not cooperate.

Across **2,821 closed stays**, an all-black coat waits **24 days against 23** — a one-day gap a permutation test cannot separate from noise (p = 0.69). Restrict it to adults and the gap is 34 against 31, still noise (p = 0.42).

What does separate is the paperwork. A **bully-type breed label on an adult waits 62.5 days against 26** — a 36-day penalty at p = 0.0002. Not the dog. The label a human typed into the breed field.

Two other splits land the same way: dogs who arrive unnamed leave *faster* (7 days against 27), and so do small-breed labels (9 against 27). Every significant effect in this dataset runs through a text field, not a coat.

Beige Dog Bureau ranks who is still in care today. The overlooked index is days + unnamed + bully label + adult. **Coat color is not in the score** — the analysis is what removed it. Cortex writes a letter using only that dog's row.

## Demo

Live: *(deployment URL)*

## Code

*(GitHub repo embed)*

## How I Built It

Austin open data → stay pairing in Snowflake → `CENSUS` view → Next.js gazette. If the warehouse is asleep, a snapshot JSON still renders the bulletin.

`animal_id` is reused across visits, so each intake pairs to the earliest later outcome and unmatched intakes are dogs still in care. Findings are computed in dynamic tables with a 5,000-iteration permutation test per split, so the p-values come out of the warehouse rather than out of a notebook.

Cortex (`llama3.1-70b` via REST) receives only the case-file JSON. If it is down, a template letter is assembled from the same fields. It never invents a name.

## What Went Wrong (the useful part)

Three bugs, and only one was a typo.

**The cohort was missing every puppy.** The intake data separates `type = 'Puppy'` from `type = 'Dog'`, so a `WHERE type = 'Dog'` filter silently dropped 492 intakes. Puppies leave fast. Excluding them shortened the baseline wait for every group — and it flattered the coat thesis I had started with. The first version of this post claimed black coats waited 28 days against 28 in a cohort of 3,121. That cohort was wrong, and the headline built on it did not survive the fix.

**The census was quietly truncated.** Snowflake's SQL API splits wide result sets across partitions and only inlines the first one. Reading `body.data` and stopping there returned 520 of 593 open dogs — no error, no warning, just 73 missing dogs on a page that claims to be a complete bulletin. A silent wrong answer is worse than a failed request, and this one was invisible until I compared against `COUNT(*)`.

**An unmatched-intake join dropped the open stays entirely.** `LEFT JOIN LATERAL … QUALIFY` filtered away the very rows with no match — the dogs still in care, which is the entire point of the bulletin.

The through-line: every one of these failed toward a *cleaner, more confident* answer. A smaller cohort, a shorter list, a tidier join. Nothing crashed. If I had trusted the first numbers that rendered without an error, I would have published a confident claim about coat color that the corrected data does not support.

## Prize Categories

Best Use of Snowflake.
