-- ============================================================================
-- 06_returns.sql · The dogs that come back
--
-- Beige Dog Bureau · Austin Animal Center open data · SHELTER.AAC
--
-- Every number this file produces is computed here, against the warehouse.
-- Nothing below is a typed-in constant. Re-running this script reproduces the
-- same p-values exactly: the permutation shuffles are seeded from
-- HASH(stay_id, replicate), not RANDOM(), so the receipts are deterministic.
--
-- ----------------------------------------------------------------------------
-- WHY THIS EXISTS
--
-- animal_id is reused. 343 of the 5,685 canine animal_ids in this window have
-- more than one stay, accounting for 399 repeat admissions. A JOIN ON
-- animal_id silently fans those out and merges a dog's second life into its
-- first. SHELTER.AAC.STAYS already pairs each intake to the earliest outcome
-- at-or-after it, so the return question is answerable here and almost
-- nowhere else.
--
-- ----------------------------------------------------------------------------
-- DEFINITIONS (all of them are choices; all of them are stated)
--
-- EXIT           one closed stay: an intake that has a paired outcome.
-- RETURN         the same animal_id is admitted again, on or after the date of
--                that exit's outcome. Gap is measured in whole days from
--                outcome_date to the next intake_date.
--                Same-day (gap = 0) counts as a return: STAYS truncates to
--                DATE, and spot-checking the raw timestamps shows these are
--                genuine -- e.g. animal 26684 was adopted and readmitted 50
--                minutes later. Negative gaps do NOT count; there are 4, all
--                caused by the 4 stays that share an outcome row, and they are
--                labelled data_artifact rather than silently dropped.
-- OBS_END        MAX(intake_date) over STAYS -- the last day the feed could
--                have recorded a return.
-- FOLLOWUP_DAYS  OBS_END - outcome_date. A dog adopted last week has not had
--                time to come back; counting it as "did not return" biases the
--                rate down. Every rate below is therefore reported twice:
--                once uncensored, and once inside a fixed window.
-- WINDOW         180 days. Chosen before testing, for two reasons: it is the
--                conventional return-to-shelter horizon in shelter medicine,
--                and 368 of the 394 observed returns land inside it. An exit
--                enters the windowed analysis only if FOLLOWUP_DAYS >= 180.
-- ADOPTED        outcome_status ILIKE 'Adopted%'. This is the Adopted family
--                (Adopted, Adopted Altered, Adopted Offsite, ...), n = 2,821,
--                not the bare 'Adopted' string, n = 2,523. Adopted Altered is
--                an adoption. Stated because the two differ by 298 dogs.
--
-- ----------------------------------------------------------------------------
-- STATISTICS
--
-- Two-sided permutation tests, 5,000 replicates, so the smallest reportable
-- p is 1/5001 = 0.0002. Labels are shuffled; the outcome column is never
-- touched. Rates are compared as a difference in proportions.
--
-- Six PRIMARY tests are declared up front and all six are published, whichever
-- way they come out, so nothing can be quietly dropped. Holm-Bonferroni is
-- applied across that family of six -- with six shots at the data, a raw
-- p of 0.03 is not a finding, and the table says so in a column.
--
-- Four ROBUSTNESS tests repeat the demographic contrasts with the shuffle
-- confined WITHIN age band, holding age composition fixed, to answer "is this
-- just puppies?" before anyone asks.
--
-- Two OMNIBUS tests guard the intake-source claim. The targeted two-group test
-- answers "do owner-surrendered dogs come back more?". The size-weighted
-- omnibus answers "does return rate vary by source at all?". The selected-max
-- test answers the different and much weaker question "is the source with the
-- highest observed rate really the highest?" -- it is reported because the
-- answer is no, and a table that scanned seven sources for a maximum owes the
-- reader that number.
--
-- DESCRIPTIVE rows carry p_value = NULL and tested = FALSE. They are counts
-- and medians, not claims, and the view labels them that way.
-- ============================================================================

USE SCHEMA SHELTER.AAC;


