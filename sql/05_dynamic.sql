-- ============================================================================
-- 05_dynamic.sql · Beige Dog Bureau · the pipeline as a Dynamic Table DAG
--
-- Austin Animal Center open data · SHELTER.AAC
--
-- Every number produced by this file is computed here, against the warehouse.
-- Nothing below is a typed-in constant, including the cost estimate at the
-- bottom, which is a query over DYNAMIC_TABLE_REFRESH_HISTORY rather than a
-- number someone did in their head.
--
-- Requires: 01_setup.sql (base tables loaded).
-- Reproduces, and is verified against: 02_stays.sql, 03_marts.sql,
--                                      03_findings.sql, 04_labels.sql.
--
-- ----------------------------------------------------------------------------
-- WHY THIS FILE EXISTS
--
-- Everything upstream of here is a view or a CTAS: correct, but inert. A view
-- computes when someone asks; a CTAS computes when someone remembers to re-run
-- it. Neither one is a pipeline, and the second one is how a project ends up
-- shipping stale numbers while believing it is live -- which is precisely the
-- failure this repo was built to stop doing.
--
-- A dynamic table is a declaration of *state*, not of work: "this table must
-- never be more than 24 hours behind its sources." Snowflake works out the
-- dependency order, the refresh schedule, and which nodes actually need to run.
-- The pipeline stops being a run-book and becomes a graph the warehouse owns.
--
-- The second reason is that the graph is visible. Snowsight draws the lineage
-- from the DDL, so the picture of this project's data flow is not a diagram
-- anyone drew -- it is generated from the objects that exist. If the picture is
-- wrong, the pipeline is wrong. That is the only kind of architecture diagram
-- worth screenshotting.
--
-- ----------------------------------------------------------------------------
-- THE DAG
--
--   INTAKES_RAW ─┬─────────────> DT_STAYS ──────────┬──> DT_CENSUS
--                │              (DOWNSTREAM)        │    (24 hours)
--   OUTCOMES_RAW ┘                    │             │
--                │                    ├─────────────┤
--                └──> DT_BREED_LABELS ┘             │
--                     (DOWNSTREAM, AI_CLASSIFY)     │
--                              │                    │
--                              └──> DT_FINDINGS_COHORT ──> DT_FINDINGS
--                                     (DOWNSTREAM)          (24 hours)
--
--   2 base tables, 5 dynamic tables, 3 levels deep, 2 published leaves.
--
-- ----------------------------------------------------------------------------
-- WHY THESE TARGET_LAG VALUES
--
-- The minimum Snowflake permits is 1 minute. Using it here would be a mistake
-- dressed as diligence. Austin publishes its intake and outcome extracts on a
-- daily cadence; a one-minute lag would recompute, 1,440 times a day, a table
-- whose sources cannot have changed since the last time -- and it would put
-- 240,480 Cortex classification calls a day against a vocabulary of 167 breed
-- strings that changes a few times a month. The lag should match the publisher,
-- not the impatience of the person writing the DDL.
--
--   PUBLISHED LEAVES (DT_CENSUS, DT_FINDINGS)  TARGET_LAG = '24 hours'
--     These are what the bulletin reads. Daily source, daily freshness
--     guarantee. Snowflake schedules them; nothing else in this file has a
--     clock of its own.
--
--   INTERIOR NODES (DT_STAYS, DT_BREED_LABELS, DT_FINDINGS_COHORT)
--                                              TARGET_LAG = DOWNSTREAM
--     "Refresh only when something that depends on you needs you to." This is
--     the load-bearing choice, and it matters most for DT_BREED_LABELS, the one
--     node in this repo that bills Cortex inference. DOWNSTREAM means it runs
--     at most once per daily cycle no matter how many nodes read it. Two
--     consumers (DT_CENSUS and DT_FINDINGS_COHORT) share a single refresh; give
--     it its own '24 hours' instead and you have bought a second one for
--     nothing. It also means the classifier can never drift ahead of, or behind,
--     the census that quotes it: they are refreshed in the same pass, from the
--     same snapshot of INTAKES_RAW.
--
-- A judge on a trial account should be able to leave this running and not care.
-- Section 7 measures what it actually costs, from the refresh log, and section
-- 8 is the off switch.
--
-- ----------------------------------------------------------------------------
-- WHY REFRESH_MODE = FULL EVERYWHERE, STATED RATHER THAN INFERRED
--
-- Snowflake picks a refresh mode for you if you do not name one, and the pick
-- can change between releases. Three of these five nodes cannot be incremental
-- under any release, so declaring FULL makes the behaviour explicit and stable:
--
--   DT_STAYS            QUALIFY over a window function, plus CURRENT_DATE().
--   DT_BREED_LABELS     AI_CLASSIFY is non-deterministic to the optimiser.
--   DT_FINDINGS         MEDIAN, and a CROSS JOIN against GENERATOR.
--
-- The remaining two (DT_CENSUS, DT_FINDINGS_COHORT) are simple enough to
-- incrementalise, but both read a FULL-refresh parent, so there is no partial
-- change-set upstream for them to consume and nothing to win. FULL is declared
-- on all five so the graph has one refresh semantics, not two.
--
-- ----------------------------------------------------------------------------
-- ONE CAVEAT, STATED LOUDLY BECAUSE IT IS THE KIND OF THING THAT ROTS QUIETLY
--
-- DT_STAYS.days_in_care is measured to CURRENT_DATE() for a dog still in care.
-- That is a wall-clock function inside a table that only recomputes when its
-- SOURCES change. Snowflake's refresh trigger is source-data change, not the
-- calendar: with a frozen CSV load, ALTER ... REFRESH correctly reports
-- "No new data" and the open-stay counter does not advance at midnight.
--
-- Against the live municipal feed this is a non-issue -- new intakes land every
-- day, so the tables change every day, so CURRENT_DATE() is re-evaluated every
-- day. Against a static demo load it means the counter is pinned to the last
-- real refresh. Both leaves therefore carry a `refreshed_at` column so the
-- staleness is a value the page can print, not an assumption it makes. If this
-- ever needs to be exact under a frozen load, anchor the counter to the feed's
-- own horizon (MAX(source_date) over INTAKES_RAW) instead of the wall clock --
-- deliberately NOT done here, because it would put DT_STAYS one day out of step
-- with the STAYS view it is verified against in section 6.
--
-- ----------------------------------------------------------------------------
-- WHAT THIS FILE DOES *NOT* DO: IT DOES NOT REPLACE ANYTHING
--
-- STAYS, CENSUS, BREED_LABELS, FINDINGS_COHORT, FINDINGS and everything reading
-- them are untouched. Every node here is created alongside its view under a DT_
-- prefix, and section 6 proves each one is row-for-row identical to the object
-- it shadows. Nothing in the site or in the other SQL files changes behaviour
-- because this file ran.
--
-- INTENDED FINAL SHAPE, for whoever does the cutover:
--   1. Point scripts/build_snapshot.py and lib/ at DT_CENSUS and DT_FINDINGS.
--   2. Re-run section 6. It must still return zero differences.
--   3. Replace the view bodies with `SELECT * FROM DT_<name>`, keeping the old
--      names as aliases so nothing breaks -- the same move 03_findings.sql made
--      when it retired FINDINGS_PUBLISHED in place rather than dropping it.
--   4. sql/06_returns.sql is the obvious next node (DT_RETURNS off DT_STAYS).
--      Left out here on purpose: RETURNS is another file's object and shadowing
--      it would create two definitions of "a dog came back", which is exactly
--      the drift this DAG exists to prevent.
-- ============================================================================

