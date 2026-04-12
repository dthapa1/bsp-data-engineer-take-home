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

## How I Approached The Assignment

I treated this as a production-hardening exercise rather than only a feature build. The sequence was intentional:

1. **Profile and trust-check source + bronze data** so downstream fixes were evidence-based.
2. **Stabilize silver first** to prevent known upstream defects from contaminating gold metrics.
3. **Build shared gold foundation objects** (dimensions/facts/reference) before requirement-specific marts.
4. **Implement one analytical view per stakeholder requirement** at the requested business grain.
5. **Add data quality contracts + repo-native validators** so correctness is repeatable from command line.
6. **Document assumptions, tradeoffs, and limitations** so reviewers can understand why specific decisions were made.

This order reduced rework: once silver and shared facts were trustworthy, each requirement view could stay relatively thin and business-semantic.

## Data Exploration And Profiling Highlights

Before modifying transformations, I profiled entities and joins to identify likely break points:

- clinic rename behavior caused historical key drift across clinic-linked entities
- referral stage events contained invalid temporal patterns and duplicates
- appointment data included records that violate clinic lifecycle boundaries
- source data did not include a dedicated `region` field, so `clinic_area` was used as the regional rollup proxy
- patient history feed did not provide change events needed for true multi-version SCD2 tracking

These findings directly drove silver cleanup rules and gold modeling constraints.

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

This section summarizes outcomes. The debugging workflow itself was:

1. isolate the symptom using targeted count/uniqueness/time-window checks
2. trace the break to a specific silver transformation or join key
3. patch logic in migration SQL (not duplicated in Python flows)
4. rerun validators and business-view checks to confirm no regression
5. encode the expectation in tests/contracts where possible

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

The project uses a multi-layered testing strategy:

### 1. Automated Pytest Suite (Primary)

**18 comprehensive tests** covering all layers:

- **Unit Tests (7)**: Isolated test database; fast feedback during development
  - Silver transformations: view creation, deduplication, type conversion (4 tests)
  - Gold requirements: metrics calculation, duplicate detection, retention cohorts (3 tests)

- **Integration Tests (11)**: Production warehouse validation
  - Foundation: all dimensions and facts populated
  - Requirements: all 6 requirements validated against real data
  - Data quality: metrics bounded, monotonicity, rate constraints

Run tests with:
```bash
pytest tests/ -v                                    # All tests
pytest tests/test_integration.py -v               # Production validation
pytest tests/test_silver_transforms.py -v        # Unit tests (fast)
```

**Benefits**: <1 second runtime, isolated test databases, automatic cleanup, CI/CD ready.

### 2. Repo-Native Validators (Supplementary)

Available validators for comprehensive checks:

- `scripts/validate_silver.py` — Silver layer structure and quality checks
- `scripts/validate_gold_foundation.py` — Gold dimension/fact foundation checks
- `scripts/validate_requirements.py` — All 6 requirements (16 checks)
- `scripts/validate_soda_contracts.py` — Soda contract execution checks
- `scripts/validate_final.py` — Single entrypoint that runs core validators in sequence
- `scripts/demo_dashboard.py` — Visual warehouse walkthrough

Run validators with:
```bash
./.venv/bin/python scripts/validate_silver.py
./.venv/bin/python scripts/validate_gold_foundation.py
./.venv/bin/python scripts/validate_requirements.py
./.venv/bin/python scripts/validate_final.py
./.venv/bin/python scripts/demo_dashboard.py
```

### 3. Soda Data Contracts (Reference Data Quality)

Schema and business rule checks for:
- 7 silver objects
- 12 gold objects

Includes:
- schema validation with `allow_extra_columns: true`
- row-count thresholds
- business logic constraints

## Soda Contracts

Contracts were added for:

- 7 silver objects
- 12 gold objects

The contract suite uses:

- schema checks with `allow_extra_columns: true`
- lightweight business rules such as row-count thresholds

## Requirement-By-Requirement Solution Narrative

### Requirement 1: Clinic Appointment Volume

Goal: weekly appointment operations by clinic with completion/cancellation/no-show rates and area rollups.

Solution approach:

- standardized appointment status logic in silver
- modeled weekly grain in gold at **one row per clinic per week**
- calculated rates defensively from totals to avoid divide-by-zero behavior
- exposed clinic attributes needed for operations slicing (`clinic_area` used as available regional grouping)

Primary output: `gold.v_ops_clinic_appointment_weekly`

### Requirement 2: Referral Funnel Analysis

Goal: monthly funnel volumes/conversions and stage-time behavior.

Solution approach:

- cleaned referral stage sequencing in silver (removed invalid windows, collapsed duplicate stage rows)
- built stage fact foundation for reusable funnel analytics
- generated monthly funnel outputs only when cohort anchors are valid
- included conversion-style progression metrics and stage latency behavior

Primary output: `gold.v_pipe_referral_funnel_monthly`

### Requirement 3: Revenue vs Budget

Goal: monthly clinic revenue with payer split and budget variance.

Solution approach:

- normalized invoice amounts in silver and preserved payment-channel semantics
- built invoice fact + budget reference in gold
- produced monthly clinic-level actuals vs targets with variance columns
- preserved insurance/self-pay split and collection context

