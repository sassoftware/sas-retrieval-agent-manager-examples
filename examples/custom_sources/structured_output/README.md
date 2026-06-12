# Structured Output Custom Source

This folder contains a custom source template that generates synthetic medical records
using structured LLM output and saves them as CSV files for ingestion. The number of
patients generated is controlled by the `NUM_GENERATED_PATIENTS` environment variable
(default: `10`).

## How It Works

When the source runs, it:

1. **Generates synthetic records** — Calls the LLM with a JSON schema derived from the
   Pydantic models below, asking it to produce realistic-but-fictional medical data for
   the requested number of patients.
2. **Validates the output** — Parses and validates the LLM response against the
   `GeneratedData` Pydantic model, which bundles four record types:
   - `PatientRecord` — Demographics: name, date of birth, age, blood type, contact info.
   - `ClinicalEncounter` — Visit records: visit type, attending physician, chief complaint,
     primary/secondary diagnoses (with ICD-10 codes), physician notes, and follow-up details.
   - `LabResult` — Lab orders: panel name, collection/result timestamps, facility, and an
     overall status (`normal`, `abnormal_low`, `abnormal_high`, `critical`).
   - `Medication` — Prescriptions: drug name and class, indication, dose, frequency, route,
     start/end dates, and status.
3. **Writes CSV files** — Serializes each record type to a flat CSV file and saves it:
   - `/tmp/patients.csv`
   - `/tmp/medications.csv`
   - `/tmp/lab_results.csv`
   - `/tmp/clinical_encounters.csv`

## Setup

Follow the [general custom source instructions](../README.md) with these specifics:

- **Environment variables:** Optionally set `NUM_GENERATED_PATIENTS` to control how many
  patient records (and associated encounters, labs, and medications) the LLM generates.
  Defaults to `10` if not set.
- **File Update Schedule:** On the `File Update Schedule` tab of the source, configure it
  to run on whatever cadence you need fresh synthetic data.

## Dependencies

- `pydantic` — Schema definition and output validation
