"""
Requirements validation script.

Builds all gold requirement views and validates outputs for all 6 requirements:
1. Clinic Appointment Volume
2. Referral Funnel Analysis
3. Revenue vs Budget
4. Provider Utilization
5. Duplicate Patient Detection
6. Patient Retention Cohort

Usage:
    ./.venv/bin/python scripts/validate_requirements.py
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys
from typing import Any

REPO_ROOT = Path(__file__).parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from flows.common import ensure_schemas, get_connection, run_migration

MIGRATION_PATHS = [
    REPO_ROOT / "sql" / "migrations" / "0002_create_silver_views.sql",
    REPO_ROOT / "sql" / "migrations" / "0003_create_gold_foundation.sql",
    REPO_ROOT / "sql" / "migrations" / "0004_gold_requirement_1_clinic_appointment.sql",
    REPO_ROOT / "sql" / "migrations" / "0005_gold_requirement_2_referral_funnel.sql",
    REPO_ROOT / "sql" / "migrations" / "0006_gold_requirement_3_revenue_budget.sql",
    REPO_ROOT / "sql" / "migrations" / "0007_gold_requirement_4_provider_utilization.sql",
    REPO_ROOT / "sql" / "migrations" / "0008_gold_requirement_5_duplicate_patients.sql",
    REPO_ROOT / "sql" / "migrations" / "0009_gold_requirement_6_patient_retention.sql",
]


@dataclass
class CheckResult:
    name: str
    expected: Any
    actual: Any
    requirement: int | None = None

    @property
    def passed(self) -> bool:
        return self.expected == self.actual


def rebuild_requirement_views() -> None:
    con = get_connection()
    try:
        ensure_schemas(con)
        for migration_path in MIGRATION_PATHS:
            run_migration(con, str(migration_path))
    finally:
        con.close()


def run_checks() -> list[CheckResult]:
    con = get_connection()
    try:
        checks = [
            # Requirements 1-4: Operational requirements
            CheckResult(
                name="all 6 analytical views exist",
                expected=[
                    ("v_clin_duplicate_patients_exceptions",),
                    ("v_clin_patient_retention_monthly",),
                    ("v_fin_revenue_budget_monthly",),
                    ("v_ops_clinic_appointment_weekly",),
                    ("v_ops_provider_utilization_weekly",),
                    ("v_pipe_referral_funnel_monthly",),
                ],
                actual=con.execute(
                    """
                    SELECT table_name
                    FROM information_schema.views
                    WHERE table_schema = 'gold'
                      AND table_name IN (
                          'v_clin_duplicate_patients_exceptions',
                          'v_clin_patient_retention_monthly',
                          'v_fin_revenue_budget_monthly',
                          'v_ops_clinic_appointment_weekly',
                          'v_ops_provider_utilization_weekly',
                          'v_pipe_referral_funnel_monthly'
                      )
                    ORDER BY table_name
                    """
                ).fetchall(),
            ),
            # Requirement 1: Clinic Appointment Volume
            CheckResult(
                name="[Req 1] clinic weekly appointment view has rows",
                expected=True,
                actual=con.execute(
                    "SELECT COUNT(*) > 0 FROM gold.v_ops_clinic_appointment_weekly"
                ).fetchone()[0],
                requirement=1,
            ),
            CheckResult(
                name="[Req 1] clinic weekly rates are bounded",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM gold.v_ops_clinic_appointment_weekly
                    WHERE completion_rate < 0 OR completion_rate > 1
                       OR cancellation_rate < 0 OR cancellation_rate > 1
                       OR no_show_rate < 0 OR no_show_rate > 1
                    """
                ).fetchone()[0],
                requirement=1,
            ),
            # Requirement 2: Referral Funnel Analysis
            CheckResult(
                name="[Req 2] referral funnel view has rows",
                expected=True,
                actual=con.execute(
                    "SELECT COUNT(*) > 0 FROM gold.v_pipe_referral_funnel_monthly"
                ).fetchone()[0],
                requirement=2,
            ),
            CheckResult(
                name="[Req 2] referral funnel stage counts are monotonic",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM gold.v_pipe_referral_funnel_monthly
                    WHERE consultations_count > inquiries_count
                       OR registrations_count > consultations_count
                       OR active_patients_count > registrations_count
                    """
                ).fetchone()[0],
                requirement=2,
            ),
            # Requirement 3: Revenue vs Budget
            CheckResult(
                name="[Req 3] revenue budget view has rows",
                expected=True,
                actual=con.execute(
                    "SELECT COUNT(*) > 0 FROM gold.v_fin_revenue_budget_monthly"
                ).fetchone()[0],
                requirement=3,
            ),
            CheckResult(
                name="[Req 3] revenue budget targets populated for 2024",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM gold.v_fin_revenue_budget_monthly
                    WHERE EXTRACT(year FROM invoice_month_start_date) = 2024
                      AND target_revenue_amount IS NULL
                    """
                ).fetchone()[0],
                requirement=3,
            ),
            # Requirement 4: Provider Utilization
            CheckResult(
                name="[Req 4] provider utilization view has rows",
                expected=True,
                actual=con.execute(
                    "SELECT COUNT(*) > 0 FROM gold.v_ops_provider_utilization_weekly"
                ).fetchone()[0],
                requirement=4,
            ),
            CheckResult(
                name="[Req 4] provider utilization threshold flag appears",
                expected=True,
                actual=con.execute(
                    """
                    SELECT COUNT(*) > 0
                    FROM gold.v_ops_provider_utilization_weekly
                    WHERE is_below_minimum_threshold = TRUE
                    """
                ).fetchone()[0],
                requirement=4,
            ),
            # Requirement 5: Duplicate Patient Detection
            CheckResult(
                name="[Req 5] duplicate patient exceptions view has rows",
                expected=True,
                actual=con.execute(
                    "SELECT COUNT(*) > 0 FROM gold.v_clin_duplicate_patients_exceptions"
                ).fetchone()[0],
                requirement=5,
            ),
            CheckResult(
                name="[Req 5] duplicate patient pairs are distinct",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM gold.v_clin_duplicate_patients_exceptions
                    WHERE patient_id_left = patient_id_right
                    """
                ).fetchone()[0],
                requirement=5,
            ),
            CheckResult(
                name="[Req 5] duplicate patient match reasons populated",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM gold.v_clin_duplicate_patients_exceptions
                    WHERE match_reasons IS NULL OR match_reasons = ''
                    """
                ).fetchone()[0],
                requirement=5,
            ),
            # Requirement 6: Patient Retention Cohort
            CheckResult(
                name="[Req 6] patient retention view has rows",
                expected=True,
                actual=con.execute(
                    "SELECT COUNT(*) > 0 FROM gold.v_clin_patient_retention_monthly"
                ).fetchone()[0],
                requirement=6,
            ),
            CheckResult(
                name="[Req 6] retention cohort sizes are positive",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM gold.v_clin_patient_retention_monthly
                    WHERE cohort_size <= 0
                    """
                ).fetchone()[0],
                requirement=6,
            ),
            CheckResult(
                name="[Req 6] retention rates are bounded",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM gold.v_clin_patient_retention_monthly
                    WHERE retention_30_day_rate < 0 OR retention_30_day_rate > 1
                       OR retention_60_day_rate < 0 OR retention_60_day_rate > 1
                       OR retention_90_day_rate < 0 OR retention_90_day_rate > 1
                    """
                ).fetchone()[0],
                requirement=6,
            ),
            CheckResult(
                name="[Req 6] retention rates are monotonic (30 <= 60 <= 90)",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM gold.v_clin_patient_retention_monthly
                    WHERE retention_30_day_rate > retention_60_day_rate
                       OR retention_60_day_rate > retention_90_day_rate
                    """
                ).fetchone()[0],
                requirement=6,
            ),
        ]
        return checks
    finally:
        con.close()


def main() -> int:
    print("=" * 70)
    print("Requirements Validation (All 6 Stakeholder Requirements)".center(70))
    print("=" * 70)
    print()
    
    print("Applying migrations:")
    for migration_path in MIGRATION_PATHS:
        print(f"  - {migration_path.name}")
    print()
    
    rebuild_requirement_views()
    print("Gold analytical views built")
    print()

    results = run_checks()
    failures = [result for result in results if not result.passed]

    # Group by requirement
    by_req = {}
    for result in results:
        req = result.requirement or 0
        if req not in by_req:
            by_req[req] = []
        by_req[req].append(result)

    # Print grouped results
    if 0 in by_req:
        print("SCHEMA VALIDATION:")
        for result in by_req[0]:
            status = "✓ PASS" if result.passed else "✗ FAIL"
            print(f"  {status} | {result.name}")
        print()

    for req_num in sorted([r for r in by_req.keys() if r > 0]):
        results_for_req = by_req[req_num]
        passed_for_req = sum(1 for r in results_for_req if r.passed)
        total_for_req = len(results_for_req)
        print(f"REQUIREMENT {req_num}: {passed_for_req}/{total_for_req} checks passed")
        for result in results_for_req:
            status = "✓" if result.passed else "✗"
            print(f"  {status} {result.name}")
        print()

    # Summary
    print("=" * 70)
    print(f"Total Checks: {len(results)}")
    print(f"Passed: {len(results) - len(failures)}")
    print(f"Failed: {len(failures)}")
    if failures:
        print("\nFailed checks:")
        for result in failures:
            print(f"  - {result.name}")
            print(f"    expected: {result.expected}")
            print(f"    actual:   {result.actual}")
    print("=" * 70)

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