Primary output: `gold.v_fin_revenue_budget_monthly`

### Requirement 4: Provider Utilization

Goal: weekly provider workload by service with under-threshold flagging.

Solution approach:

- counted appointments at provider-week grain
- excluded cancelled visits from utilization minutes to avoid inflated activity
- aggregated service-type context and total appointment minutes
- added low-utilization flag using stakeholder threshold rule

Primary output: `gold.v_ops_provider_utilization_weekly`

### Requirement 5: Duplicate Patient Detection

Goal: surface likely duplicate records for manual review with reason codes.

Solution approach:

- implemented multi-signal matching logic instead of single-key exact joins
- included exact identity-like matches plus shared-contact and fuzzy-name signals
- emitted review-friendly record pairs with explicit match reason

Primary output: `gold.v_clin_duplicate_patients_exceptions`

### Requirement 6: Patient Retention Cohort

Goal: first-appointment cohorts and 30/60/90-day return rates by clinic/referral context.

Solution approach:

- defined cohorts from first completed appointment month
- calculated return windows with clear temporal boundaries (30/60/90 days)
- output cohort size with retention percentages for stakeholder readability

Primary output: `gold.v_clin_patient_retention_monthly`

## Delivery Checklist Against README Expectations

The take-home asks for specific delivery artifacts. Coverage in this repo:

1. **Data exploration and profiling**: reflected in documented source-quality findings and silver bug diagnoses.
2. **Debug silver layer**: completed and documented in the bug-fix section.
3. **Complete silver layer**: implemented through `silver.stg_vet_*` staging views.
4. **Build gold layer**: shared foundation plus 6 analytical requirement views delivered.
5. **Add data quality contracts**: silver and gold Soda contracts added.
6. **AI development configuration**: `CLAUDE.md` provides assistant guardrails and workflow guidance.
7. **Write migrations**: all DDL/transform objects managed via `sql/migrations/` scripts.

## Tradeoffs And Limits

- `clinic_area` substitutes for region because a distinct region field is not available in source data.
- patient dimension follows SCD2 shape but currently loads one active version per patient due to missing historical change feed.
- Soda contracts are intentionally lightweight for the take-home timeline; deeper business-rule contracts are listed as next-step work.

## Infrastructure And Tooling Fixes

In addition to the modeling bugs documented above, several infrastructure bugs were fixed:

### 1. SQL Migration Parser - Comments with Semicolons
- **Problem**: `flows/common.py` failed when migration comments contained semicolons
- **Example**: "appointment; tracks retention" would break the parser
- **Fix**: Strip line comments before splitting on semicolons
- **Impact**: All migrations now parse correctly

### 2. Platform-Specific Python Paths
- **Problem**: `scripts/validate_final.py` hardcoded Windows path `.venv/Scripts/python.exe`
- **Impact**: Scripts failed on macOS/Linux
- **Fix**: Detect platform and use correct path (`.venv/bin/python` on Unix)
- **Impact**: All validation scripts now work cross-platform

### 3. Dashboard Column Mismatch
- **Problem**: `demo_dashboard.py` referenced non-existent `clinic_region` column
- **Fix**: Updated to use correct `clinic_area` column
- **Impact**: Dashboard now displays correctly

### 4. Validation Script Migration Paths
- **Problem**: Validator scripts referenced consolidated migration file that doesn't exist
- **Fix**: Updated paths to match actual split requirement migrations
- **Impact**: `validate_requirements.py` and `validate_soda_contracts.py` now execute successfully

## AI Development Configuration

`CLAUDE.md` was written to give AI coding assistants (Claude Code, Copilot, Cursor, etc.) enough context to contribute safely without drifting the implementation.

What it covers:

- **Project goal and current status** — so the assistant understands what is already built and does not re-implement finished layers
- **Business scope** — the 6 selected requirements, so the assistant preserves scope instead of adding unrequested features
- **Architecture map** — key paths for flows, migrations, contracts, validators, and the dashboard
- **Working rules** — use `get_connection()`, put DDL in migrations, keep migrations idempotent, prefer migrations over inline Python SQL
- **Modeling notes** — terse facts about unusual decisions (SCD2 current-only load, clinic rename remapping, funnel null-cohort filter, duplicate patient signals) so the assistant does not unknowingly revert intentional choices
- **Validation workflow** — a documented validator workflow that should be kept in sync as scripts evolve

The goal was to make the rules machine-readable and opinionated enough that an AI assistant acting autonomously would not break existing contracts or drift from project conventions.

## Assumptions

- `clinic_area` is used as the regional grouping because the data does not expose a separate `region` attribute.
- provider utilization excludes cancelled appointments and sums minutes only from completed appointments.
- patient SCD2 history is represented as a single current row per patient because the source does not provide historical attribute changes.

## What I Would Do With More Time

- strengthen Soda business-rule checks beyond row counts (e.g., referential integrity, domain validation)
- add pytest mutation testing to verify test effectiveness
- add performance benchmarks for critical queries
- add pre-commit hook for automatic test execution
- expand integration tests with data generation factories for edge cases
- add interactive notebook demos for stakeholder presentation