-- ----------------------------------------------------------------------------
-- 1. RETURNS -- one row per exit (closed stay), with what happened next.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW RETURNS AS
WITH horizon AS (
  SELECT MAX(intake_date) AS obs_end FROM STAYS
),
chained AS (
  -- Next admission for THIS animal, by intake order. LEAD over the correctly
  -- paired stay sequence -- not a self-join on animal_id, which would pair a
  -- dog's first exit with its third intake as readily as its second.
  SELECT
    s.*,
    LEAD(s.intake_date)  OVER (PARTITION BY s.animal_id ORDER BY s.intake_date, s.stay_id) AS next_intake_date,
    LEAD(s.stay_id)      OVER (PARTITION BY s.animal_id ORDER BY s.intake_date, s.stay_id) AS next_stay_id,
    LEAD(s.source_name)  OVER (PARTITION BY s.animal_id ORDER BY s.intake_date, s.stay_id) AS next_source_name
  FROM STAYS s
),
gapped AS (
  SELECT
    c.*,
    h.obs_end,
    DATEDIFF('day', c.outcome_date, h.obs_end)          AS followup_days,
    DATEDIFF('day', c.outcome_date, c.next_intake_date) AS raw_gap_days
  FROM chained c CROSS JOIN horizon h
  WHERE c.outcome_date IS NOT NULL          -- an exit must have happened
)
SELECT
  stay_id,
  animal_id,
  intake_date,
  outcome_date,
  outcome_status,
  obs_end,
  followup_days,

  -- exit cohort
  outcome_status ILIKE 'Adopted%' AS adopted,
  CASE
    WHEN outcome_status ILIKE 'Adopted%'                                            THEN 'adopted'
    WHEN outcome_status IN ('Reclaimed', 'Redemption (Offsite)', 'Returned To Owner') THEN 'reclaimed by owner'
    WHEN outcome_status = 'Transfer Out'                                            THEN 'transferred out'
    ELSE 'other exit'
  END AS exit_cohort,

  -- the return itself
  IFF(raw_gap_days >= 0, next_stay_id,       NULL) AS return_stay_id,
  IFF(raw_gap_days >= 0, next_intake_date,   NULL) AS return_date,
  IFF(raw_gap_days >= 0, next_source_name,   NULL) AS return_source_name,
  IFF(raw_gap_days >= 0, raw_gap_days,       NULL) AS days_to_return,
  -- COALESCE, not a bare comparison. raw_gap_days is NULL for every dog that
  -- never came back, and NULL >= 0 is NULL, not FALSE -- so COUNT_IF(NOT
  -- returned_ever) would have counted 3 non-returners instead of 2,543 and
  -- every denominator downstream would have been silently wrong.
  COALESCE(raw_gap_days >= 0, FALSE)               AS returned_ever,
  COALESCE(raw_gap_days BETWEEN 0 AND 180, FALSE)  AS returned_180,
  (followup_days >= 180)                           AS eligible_180,
  COALESCE(raw_gap_days < 0, FALSE)                AS data_artifact,

  -- WHO brought the dog back. An adopter handing a dog back and an animal
  -- control officer scooping the same dog off a road are not the same event
  -- and must never be averaged together.
  CASE
    WHEN raw_gap_days < 0 OR raw_gap_days IS NULL                   THEN NULL
    WHEN next_source_name = 'Returns'                               THEN 'handed back: adoption return'
    WHEN next_source_name ILIKE '%Owner Surrender%'
      OR next_source_name = 'Abandoned'                             THEN 'handed back: surrendered'
    WHEN next_source_name IN ('Stray', 'ACO - Impound', 'Ambulance',
                              'Community Animal - Field Services')  THEN 'picked up loose again'
    ELSE 'other / agency'
  END AS return_kind,

  -- predictors, defined identically to CENSUS so the two views cannot drift
  source_name,
  breed,
  color,
  sex,
  ROUND(age_years, 2) AS age_years,
  CASE
    WHEN age_years IS NULL  THEN 'unknown'
    WHEN age_years < 0.5    THEN 'puppy'
    WHEN age_years < 2      THEN 'young'
    WHEN age_years < 7      THEN 'adult'
    ELSE 'senior'
  END AS age_band,
  IFF(breed ILIKE '%Pit Bull%' OR breed ILIKE '%Staffordshire%' OR breed ILIKE '%American Bully%',
      TRUE, FALSE) AS bully_label,
  IFF(TRIM(COALESCE(name_at_intake, '')) = '' OR TRIM(name_at_intake, '*') RLIKE '^[0-9]+$',
      TRUE, FALSE) AS unnamed,
  -- INTAKES_RAW carries no secondary_color, so this is "primary colour on the
  -- intake record is Black", not "no white anywhere". Named honestly.
  IFF(UPPER(TRIM(color)) = 'BLACK', TRUE, FALSE) AS black_coat,
  IFF(source_name ILIKE '%Owner Surrender%', TRUE, FALSE) AS came_in_surrendered
