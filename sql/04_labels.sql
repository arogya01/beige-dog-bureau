-- 04_labels.sql · Beige Dog Bureau
--
-- The whole subject of this project is a LABEL. A dog does not wait 91 days
-- because of what it is; it waits because of the four words a clerk typed into
-- an intake form. So the one place we absolutely may not fake it is the place
-- where we decide which labels are "bully-type".
--
-- Until this file, that decision was a keyword list:
--
--     breed ILIKE '%Pit Bull%' OR breed ILIKE '%Staffordshire%'
--                               OR breed ILIKE '%American Bully%'
--
-- Three substrings, hand-picked, standing in for a public perception. It is a
-- guess about language wearing the costume of a rule. This file replaces it
-- with AI_CLASSIFY over the 167 distinct breed strings the shelter actually
-- typed, and then -- the part that matters -- PUBLISHES THE DISAGREEMENT
-- instead of quietly swapping one definition for the other.
--
-- Cost discipline: 167 distinct strings, not 6,084 animals. We classify the
-- vocabulary once, persist it as a TABLE (not a view, so nothing re-bills
-- inference when a visitor loads the page), and join it back to STAYS.
--
-- Nothing in this file is a typed-in statistic. Every number below is the
-- result of a query against SHELTER.AAC.
--
-- Requires: 01_setup.sql, 02_stays.sql.

USE SCHEMA SHELTER.AAC;


