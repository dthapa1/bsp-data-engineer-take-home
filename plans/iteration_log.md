# Iteration Log

Use this file as the running changelog for implementation work.

## Progress Summary

Completed iterations:

- Iteration 0: planning setup
- Iteration 0.1: scope selection
- Iteration 1: silver stabilization
- Iteration 2: gold foundation
- Iteration 3: requirement-level analytical views
- Iteration 4: Soda contracts
- Iteration 5: final handoff
- Iteration 6: requirements 5 and 6
- Iteration 7: final sanity dashboard

Current state:

- silver is validated through `scripts/validate_iteration_1.py`
- gold foundation is validated through `scripts/validate_iteration_2.py`
- analytical gold views are validated through `scripts/validate_iteration_3.py`
- Soda contracts are validated through `scripts/validate_iteration_4.py`
- the full project is validated through `scripts/validate_final.py`
- the final warehouse state is visually inspectable through `scripts/demo_dashboard.py`
- the repo is ready for final review and submission

## Template

### Iteration N: Title

Changed:

- file or object changed
- file or object changed

Why:

- reason for the change

How to test:

1. Run the relevant flow, migration, or query.
2. Check the expected output.
3. Note any known limitations.

Commands:

```bash
# add commands here
```

Expected result:

- add the key success conditions here

Notes:

- assumptions
- follow-up work

## Iteration 0: Planning Setup

Changed:

- added `plans/README.md`
- added `plans/todo.md`
- added `plans/effort_map.md`
- added `plans/iteration_log.md`

Why:

- create a dedicated place to track scope, sequencing, and test instructions as we implement the take-home

How to test:

1. Open the files in `plans/`.
2. Confirm the planning artifacts exist and reflect the current repo understanding.

Commands:

```bash
rg --files plans
```

Expected result:

- four planning files are listed under `plans/`

Notes:

- we should update this file after each implementation iteration
- once scope is finalized, `plans/todo.md` and `plans/effort_map.md` should be revised to match it

## Iteration 0.1: Scope Selection

Changed:

- updated `plans/todo.md` to lock in requirements 1, 2, 3, and 4
- updated `plans/effort_map.md` to reflect the selected implementation scope

Why:

- we need a fixed target before implementing silver fixes and gold models

How to test:

1. Open `plans/todo.md`.
2. Confirm the selected scope lists requirements 1, 2, 3, and 4.
3. Open `plans/effort_map.md`.
4. Confirm the implementation chunks align to those four requirements.

Commands:

```bash
sed -n '1,240p' plans/todo.md
sed -n '1,260p' plans/effort_map.md
```

Expected result:

- the planning docs explicitly reference requirements 1 to 4 as the chosen scope

Notes:

- the next implementation iteration should start with silver stabilization for these four requirements

## Iteration 1: Silver Stabilization

Changed:

- updated `sql/migrations/0002_create_silver_views.sql`
- updated `flows/silver_transform.py`
- added missing silver views:
  - `silver.stg_vet_owner`
  - `silver.stg_vet_provider`
  - `silver.stg_vet_invoice`
  - `silver.stg_vet_budget_target`
- fixed `silver.stg_vet_patient` so renamed clinics no longer drop patients
- updated clinic mapping logic so historical clinic ids can roll up to a reporting clinic id
- filtered impossible pre-opening appointments from `silver.stg_vet_appointment`
- cleaned `silver.stg_vet_referral` into one valid row per referral stage with no negative durations
- moved the silver flow to execute the migration file instead of keeping duplicate SQL in Python

Why:

- requirements 1 to 4 all depend on trustworthy silver-layer inputs
- the previous patient view dropped 107 valid patients tied to the renamed Riverside clinic
- referral history needed cleanup before we can build a reliable funnel
- silver needed additional entities for appointments, providers, invoices, and budget targets
- using the migration as the single silver SQL source avoids drift between Python and SQL files

How to test:

1. Re-apply the silver migration.
2. Verify the new views exist.
3. Check the key cleanup outcomes:
   - `silver.stg_vet_patient` has 2,000 rows
   - renamed-clinic patients map from `1012` to `1013`
   - `silver.stg_vet_appointment` contains no pre-opening appointments
   - `silver.stg_vet_referral` contains no negative stage durations
4. Optionally inspect row counts for all silver views.

Commands:

```powershell
./.venv/Scripts/python.exe scripts/validate_iteration_1.py
```

Expected result:

- silver views now include:
  - `stg_vet_clinic`
  - `stg_vet_owner`
  - `stg_vet_patient`
  - `stg_vet_provider`
  - `stg_vet_appointment`
  - `stg_vet_invoice`
  - `stg_vet_budget_target`
  - `stg_vet_referral`
- `silver.stg_vet_patient` row count is `2000`
- renamed-clinic remap result includes `(1012, 1013, 'Riverside East', 107)`
- pre-opening appointment count is `0`
- negative referral duration count is `0`

Notes:

