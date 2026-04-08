"""
Iteration 3 validation script.

Builds the analytical gold views and validates requirement-level outputs.

Usage:
    ./.venv/Scripts/python.exe scripts/validate_iteration_3.py
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
    REPO_ROOT / "sql" / "migrations" / "0004_create_gold_requirement_views.sql",
]


@dataclass
class CheckResult:
    name: str
    expected: Any
    actual: Any

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
        return [
            CheckResult(
                name="gold analytical views exist",
                expected=[
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
                          'v_fin_revenue_budget_monthly',
                          'v_ops_clinic_appointment_weekly',
                          'v_ops_provider_utilization_weekly',
                          'v_pipe_referral_funnel_monthly'
                      )
                    ORDER BY table_name
                    """
                ).fetchall(),
            ),
            CheckResult(
                name="clinic weekly view has rows",
                expected=True,
                actual=con.execute(
                    "SELECT COUNT(*) > 0 FROM gold.v_ops_clinic_appointment_weekly"
                ).fetchone()[0],
            ),
            CheckResult(
                name="referral funnel view has rows",
                expected=True,
                actual=con.execute(
                    "SELECT COUNT(*) > 0 FROM gold.v_pipe_referral_funnel_monthly"
                ).fetchone()[0],
            ),
            CheckResult(
                name="revenue budget view has rows",
                expected=True,
                actual=con.execute(
                    "SELECT COUNT(*) > 0 FROM gold.v_fin_revenue_budget_monthly"
                ).fetchone()[0],
            ),
            CheckResult(
                name="provider utilization view has rows",
                expected=True,
                actual=con.execute(
                    "SELECT COUNT(*) > 0 FROM gold.v_ops_provider_utilization_weekly"
                ).fetchone()[0],
            ),
            CheckResult(
                name="clinic weekly rates are bounded",
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
            ),
            CheckResult(
                name="referral funnel stage counts are monotonic",
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
            ),
            CheckResult(
                name="revenue budget target joins populated for 2024 revenue months",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM gold.v_fin_revenue_budget_monthly
                    WHERE EXTRACT(year FROM invoice_month_start_date) = 2024
                      AND target_revenue_amount IS NULL
                    """
                ).fetchone()[0],
            ),
            CheckResult(
                name="provider utilization threshold flag appears",
                expected=True,
                actual=con.execute(
                    """
                    SELECT COUNT(*) > 0
                    FROM gold.v_ops_provider_utilization_weekly
                    WHERE is_below_minimum_threshold = TRUE
                    """
                ).fetchone()[0],
            ),
        ]
    finally:
        con.close()


def main() -> int:
    print("Iteration 3 validation")
    for migration_path in MIGRATION_PATHS:
        print(f"Applying migration: {migration_path}")
    rebuild_requirement_views()
    print("Gold analytical views built")
    print()

    results = run_checks()
    failures = [result for result in results if not result.passed]

    for result in results:
        status = "PASS" if result.passed else "FAIL"
        print(f"[{status}] {result.name}")
        print(f"  expected: {result.expected}")
        print(f"  actual:   {result.actual}")

    print()
    print(f"Checks run: {len(results)}")
    print(f"Passed: {len(results) - len(failures)}")
    print(f"Failed: {len(failures)}")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