FROM gapped;


-- ----------------------------------------------------------------------------
-- 2. RETURNS_TESTS -- materialised permutation results.
--
--    Materialised, not a view, because 5,000 replicates x 1,594 exits x 10
--    contrasts is not something to recompute on every page load. Deterministic,
--    because the shuffle key is HASH(stay_id, replicate): re-running this CTAS
--    reproduces these p-values to the digit.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE RETURNS_TESTS AS
WITH cohort AS (
  -- Adopted exits with a full 180 days of follow-up. One cohort for every
  -- proportion test, so the tests are comparable to each other.
  SELECT * FROM RETURNS WHERE adopted AND eligible_180
),
panel AS (
  -- family='primary'    -> stratum 'all'      (plain shuffle)
  -- family='robustness' -> stratum = age_band (shuffle within age band)
  SELECT 'bully_label' AS finding_key, 'primary' AS family,
         'Bully-type breed label' AS label,
         'bully-labelled' AS group_yes, 'every other label' AS group_no,
         stay_id AS rid, 'all' AS stratum, bully_label AS g,
         IFF(returned_180, 1, 0)::FLOAT AS y
  FROM cohort
  UNION ALL SELECT 'unnamed', 'primary', 'Arrived with no name',
         'unnamed at intake', 'named at intake',
         stay_id, 'all', unnamed, IFF(returned_180, 1, 0)::FLOAT FROM cohort
  UNION ALL SELECT 'adult', 'primary', 'Adult at intake (2-7 years)',
         'adult', 'puppy, young or senior',
         stay_id, 'all', age_band = 'adult', IFF(returned_180, 1, 0)::FLOAT FROM cohort
  UNION ALL SELECT 'senior', 'primary', 'Senior at intake (7 years or older)',
         'senior', 'under 7',
         stay_id, 'all', age_band = 'senior', IFF(returned_180, 1, 0)::FLOAT FROM cohort
  UNION ALL SELECT 'black_coat', 'primary', 'Primary colour recorded as Black',
         'black coat', 'every other coat',
         stay_id, 'all', black_coat, IFF(returned_180, 1, 0)::FLOAT FROM cohort
  UNION ALL SELECT 'came_in_surrendered', 'primary', 'Came in as an owner surrender',
         'owner-surrendered', 'stray, impound or agency',
         stay_id, 'all', came_in_surrendered, IFF(returned_180, 1, 0)::FLOAT FROM cohort

  UNION ALL SELECT 'bully_label_by_age', 'robustness', 'Bully-type label, shuffled within age band',
         'bully-labelled', 'every other label',
         stay_id, age_band, bully_label, IFF(returned_180, 1, 0)::FLOAT FROM cohort
  UNION ALL SELECT 'unnamed_by_age', 'robustness', 'No name at intake, shuffled within age band',
         'unnamed at intake', 'named at intake',
         stay_id, age_band, unnamed, IFF(returned_180, 1, 0)::FLOAT FROM cohort
  UNION ALL SELECT 'black_coat_by_age', 'robustness', 'Black coat, shuffled within age band',
         'black coat', 'every other coat',
         stay_id, age_band, black_coat, IFF(returned_180, 1, 0)::FLOAT FROM cohort
  UNION ALL SELECT 'came_in_surrendered_by_age', 'robustness', 'Owner surrender, shuffled within age band',
         'owner-surrendered', 'stray, impound or agency',
         stay_id, age_band, came_in_surrendered, IFF(returned_180, 1, 0)::FLOAT FROM cohort
),
observed AS (
  SELECT finding_key, ANY_VALUE(family) AS family, ANY_VALUE(label) AS label,
         ANY_VALUE(group_yes) AS group_yes, ANY_VALUE(group_no) AS group_no,
         COUNT_IF(g) AS n_yes, COUNT_IF(NOT g) AS n_no,
         AVG(IFF(g, y, NULL)) AS v_yes, AVG(IFF(NOT g, y, NULL)) AS v_no,
         AVG(IFF(g, y, NULL)) - AVG(IFF(NOT g, y, NULL)) AS d_obs
  FROM panel GROUP BY finding_key
),
slot AS (
  -- how many "yes" labels each stratum is allowed to hand out
  SELECT finding_key, stratum, COUNT_IF(g) AS n_yes_in_stratum
  FROM panel GROUP BY finding_key, stratum
),
reps AS (
  SELECT SEQ4() + 1 AS rep FROM TABLE(GENERATOR(ROWCOUNT => 5000))
),
shuffled AS (
  SELECT p.finding_key, p.stratum, r.rep, p.y,
         ROW_NUMBER() OVER (PARTITION BY p.finding_key, p.stratum, r.rep
                            ORDER BY HASH(p.rid, r.rep)) AS rn
  FROM panel p CROSS JOIN reps r
),
relabelled AS (
  SELECT s.finding_key, s.rep, s.y, (s.rn <= sl.n_yes_in_stratum) AS g_perm
  FROM shuffled s
  JOIN slot sl ON sl.finding_key = s.finding_key AND sl.stratum = s.stratum
),
null_dist AS (
  SELECT finding_key, rep,
         AVG(IFF(g_perm, y, NULL)) - AVG(IFF(NOT g_perm, y, NULL)) AS d_perm
  FROM relabelled GROUP BY finding_key, rep
)
-- The explicit VARCHAR(200) casts are load-bearing: a CTAS sizes its text
-- columns from the literals it happens to see, and the later INSERTs carry
-- longer labels that Snowflake would otherwise refuse rather than truncate.
SELECT
  o.finding_key::VARCHAR(80)  AS finding_key,
  o.family::VARCHAR(20)       AS family,
  o.label::VARCHAR(200)       AS label,
  'adopted exits with 180d follow-up'::VARCHAR(120) AS cohort,
  'return rate within 180 days (percentage points)'::VARCHAR(120) AS metric,
  o.group_yes::VARCHAR(80)    AS group_yes,
  o.group_no::VARCHAR(80)     AS group_no,
  o.n_yes, o.n_no,
  ROUND(100 * o.v_yes, 2)::FLOAT  AS val_yes,
  ROUND(100 * o.v_no,  2)::FLOAT  AS val_no,
  ROUND(100 * o.d_obs, 2)::FLOAT  AS delta,
  -- +1 in numerator and denominator: the observed labelling is itself one of
  -- the possible labellings, so p can never be reported as exactly 0.
  (1 + COUNT_IF(ABS(n.d_perm) >= ABS(o.d_obs) - 1e-12)) / 5001.0 AS p_value,
  5000 AS n_permutations,
  TRUE AS tested
