# It's Not the Coat — Beige Dog Bureau

*This is a submission for [Weekend Challenge: Dog Days Edition](https://dev.to/challenges/weekend-2026-08-13)*

## What I Built

A public bulletin, not an adoption desk. Austin Animal Center already lists dogs. I wanted the file the marketing photo skips.

In 3,121 adopted dogs, an all-black coat waits **28 days — the same as any other coat** (p = 1.00). A bully-type label on an adult waits **91 days against 32**.

Beige Dog Bureau ranks who is still in care. The overlooked index is days + unnamed + bully label + adult. **Coat color is not in the score.** Cortex may write a letter only from that row.

## Demo

Local: `npm run dev` → http://localhost:3456

## Code

GitHub repo embed goes here.

## How I Built It

Austin open data → stay pairing in Snowflake (`animal_id` is reused; each intake pairs to the earliest later outcome; unmatched = still in care) → `CENSUS` view → Next.js gazette. If the warehouse is asleep, a snapshot JSON still renders the bulletin.

Cortex (`llama3.1-70b` via REST) receives only the case-file JSON. If it is down, a template letter is assembled from the same fields. It never invents a name.

## Prize Categories

Best Use of Snowflake.