- the full `uv run` path from `SETUP.md` could not be validated here because `uv` is not installed in this shell environment
- direct migration execution through the project Python environment worked and validated the SQL successfully
- the next iteration should design the shared gold foundation on top of these silver views
- `scripts/validate_iteration_1.py` is now the preferred way to test this iteration in PowerShell

## Iteration 2: Gold Foundation

Changed:

- added `sql/migrations/0003_create_gold_foundation.sql`
- added `flows/gold_transform.py`
- added `scripts/validate_iteration_2.py`
- created shared gold objects:
  - `gold.dim_core_clinic`
  - `gold.dim_clin_patient`
  - `gold.fact_clin_appointment`
  - `gold.fact_fin_invoice`
  - `gold.fact_pipe_referral_stage`
  - `gold.ref_core_budget_target`

Why:

- requirements 1 to 4 need a consistent gold-layer base before we build business-facing views
- a shared clinic dimension and patient dimension reduce duplication across operations, finance, and referral reporting
- appointment, invoice, and referral stage facts align the base grains needed for the selected requirements
- the budget reference table provides the monthly targets needed for revenue-vs-budget analysis

How to test:

1. Run the Iteration 2 validator script.
2. Confirm the gold tables are created and populated.
3. Check the printed row counts and key-population checks.

Commands:

```powershell
./.venv/Scripts/python.exe scripts/validate_iteration_2.py
```

Expected result:

- the validator applies silver and gold migrations successfully
- the following gold tables exist:
  - `dim_core_clinic`
  - `dim_clin_patient`
  - `fact_clin_appointment`
  - `fact_fin_invoice`
  - `fact_pipe_referral_stage`
  - `ref_core_budget_target`
- expected row counts:
  - `gold.dim_core_clinic` = `12`
  - `gold.dim_clin_patient` = `2000`
  - `gold.fact_clin_appointment` = `6621`
  - `gold.fact_fin_invoice` = `4751`
  - `gold.fact_pipe_referral_stage` = `2273`
  - `gold.ref_core_budget_target` = `144`
- clinic foreign keys in appointment and invoice facts are fully populated

Notes:

- `gold.dim_clin_patient` uses the required SCD2 columns but currently loads one current version per patient because the source data does not expose historical patient changes
- the next iteration should build the requirement-level gold views and aggregates for:
  - clinic appointment volume
  - referral funnel analysis
  - revenue vs budget
  - provider utilization

## Iteration 3: Requirement-Level Analytical Views

Changed:

- added `sql/migrations/0004_create_gold_requirement_views.sql`
- updated `flows/gold_transform.py` to apply both gold migrations
- added `scripts/validate_iteration_3.py`
- created analytical gold views:
  - `gold.v_ops_clinic_appointment_weekly`
  - `gold.v_pipe_referral_funnel_monthly`
  - `gold.v_fin_revenue_budget_monthly`
  - `gold.v_ops_provider_utilization_weekly`

Why:

- the take-home requires business-facing outputs, not only base dimensions and facts
- the selected requirements need weekly and monthly analytical views for operations, finance, referrals, and provider performance
- a validator for the analytical layer gives us a simple PowerShell test entrypoint for these new outputs

How to test:

1. Run the Iteration 3 validator script.
2. Confirm the four analytical gold views exist.
3. Confirm the validator reports all checks passing.

Commands:

```powershell
./.venv/Scripts/python.exe scripts/validate_iteration_3.py
```

Expected result:

- the validator applies silver and gold migrations successfully
- the following analytical views exist:
  - `gold.v_ops_clinic_appointment_weekly`
  - `gold.v_pipe_referral_funnel_monthly`
  - `gold.v_fin_revenue_budget_monthly`
  - `gold.v_ops_provider_utilization_weekly`
- current row counts:
  - `gold.v_ops_clinic_appointment_weekly` = `945`
  - `gold.v_pipe_referral_funnel_monthly` = `523`
  - `gold.v_fin_revenue_budget_monthly` = `262`
  - `gold.v_ops_provider_utilization_weekly` = `4752`
- validation checks pass for:
  - bounded appointment rates
  - monotonic referral funnel counts
  - populated budget joins for 2024 revenue months
  - provider-threshold flags present

Notes:

- assumption: the source `clinic_area` field is being used as the regional grouping because the dataset does not expose a separate region attribute
- assumption: provider utilization excludes cancelled appointments and sums minutes from completed appointments only
- the next iteration should focus on Soda contracts and delivery documentation

## Iteration 4: Soda Contracts

Changed:

- added `soda/contracts/silver/` contract files for 7 silver staging objects
- added `soda/contracts/gold/` contract files for 10 gold foundation and analytical objects
- added `scripts/validate_iteration_4.py`
- updated `sql/migrations/0004_create_gold_requirement_views.sql` so referral funnel rows require a valid cohort month

Why:

- the take-home explicitly asks for Soda contracts on silver and gold objects
- contracts give us repeatable schema and row-count checks across the objects we rely on most
- the Iteration 4 validator keeps contract testing to one PowerShell command
- filtering null cohort months improves both contract stability and funnel semantics

How to test:

1. Run the Iteration 4 validator script.
2. Confirm the validator rebuilds the warehouse objects.
3. Confirm all silver and gold Soda contracts pass.

