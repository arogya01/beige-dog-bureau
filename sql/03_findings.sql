-- ============================================================================
-- Beige Dog Bureau · SHELTER.AAC.FINDINGS
-- The published splits, computed in the warehouse. Nothing here is typed in.
-- ============================================================================
--
-- WHAT THIS REPLACES
--
-- The first version of this project shipped a view called FINDINGS_PUBLISHED
-- whose body was, literally:
--
--     SELECT 'All-black coat' AS label, 28.0, 28.0, 0.0, 1.0
--     UNION ALL SELECT 'Bully label (adult)', 91.0, 32.0, 59.0, 0.0002 ...
--
-- Five rows of hand-typed constants wearing a warehouse costume. For a bulletin
-- whose entire pitch is "here are the receipts", the receipts were forged. This
-- file deletes that idea. Every number below is produced by a query that reads
-- SHELTER.AAC.STAYS, and re-running this file reproduces them exactly.
--
--
-- THE COHORT: ADOPTED DOGS ONLY
--
-- outcome_status has 25 distinct values in this feed. Three of them look like
-- an exit but are not an adoption: `Reclaimed` (890 stays, median 3 days),
-- `Returned To Owner` (6) and `Redemption (Offsite)` (37, median 0 days). Those
-- are owners collecting their own lost dog off the stray hold. They are fast by
-- construction and they have nothing to do with whether a stranger chose this
-- dog. Sweeping them into the cohort would drag every median down and
-- manufacture an effect wherever a group happens to contain more strays.
--
-- The adopted family is `outcome_status ILIKE 'Adopted%'`:
--   Adopted 2523, Adopted Altered 246, Adopted Offsite(Altered) 18,
--   Adopted Unaltered 17, Adopted Offsite 12, Adopted Offsite(Unaltered) 5
--   = 2821 stays.
-- Bare `= 'Adopted'` would be 2523 and would silently drop 298 real adoptions
-- for no reason other than which desk processed the paperwork. We take all six.
--
--
-- THE TEST: A PERMUTATION TEST, IN SQL
--
-- We are comparing medians of two groups of wait times. Wait times are not
-- normal -- they are a long right tail with a wall at zero -- so a t-test is
-- the wrong instrument, and the median has no tidy closed-form standard error
-- anyway. The honest answer is to ask the data directly:
--
--   "If the label meant nothing, how often would pure chance deal me a gap at
--    least this big?"
--
-- So we deal the cards again, 5,000 times per split:
--
--   1. Freeze the observed gap:  delta = median(yes) - median(no).
--   2. Keep the same wait times and the same group sizes, but reshuffle which
--      dog is in which group -- 5,000 independent reshuffles.
--   3. Recompute the gap inside every reshuffle.
--   4. p = how often a reshuffled |gap| reached the observed |gap|.
--
-- If the label carries no information, the observed gap is just one draw from
-- that reshuffled pile and p lands high. If p is at the floor, chance never
-- once matched what the label does.
--
-- We report p as (hits + 1) / (trials + 1), the add-one estimator. 5,000
-- reshuffles cannot resolve a probability below 1/5001, so we never print
-- p = 0 -- a claim no finite simulation can support. The floor is 0.0002.
--
--
-- WHY A WAREHOUSE
--
-- 13,609 cohort rows x 5,000 trials = 68.0 million rows, each needing a
-- partitioned sort and then a median per group per trial. On a laptop this is a
-- coffee break and a fan. Snowflake does it in one statement, in seconds,
-- because the shuffle is a window function over a hash-partitioned scan and it
-- spreads across the cluster for free. This is the single query that justifies
-- the whole prize lane: the statistics are not precomputed somewhere else and
-- copied in, they are what the warehouse does.
--
--
-- REPRODUCIBILITY
--
-- The shuffle key is HASH(<seed>, trial_id, stay_id), not RANDOM(seed).
-- RANDOM(seed) reproduces a *sequence*, but which row of a parallel scan draws
-- which element of that sequence depends on how Snowflake happens to partition
-- the work that day -- so it is reproducible in theory and not in practice.
-- A hash of (seed, trial, stay) is pinned to the row itself: same seed, same
-- permutation, on any warehouse size, in any order, forever. Change the literal
-- 20260816 below and you get a different, equally valid, 5,000 reshuffles.
--
--
-- ONE RESULT THAT MOVED, AND WHY IT IS LEFT ALONE
--
-- The old hardcoded table claimed unnamed dogs wait LONGER (38.5 vs 27 days).
-- Computed against this feed, unnamed dogs leave far FASTER (7 vs 27). That is
-- not a bug: 205 of the 315 dogs who arrive with no name are under six months
-- old. "Unnamed" in this data is largely a synonym for "neonatal litter", and
-- puppies go home fast. Split 6 exists to say so out loud -- it re-runs the
-- same test inside the adult band, where the confound is held still. We publish
-- the number we computed, including when it contradicts the number we shipped.
--
-- ============================================================================