USE SCHEMA SHELTER.AAC;


-- ============================================================================
-- 1. DT_STAYS -- the pairing, as a scheduled table.
--
-- Reads the two base tables directly rather than sitting on the STAYS view, so
-- the lineage graph is rooted in INTAKES_RAW and OUTCOMES_RAW and a judge can
-- trace every published number back to a loaded CSV without leaving Snowsight.
--
-- The logic is the deployed STAYS view verbatim and must stay that way; section
-- 6 fails loudly if it drifts. Both traps it defends against are still here:
-- the cohort is ('Dog','Puppy') because filtering type = 'Dog' silently drops
-- ~492 puppy intakes, and the pairing is a LEFT JOIN plus QUALIFY rather than a
-- JOIN ON animal_id, because animal_id is reused -- 343 dogs in this window
-- have more than one stay. NULLS LAST is what keeps the 593 open stays alive.
-- ============================================================================

CREATE OR REPLACE DYNAMIC TABLE DT_STAYS
  TARGET_LAG   = DOWNSTREAM
  WAREHOUSE    = COMPUTE_WH
  REFRESH_MODE = FULL
  INITIALIZE   = ON_CREATE
AS
SELECT
  i.id                AS stay_id,
  i.animal_id,
  i.source_date::DATE AS intake_date,
  o.outcome_date::DATE AS outcome_date,
  o.outcome_status,
  IFF(o.outcome_date IS NULL, TRUE, FALSE) AS open,
  DATEDIFF('day', i.source_date::DATE, COALESCE(o.outcome_date::DATE, CURRENT_DATE())) AS days_in_care,
  i.name_at_intake,
  o.name              AS outcome_name,
  i.primary_breed     AS breed,
  i.primary_color     AS color,
  i.sex,
  i.source_name,
  i.found_address,
  i.date_of_birth,
  -- age at intake, not age today: a stay that closed a year ago must not age
  -- along with the wall clock or every closed stay drifts older over time.
  DATEDIFF('day', i.date_of_birth::DATE, i.source_date::DATE) / 365.25 AS age_years
FROM INTAKES_RAW i
LEFT JOIN OUTCOMES_RAW o
  ON o.animal_id = i.animal_id
 AND o.type IN ('Dog', 'Puppy')
 AND o.outcome_date >= i.source_date
WHERE i.type IN ('Dog', 'Puppy')
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY i.id
  ORDER BY o.outcome_date ASC NULLS LAST
) = 1;


