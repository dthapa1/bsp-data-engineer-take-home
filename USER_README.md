# User README

This is the quickest way to understand what was built, what problems were fixed, and how to talk through the project.

## What This Project Is

This repo is a veterinary data warehouse take-home built on:

- DuckDB
- Prefect
- Soda
- a medallion layout: `bronze -> silver -> gold`

The original repo already had:

- seed data generation
- bronze ingestion
- bronze contracts

The main work completed here was:

- fixing and completing the silver layer
- building the gold layer for all 6 business requirements
- adding silver and gold data quality contracts
- adding AI-assistant guidance, validation scripts, and a terminal dashboard

## Scope Chosen

The final implementation covers all 6 business requirements:

1. Clinic Appointment Volume
2. Referral Funnel Analysis
3. Revenue vs Budget
4. Provider Utilization
5. Duplicate Patient Detection
6. Patient Retention Cohort

## What I Fixed

### Silver issues

The repo explicitly warned that silver had problems. I investigated and fixed the main ones:

- patient loss caused by a renamed clinic
  - `silver.stg_vet_patient` was dropping patients tied to the old Riverside clinic id
  - I added reporting-clinic mapping so those patients roll up correctly

- invalid referral staging
  - the referral data had negative durations, repeated stages, and dirty transitions
  - I cleaned the silver referral view so it keeps valid stage history only

- incomplete silver coverage
  - the original silver layer was missing objects needed for the selected requirements
  - I added staging views for:
    - owners
    - providers
    - invoices
    - budget targets

- duplicated silver SQL
  - silver SQL existed both in Python and in a migration
  - I moved silver execution to the migration so there is one source of truth

### Gold issue tightened during contract work

- some referral funnel rows had no valid cohort month
  - I filtered those out in the analytical funnel view
  - that made the view more consistent and allowed the contract to pass for the right reason

## What I Built

### Gold foundation

I created shared gold objects first so the reporting layer would sit on a stable base:

- `gold.dim_core_clinic`
- `gold.dim_clin_patient`
- `gold.fact_clin_appointment`
- `gold.fact_fin_invoice`
- `gold.fact_pipe_referral_stage`
- `gold.ref_core_budget_target`

### Gold analytical views

Then I built one analytical view per selected requirement:

- `gold.v_ops_clinic_appointment_weekly`
  - weekly appointment volume
  - completion, cancellation, and no-show rates
  - underperforming clinic flag

- `gold.v_pipe_referral_funnel_monthly`
  - inquiries, consultations, registrations, active patients
  - conversion rates between stages
  - median days in each stage
  - grouped by clinic, month, and referral source

- `gold.v_fin_revenue_budget_monthly`
  - monthly clinic revenue
  - insurance vs self-pay split
  - budget comparison
  - variance and collection rate

- `gold.v_ops_provider_utilization_weekly`
  - appointments per provider per week
  - service-type breakdown
  - completed minutes
  - below-threshold flag

- `gold.v_clin_duplicate_patients_exceptions`
  - likely duplicate patient pairs for manual review
  - exact-match, shared-phone, and fuzzy last-name signals
  - aggregated match reasons

- `gold.v_clin_patient_retention_monthly`
  - cohort by first completed appointment month
  - 30/60/90-day return counts and rates
  - grouped by clinic and referral source

## Why The Design Looks Like This

The main design idea was:

- clean silver first
- create reusable gold dimensions/facts
- build business views on top

That gave a cleaner warehouse story than building one-off reporting SQL directly from silver.

It also matches the take-home expectations better because it demonstrates:

- debugging
- Kimball-style modeling
- analytical view design
- data quality engineering

## Important Decisions And Assumptions

### 1. I used `clinic_area` as the regional grouping

The requirement mentions both region and area, but the dataset does not expose a separate `region` field.

So the current implementation uses `clinic_area` as the grouping attribute for that concept.

If asked about this, the right explanation is:

- I did not want to silently invent a field that was not present in source data
- I chose the nearest stable attribute and documented the assumption

### 2. Patient SCD2 is structurally implemented, but not historically versioned

`gold.dim_clin_patient` includes the required SCD2 columns:

- surrogate key
- natural key
- `effective_start`
- `effective_end`
- `is_current`
- `row_hash`

