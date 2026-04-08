# Submission Notes

This document summarizes the implemented scope, major design decisions, bugs found, testing approach, and what I would do next with more time.

## Implemented Scope

The submission now targets all six stakeholder requirements:

1. Clinic Appointment Volume
2. Referral Funnel Analysis
3. Revenue vs Budget
4. Provider Utilization
5. Duplicate Patient Detection
6. Patient Retention Cohort

## Delivered Objects

### Silver

Key silver outputs:

- `silver.stg_vet_clinic`
- `silver.stg_vet_owner`
- `silver.stg_vet_patient`
- `silver.stg_vet_provider`
- `silver.stg_vet_appointment`
- `silver.stg_vet_invoice`
- `silver.stg_vet_budget_target`
- `silver.stg_vet_referral`

### Gold Foundation

- `gold.dim_core_clinic`
- `gold.dim_clin_patient`
- `gold.fact_clin_appointment`
- `gold.fact_fin_invoice`
- `gold.fact_pipe_referral_stage`
- `gold.ref_core_budget_target`

### Gold Analytical Views

- `gold.v_ops_clinic_appointment_weekly`
- `gold.v_pipe_referral_funnel_monthly`
- `gold.v_fin_revenue_budget_monthly`
- `gold.v_ops_provider_utilization_weekly`
- `gold.v_clin_duplicate_patients_exceptions`
- `gold.v_clin_patient_retention_monthly`

## Key Design Decisions

### Silver as the trusted base

Before building gold, the silver layer was stabilized so gold logic would not encode known upstream defects.

### Migrations as the SQL source of truth

Silver SQL had existed in both Python and migration files. The implementation moved silver execution to the migration so the SQL lives in one place.

### Shared gold foundation before analytical views

Rather than building each business requirement independently, the project first created shared dimensions and facts, then added analytical views on top. This makes the warehouse more coherent and easier to extend.

### SCD2 patient dimension

`gold.dim_clin_patient` follows the required SCD2 shape. Because the source data does not contain historical patient-change events, the current implementation loads one current row per patient.

### Conservative funnel logic

Referral stage data in the source was intentionally messy. The solution collapses duplicate stages, removes negative windows, and only includes funnel rows with a valid cohort month.

## Bugs Found And Fixed

### 1. Renamed clinic patient loss

Problem:

- patients tied to the renamed Riverside clinic were dropped by the silver patient view

Fix:

- added reporting-clinic mapping in `silver.stg_vet_clinic`
- remapped patient clinic ids in `silver.stg_vet_patient`

Outcome:

- silver patient row count returned to 2,000

### 2. Invalid referral durations and duplicate stages

Problem:

- referral staging included negative durations and repeated stages

Fix:

- filtered invalid windows
- collapsed repeated stage rows
- enforced cleaner stage sequencing

Outcome:

- no negative stage durations in silver
- no duplicate stage rows per referral in silver

### 3. Impossible pre-opening appointments

Problem:

- some appointments occurred before the clinic open date

Fix:

- filtered those rows from the silver appointment view

Outcome:

- silver appointment staging excludes pre-opening appointments

### 4. Funnel rows without valid cohort month

Problem:

- some analytical funnel rows had null cohort month because no valid inquiry anchor remained after cleanup

Fix:

- filtered the analytical funnel view to keep only rows with a valid cohort month

Outcome:

- contracts and business logic align better for the monthly funnel

## Testing Approach

The project uses repo-native iteration validators instead of long shell snippets.

Available validators:

- `scripts/validate_iteration_1.py`
- `scripts/validate_iteration_2.py`
- `scripts/validate_iteration_3.py`
- `scripts/validate_iteration_4.py`
- `scripts/validate_iteration_6.py`
- `scripts/validate_final.py`
- `scripts/demo_dashboard.py`

Recommended PowerShell command:

```powershell
./.venv/Scripts/python.exe scripts/validate_final.py
```

That script runs the iteration validators in sequence and gives a single pass/fail summary.

For a visual walkthrough of the final warehouse state:

```powershell
./.venv/Scripts/python.exe scripts/demo_dashboard.py
```

That dashboard prints:

- gold object row counts
- sample output for all 6 business requirements
- a compact sanity summary for the core facts and derived views

## Soda Contracts

Contracts were added for:

- 7 silver objects
- 12 gold objects

The contract suite uses:

- schema checks with `allow_extra_columns: true`
- lightweight business rules such as row-count thresholds

## Assumptions

- `clinic_area` is used as the regional grouping because the data does not expose a separate `region` attribute.
- provider utilization excludes cancelled appointments and sums minutes only from completed appointments.
- patient SCD2 history is represented as a single current row per patient because the source does not provide historical attribute changes.

## What I Would Do With More Time

- add stronger business-rule Soda checks beyond row counts
- add a final PR-style summary to the root README
- add a few interview-style demo queries against the gold views
- strengthen referral business rules further, especially around stage entry/exit semantics
- add lightweight automated tests around migration behavior if the repo were to grow beyond the take-home