USE SCHEMA SHELTER.AAC;


-- ----------------------------------------------------------------------------
-- 1. The cohort. One row per adopted canine stay, with every label flag the
--    splits need. Flag definitions are kept identical to CENSUS so the bulletin
--    and the findings cannot drift apart.
--
--    Note what is NOT a flag anywhere downstream of here: nothing about coat
--    color enters the overlooked index. Color is tested (split 1) and then
--    deliberately discarded, because the test is how we learned it is inert.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW SHELTER.AAC.FINDINGS_COHORT AS
SELECT
  stay_id,
  days_in_care,
  color,
  breed,
  age_years,

  -- All-black: the single-token color. This feed spells mixed coats out in
  -- full ('Black Brindle', 'Black Brown'), so a bare 'Black' really is all
  -- black. INTAKES_RAW carries no secondary_color column, so primary is all we
  -- have and all we claim.
  IFF(color = 'Black', TRUE, FALSE) AS black_coat,

  -- Same three patterns the overlooked index uses.
  IFF(breed ILIKE '%Pit Bull%'
   OR breed ILIKE '%Staffordshire%'
   OR breed ILIKE '%American Bully%', TRUE, FALSE) AS bully_label,

  -- Austin writes these as 'Poodle - Miniature', not 'Miniature Poodle', so the
  -- patterns follow the feed's own word order rather than a generic breed list.
  IFF(breed ILIKE '%Chihuahua%'
   OR breed ILIKE '%Dachshund%'
   OR breed ILIKE '%Poodle - Miniature%'
   OR breed ILIKE '%Poodle - Toy%'
   OR breed ILIKE '%Yorkshire%'
   OR breed ILIKE '%Shih Tzu%'
   OR breed ILIKE '%Maltese%'
   OR breed ILIKE '%Pomeranian%'
   OR breed ILIKE '%Jack Russell%'
   OR breed ILIKE '%Rat Terrier%'
   OR breed ILIKE '%Schnauzer - Miniature%'
   OR breed ILIKE '%Pug%'
   OR breed ILIKE '%Boston Terrier%'
   OR breed ILIKE '%Cairn Terrier%', TRUE, FALSE) AS small_breed,

  -- Arrived with no name on the intake record. A handful arrive tagged with a
  -- bare number instead, which is the same thing wearing a different hat.
  IFF(TRIM(COALESCE(name_at_intake, '')) = ''
   OR TRIM(COALESCE(name_at_intake, ''), '*') RLIKE '^[0-9]+$', TRUE, FALSE) AS unnamed,

  -- Same band cuts as CENSUS. Age is age at intake, so a stay that closed a
  -- year ago does not age along with the wall clock.
  IFF(age_years >= 2 AND age_years < 7, TRUE, FALSE) AS adult

FROM SHELTER.AAC.STAYS
WHERE outcome_status ILIKE 'Adopted%';


-- ----------------------------------------------------------------------------
-- 2. The splits, long. One row per (split, dog). Splits 3, 6 and 7 restrict the
--    cohort to the adult band; the rest run over all adopted dogs.
--
--    Splits 3 and 7 are the pair the bulletin's headline is built from: the
--    same age band, the same cohort, one tested on the label and one on the
--    coat. That is the whole argument in two rows, and it is only fair because
--    both sides are held to the identical population.
--
--    Long form is what makes the permutation test a single statement instead of
--    six: every split shuffles inside its own partition, in the same pass.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW SHELTER.AAC.FINDINGS_SPLITS AS
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
  END AS in_yes
