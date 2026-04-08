"""
Iteration 6 validation script.

Builds the full warehouse including the expanded requirement views and validates
the new outputs for requirements 5 and 6.

Usage:
    ./.venv/Scripts/python.exe scripts/validate_iteration_6.py
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
    REPO_ROOT / "sql" / "migrations" / "0005_create_gold_expansion_views.sql",
]


@dataclass
class CheckResult:
    name: str
    expected: Any
    actual: Any

    @property
    def passed(self) -> bool:
        return self.expected == self.actual


def rebuild_expansion_views() -> None:
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
                name="expanded gold views exist",
                expected=[
                    ("v_clin_duplicate_patients_exceptions",),
                    ("v_clin_patient_retention_monthly",),
                ],
                actual=con.execute(
                    """
                    SELECT table_name
                    FROM information_schema.views
                    WHERE table_schema = 'gold'
                      AND table_name IN (
                          'v_clin_duplicate_patients_exceptions',
                          'v_clin_patient_retention_monthly'
                      )
                    ORDER BY table_name
                    """
                ).fetchall(),
            ),
            CheckResult(
                name="duplicate patient exceptions has rows",
                expected=True,
                actual=con.execute(
                    "SELECT COUNT(*) > 0 FROM gold.v_clin_duplicate_patients_exceptions"
                ).fetchone()[0],
            ),
            CheckResult(
                name="retention view has rows",
                expected=True,
                actual=con.execute(
                    "SELECT COUNT(*) > 0 FROM gold.v_clin_patient_retention_monthly"
                ).fetchone()[0],
            ),
            CheckResult(
                name="duplicate patient pairs are distinct",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM gold.v_clin_duplicate_patients_exceptions
                    WHERE patient_id_left = patient_id_right
                    """
                ).fetchone()[0],
            ),
            CheckResult(
                name="duplicate patient reasons are populated",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM gold.v_clin_duplicate_patients_exceptions
                    WHERE match_reasons IS NULL OR match_reasons = ''
                    """
                ).fetchone()[0],
            ),
            CheckResult(
                name="retention cohort size is positive",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM gold.v_clin_patient_retention_monthly
                    WHERE cohort_size <= 0
                    """
                ).fetchone()[0],
            ),
            CheckResult(
                name="retention rates are bounded",
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
            ),
            CheckResult(
                name="retention rates are monotonic",
                expected=0,
                actual=con.execute(
                    """
                    SELECT COUNT(*)
                    FROM gold.v_clin_patient_retention_monthly
                    WHERE retention_30_day_rate > retention_60_day_rate
                       OR retention_60_day_rate > retention_90_day_rate
                    """
                ).fetchone()[0],
            ),
        ]
    finally:
        con.close()


def main() -> int:
    print("Iteration 6 validation")
    for migration_path in MIGRATION_PATHS:
        print(f"Applying migration: {migration_path}")
    rebuild_expansion_views()
    print("Expanded gold views built")
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
