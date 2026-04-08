"""
Iteration 1 validation script.

Rebuilds the silver layer and validates the silver stabilization work.

Usage:
    ./.venv/Scripts/python.exe scripts/validate_iteration_1.py
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

MIGRATION_PATH = REPO_ROOT / "sql" / "migrations" / "0002_create_silver_views.sql"


@dataclass
class CheckResult:
    name: str
    expected: Any
    actual: Any

    @property
    def passed(self) -> bool:
        return self.expected == self.actual


def rebuild_silver() -> None:
    con = get_connection()
    try:
        ensure_schemas(con)
        run_migration(con, str(MIGRATION_PATH))
    finally:
        con.close()


def run_checks() -> list[CheckResult]:
    con = get_connection()
    try:
        return [
            CheckResult(
                name="silver views exist",
                expected=[
                    ("stg_vet_appointment",),
                    ("stg_vet_budget_target",),
                    ("stg_vet_clinic",),
                    ("stg_vet_invoice",),
                    ("stg_vet_owner",),
                    ("stg_vet_patient",),
                    ("stg_vet_provider",),
                    ("stg_vet_referral",),
                ],
                actual=con.execute(
                    """
                    SELECT table_name
                    FROM information_schema.views
                    WHERE table_schema = 'silver'
                    ORDER BY table_name
                    """
                ).fetchall(),
            ),
            CheckResult(
                name="silver patient row count",
                expected=2000,
                actual=con.execute(
                    "SELECT COUNT(*) FROM silver.stg_vet_patient"
                ).fetchone()[0],
            ),
            CheckResult(
                name="renamed clinic patients remapped",
                expected=[(1012, 1013, "Riverside East", 107)],
                actual=con.execute(
                    """
                    SELECT source_clinic_id, clinic_id, clinic_name, COUNT(*)
                    FROM silver.stg_vet_patient
                    WHERE source_clinic_id != clinic_id
                    GROUP BY 1, 2, 3
                    ORDER BY 1, 2, 3
                    """
                ).fetchall(),
            ),
            CheckResult(
                name="pre-opening appointments removed",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM silver.stg_vet_appointment AS appointment
                    JOIN silver.stg_vet_clinic AS clinic
                      ON appointment.source_clinic_id = clinic.clinic_id
                    WHERE appointment.appointment_date < clinic.opened_date
                    """
                ).fetchone()[0],
            ),
            CheckResult(
                name="negative referral durations removed",
                expected=0,
                actual=con.execute(
                    "SELECT COUNT(*) FROM silver.stg_vet_referral WHERE days_in_stage < 0"
                ).fetchone()[0],
            ),
            CheckResult(
                name="duplicate referral stages removed",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM (
                        SELECT referral_id, stage, COUNT(*) AS row_count
                        FROM silver.stg_vet_referral
                        GROUP BY 1, 2
                        HAVING COUNT(*) > 1
                    )
                    """
                ).fetchone()[0],
            ),
            CheckResult(
                name="referral stage regressions removed",
                expected=0,
                actual=con.execute(
                    """
                    WITH ordered AS (
                        SELECT
                            referral_id,
                            stage_rank,
                            LAG(stage_rank) OVER (
                                PARTITION BY referral_id
                                ORDER BY stage_rank
                            ) AS previous_stage_rank
                        FROM silver.stg_vet_referral
                    )
                    SELECT COUNT(*)
                    FROM ordered
                    WHERE previous_stage_rank IS NOT NULL
                      AND stage_rank < previous_stage_rank
                    """
                ).fetchone()[0],
            ),
        ]
    finally:
        con.close()


def main() -> int:
    print("Iteration 1 validation")
    print(f"Applying migration: {MIGRATION_PATH}")
    rebuild_silver()
    print("Silver migration applied")
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