FROM SHELTER.AAC.FINDINGS_COHORT c
CROSS JOIN (
  SELECT * FROM VALUES
    (1, 'All-black coat',                  FALSE),
    (2, 'Bully-type breed label',          FALSE),
    (3, 'Bully-type label (adults only)',  TRUE ),
    (4, 'Arrived unnamed',                 FALSE),
    (5, 'Small-breed label',               FALSE),
    (6, 'Arrived unnamed (adults only)',   TRUE ),
    (7, 'All-black coat (adults only)',    TRUE )
  AS v(split_id, label, adults_only)
) s
WHERE NOT s.adults_only OR c.adult;


-- ----------------------------------------------------------------------------
-- 3. FINDINGS. The permutation test.
--
--    Materialized as a table, not a view, on purpose: this is 68 million row
--    operations and the bulletin reads it on every page load. The DDL is the
--    provenance -- re-run this statement and you get byte-identical numbers.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE SHELTER.AAC.FINDINGS AS
WITH
-- What actually happened.
observed AS (
  SELECT
    split_id,
    ANY_VALUE(label)                                AS label,
    COUNT(*)                                        AS cohort_n,
    COUNT_IF(in_yes)                                AS n_yes,
    COUNT_IF(NOT in_yes)                            AS n_no,
    MEDIAN(IFF(in_yes,     days_in_care, NULL))     AS med_yes,
    MEDIAN(IFF(NOT in_yes, days_in_care, NULL))     AS med_no
  FROM SHELTER.AAC.FINDINGS_SPLITS
  GROUP BY split_id
),

-- 5,000 parallel universes.
trials AS (
  SELECT SEQ4() + 1 AS trial_id
  FROM TABLE(GENERATOR(ROWCOUNT => 5000))
),

-- Deal the cards again. Every dog keeps its wait time; only the ordering is
-- redrawn, independently inside each (split, trial). 68.0M rows land here.
shuffled AS (
  SELECT
    s.split_id,
    t.trial_id,
    s.days_in_care,
    ROW_NUMBER() OVER (
      PARTITION BY s.split_id, t.trial_id
      ORDER BY HASH(20260816, t.trial_id, s.stay_id)   -- seed: fixed, see header
    ) AS shuffled_rank
  FROM SHELTER.AAC.FINDINGS_SPLITS s
  CROSS JOIN trials t
),

-- Hand the first n_yes cards of each shuffle the "yes" label. Group sizes are
-- preserved exactly; only membership is random. That is the null hypothesis.
relabelled AS (
  SELECT
    sh.split_id,
    sh.trial_id,
    sh.days_in_care,
    sh.shuffled_rank <= o.n_yes AS fake_yes
  FROM shuffled sh
  JOIN observed o USING (split_id)
),

-- The gap chance produced, once per trial.
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
  -- Two-sided: chance only counts as a match if it produced a gap at least as
  -- extreme in either direction. Add-one estimator, so the floor is 1/5001.
  ROUND(
    (COUNT_IF(ABS(td.delta) >= ABS(o.med_yes - o.med_no)) + 1)
      / (COUNT(*) + 1),
    4
  ) AS p_value,
  o.n_yes,
  o.n_no,
  COUNT(*) AS n_permutations
FROM observed o
JOIN trial_delta td USING (split_id)
GROUP BY o.split_id, o.label, o.cohort_n, o.med_yes, o.med_no, o.n_yes, o.n_no
ORDER BY o.split_id;


-- ----------------------------------------------------------------------------
-- 4. FINDINGS_PUBLISHED, retired in place.
--
--    This name used to be the hardcoded view (its body was five UNION ALLs of
--    typed-in constants; see the header). It still exists in the warehouse, so
--    rather than drop it and leave a demo or a worksheet pointing at a missing
--    object, we redefine it as a thin alias over the computed table using the
--    old column names. Anything still asking for FINDINGS_PUBLISHED now gets
--    real numbers instead of forged ones.
--
--    New code should read SHELTER.AAC.FINDINGS directly.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW SHELTER.AAC.FINDINGS_PUBLISHED AS
SELECT
  label,
  med_yes,
  med_no,
  delta_days AS delta,
  p_value    AS p
FROM SHELTER.AAC.FINDINGS
ORDER BY split_id;
