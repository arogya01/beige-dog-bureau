export type FindingSplit = {
  label: string;
  n_yes: number;
  med_yes: number;
  n_no: number;
  med_no: number;
  delta: number;
  p: number;
};

export type DogStay = {
  stay_id: string;
  animal_id: string;
  intake_date: string;
  outcome_date: string | null;
  outcome_status: string | null;
  open: boolean;
  days_in_care: number;
  name: string;
  name_raw: string;
  unnamed: boolean;
  breed: string;
  color: string;
  sex: string;
  source_name: string;
  found_address: string;
  age_years: number | null;
  age_band: string;
  bully_label: boolean;
  senior: boolean;
  adult: boolean;
  index: number;
};

export type CensusPayload = {
  generated_at: string;
  as_of: string;
  source: "snapshot" | "snowflake";
  open_count: number;
  stay_count: number;
  findings: {
    cohort_n: number;
    splits: FindingSplit[];
    bully_adult: FindingSplit;
    black_adult: FindingSplit;
  };
  dogs: DogStay[];
};