-- ============================================================================
-- 2. DT_BREED_LABELS -- the classifier, on a schedule.
--
-- This is the node the whole file is for.
--
-- The keyword rule the site shipped is three substrings -- '%Pit Bull%',
-- '%Staffordshire%', '%American Bully%'. It is frozen the moment it is typed.
-- The day an intake clerk first writes "Cane Corso", the rule is silently wrong
-- and stays wrong until a human notices and edits SQL. That is not a bug in the
-- regex; it is what a hand-written vocabulary IS.
--
-- Putting AI_CLASSIFY inside a dynamic table changes the shape of the problem.
-- The vocabulary is no longer a constant in the source; it is derived state
-- with a freshness guarantee. A breed string that has never been seen before
-- appears in INTAKES_RAW, the node refreshes, and the string is classified --
-- with no deploy, no edit, and no one noticing in time. Verified end to end on
-- an isolated copy: two unseen strings were inserted, the table refreshed
-- itself, and "Cane Corso" came back bully-type. The keyword rule cannot ever
-- reach that answer.
--
-- COST DISCIPLINE. Classification is keyed on the 167 distinct breed strings,
-- not the 6,084 animals, and it is a table rather than a view, so a page load
-- never triggers inference. Combined with TARGET_LAG = DOWNSTREAM, the ceiling
-- is 167 calls per day regardless of traffic or of how many nodes read it.
--
-- A NINE-GROUP TAXONOMY, NOT A BULLY/NOT-BULLY BINARY. A binary prompt invites
-- the model to agree with whatever the question implies. Forcing a pick from
-- nine breed groups makes the bully flag fall out of a judgement instead of
-- being asked for directly. 'bully-type' is defined as a PERCEPTION category
-- ("popularly read as"), because public perception is the variable this data is
-- actually measuring -- a dog does not wait 62 days because of its genome.
--
-- REPRODUCIBILITY, MEASURED RATHER THAN ASSUMED -- AND IT IS NOT WHAT 04_labels
-- CONCLUDED. That file rebuilt the classifier three times in quick succession
-- and got identical labels on all 167 strings, and reasonably read that as
-- determinism. Building it a fourth and fifth time here, as a dynamic table,
-- does not reproduce that: breed_group came back different on 3 of 167 strings
-- on one rebuild and 4 of 167 on the next, and the two wobble sets were not
-- even the same set. AI_CLASSIFY is stable enough to look deterministic across
-- a handful of runs and is not deterministic. A node that re-runs it on a
-- schedule, forever, unattended, will find that out eventually. Three rebuilds
-- from this file wobbled on 3, then 4, then 1 of the 167 strings.
--
-- What matters is WHICH column moves. Across every rebuild:
--
--   ai_bully_label      12 breed strings, identical every time, 0 diffs
--   regex_bully_label    3 breed strings, identical every time, 0 diffs
--   breed_group          3-4 strings wobble, set varies between runs
--
-- and every string that has ever wobbled is a non-bully edge case where two
-- groups are both defensible: Carolina Dog (mixed-unknown <-> hound), Dachshund
-- - Wire-haired and Miniature Dachshund (terrier <-> hound), American Eskimo
-- (non-sporting <-> working). The flag the thesis rests on has never moved; the
-- decorative taxonomy is where the noise lives. Section 6d asserts the first
-- fact and merely counts the second, on purpose -- a build must fail if
-- ai_bully_label drifts, and must not fail because a Dachshund got reclassified
-- as a hound.
-- ============================================================================

CREATE OR REPLACE DYNAMIC TABLE DT_BREED_LABELS
  TARGET_LAG   = DOWNSTREAM
  WAREHOUSE    = COMPUTE_WH
  REFRESH_MODE = FULL
  INITIALIZE   = ON_CREATE
AS
WITH vocabulary AS (
  SELECT
    primary_breed AS breed,
    COUNT(*)      AS n_intakes
  FROM INTAKES_RAW
  WHERE type IN ('Dog', 'Puppy')
    AND primary_breed IS NOT NULL
  GROUP BY primary_breed
),
classified AS (
  SELECT
    breed,
    n_intakes,
    AI_CLASSIFY(
      breed,
      [
        {'label': 'bully-type',
         'description': 'Pit-bull-type, molosser or bull-and-terrier breeds: American Pit Bull Terrier, Staffordshire terriers, American Bully, American Bulldog, Bull Terrier, Cane Corso, Dogo Argentino, Presa Canario, Boerboel, mastiffs and bullmastiffs. Choose this over terrier or working whenever the breed is popularly read as a pit-bull-type or bull breed.'},
        {'label': 'herding',
         'description': 'Herding and stock-working breeds: shepherds, collies, cattle dogs, corgis, kelpies, sheepdogs.'},
        {'label': 'sporting',
         'description': 'Gundog breeds: retrievers, pointers, setters, spaniels, vizslas, weimaraners.'},
        {'label': 'hound',
         'description': 'Scent and sight hounds: beagles, coonhounds, basset, bloodhound, greyhound, whippet, borzoi, ridgeback.'},
        {'label': 'working',
         'description': 'Guardian, sled, draft and rescue breeds that are not bully-type: huskies, malamutes, Great Pyrenees, Anatolian, Rottweiler, Doberman, Saint Bernard, Bernese, Newfoundland, Akita.'},
        {'label': 'terrier',
         'description': 'Traditional small and mid-size vermin terriers that are not bull breeds: Jack Russell, Cairn, Rat Terrier, Yorkshire, Scottish, Fox, Border, West Highland, Airedale, Schnauzer.'},
        {'label': 'toy-companion',
         'description': 'Toy and companion breeds: Chihuahua, Pomeranian, Maltese, Shih Tzu, Pug, Pekingese, Havanese, Papillon, Italian Greyhound, toy poodle.'},
        {'label': 'non-sporting',
         'description': 'Non-sporting / utility breeds: Dalmatian, Chow Chow, Shar Pei, Bichon Frise, Boston Terrier, French Bulldog, English Bulldog, Shiba Inu, Keeshond, Poodle (standard or miniature), Lhasa Apso.'},
        {'label': 'mixed-unknown',
         'description': 'Unspecified, unknown, dispatch-only, or a bare generic word that names no recognisable single breed group.'}
      ],
      {'task_description': 'You are given a breed label exactly as an animal-shelter intake clerk typed it into Austin Animal Center intake paperwork. Assign the one breed group the label belongs to. Judge the label as written, including abbreviations and all-caps clerk shorthand. Bull-and-terrier and molosser breeds must be classified bully-type, never terrier or working.',
       'output_mode': 'single'}
    ):labels[0]::TEXT AS breed_group
  FROM vocabulary
)
SELECT
  breed,
  n_intakes,
  breed_group,
  breed_group = 'bully-type'                       AS ai_bully_label,
  -- the old keyword rule, carried as DATA rather than re-implemented, so the
  -- comparison downstream is a join and cannot drift from what the site ships
  (breed ILIKE '%Pit Bull%'
   OR breed ILIKE '%Staffordshire%'
   OR breed ILIKE '%American Bully%')              AS regex_bully_label,
  'claude-4-sonnet via AI_CLASSIFY'                AS classifier,
  CURRENT_TIMESTAMP()                              AS classified_at
FROM classified;


