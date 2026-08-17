# What I need from you before `/goal`

Do these in order. The first one is the long pole (email activation).

## 1. Snowflake trial (required)

1. Sign up: https://signup.snowflake.com/ (or the challenge [student/trial link](https://signup.snowflake.com/?trial=student&utm_source=%20mlh&utm_medium=student-hackathon&utm_campaign=mlh-rest-api-experiment-4-18&k=snowflake-ai-mlh&t=1852e74be11981c4c39cc525d4bdda6cd08e2b19d928cac77c60ddea361beec0))
2. Activate from the email (“Snowflake Computing”).
3. In Snowsight, bottom-left name → **Connect a tool to Snowflake**. Copy:
   - Account identifier (looks like `xy12345.us-east-1`)
   - Username
   - Server URL host
4. **Authentication settings** → create a **Programmatic Access Token (PAT)**.
5. Set a **network policy exception** for the PAT (the official Cortex demo will 429/403 without this).
6. In a worksheet, as ACCOUNTADMIN, run:

```sql
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

CREATE NETWORK POLICY IF NOT EXISTS ALL_IPS_NETWORK_POLICY
  ALLOWED_IP_LIST = ('0.0.0.0/0');

ALTER ACCOUNT SET NETWORK_POLICY = ALL_IPS_NETWORK_POLICY;
```

7. Confirm a warehouse exists (`COMPUTE_WH` is fine). Auto-suspend ≤ 5 minutes.

Paste into `.env.local` (do not paste the PAT into chat if you can avoid it — say “PAT is in `.env.local`”):

```
SNOWFLAKE_ACCOUNT=
SNOWFLAKE_USER=
SNOWFLAKE_PAT=
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
```

## 2. I do not need

- Gemini key (optional; 57-days already classified names offline)
- ElevenLabs key (not on the judge-critical path)
- Petfinder API
- A dog photo
- Hosting account yet (Vercel can wait until the app runs locally)

## 3. Nice if you have it

- A GitHub repo you want this pushed to (or I can `git init` here)
- Your DEV handle for the submission post
- Whether you already loaded `57-days/data/*.csv` into Snowflake (`SHELTER.AAC`)

## When that is done

Reply `/goal` the whole Beige Dog Bureau app against `docs/superpowers/specs/2026-08-16-beige-dog-bureau-design.md`.
The site must still open with **no** Snowflake env (snapshot fallback). Live warehouse + Cortex is the prize-category path.