But the source data does not contain historical patient-change events, so the current implementation loads one current row per patient.

### 3. Provider utilization counts non-cancelled appointments and sums completed minutes

That was the cleanest interpretation of the available data:

- cancelled appointments are excluded from utilization counts
- time utilization uses completed appointments only

## Data Quality Work

I added Soda contracts for the key silver and gold objects:

- 7 silver contracts
- 12 gold contracts

The contracts check:

- schema shape
- key column presence
- lightweight business rules such as minimum row counts

## How To Test Everything

The easiest command is:

```powershell
./.venv/Scripts/python.exe scripts/validate_final.py
```

For a visual terminal walkthrough, run:

```powershell
./.venv/Scripts/python.exe scripts/demo_dashboard.py
```

That prints:

- gold table and view row counts
- sample rows for all 6 business requirements
- a compact sanity summary you can scan quickly

Recommended order:

1. Run `scripts/validate_final.py` to confirm the warehouse passes end-to-end validation.
2. Run `scripts/demo_dashboard.py` to visually confirm the facts and business views are populated.

That runs all iteration validators:

- `validate_iteration_1.py`
- `validate_iteration_2.py`
- `validate_iteration_3.py`
- `validate_iteration_4.py`
- `validate_iteration_6.py`

Current final result:

- validators run: 5
- passed: 5
- failed: 0

## Files Worth Mentioning In A Walkthrough

### Project summary

- [submission_notes.md](/mnt/d/take-home/bsp-data-engineer-take-home/docs/submission_notes.md)
- [CLAUDE.md](/mnt/d/take-home/bsp-data-engineer-take-home/CLAUDE.md)

### Silver

- [0002_create_silver_views.sql](/mnt/d/take-home/bsp-data-engineer-take-home/sql/migrations/0002_create_silver_views.sql)
- [silver_transform.py](/mnt/d/take-home/bsp-data-engineer-take-home/flows/silver_transform.py)

### Gold foundation

- [0003_create_gold_foundation.sql](/mnt/d/take-home/bsp-data-engineer-take-home/sql/migrations/0003_create_gold_foundation.sql)
- [gold_transform.py](/mnt/d/take-home/bsp-data-engineer-take-home/flows/gold_transform.py)

### Gold analytical views

- [0004_create_gold_requirement_views.sql](/mnt/d/take-home/bsp-data-engineer-take-home/sql/migrations/0004_create_gold_requirement_views.sql)
- [0005_create_gold_expansion_views.sql](/mnt/d/take-home/bsp-data-engineer-take-home/sql/migrations/0005_create_gold_expansion_views.sql)

### Validation

- [validate_final.py](/mnt/d/take-home/bsp-data-engineer-take-home/scripts/validate_final.py)
- [demo_dashboard.py](/mnt/d/take-home/bsp-data-engineer-take-home/scripts/demo_dashboard.py)

## A Good Short Verbal Summary

If you want a concise explanation, you can say:

"I treated the take-home as a warehouse recovery and completion project. I first debugged and stabilized the silver layer, especially around clinic renames and messy referral history. Then I built a reusable gold foundation with a conformed clinic dimension, an SCD2 patient dimension, and core appointment, invoice, and referral facts. On top of that, I delivered analytical views for all six stakeholder requirements: clinic appointment volume, referral funnel, revenue vs budget, provider utilization, duplicate patient detection, and patient retention cohorts. I also added Soda contracts for the key silver and gold objects, plus repo-native validation scripts and AI-assistant guidance."

## Remaining Risks Or Honest Caveats

There are no failing validators at the moment, but these are the main honest caveats I would mention:

- `region` is inferred from `clinic_area` because the data does not provide a separate region field
- the patient SCD2 dimension has the right structure, but only one current version per patient because no history feed exists
- Soda CLI output on Windows can be noisy due to console encoding, which is why the Python validator scripts are the preferred testing interface

## Bottom Line

The project is in a good final state:
- all 6 requirements implemented
- silver fixed and expanded
- gold dimensions, facts, and analytical views built
- silver and gold contracts added
- AI guidance and submission notes added
- full validation passing
- terminal dashboard available for visual verification
- all 6 requirements implemented
- silver fixed
- gold foundation built
- business views built
- contracts added
- AI guidance added
- final validation passing