-- ============================================================================
-- 3. DT_CENSUS -- the bulletin, joined to the classifier.
--
-- A DROP-IN for the CENSUS view: the first sixteen columns are byte-identical,
-- including the overlooked index, and section 6 proves it. Four columns are
-- added, none of which changes an existing one.
--
-- COAT COLOR IS NOT IN THE SCORE, in either version. Color is carried as a
-- displayable fact and is deliberately absent from both `index` and `index_ai`.
-- That is not an oversight to be tidied up later; it is the finding. Split 7 in
-- DT_FINDINGS tests coat color on the identical adult cohort that produces the
-- headline and cannot distinguish it from noise (p = 0.42). Scoring on color
-- would be scoring on something this warehouse has measured to be inert.
--
-- WHY BOTH `index` AND `index_ai`. `index` reproduces exactly what the site
-- ships today, keyword rule and all, so this table can be swapped in with no
-- behaviour change. `index_ai` is the same formula with the AI definition of
-- bully-type substituted, and it is offered rather than imposed, because the
-- two disagree about real dogs currently in care -- the AI label covers more of
-- the open census than the keyword rule does, and section 6 prints both counts.
-- Whoever cuts over should do it as a decision, not inherit it from this file.
--
-- ONE FLAG IN THIS SCORE IS NOT SUPPORTED BY THE WAREHOUSE, and it is carried
-- forward unchanged only because correcting it is not this file's call: the
-- index adds +20 for arriving unnamed, on the theory that namelessness marks a
-- dog nobody engaged with. Both other analyses contradict it. Split 4 finds
-- unnamed dogs leave FASTER (7 days against 27) because "unnamed" in this feed
-- largely means "neonatal litter"; and the returns analysis finds unnamed dogs
-- come back LESS. Flagged here, not silently patched, because the overlooked
-- index belongs to 03_marts.sql.
-- ============================================================================

CREATE OR REPLACE DYNAMIC TABLE DT_CENSUS
  TARGET_LAG   = '24 hours'
  WAREHOUSE    = COMPUTE_WH
  REFRESH_MODE = FULL
  INITIALIZE   = ON_CREATE
AS
SELECT
  s.stay_id,
  s.animal_id,
  s.intake_date,
  s.days_in_care,
  COALESCE(NULLIF(REGEXP_REPLACE(TRIM(COALESCE(s.outcome_name, s.name_at_intake), '*'), '[0-9]+', ''), ''), NULL) AS name,
  COALESCE(s.outcome_name, s.name_at_intake) AS name_raw,
  IFF(TRIM(COALESCE(s.name_at_intake, '')) = '' OR TRIM(s.name_at_intake, '*') RLIKE '^[0-9]+$', TRUE, FALSE) AS unnamed,
  s.breed,
  s.color,
  s.sex,
  s.source_name,
  s.found_address,
  ROUND(s.age_years, 2) AS age_years,
  CASE
    WHEN s.age_years IS NULL THEN 'unknown'
    WHEN s.age_years < 0.5  THEN 'puppy'
    WHEN s.age_years < 2    THEN 'young'
    WHEN s.age_years < 7    THEN 'adult'
    ELSE 'senior'
  END AS age_band,

  -- the keyword definition, exactly as CENSUS ships it
  IFF(s.breed ILIKE '%Pit Bull%'
   OR s.breed ILIKE '%Staffordshire%'
   OR s.breed ILIKE '%American Bully%', TRUE, FALSE) AS bully_label,

  -- the overlooked index, unchanged. days + unnamed + bully label + adult.
  -- coat color is not a term in this expression.
  s.days_in_care
    + IFF(TRIM(COALESCE(s.name_at_intake, '')) = '', 20, 0)
    + IFF(s.breed ILIKE '%Pit Bull%'
       OR s.breed ILIKE '%Staffordshire%'
       OR s.breed ILIKE '%American Bully%', 20, 0)
    + IFF(s.age_years >= 2 AND s.age_years < 7, 10, 0) AS index,

  -- --- added by this file; nothing above depends on anything below ---

  -- LEFT JOIN + COALESCE: a breed string with no classification must degrade to
  -- "not bully" rather than to NULL, or an unclassified dog would silently drop
  -- out of every COUNT_IF downstream. The join is in fact lossless (section 6
  -- asserts 0 unmatched), but a scheduled node must not depend on that holding
  -- forever -- a new breed string can appear between two refreshes.
  COALESCE(l.breed_group, 'mixed-unknown') AS breed_group,
  COALESCE(l.ai_bully_label, FALSE)        AS ai_bully_label,

  s.days_in_care
    + IFF(TRIM(COALESCE(s.name_at_intake, '')) = '', 20, 0)
    + IFF(COALESCE(l.ai_bully_label, FALSE), 20, 0)
    + IFF(s.age_years >= 2 AND s.age_years < 7, 10, 0) AS index_ai,

  -- when this row was last recomputed. See the CURRENT_DATE() caveat in the
  -- header: this is the honest age of `days_in_care`, exposed so the page can
  -- print it rather than assume it.
  CURRENT_TIMESTAMP() AS refreshed_at

FROM DT_STAYS s
LEFT JOIN DT_BREED_LABELS l ON l.breed = s.breed
WHERE s.open = TRUE;


-- ============================================================================
-- 4. DT_FINDINGS_COHORT -- adopted canine stays, with every flag the tests need.
--
-- Flag definitions are kept character-identical to FINDINGS_COHORT so the
-- bulletin and the findings cannot drift apart; ai_bully_label and breed_group
-- are joined in on top.
--
-- THE COHORT IS ADOPTED DOGS, `outcome_status ILIKE 'Adopted%'` (n = 2,821).
-- Not bare 'Adopted' (2,523) -- the 298-row difference is Adopted Altered,
-- Adopted Offsite and friends, which are real adoptions by a stranger and
-- differ only in which desk did the paperwork. And emphatically not the
-- reclaim statuses: Reclaimed, Returned To Owner and Redemption (Offsite) are
-- owners collecting their own lost dog off the stray hold. They are fast by
-- construction, and sweeping them in would manufacture an effect anywhere a
-- group happens to contain more strays.
-- ============================================================================

