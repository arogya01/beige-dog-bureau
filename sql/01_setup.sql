-- Beige Dog Bureau · Snowflake DAG
-- Paste into a Snowsight worksheet as ACCOUNTADMIN. Then run scripts/load_snowflake.py
-- or load the CSVs via Data → Add Data.

CREATE DATABASE IF NOT EXISTS SHELTER;
CREATE SCHEMA IF NOT EXISTS SHELTER.AAC;
USE SCHEMA SHELTER.AAC;

CREATE OR REPLACE TABLE INTAKES_RAW (
  id TEXT,
  source_date TIMESTAMP_NTZ,
  animal_id TEXT,
  type TEXT,
  source_name TEXT,
  name_at_intake TEXT,
  ispreviouslyspayedneutered BOOLEAN,
  sex TEXT,
  primary_breed TEXT,
  primary_color TEXT,
  date_of_birth TIMESTAMP_NTZ,
  found_address TEXT,
  timestamp TIMESTAMP_NTZ
);

CREATE OR REPLACE TABLE OUTCOMES_RAW (
  id TEXT,
  outcome_date TIMESTAMP_NTZ,
  animal_id TEXT,
  name TEXT,
  outcome_status TEXT,
  euthanasia_reason TEXT,
  type TEXT,
  sex TEXT,
  spayed_neutered TEXT,
  primary_breed TEXT,
  primary_color TEXT,
  secondary_color TEXT,
  date_of_birth TIMESTAMP_NTZ,
  intake_date TIMESTAMP_NTZ,
  days_in_shelter NUMBER,
  timestamp TIMESTAMP_NTZ
);