FROM observed o JOIN null_dist n ON n.finding_key = o.finding_key
GROUP BY o.finding_key, o.family, o.label, o.group_yes, o.group_no,
         o.n_yes, o.n_no, o.v_yes, o.v_no, o.d_obs;


-- ----------------------------------------------------------------------------
-- 3. Omnibus guards on the intake-source claim.
--
--    Two different questions, deliberately kept apart:
--      source_varies_at_all  -- size-weighted SUM(n_g * (rate_g - rate)^2).
--                               Does return rate depend on intake source?
--      source_max_is_real    -- MAX(rate_g) over sources with n >= 30.
--                               Having scanned seven sources for a winner,
--                               is the winner distinguishable from noise?
-- ----------------------------------------------------------------------------
INSERT INTO RETURNS_TESTS
WITH cohort AS (
  SELECT stay_id AS rid, source_name AS src, IFF(returned_180, 1, 0)::FLOAT AS y
  FROM RETURNS WHERE adopted AND eligible_180
),
grand AS (SELECT AVG(y) AS r0, COUNT(*) AS n_all FROM cohort),
big AS (SELECT src FROM cohort GROUP BY src HAVING COUNT(*) >= 30),
by_src AS (SELECT src, COUNT(*) AS n, AVG(y) AS r FROM cohort GROUP BY src),
obs_stat AS (
  SELECT
    (SELECT SUM(n * POWER(r - (SELECT r0 FROM grand), 2)) FROM by_src)                        AS x_var,
    (SELECT MAX(b.r) FROM by_src b JOIN big ON big.src = b.src)                               AS x_max,
    (SELECT COUNT(*) FROM big)                                                                AS n_sources
),
reps AS (SELECT SEQ4() + 1 AS rep FROM TABLE(GENERATOR(ROWCOUNT => 5000))),
shuffled AS (
  SELECT r.rep, c.y, ROW_NUMBER() OVER (PARTITION BY r.rep ORDER BY HASH(c.rid, r.rep)) AS rn
  FROM cohort c CROSS JOIN reps r
),
slot AS (
  -- deal the shuffled rows back out into source-sized blocks
  SELECT src, COUNT(*) AS n,
         SUM(COUNT(*)) OVER (ORDER BY src ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS hi,
         SUM(COUNT(*)) OVER (ORDER BY src ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
           - COUNT(*) AS lo
  FROM cohort GROUP BY src
),
assigned AS (
  SELECT sh.rep, sl.src, sh.y
  FROM shuffled sh JOIN slot sl ON sh.rn > sl.lo AND sh.rn <= sl.hi
),
perm_src AS (SELECT rep, src, COUNT(*) AS n, AVG(y) AS r FROM assigned GROUP BY rep, src),
perm_stat AS (
  SELECT p.rep,
         SUM(p.n * POWER(p.r - (SELECT r0 FROM grand), 2)) AS x_var,
         MAX(IFF(big.src IS NOT NULL, p.r, NULL))          AS x_max
  FROM perm_src p LEFT JOIN big ON big.src = p.src
  GROUP BY p.rep
)
SELECT 'source_varies_at_all', 'omnibus',
       'Return rate differs across intake sources (size-weighted)',
       'adopted exits with 180d follow-up',
       'val_yes = sum of n_g * (rate_g - pooled rate)^2. n_yes = exits, n_no = sources compared',
       'adopted exits in the cohort', 'intake sources with n >= 30',
       (SELECT n_all FROM grand), (SELECT n_sources FROM obs_stat),
       ROUND((SELECT x_var FROM obs_stat), 4), NULL, NULL,
       (1 + COUNT_IF(ps.x_var >= (SELECT x_var FROM obs_stat) - 1e-12)) / 5001.0,
       5000, TRUE
FROM perm_stat ps
UNION ALL
SELECT 'source_max_is_real', 'omnibus',
       'The highest-returning intake source is really the highest',
       'adopted exits with 180d follow-up',
       'val_yes = highest observed source return rate (percent). n_yes = exits, n_no = sources scanned',
       'adopted exits in the cohort', 'intake sources with n >= 30',
       (SELECT n_all FROM grand), (SELECT n_sources FROM obs_stat),
       ROUND(100 * (SELECT x_max FROM obs_stat), 2), NULL, NULL,
       (1 + COUNT_IF(ps.x_max >= (SELECT x_max FROM obs_stat) - 1e-12)) / 5001.0,
       5000, TRUE
FROM perm_stat ps;


-- ----------------------------------------------------------------------------
-- 4. How fast they come back, split by who brought them.
--
--    Median gap, permuted. Different cohort from the tests above -- this one is
--    conditional on having returned at all -- so it is kept as its own row with
--    its own stated cohort rather than folded into the primary family.
-- ----------------------------------------------------------------------------
INSERT INTO RETURNS_TESTS
WITH ev AS (
  SELECT stay_id AS rid, days_to_return::FLOAT AS y,
         (return_kind IN ('handed back: adoption return', 'handed back: surrendered')) AS g
  FROM RETURNS
  WHERE returned_ever
    AND return_kind IN ('handed back: adoption return', 'handed back: surrendered',
                        'picked up loose again')
),
tot AS (
  SELECT COUNT_IF(g) AS n_yes, COUNT_IF(NOT g) AS n_no,
         MEDIAN(IFF(g, y, NULL)) AS v_yes, MEDIAN(IFF(NOT g, y, NULL)) AS v_no,
         MEDIAN(IFF(g, y, NULL)) - MEDIAN(IFF(NOT g, y, NULL)) AS d_obs
  FROM ev
),
reps AS (SELECT SEQ4() + 1 AS rep FROM TABLE(GENERATOR(ROWCOUNT => 5000))),
shuffled AS (
  SELECT r.rep, v.y, ROW_NUMBER() OVER (PARTITION BY r.rep ORDER BY HASH(v.rid, r.rep)) AS rn
  FROM ev v CROSS JOIN reps r
),
null_dist AS (
  SELECT rep,
         MEDIAN(IFF(rn <= (SELECT n_yes FROM tot), y, NULL))
       - MEDIAN(IFF(rn >  (SELECT n_yes FROM tot), y, NULL)) AS d_perm
  FROM shuffled GROUP BY rep
)
SELECT 'handback_speed', 'omnibus',
       'Handed back vs picked up loose again: days until the dog is back',
       'the 380 returns with a known route back',
       'median days from outcome to next intake',
       'handed back by a person', 'picked up loose again',
       (SELECT n_yes FROM tot), (SELECT n_no FROM tot),
       (SELECT v_yes FROM tot), (SELECT v_no FROM tot), (SELECT d_obs FROM tot),
       (1 + COUNT_IF(ABS(n.d_perm) >= ABS((SELECT d_obs FROM tot)) - 1e-12)) / 5001.0,
       5000, TRUE
FROM null_dist n;


-- ----------------------------------------------------------------------------
-- 5. RETURNS_FINDINGS -- the publishable table.
--
--    Tests come from RETURNS_TESTS with Holm-Bonferroni applied inside the
--    primary family. Descriptive rows are aggregated live off RETURNS and
--    carry tested = FALSE and p_value = NULL, so nothing in this table can be
--    read as a claim it has not earned.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW RETURNS_FINDINGS AS
WITH ranked AS (
  SELECT t.*,
         ROW_NUMBER() OVER (PARTITION BY family ORDER BY p_value, finding_key) AS rnk,
         COUNT(*)     OVER (PARTITION BY family)                               AS m
  FROM RETURNS_TESTS t
),
holm AS (
  SELECT r.*,
         -- Holm step-down: running max of (m - rank + 1) * p, capped at 1.
         IFF(family = 'primary',
             MAX(LEAST(1.0, (m - rnk + 1) * p_value))
               OVER (PARTITION BY family ORDER BY rnk ROWS UNBOUNDED PRECEDING),
             NULL) AS p_holm
  FROM ranked r
),
tests AS (
  SELECT finding_key, family, label, cohort, metric, group_yes, group_no,
         n_yes, n_no, val_yes, val_no, delta, p_value, p_holm,
         n_permutations, tested,
         CASE
           WHEN family = 'primary' AND p_holm  <= 0.05 THEN 'significant after Holm correction across the six primary tests'
           WHEN family = 'primary' AND p_value <= 0.05 THEN 'nominally significant, does NOT survive Holm correction across six tests'
           WHEN family = 'primary'                     THEN 'no detectable effect'
           -- A robustness row is not an independent finding. It exists only to
           -- show whether its primary twin survives holding age fixed, so it
           -- never gets to announce significance on its own.
           WHEN family = 'robustness' AND p_value <= 0.05
             THEN 'age-stratified check: the effect holds with age composition fixed. Read with the primary row'
           WHEN family = 'robustness'
             THEN 'age-stratified check: still no effect with age composition fixed. Read with the primary row'
           WHEN p_value <= 0.05                        THEN 'significant'
           ELSE 'no detectable effect'
         END AS verdict
  FROM holm
),
-- ---- descriptive rows: counts and medians, never presented as tests --------
d_cohort AS (
  SELECT
    'rate_' || REPLACE(exit_cohort, ' ', '_') AS finding_key,
    'descriptive' AS family,
    'Came back at all, after ' || exit_cohort AS label,
    'all closed stays, uncensored' AS cohort,
    'val_yes = percent of exits followed by another admission. val_no = median days until they were back' AS metric,
    'came back' AS group_yes, 'never came back' AS group_no,
    COUNT_IF(returned_ever) AS n_yes,
    COUNT_IF(NOT returned_ever) AS n_no,
    ROUND(100.0 * COUNT_IF(returned_ever) / COUNT(*), 2) AS val_yes,
    MEDIAN(days_to_return) AS val_no,
    NULL AS delta
  FROM RETURNS GROUP BY exit_cohort
),
d_cohort_windowed AS (
  SELECT
    'rate180_' || REPLACE(exit_cohort, ' ', '_'),
    'descriptive',
    'Came back within 180 days, after ' || exit_cohort,
    'closed stays with a full 180 days of follow-up',
    'val_yes = percent returning inside the window. val_no = median days until they were back',
    'came back inside 180d', 'never came back inside 180d',
    COUNT_IF(returned_180), COUNT_IF(NOT returned_180),
    ROUND(100.0 * COUNT_IF(returned_180) / COUNT(*), 2),
    MEDIAN(IFF(returned_180, days_to_return, NULL)),
    NULL
  FROM RETURNS WHERE eligible_180 GROUP BY exit_cohort
),
d_kind AS (
  SELECT
    'kind_' || REPLACE(REPLACE(REPLACE(return_kind, ' ', '_'), ':', ''), '/', ''),
    'descriptive',
    'Route back: ' || return_kind,
    'the 394 observed returns',
    'val_yes = median days until the dog is back. val_no = 75th percentile of the same gap',
    'returns of this kind', 'of which followed an adoption',
    COUNT(*), COUNT_IF(adopted),
    MEDIAN(days_to_return),
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY days_to_return),
    NULL
  FROM RETURNS WHERE returned_ever GROUP BY return_kind
),
d_source AS (
  SELECT
    'source_' || REPLACE(REPLACE(source_name, ' ', '_'), '-', ''),
    'descriptive',
    'Adopted out after arriving as: ' || source_name,
    'adopted exits with 180d follow-up',
    'val_yes = percent back within 180 days of the adoption',
    'came back inside 180d', 'never came back inside 180d',
    COUNT_IF(returned_180), COUNT_IF(NOT returned_180),
    ROUND(100.0 * COUNT_IF(returned_180) / COUNT(*), 2),
    NULL, NULL
  FROM RETURNS WHERE adopted AND eligible_180
  GROUP BY source_name HAVING COUNT(*) >= 30
),
descriptives AS (
  SELECT finding_key, family, label, cohort, metric, group_yes, group_no,
         n_yes, n_no, val_yes, val_no, delta,
         NULL::FLOAT AS p_value, NULL::FLOAT AS p_holm,
         0 AS n_permutations, FALSE AS tested,
         'descriptive only, not tested' AS verdict
  FROM (
    SELECT * FROM d_cohort
    UNION ALL SELECT * FROM d_cohort_windowed
    UNION ALL SELECT * FROM d_kind
    UNION ALL SELECT * FROM d_source
  )
)
SELECT * FROM tests
UNION ALL
SELECT * FROM descriptives;