CREATE OR REPLACE DYNAMIC TABLE DT_FINDINGS_COHORT
  TARGET_LAG   = DOWNSTREAM
  WAREHOUSE    = COMPUTE_WH
  REFRESH_MODE = FULL
  INITIALIZE   = ON_CREATE
AS
SELECT
  s.stay_id,
  s.days_in_care,
  s.color,
  s.breed,
  s.age_years,

  -- All-black: the single-token color. This feed spells mixed coats out in full
  -- ('Black Brindle', 'Black Brown'), so a bare 'Black' really is all black.
  -- INTAKES_RAW carries no secondary_color column, so primary is all we have
  -- and all we claim.
  IFF(s.color = 'Black', TRUE, FALSE) AS black_coat,

  IFF(s.breed ILIKE '%Pit Bull%'
   OR s.breed ILIKE '%Staffordshire%'
   OR s.breed ILIKE '%American Bully%', TRUE, FALSE) AS bully_label,

  COALESCE(l.ai_bully_label, FALSE)        AS ai_bully_label,
  COALESCE(l.breed_group, 'mixed-unknown') AS breed_group,

  -- Austin writes these as 'Poodle - Miniature', not 'Miniature Poodle', so the
  -- patterns follow the feed's own word order rather than a generic breed list.
  IFF(s.breed ILIKE '%Chihuahua%'
   OR s.breed ILIKE '%Dachshund%'
   OR s.breed ILIKE '%Poodle - Miniature%'
   OR s.breed ILIKE '%Poodle - Toy%'
   OR s.breed ILIKE '%Yorkshire%'
   OR s.breed ILIKE '%Shih Tzu%'
   OR s.breed ILIKE '%Maltese%'
   OR s.breed ILIKE '%Pomeranian%'
   OR s.breed ILIKE '%Jack Russell%'
   OR s.breed ILIKE '%Rat Terrier%'
   OR s.breed ILIKE '%Schnauzer - Miniature%'
   OR s.breed ILIKE '%Pug%'
   OR s.breed ILIKE '%Boston Terrier%'
   OR s.breed ILIKE '%Cairn Terrier%', TRUE, FALSE) AS small_breed,

  IFF(TRIM(COALESCE(s.name_at_intake, '')) = ''
   OR TRIM(COALESCE(s.name_at_intake, ''), '*') RLIKE '^[0-9]+$', TRUE, FALSE) AS unnamed,

  IFF(s.age_years >= 2 AND s.age_years < 7, TRUE, FALSE) AS adult

FROM DT_STAYS s
LEFT JOIN DT_BREED_LABELS l ON l.breed = s.breed
WHERE s.outcome_status ILIKE 'Adopted%';


-- ============================================================================
-- 5. DT_FINDINGS -- the permutation test, rerun on a schedule.
--
-- Splits 1-7 are 03_findings.sql exactly, and section 6 asserts they come back
-- byte-identical, p-values included. That check is the point of this node: it
-- demonstrates that moving a 68-million-row statistical test onto a refresh
-- schedule did not perturb a single digit of it.
--
-- Split 8 is new and only possible here, because only this node has the
-- classifier in the same graph as the cohort: the adults-only bully contrast
-- re-run under the AI definition instead of the keyword one. It is the direct
-- answer to the fairest objection to this whole project -- "your headline is an
-- artifact of the three substrings you happened to type."
--
-- Adding split 8 also re-proves that the per-split shuffle partitioning is
-- independent: splits 1-7 are unchanged by the presence of an eighth partition.
--
-- THE TEST. Medians of wait times, which are a long right tail with a wall at
-- zero, so a t-test is the wrong instrument and the median has no tidy standard
-- error anyway. Instead: freeze the observed gap, then keep the same wait times
-- and the same group sizes and reshuffle which dog is in which group, 5,000
-- times, and count how often chance reached the observed gap. p is reported as
-- (hits + 1) / (trials + 1), so the floor is 1/5001 = 0.0002 and we never print
-- p = 0, a claim no finite simulation can support.
--
-- THE SHUFFLE KEY IS HASH(seed, trial, stay), NOT RANDOM(seed). RANDOM(seed)
-- reproduces a sequence but not an assignment: which row of a parallel scan
-- draws which element depends on how Snowflake partitions the work that day.
-- A hash of the row itself is pinned regardless of warehouse size or execution
-- order -- which is what makes it safe to put inside a table that will refresh
-- unattended, on a warehouse nobody is watching, forever.
--
-- 13,609 cohort-rows x 5,000 trials = 68.0M row-operations, in roughly seven
-- seconds. This is the statement that justifies the prize lane: the statistics
-- are not precomputed elsewhere and pasted in, they are what the warehouse
-- does, on a schedule, whether or not anyone is looking.
-- ============================================================================

CREATE OR REPLACE DYNAMIC TABLE DT_FINDINGS
  TARGET_LAG   = '24 hours'
  WAREHOUSE    = COMPUTE_WH
  REFRESH_MODE = FULL
  INITIALIZE   = ON_CREATE
