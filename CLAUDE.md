# CLAUDE.md

This file gives AI coding assistants repo-specific guidance for the PawsFirst veterinary warehouse take-home.

## Project Goal

This repository is a medallion-style DuckDB warehouse for a veterinary clinic network.

Current implementation status:

- bronze ingestion is in place
- silver has been stabilized and expanded
- gold foundation objects are built
- gold analytical views are built for all 6 business requirements
- Soda contracts exist for the key silver and gold objects
- a terminal dashboard exists for visual verification
- full-project validation passes through the repo-native validator scripts

## Business Scope

The selected stakeholder requirements for this submission are:

1. Clinic Appointment Volume
2. Referral Funnel Analysis
3. Revenue vs Budget
4. Provider Utilization
5. Duplicate Patient Detection
6. Patient Retention Cohort

## Architecture

- `bronze`: raw CSV ingestion tables
- `silver`: cleaned and typed staging views
- `gold`: business-semantic dimensions, facts, references, and analytical views

Important paths:

- `flows/common.py`: DuckDB connection helper and migration runner
- `flows/ingest.py`: bronze ingestion flow
- `flows/silver_transform.py`: silver build flow
- `flows/gold_transform.py`: gold build flow
- `sql/migrations/`: warehouse DDL and load logic
- `soda/contracts/`: data contracts
- `scripts/validate_iteration_*.py`: repo-native validation scripts
- `scripts/demo_dashboard.py`: terminal-friendly warehouse walkthrough
- `plans/`: implementation progress and testing notes

## Working Rules

1. Use `flows.common.get_connection()` for DuckDB access.
2. Put DDL and repeatable load logic in `sql/migrations/`.
3. Keep migrations idempotent.
4. Prefer updating views/tables through migrations instead of embedding duplicate SQL in Python flows.
5. Follow `docs/conventions.md` for naming and date grammar.
6. Preserve the selected project scope unless the user asks otherwise.

## Modeling Notes

- `silver.stg_vet_clinic` includes reporting-clinic mapping for renamed clinics.
- `silver.stg_vet_patient` remaps historical clinic ids to the reporting clinic id.
- `silver.stg_vet_referral` removes negative-duration windows and collapses duplicate stage rows.
- `gold.dim_clin_patient` uses SCD2 columns, but currently loads one current version per patient because no historical patient-change feed exists in the source data.
- `gold.v_pipe_referral_funnel_monthly` only includes referrals with a valid cohort month.
- `gold.v_clin_duplicate_patients_exceptions` uses exact-match, shared-phone, and fuzzy owner-last-name signals.
- `gold.v_clin_patient_retention_monthly` uses first completed appointment cohorts and 30/60/90-day return windows.
- `clinic_area` is currently used as the regional grouping because the dataset does not expose a separate `region` field.

## Validation Workflow

Prefer the iteration validators over ad hoc shell one-liners.

PowerShell-friendly commands:

```powershell
./.venv/Scripts/python.exe scripts/validate_iteration_1.py
./.venv/Scripts/python.exe scripts/validate_iteration_2.py
./.venv/Scripts/python.exe scripts/validate_iteration_3.py
./.venv/Scripts/python.exe scripts/validate_iteration_4.py
./.venv/Scripts/python.exe scripts/validate_iteration_6.py
./.venv/Scripts/python.exe scripts/validate_final.py
./.venv/Scripts/python.exe scripts/demo_dashboard.py
```

Recommended usage:

1. Run `scripts/validate_final.py` for pass/fail confirmation.
2. Run `scripts/demo_dashboard.py` for a readable terminal walkthrough of row counts and business-view output.

## Soda Notes

- Soda contracts are intentionally limited to schema checks plus lightweight business rules such as row-count thresholds.
- Soda CLI output may look noisy on Windows terminals because of encoding/logging behavior.
- Treat the validator script exit code as the reliable pass/fail signal.
- `scripts/validate_final.py` includes a light retry to smooth over occasional transient validator flakiness when scripts re-open DuckDB in sequence.

## If You Change The Repo

When making additional changes:

1. update the relevant migration or flow
2. add or update a validator script if testing changes materially
3. update `plans/iteration_log.md`
4. keep `plans/README.md`, `plans/todo.md`, and `plans/effort_map.md` readable and current
5. update `USER_README.md` and `docs/submission_notes.md` if the testing story or deliverables change

## Suggested Next Enhancements

If there is time beyond the take-home baseline:

- add stronger business-rule Soda checks
- add a small README section with example analytical queries
- add a lightweight demo script with interview-style question outputs beyond the current dashboard
