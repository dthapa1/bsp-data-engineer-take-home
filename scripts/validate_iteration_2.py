"""
Iteration 2 validation script.

Builds the gold foundation and validates the shared dimensions and facts.

Usage:
    ./.venv/Scripts/python.exe scripts/validate_iteration_2.py
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

SILVER_MIGRATION_PATH = REPO_ROOT / "sql" / "migrations" / "0002_create_silver_views.sql"
GOLD_MIGRATION_PATH = REPO_ROOT / "sql" / "migrations" / "0003_create_gold_foundation.sql"


@dataclass
class CheckResult:
    name: str
    expected: Any
    actual: Any

    @property
    def passed(self) -> bool:
        return self.expected == self.actual


def rebuild_gold_foundation() -> None:
    con = get_connection()
    try:
        ensure_schemas(con)
        run_migration(con, str(SILVER_MIGRATION_PATH))
        run_migration(con, str(GOLD_MIGRATION_PATH))
    finally:
        con.close()


def run_checks() -> list[CheckResult]:
    con = get_connection()
    try:
        return [
            CheckResult(
                name="gold tables exist",
                expected=[
                    ("dim_clin_patient",),
                    ("dim_core_clinic",),
                    ("fact_clin_appointment",),
                    ("fact_fin_invoice",),
                    ("fact_pipe_referral_stage",),
                    ("ref_core_budget_target",),
                ],
                actual=con.execute(
                    """
                    SELECT table_name
                    FROM information_schema.tables
                    WHERE table_schema = 'gold'
                      AND table_type = 'BASE TABLE'
                    ORDER BY table_name
                    """
                ).fetchall(),
            ),
            CheckResult(
                name="gold clinic dimension row count",
                expected=12,
                actual=con.execute(
                    "SELECT COUNT(*) FROM gold.dim_core_clinic"
                ).fetchone()[0],
            ),
            CheckResult(
                name="gold patient dimension row count",
                expected=2000,
                actual=con.execute(
                    "SELECT COUNT(*) FROM gold.dim_clin_patient"
                ).fetchone()[0],
            ),
            CheckResult(
                name="gold appointment fact row count",
                expected=6621,
                actual=con.execute(
                    "SELECT COUNT(*) FROM gold.fact_clin_appointment"
                ).fetchone()[0],
            ),
            CheckResult(
                name="gold invoice fact row count",
                expected=4751,
                actual=con.execute(
                    "SELECT COUNT(*) FROM gold.fact_fin_invoice"
                ).fetchone()[0],
            ),
            CheckResult(
                name="gold referral stage fact row count",
                expected=2273,
                actual=con.execute(
                    "SELECT COUNT(*) FROM gold.fact_pipe_referral_stage"
                ).fetchone()[0],
            ),
            CheckResult(
                name="gold budget reference row count",
                expected=144,
                actual=con.execute(
                    "SELECT COUNT(*) FROM gold.ref_core_budget_target"
                ).fetchone()[0],
            ),
            CheckResult(
                name="patient dimension current rows",
                expected=2000,
                actual=con.execute(
                    "SELECT COUNT(*) FROM gold.dim_clin_patient WHERE is_current = TRUE"
                ).fetchone()[0],
            ),
            CheckResult(
                name="appointment fact clinic keys populated",
                expected=0,
                actual=con.execute(
                    "SELECT COUNT(*) FROM gold.fact_clin_appointment WHERE clinic_sk IS NULL"
                ).fetchone()[0],
            ),
            CheckResult(
                name="invoice fact clinic keys populated",
                expected=0,
                actual=con.execute(
                    "SELECT COUNT(*) FROM gold.fact_fin_invoice WHERE clinic_sk IS NULL"
                ).fetchone()[0],
            ),
        ]
    finally:
        con.close()


def main() -> int:
    print("Iteration 2 validation")
    print(f"Applying migration: {SILVER_MIGRATION_PATH}")
    print(f"Applying migration: {GOLD_MIGRATION_PATH}")
    rebuild_gold_foundation()
    print("Gold foundation built")
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