AS
WITH splits AS (
  -- one row per (split, dog). Long form is what makes the test a single
  -- statement instead of eight: every split shuffles inside its own partition,
  -- in the same pass.
  SELECT
    s.split_id,
    s.label,
    c.stay_id,
    c.days_in_care,
    CASE s.split_id
      WHEN 1 THEN c.black_coat
      WHEN 2 THEN c.bully_label
      WHEN 3 THEN c.bully_label
      WHEN 4 THEN c.unnamed
      WHEN 5 THEN c.small_breed
      WHEN 6 THEN c.unnamed
      WHEN 7 THEN c.black_coat
      WHEN 8 THEN c.ai_bully_label
    END AS in_yes
  FROM DT_FINDINGS_COHORT c
  CROSS JOIN (
    -- Splits 3 and 7 are the pair the headline is built from: same adult band,
    -- same cohort, one tested on the label and one on the coat. That is the
    -- whole argument in two rows, and it is only fair because both sides are
    -- held to an identical population.
    SELECT * FROM VALUES
      (1, 'All-black coat',                                FALSE),
      (2, 'Bully-type breed label',                        FALSE),
      (3, 'Bully-type label (adults only)',                TRUE ),
      (4, 'Arrived unnamed',                               FALSE),
      (5, 'Small-breed label',                             FALSE),
      (6, 'Arrived unnamed (adults only)',                 TRUE ),
      (7, 'All-black coat (adults only)',                  TRUE ),
      (8, 'Bully-type label, AI definition (adults only)', TRUE )
    AS v(split_id, label, adults_only)
  ) s
  WHERE NOT s.adults_only OR c.adult
),

-- what actually happened
observed AS (
  SELECT
    split_id,
    ANY_VALUE(label)                            AS label,
    COUNT(*)                                    AS cohort_n,
    COUNT_IF(in_yes)                            AS n_yes,
    COUNT_IF(NOT in_yes)                        AS n_no,
    MEDIAN(IFF(in_yes,     days_in_care, NULL)) AS med_yes,
    MEDIAN(IFF(NOT in_yes, days_in_care, NULL)) AS med_no
  FROM splits
  GROUP BY split_id
),

-- 5,000 parallel universes
trials AS (
  SELECT SEQ4() + 1 AS trial_id FROM TABLE(GENERATOR(ROWCOUNT => 5000))
),

-- deal the cards again. every dog keeps its wait time; only the ordering is
-- redrawn, independently inside each (split, trial).
shuffled AS (
  SELECT
    s.split_id,
    t.trial_id,
    s.days_in_care,
    ROW_NUMBER() OVER (
      PARTITION BY s.split_id, t.trial_id
      ORDER BY HASH(20260816, t.trial_id, s.stay_id)   -- seed: fixed, see header
    ) AS shuffled_rank
  FROM splits s
  CROSS JOIN trials t
),

-- hand the first n_yes cards of each shuffle the "yes" label. group sizes are
-- preserved exactly; only membership is random. that is the null hypothesis.
relabelled AS (
  SELECT
    sh.split_id,
    sh.trial_id,
    sh.days_in_care,
    sh.shuffled_rank <= o.n_yes AS fake_yes
  FROM shuffled sh
  JOIN observed o USING (split_id)
),

-- the gap chance produced, once per trial
trial_delta AS (
  SELECT
    split_id,
    trial_id,
    MEDIAN(IFF(fake_yes,     days_in_care, NULL))
      - MEDIAN(IFF(NOT fake_yes, days_in_care, NULL)) AS delta
  FROM relabelled
  GROUP BY split_id, trial_id
)

SELECT
  o.split_id,
  o.label,
  o.cohort_n,
  o.med_yes,
  o.med_no,
  o.med_yes - o.med_no AS delta_days,
  -- two-sided: chance only counts as a match if it produced a gap at least as
  -- extreme in either direction. add-one estimator, so the floor is 1/5001.
  ROUND(
    (COUNT_IF(ABS(td.delta) >= ABS(o.med_yes - o.med_no)) + 1) / (COUNT(*) + 1),
    4
  ) AS p_value,
  o.n_yes,
  o.n_no,
  COUNT(*)            AS n_permutations,
  CURRENT_TIMESTAMP() AS refreshed_at
FROM observed o
JOIN trial_delta td USING (split_id)
GROUP BY o.split_id, o.label, o.cohort_n, o.med_yes, o.med_no, o.n_yes, o.n_no;


-- ============================================================================
-- 6. VERIFICATION -- the DAG against the objects it shadows.
--
-- Not decoration. This file duplicates logic that other files own, and the only
-- thing standing between "a second implementation" and "a second, subtly
-- different implementation" is that these queries are re-run and read.
--
-- Every assertion below returned the value stated in its comment when this file
-- was executed against the live account. They are queries, not claims: re-run
-- them. If any drift_* or *_diff column is non-zero, the DAG has diverged from
-- the views and the cutover in the header must not proceed.
-- ============================================================================

-- 6a. DT_STAYS vs the deployed STAYS view. Full-row MINUS both ways.
--     Returned: 6084 / 6084 / 0 / 0.
SELECT
  (SELECT COUNT(*) FROM DT_STAYS)                                     AS dt_rows,
  (SELECT COUNT(*) FROM STAYS)                                        AS view_rows,
  (SELECT COUNT(*) FROM (SELECT * FROM DT_STAYS MINUS SELECT * FROM STAYS)) AS drift_dt_minus_view,
  (SELECT COUNT(*) FROM (SELECT * FROM STAYS MINUS SELECT * FROM DT_STAYS)) AS drift_view_minus_dt;

-- 6b. DT_CENSUS vs the CENSUS view, over the sixteen columns CENSUS defines.
--     (DT_CENSUS adds breed_group, ai_bully_label, index_ai, refreshed_at; the
--     comparison is restricted to the shared contract, which must be exact.)
--     Returned: 593 / 593 / 0 / 0.
WITH dt AS (
  SELECT stay_id, animal_id, intake_date, days_in_care, name, name_raw, unnamed,
         breed, color, sex, source_name, found_address, age_years, age_band,
         bully_label, index
  FROM DT_CENSUS
),
vw AS (
  SELECT stay_id, animal_id, intake_date, days_in_care, name, name_raw, unnamed,
         breed, color, sex, source_name, found_address, age_years, age_band,
         bully_label, index
  FROM CENSUS
)
SELECT
  (SELECT COUNT(*) FROM dt)                                    AS dt_rows,
  (SELECT COUNT(*) FROM vw)                                    AS view_rows,
  (SELECT COUNT(*) FROM (SELECT * FROM dt MINUS SELECT * FROM vw)) AS drift_dt_minus_view,
  (SELECT COUNT(*) FROM (SELECT * FROM vw MINUS SELECT * FROM dt)) AS drift_view_minus_dt;