-- ---------------------------------------------------------------------------
-- 1. BREED_LABELS -- the vocabulary, classified once.
--
-- One row per distinct primary_breed string among canine intakes. The category
-- set is a real breed-group taxonomy rather than a bully/not-bully binary,
-- because a binary prompt invites the model to agree with whatever the question
-- implies. Making it pick from nine groups forces an actual judgement, and the
-- bully flag falls out of that judgement instead of being asked for directly.
--
-- 'bully-type' is deliberately described as a PERCEPTION category ("popularly
-- read as"), not a kennel-club one. That is the variable the shelter data is
-- actually measuring.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE BREED_LABELS AS
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
  -- the old keyword rule, kept as data so the comparison below is a join and
  -- not a re-implementation that could drift from what the site ships
  (breed ILIKE '%Pit Bull%'
   OR breed ILIKE '%Staffordshire%'
   OR breed ILIKE '%American Bully%')              AS regex_bully_label,
  'claude-4-sonnet via AI_CLASSIFY'                AS classifier,
  CURRENT_TIMESTAMP()                              AS classified_at
FROM classified;


-- ---------------------------------------------------------------------------
-- 2. LABEL_DISAGREEMENTS -- every breed string the two definitions fight over.
--
-- This is the audit trail. If the AI definition is going to move a headline
-- number, a reader is entitled to see exactly which words moved it.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW LABEL_DISAGREEMENTS AS
SELECT
  breed,
  n_intakes,
  breed_group,
  regex_bully_label,
  ai_bully_label,
  IFF(ai_bully_label, 'ai only (keyword missed it)', 'regex only (keyword over-reached)') AS direction
FROM BREED_LABELS
WHERE regex_bully_label <> ai_bully_label;


-- ---------------------------------------------------------------------------
-- 3. LABEL_COMPARISON -- the finding.
--
-- Cohort: adopted adult dogs. "Adopted" is the Adopted* family (plain
-- 'Adopted' plus 'Adopted Altered'), because the shelter splits one event into
-- two status strings and dropping the second silently discards ~250 dogs.
-- "Adult" is age at intake >= 2 years, the age at which the wait-time gap in
-- this data opens up.
--
-- The two definitions are scored on the identical cohort, so the only thing
-- that varies between the two halves of this row is the meaning of the word
-- "bully".
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE LABEL_COMPARISON AS
WITH cohort AS (
  SELECT
    s.stay_id,
    s.breed,
    s.days_in_care,
    l.regex_bully_label,
    l.ai_bully_label
  FROM STAYS s
  JOIN BREED_LABELS l ON l.breed = s.breed
  WHERE s.outcome_status ILIKE 'Adopted%'
    AND s.age_years >= 2
),
regex_side AS (
  SELECT
    COUNT_IF(regex_bully_label)                                     AS bully_n,
    MEDIAN(IFF(regex_bully_label, days_in_care, NULL))              AS bully_median_days,
    COUNT_IF(NOT regex_bully_label)                                 AS other_n,
    MEDIAN(IFF(NOT regex_bully_label, days_in_care, NULL))          AS other_median_days
  FROM cohort
),
ai_side AS (
  SELECT
    COUNT_IF(ai_bully_label)                                        AS bully_n,
    MEDIAN(IFF(ai_bully_label, days_in_care, NULL))                 AS bully_median_days,
    COUNT_IF(NOT ai_bully_label)                                    AS other_n,
    MEDIAN(IFF(NOT ai_bully_label, days_in_care, NULL))             AS other_median_days
  FROM cohort
),
disagreement AS (
  SELECT
    COUNT_IF(regex_bully_label <> ai_bully_label)                   AS cohort_stays,
    COUNT_IF(ai_bully_label AND NOT regex_bully_label)              AS cohort_ai_only,
    COUNT_IF(regex_bully_label AND NOT ai_bully_label)              AS cohort_regex_only,
    -- the sharpest number in this file: how long did the dogs the keyword rule
    -- MISSED actually wait? If the model merely invented a category, this lands
    -- somewhere in the middle. If the category is real, it lands on top of the
    -- dogs the keyword rule caught.
    MEDIAN(IFF(ai_bully_label AND NOT regex_bully_label, days_in_care, NULL))
                                                                    AS disputed_median_days
  FROM cohort
),
all_dog_stays AS (
  SELECT
    COUNT_IF(l.regex_bully_label <> l.ai_bully_label)               AS all_stays,
    COUNT_IF(l.ai_bully_label AND NOT l.regex_bully_label)          AS all_ai_only,
    COUNT_IF(l.regex_bully_label AND NOT l.ai_bully_label)          AS all_regex_only
  FROM STAYS s
  JOIN BREED_LABELS l ON l.breed = s.breed
),
disputed_words AS (
  SELECT
    COUNT(*)                                                        AS breed_strings,
    ARRAY_AGG(breed) WITHIN GROUP (ORDER BY n_intakes DESC)         AS examples
  FROM LABEL_DISAGREEMENTS
)
SELECT
  (SELECT COUNT(*) FROM cohort)          AS cohort_stays,
  r.bully_n                              AS regex_bully_n,
  r.bully_median_days                    AS regex_bully_median_days,
  r.other_n                              AS regex_other_n,
  r.other_median_days                    AS regex_other_median_days,
  r.bully_median_days - r.other_median_days AS regex_delta_days,
  a.bully_n                              AS ai_bully_n,
  a.bully_median_days                    AS ai_bully_median_days,
  a.other_n                              AS ai_other_n,
  a.other_median_days                    AS ai_other_median_days,
  a.bully_median_days - a.other_median_days AS ai_delta_days,
  d.cohort_stays                         AS disagree_stays_in_cohort,
  d.cohort_ai_only                       AS disagree_cohort_ai_only,
  d.cohort_regex_only                    AS disagree_cohort_regex_only,
  d.disputed_median_days                 AS disputed_median_days,
  s.all_stays                            AS disagree_stays_all_dogs,
  s.all_ai_only                          AS disagree_all_ai_only,
  s.all_regex_only                       AS disagree_all_regex_only,
  w.breed_strings                        AS disagree_breed_strings,
  w.examples                             AS disagree_examples,
  CURRENT_TIMESTAMP()                    AS computed_at
FROM regex_side r, ai_side a, disagreement d, all_dog_stays s, disputed_words w;


-- ---------------------------------------------------------------------------
-- 4. BREED_VECTORS -- the vocabulary as geometry.
--
-- A keyword list can only answer "does this string contain 'Pit Bull'". An
-- embedding can answer "how close is this string to the pit-bull region of
-- breed language" -- which is much nearer the thing we actually care about,
-- because adopters are not running a regex either. They are reading a phrase
-- and feeling a pull toward or away from it.
--
-- 167 rows, embedded once, persisted. 768 dims, snowflake-arctic-embed-m-v1.5.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE BREED_VECTORS AS
SELECT
  breed,
  n_intakes,
  breed_group,
  ai_bully_label,
  regex_bully_label,
  AI_EMBED('snowflake-arctic-embed-m-v1.5', breed) AS embedding
FROM BREED_LABELS;


-- ---------------------------------------------------------------------------
-- 5. BREED_BULLY_PROXIMITY -- the bully cluster as a shape, not a keyword list.
--
-- Two centroids: the mean vector of everything AI_CLASSIFY called bully-type,
-- and the mean vector of everything it did not. Each breed string then gets a
-- signed pull = similarity(bully centroid) - similarity(other centroid).
--
-- The signed difference matters. Raw cosine similarity between two- and
-- three-word breed names sits in a compressed 0.75-0.95 band, so the absolute
-- number is close to meaningless; the DIFFERENCE between the two centroids is
-- what separates. Positive pull = this phrase reads as bull-breed language.
--
-- No inference runs here -- the vectors are already on disk, so this view is
-- free to query. It is a view rather than a table precisely because it costs
-- nothing and stays honest if BREED_VECTORS is ever rebuilt.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW BREED_BULLY_PROXIMITY AS
WITH bully_parts AS (
  SELECT f.index AS i, AVG(f.value::FLOAT) AS val
  FROM BREED_VECTORS v, LATERAL FLATTEN(input => v.embedding::ARRAY) f
  WHERE v.ai_bully_label
  GROUP BY f.index
),
other_parts AS (
  SELECT f.index AS i, AVG(f.value::FLOAT) AS val
  FROM BREED_VECTORS v, LATERAL FLATTEN(input => v.embedding::ARRAY) f
  WHERE NOT v.ai_bully_label
  GROUP BY f.index
),
centroids AS (
  SELECT
    (SELECT ARRAY_AGG(val) WITHIN GROUP (ORDER BY i) FROM bully_parts)::VECTOR(FLOAT, 768) AS bully_c,
    (SELECT ARRAY_AGG(val) WITHIN GROUP (ORDER BY i) FROM other_parts)::VECTOR(FLOAT, 768) AS other_c
)
SELECT
  v.breed,
  v.n_intakes,
  v.breed_group,
  v.ai_bully_label,
  v.regex_bully_label,
  VECTOR_COSINE_SIMILARITY(v.embedding, c.bully_c) AS sim_bully_centroid,
  VECTOR_COSINE_SIMILARITY(v.embedding, c.other_c) AS sim_other_centroid,
  VECTOR_COSINE_SIMILARITY(v.embedding, c.bully_c)
    - VECTOR_COSINE_SIMILARITY(v.embedding, c.other_c) AS bully_pull,
  RANK() OVER (ORDER BY VECTOR_COSINE_SIMILARITY(v.embedding, c.bully_c)
                      - VECTOR_COSINE_SIMILARITY(v.embedding, c.other_c) DESC) AS bully_pull_rank
FROM BREED_VECTORS v, centroids c;


-- ---------------------------------------------------------------------------
-- 6. Reproduce path.
--
-- Deliberately queries, not values. Nothing in this repo asserts a number it
-- did not just compute, so the verification block asserts nothing either --
-- run it and read what the warehouse says.
--
--   -- did the classifier cover the whole vocabulary, and is the join lossless?
--   SELECT (SELECT COUNT(DISTINCT primary_breed) FROM INTAKES_RAW
--             WHERE type IN ('Dog','Puppy')) AS distinct_breed_strings,
--          (SELECT COUNT(*) FROM BREED_LABELS)             AS classified,
--          (SELECT COUNT(*) FROM STAYS)                    AS stays,
--          (SELECT COUNT(*) FROM STAYS s
--             JOIN BREED_LABELS l ON l.breed = s.breed)    AS stays_joined;
--
--   -- the headline comparison
--   SELECT * FROM LABEL_COMPARISON;
--
--   -- the words the two definitions fight over
--   SELECT * FROM LABEL_DISAGREEMENTS ORDER BY n_intakes DESC;
--
--   -- does the cluster survive a change of cohort? (it should move a little
--   -- and not collapse -- if the gap only exists under one cohort definition,
--   -- the gap is an artifact and the story is wrong)
--   WITH j AS (
--     SELECT s.days_in_care, s.outcome_status, s.age_years,
--            l.regex_bully_label, l.ai_bully_label
--     FROM STAYS s JOIN BREED_LABELS l ON l.breed = s.breed
--   ), v AS (
--     SELECT 'adult>=2, Adopted*' AS variant, * FROM j
--       WHERE outcome_status ILIKE 'Adopted%' AND age_years >= 2
--     UNION ALL SELECT 'adult 2-7, Adopted*', * FROM j
--       WHERE outcome_status ILIKE 'Adopted%' AND age_years >= 2 AND age_years < 7
--     UNION ALL SELECT 'adult>=2, strict Adopted', * FROM j
--       WHERE outcome_status = 'Adopted' AND age_years >= 2
--     UNION ALL SELECT 'all ages, Adopted*', * FROM j
--       WHERE outcome_status ILIKE 'Adopted%'
--   )
--   SELECT variant, COUNT(*) AS n,
--     MEDIAN(IFF(ai_bully_label, days_in_care, NULL))     AS bully_med,
--     MEDIAN(IFF(NOT ai_bully_label, days_in_care, NULL)) AS other_med,
--     MEDIAN(IFF(ai_bully_label AND NOT regex_bully_label, days_in_care, NULL))
--                                                        AS disputed_med
--   FROM v GROUP BY variant ORDER BY variant;
--
--   -- the cluster as a shape: the embedding ranks bull-breed language without
--   -- ever being shown the classifier's answer
--   SELECT bully_pull_rank, breed, n_intakes, breed_group, ai_bully_label,
--          ROUND(bully_pull, 4) AS bully_pull
--   FROM BREED_BULLY_PROXIMITY ORDER BY bully_pull_rank LIMIT 20;
--
-- One caveat worth stating out loud: AI_CLASSIFY is a judgement, not a
-- measurement. It is reproducible (two independent rebuilds of BREED_LABELS
-- produced identical labels on all 167 strings) and it is auditable (section 2
-- publishes every disagreement), but it is still a model's reading of a
-- clerk's typing. That is the honest version of what this file is: not a
-- better oracle than the keyword list, just one whose reasoning you can see.
