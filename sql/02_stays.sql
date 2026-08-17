-- Stay pairing: animal_id is reused. Pair each dog intake to the earliest
-- outcome on or after that intake. Unmatched = still in care.
--
-- Two things here are easy to get wrong and both silently corrupt every
-- downstream number:
--
-- 1. COHORT. The feed's `type` column separates 'Puppy' from 'Dog'. Filtering
--    on type = 'Dog' quietly drops ~492 puppy intakes and ~407 puppy outcomes,
--    which biases every wait-time split (puppies leave fast). Dogs are
--    ('Dog','Puppy').
--
-- 2. PAIRING. A plain JOIN ON animal_id fans a repeat visitor's intake out
--    across all of its outcomes. The earlier LEFT JOIN LATERAL ... QUALIFY
--    formulation had the opposite failure: it dropped every unmatched intake,
--    so open stays -- the entire bulletin -- came back empty, and the
--    correlated subquery forced a nested loop that never finished.
--
--    The fix is a plain LEFT JOIN plus a window function. ORDER BY
--    outcome_date NULLS LAST keeps the no-outcome row when a dog is still in
--    care, so open stays survive. Hash join instead of nested loop.

USE SCHEMA SHELTER.AAC;

CREATE OR REPLACE VIEW STAYS AS
SELECT
  i.id AS stay_id,
  i.animal_id,
  i.source_date::DATE AS intake_date,
  o.outcome_date::DATE AS outcome_date,
  o.outcome_status,
  IFF(o.outcome_date IS NULL, TRUE, FALSE) AS open,
  DATEDIFF('day', i.source_date::DATE, COALESCE(o.outcome_date::DATE, CURRENT_DATE())) AS days_in_care,
  i.name_at_intake,
  o.name AS outcome_name,
  i.primary_breed AS breed,
  i.primary_color AS color,
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