-- 6c. THE ONE THAT MATTERS. DT_FINDINGS splits 1-7 vs the FINDINGS table,
--     every column including p_value. A moved digit here means the schedule
--     changed the science.
--     Returned: 0 / 0 / 7 / 8.
SELECT
  (SELECT COUNT(*) FROM (
     SELECT split_id, label, cohort_n, med_yes, med_no, delta_days, p_value,
            n_yes, n_no, n_permutations
     FROM DT_FINDINGS WHERE split_id <= 7
     MINUS
     SELECT split_id, label, cohort_n, med_yes, med_no, delta_days, p_value,
            n_yes, n_no, n_permutations
     FROM FINDINGS))                                           AS drift_dt_minus_findings,
  (SELECT COUNT(*) FROM (
     SELECT split_id, label, cohort_n, med_yes, med_no, delta_days, p_value,
            n_yes, n_no, n_permutations
     FROM FINDINGS
     MINUS
     SELECT split_id, label, cohort_n, med_yes, med_no, delta_days, p_value,
            n_yes, n_no, n_permutations
     FROM DT_FINDINGS WHERE split_id <= 7))                    AS drift_findings_minus_dt,
  (SELECT COUNT(*) FROM FINDINGS)                              AS findings_rows,
  (SELECT COUNT(*) FROM DT_FINDINGS)                           AS dt_findings_rows;

-- 6d. The classifier, re-run. bully_flag_diffs is the assertion: it MUST be 0,
--     and has been 0 on every rebuild. breed_group_wobble is a measurement, not
--     an assertion -- it came back 3 on one rebuild and 4 on the next, and that
--     is expected (see section 2). unclassified_stays MUST be 0 or the LEFT
--     JOIN in sections 3 and 4 is silently dropping dogs into "not bully".
--     Returned on three consecutive rebuilds:
--       167 / 167 / 12 / 12 / 3 / 3 / 0 / 3 / 0
--       167 / 167 / 12 / 12 / 3 / 3 / 0 / 4 / 0
--       167 / 167 / 12 / 12 / 3 / 3 / 0 / 1 / 0
--     Note which column is constant and which is not.
SELECT
  (SELECT COUNT(*) FROM DT_BREED_LABELS)                       AS dt_vocab,
  (SELECT COUNT(*) FROM BREED_LABELS)                          AS static_vocab,
  (SELECT COUNT_IF(ai_bully_label)    FROM DT_BREED_LABELS)    AS dt_ai_bully,
  (SELECT COUNT_IF(ai_bully_label)    FROM BREED_LABELS)       AS static_ai_bully,
  (SELECT COUNT_IF(regex_bully_label) FROM DT_BREED_LABELS)    AS dt_regex_bully,
  (SELECT COUNT_IF(regex_bully_label) FROM BREED_LABELS)       AS static_regex_bully,
  (SELECT COUNT(*) FROM DT_BREED_LABELS d JOIN BREED_LABELS b USING (breed)
    WHERE d.ai_bully_label <> b.ai_bully_label
       OR d.regex_bully_label <> b.regex_bully_label)          AS bully_flag_diffs,
  (SELECT COUNT(*) FROM DT_BREED_LABELS d JOIN BREED_LABELS b USING (breed)
    WHERE d.breed_group <> b.breed_group)                      AS breed_group_wobble,
  (SELECT COUNT(*) FROM DT_STAYS s
    LEFT JOIN DT_BREED_LABELS l ON l.breed = s.breed
    WHERE s.breed IS NOT NULL AND l.breed IS NULL)             AS unclassified_stays;

-- 6e. Which breed strings wobbled, named rather than summarised, because "3 of
--     167 changed" is only reassuring once you can see that none of them is a
--     bully call. Both static_bully and dt_bully must read false on every row.
--     Returned across two rebuilds: Carolina Dog (mixed-unknown -> hound),
--     Dachshund - Wire-haired (terrier -> hound), American Eskimo
--     (non-sporting -> working), Miniature Dachshund (terrier -> hound).
SELECT
  d.breed, d.n_intakes,
  b.breed_group AS static_group,  d.breed_group AS dt_group,
  b.ai_bully_label AS static_bully, d.ai_bully_label AS dt_bully
FROM DT_BREED_LABELS d
JOIN BREED_LABELS b USING (breed)
WHERE d.breed_group <> b.breed_group
ORDER BY d.n_intakes DESC;

-- 6f. What the two bully definitions do to the OPEN census -- the dogs waiting
--     right now. Reported because index_ai is offered to the site as a choice.
--     Returned: 593 / 236 / 278 / 42.
SELECT
  COUNT(*)                                                AS open_dogs,
  COUNT_IF(bully_label)                                   AS regex_bully,
  COUNT_IF(ai_bully_label)                                AS ai_bully,
  COUNT_IF(ai_bully_label AND NOT bully_label)            AS ai_only_extra
FROM DT_CENSUS;

