-- Census + overlooked index. Coat color is intentionally not in the score.

USE SCHEMA SHELTER.AAC;

CREATE OR REPLACE VIEW CENSUS AS
SELECT
  stay_id,
  animal_id,
  intake_date,
  days_in_care,
  COALESCE(NULLIF(REGEXP_REPLACE(TRIM(COALESCE(outcome_name, name_at_intake), '*'), '[0-9]+', ''), ''), NULL) AS name,
  COALESCE(outcome_name, name_at_intake) AS name_raw,
  IFF(TRIM(COALESCE(name_at_intake, '')) = '' OR TRIM(name_at_intake, '*') RLIKE '^[0-9]+$', TRUE, FALSE) AS unnamed,
  breed,
  color,
  sex,
  source_name,
  found_address,
  ROUND(age_years, 2) AS age_years,
  CASE
    WHEN age_years IS NULL THEN 'unknown'
    WHEN age_years < 0.5 THEN 'puppy'
    WHEN age_years < 2 THEN 'young'
    WHEN age_years < 7 THEN 'adult'
    ELSE 'senior'
  END AS age_band,
  IFF(
    breed ILIKE '%Pit Bull%' OR breed ILIKE '%Staffordshire%' OR breed ILIKE '%American Bully%',
    TRUE, FALSE
  ) AS bully_label,
  days_in_care
    + IFF(TRIM(COALESCE(name_at_intake, '')) = '', 20, 0)
    + IFF(breed ILIKE '%Pit Bull%' OR breed ILIKE '%Staffordshire%' OR breed ILIKE '%American Bully%', 20, 0)
    + IFF(age_years >= 2 AND age_years < 7, 10, 0) AS index
FROM STAYS
WHERE open = TRUE;

-- FINDINGS_PUBLISHED used to be defined here as five UNION ALL rows of
-- hand-typed constants ('All-black coat', 28.0, 28.0, 0.0, 1.0 ...). Those
-- numbers were never computed against SHELTER.AAC -- and when they finally
-- were, three of the five turned out to be wrong, one of them backwards.
--
-- The findings are now genuinely computed, by a permutation test that runs in
-- the warehouse. See sql/03_findings.sql, which builds:
--
--   SHELTER.AAC.FINDINGS_COHORT   adopted canine stays + label flags
--   SHELTER.AAC.FINDINGS_SPLITS   one row per (split, dog)
--   SHELTER.AAC.FINDINGS          label, cohort_n, med_yes, med_no,
--                                 delta_days, p_value, n_yes, n_no
--   SHELTER.AAC.FINDINGS_PUBLISHED  compatibility alias over FINDINGS
--
-- Run order: 01_setup.sql -> 02_stays.sql -> 03_marts.sql -> 03_findings.sql.
-- Do not reintroduce a literal statistic in this file.