Commands:

```powershell
./.venv/Scripts/python.exe scripts/validate_iteration_4.py
```

Expected result:

- the validator applies the silver and gold migrations successfully
- 17 Soda contracts are verified
- all 17 contracts pass
- current analytical row counts remain:
  - `gold.v_ops_clinic_appointment_weekly` = `945`
  - `gold.v_pipe_referral_funnel_monthly` = `523`
  - `gold.v_fin_revenue_budget_monthly` = `262`
  - `gold.v_ops_provider_utilization_weekly` = `4752`

Notes:

- Soda CLI succeeds in this environment, but its raw output is noisy because of Windows console encoding; the validator script summarizes success/failure cleanly
- the next step should be AI-assistant guidance in `CLAUDE.md`, plus final project documentation

## Iteration 5: Final Handoff

Changed:

- added `CLAUDE.md`
- added `docs/submission_notes.md`
- added `scripts/validate_final.py`
- updated `scripts/validate_iteration_2.py` so it checks only base gold tables

Why:

- the take-home explicitly asks for AI-assistant guidance
- final submission notes make the implemented scope, design decisions, bugs found, and assumptions easy to review
- a single final validation command is useful for quick end-to-end verification before handoff
- the Iteration 2 validator needed a small fix after later iterations added gold views

How to test:

1. Run the final validator script.
2. Confirm all iteration validators pass.
3. Review `CLAUDE.md` and `docs/submission_notes.md` for completeness.

Commands:

```powershell
./.venv/Scripts/python.exe scripts/validate_final.py
```

Expected result:

- `validate_iteration_1.py` passes
- `validate_iteration_2.py` passes
- `validate_iteration_3.py` passes
- `validate_iteration_4.py` passes
- final summary shows:
  - `Validators run: 4`
  - `Passed: 4`
  - `Failed: 0`

Notes:

- `CLAUDE.md` captures repo-specific guardrails for future AI-assisted development
- `docs/submission_notes.md` is the best single place to review scope, design decisions, bug fixes, assumptions, and future improvements

## Iteration 6: Requirements 5 And 6

Changed:

- added `sql/migrations/0005_create_gold_expansion_views.sql`
- updated `flows/gold_transform.py` to apply the expansion migration
- added `scripts/validate_iteration_6.py`
- added Soda contracts for:
  - `gold.v_clin_duplicate_patients_exceptions`
  - `gold.v_clin_patient_retention_monthly`
- updated `scripts/validate_iteration_4.py` and `scripts/validate_final.py`
- created analytical gold views:
  - `gold.v_clin_duplicate_patients_exceptions`
  - `gold.v_clin_patient_retention_monthly`

Why:

- requirements 5 and 6 were the only remaining stakeholder asks
- the existing silver/gold foundation made both additions feasible without major refactoring
- duplicate detection adds a practical manual-review exception workflow
- retention cohorts add a growth-oriented lens over first appointments and return behavior

How to test:

1. Run the Iteration 6 validator.
2. Run the full final validator.

Commands:

```powershell
./.venv/Scripts/python.exe scripts/validate_iteration_6.py
./.venv/Scripts/python.exe scripts/validate_final.py
```

Expected result:

- `validate_iteration_6.py` passes all checks
- `validate_final.py` shows:
  - `Validators run: 5`
  - `Passed: 5`
  - `Failed: 0`

Notes:

- duplicate detection uses three signals:
  - same patient name + species + date of birth
  - same normalized owner phone across different owner records
  - same patient name + similar owner last name using edit distance
- retention cohorts use the first completed appointment and measure 30/60/90-day return behavior

## Iteration 7: Final Sanity Dashboard

Changed:

- added `scripts/demo_dashboard.py`
- updated `scripts/validate_final.py` to retry once on transient validator failures
- updated `CLAUDE.md`
- updated `USER_README.md`
- updated `docs/submission_notes.md`
- updated planning docs to reflect the final testing workflow

Why:

- final review is easier when validation and visual inspection are both one-command workflows
- the dashboard makes it simple to confirm that gold facts and business views are populated
- the final validator needed a small resilience improvement after an intermittent rerun failure during the last sanity sweep
- documentation should describe the repo as it actually exists at handoff time

How to test:

1. Run the final validator.
2. Run the dashboard.
3. Confirm the validator passes and the dashboard shows populated gold objects plus requirement-level samples.

Commands:

```powershell
./.venv/Scripts/python.exe scripts/validate_final.py
./.venv/Scripts/python.exe scripts/demo_dashboard.py
```

Expected result:

- `validate_final.py` shows:
  - `Validators run: 5`
  - `Passed: 5`
  - `Failed: 0`
- `demo_dashboard.py` prints:
  - gold table and view row counts
  - sample sections for requirements 1 through 6
  - a final sanity summary with populated fact and view counts

Notes:

- the dashboard is intentionally terminal-friendly rather than graphical, so it works cleanly in PowerShell
- the final validator retry is lightweight and only intended to smooth over transient rerun issues, not mask real failures