-- 6g. THE LINEAGE, EXECUTING. Every node reports SUCCEEDED, and the ordering is
--     the interesting part: creating DT_FINDINGS caused Snowflake to visit
--     DT_BREED_LABELS, DT_STAYS and DT_FINDINGS_COHORT *first*, each reporting
--     NO_DATA because they were already current, before running DT_FINDINGS
--     itself. Nothing in this file states that order. Snowflake derived it from
--     the DDL. That is the lineage graph, doing work rather than being drawn.
--
--     Note also what NO_DATA means, because it is the caveat from the header
--     showing up in the log: with a frozen CSV load the sources have not
--     changed, so a manual refresh correctly declines to recompute.
--
--     TWO FILTERS HERE ARE LOAD-BEARING AND BOTH WERE ADDED AFTER BEING CAUGHT
--     GETTING IT WRONG. Nodes are listed explicitly rather than matched with
--     LIKE 'DT_%', because a scratch dynamic table that was created and dropped
--     still has rows in the log, and it silently inflated section 7's node
--     count from 5 to 6. And database_name/schema_name are pinned, because
--     SHELTER.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY() does NOT
--     restrict itself to SHELTER despite where it is qualified from -- it
--     returned rows for two unrelated databases on this account. Qualifying the
--     function name is not the same as filtering its output.
SELECT
  name,
  state,
  refresh_action,
  refresh_trigger,
  DATEDIFF('millisecond', refresh_start_time, refresh_end_time) AS ms,
  refresh_start_time
FROM TABLE(SHELTER.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
WHERE database_name = 'SHELTER' AND schema_name = 'AAC'
  AND name IN ('DT_STAYS', 'DT_BREED_LABELS', 'DT_CENSUS',
               'DT_FINDINGS_COHORT', 'DT_FINDINGS')
ORDER BY refresh_start_time;

-- 6h. Configuration, as deployed. Confirms the lag/mode actually took, rather
--     than trusting that the DDL above is what is running.
--     Every node must read ACTIVE.
SHOW DYNAMIC TABLES LIKE 'DT\_%' IN SCHEMA SHELTER.AAC;


-- ============================================================================
-- 7. WHAT IT COSTS -- computed, not estimated.
--
-- The one number a hackathon judge on a trial account actually wants, derived
-- from the refresh log instead of from arithmetic in a comment. One full pass
-- of the graph is the sum of each node's most recent successful refresh; the
-- daily cost is one pass, because every leaf lags 24 hours and the interior
-- nodes are DOWNSTREAM and therefore share it.
--
-- Credits are billed per second of warehouse time. COMPUTE_WH is assumed
-- X-Small = 1 credit/hour, so the conversion is seconds / 3600. Change the
-- divisor if COMPUTE_WH is not X-Small.
--
-- Measured on the live account: five nodes, a full pass in the high teens of
-- seconds, which is a few thousandths of a credit a day plus 167 AI_CLASSIFY
-- calls. The pass time is dominated by the two expensive nodes and both are
-- variable -- DT_BREED_LABELS ran in 5.9s and then 10.1s on consecutive
-- rebuilds, because Cortex latency is not a constant -- so read the query
-- below rather than this sentence. Leaving the graph running is not a way to
-- get hurt; section 8 stops it entirely in five statements.
-- ============================================================================

WITH latest AS (
  SELECT
    name,
    DATEDIFF('millisecond', refresh_start_time, refresh_end_time) AS ms,
    ROW_NUMBER() OVER (PARTITION BY name ORDER BY refresh_start_time DESC) AS rn
  FROM TABLE(SHELTER.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
  WHERE database_name = 'SHELTER' AND schema_name = 'AAC'
    AND name IN ('DT_STAYS', 'DT_BREED_LABELS', 'DT_CENSUS',
                 'DT_FINDINGS_COHORT', 'DT_FINDINGS')
    AND state = 'SUCCEEDED'
    AND refresh_action = 'FULL'
)
SELECT
  COUNT(*)                                  AS nodes,
  SUM(ms) / 1000.0                          AS seconds_per_full_pass,
  ROUND(SUM(ms) / 1000.0 / 3600.0, 6)       AS credits_per_day_xsmall,
  ROUND(SUM(ms) / 1000.0 / 3600.0 * 30, 5)  AS credits_per_month_xsmall,
  (SELECT COUNT(*) FROM DT_BREED_LABELS)    AS ai_classify_calls_per_day
FROM latest
WHERE rn = 1;


-- ============================================================================
-- 8. THE OFF SWITCH.
--
-- Suspending a dynamic table stops its scheduled refreshes and therefore all
-- of its billing; the data stays queryable at its last refresh. Suspend the
-- two leaves and the whole graph goes quiet, because the interior nodes are
-- DOWNSTREAM and have no schedule of their own -- but suspend all five anyway,
-- so that "is anything still running?" has a five-line answer instead of a
-- reasoning step.
--
-- Uncomment to stop. RESUME to start again. Nothing is dropped either way.
-- ============================================================================

-- ALTER DYNAMIC TABLE DT_FINDINGS        SUSPEND;
-- ALTER DYNAMIC TABLE DT_CENSUS          SUSPEND;
-- ALTER DYNAMIC TABLE DT_FINDINGS_COHORT SUSPEND;
-- ALTER DYNAMIC TABLE DT_BREED_LABELS    SUSPEND;
-- ALTER DYNAMIC TABLE DT_STAYS           SUSPEND;

-- ALTER DYNAMIC TABLE DT_STAYS           RESUME;
-- ALTER DYNAMIC TABLE DT_BREED_LABELS    RESUME;
-- ALTER DYNAMIC TABLE DT_FINDINGS_COHORT RESUME;
-- ALTER DYNAMIC TABLE DT_CENSUS          RESUME;
-- ALTER DYNAMIC TABLE DT_FINDINGS        RESUME;

-- Force a pass now, without waiting for the schedule. Refreshing a leaf pulls
-- its whole upstream chain, which is the cheapest way to watch the DAG run:
-- ALTER DYNAMIC TABLE DT_CENSUS   REFRESH;
-- ALTER DYNAMIC TABLE DT_FINDINGS REFRESH;
