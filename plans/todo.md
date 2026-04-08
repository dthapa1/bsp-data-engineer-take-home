# To-Do List

## Selected Scope

We are targeting these business requirements:

1. Clinic Appointment Volume
2. Referral Funnel Analysis
3. Revenue vs Budget
4. Provider Utilization
5. Duplicate Patient Detection
6. Patient Retention Cohort

## Progress Summary

Completed:

- Iteration 1:
  - fixed renamed-clinic patient loss
  - cleaned referral staging
  - added missing silver views for owners, providers, invoices, and budget targets
  - centralized silver SQL in the migration
- Iteration 2:
  - created shared gold dimensions and facts
  - added a gold build flow
  - added a validator for the gold foundation
- Iteration 3:
  - created analytical gold views for the four selected requirements
  - updated the gold flow to build both foundation objects and analytical views
  - added a validator for the analytical layer
- Iteration 4:
  - added Soda contracts for the key silver and gold objects
  - added a contract validator that rebuilds the warehouse and verifies all contracts
  - tightened the referral funnel view so all funnel rows have a valid cohort month
- Iteration 5:
  - added `CLAUDE.md`
  - added final submission notes
  - added a final validator that runs all iteration validators
  - fixed a stale Iteration 2 validator expectation after analytical views were added
- Iteration 6:
  - added duplicate patient detection and retention cohort views
  - added validator coverage for requirements 5 and 6
  - added Soda contracts for the 2 new gold views
  - updated final validation to include the expanded scope
- Iteration 7:
  - added a terminal dashboard for visual verification
  - hardened the final validator against transient rerun flakiness
  - aligned handoff documentation with the final testing workflow

In progress:

- none

Not started:

- none

## Priority Order

1. Final review and polish before submission.

## Known Silver Issues

Resolved in Iteration 1:

- `silver.stg_vet_patient` no longer drops patients tied to renamed clinics.
- `silver.stg_vet_referral` no longer exposes negative durations or duplicate stage rows.
- missing silver views were added for:
  - owners
  - providers
  - invoices
  - budget targets
- silver SQL now runs from the migration instead of duplicated Python SQL.

## Candidate Gold Deliverables

Completed in Iteration 2:

- `gold.dim_core_clinic`
- `gold.dim_clin_patient` as SCD2
- `gold.fact_clin_appointment`
- `gold.fact_fin_invoice`
- `gold.fact_pipe_referral_stage` or equivalent cleaned referral fact

Completed in Iteration 3:

- `gold.v_ops_clinic_appointment_weekly`
- `gold.v_pipe_referral_funnel_monthly`
- `gold.v_fin_revenue_budget_monthly`
- `gold.v_ops_provider_utilization_weekly`

Completed in Iteration 4:

- silver Soda contracts for 7 staging objects
- gold Soda contracts for 10 foundation and analytical objects
- `scripts/validate_iteration_4.py`

Completed in Iteration 5:

- `CLAUDE.md`
- `docs/submission_notes.md`
- `scripts/validate_final.py`

Completed in Iteration 7:

- `scripts/demo_dashboard.py`
- final documentation refresh across handoff and planning files

Completed in Iteration 6:

- `gold.v_clin_duplicate_patients_exceptions`
- `gold.v_clin_patient_retention_monthly`
- `scripts/validate_iteration_6.py`

## Working Deliverables For Selected Scope

- Requirement 1:
  - clinic dimension
  - appointment fact
  - weekly clinic appointment aggregate or view
- Requirement 2:
  - cleaned referral staging
  - referral stage fact or canonical funnel fact
  - referral funnel monthly summary view
- Requirement 3:
  - invoice fact
  - budget target reference table
  - monthly revenue vs budget view
- Requirement 4:
  - provider staging cleanup
  - provider-oriented appointment view or aggregate
  - weekly provider utilization view
- Requirement 5:
  - duplicate patient exception view
  - exact-match, shared-phone, and fuzzy owner-last-name signals
- Requirement 6:
  - first-appointment cohort model
  - 30/60/90-day retention metrics by clinic and referral source

## Suggested Sequence

1. Final review and submission.
