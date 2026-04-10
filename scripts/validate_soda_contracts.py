"""
Soda Contracts validation script.

Verifies data contracts for silver staging views and gold warehouse objects.

Usage:
    ./.venv/bin/python scripts/validate_soda_contracts.py
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import subprocess
import sys

REPO_ROOT = Path(__file__).parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from flows.common import ensure_schemas, get_connection, run_migration

MIGRATION_PATHS = [
    REPO_ROOT / "sql" / "migrations" / "0002_create_silver_views.sql",
    REPO_ROOT / "sql" / "migrations" / "0003_create_gold_foundation.sql",
    REPO_ROOT / "sql" / "migrations" / "0004_create_gold_requirement_views.sql",
]
CONTRACT_PATHS = [
    REPO_ROOT / "soda" / "contracts" / "silver" / "clinics.yml",
    REPO_ROOT / "soda" / "contracts" / "silver" / "patients.yml",
    REPO_ROOT / "soda" / "contracts" / "silver" / "providers.yml",
    REPO_ROOT / "soda" / "contracts" / "silver" / "appointments.yml",
    REPO_ROOT / "soda" / "contracts" / "silver" / "referrals.yml",
    REPO_ROOT / "soda" / "contracts" / "silver" / "invoices.yml",
    REPO_ROOT / "soda" / "contracts" / "silver" / "budget_targets.yml",
    REPO_ROOT / "soda" / "contracts" / "gold" / "dim_core_clinic.yml",
    REPO_ROOT / "soda" / "contracts" / "gold" / "dim_clin_patient.yml",
    REPO_ROOT / "soda" / "contracts" / "gold" / "fact_clin_appointment.yml",
    REPO_ROOT / "soda" / "contracts" / "gold" / "fact_fin_invoice.yml",
    REPO_ROOT / "soda" / "contracts" / "gold" / "fact_pipe_referral_stage.yml",
    REPO_ROOT / "soda" / "contracts" / "gold" / "ref_core_budget_target.yml",
    REPO_ROOT / "soda" / "contracts" / "gold" / "v_ops_clinic_appointment_weekly.yml",
    REPO_ROOT / "soda" / "contracts" / "gold" / "v_pipe_referral_funnel_monthly.yml",
    REPO_ROOT / "soda" / "contracts" / "gold" / "v_fin_revenue_budget_monthly.yml",
    REPO_ROOT / "soda" / "contracts" / "gold" / "v_ops_provider_utilization_weekly.yml",
    REPO_ROOT / "soda" / "contracts" / "gold" / "v_clin_duplicate_patients_exceptions.yml",
    REPO_ROOT / "soda" / "contracts" / "gold" / "v_clin_patient_retention_monthly.yml",
]
SODA_EXE = REPO_ROOT / ".venv" / "Scripts" / "soda.exe"
CONFIG_PATH = REPO_ROOT / "soda" / "configuration.yml"


@dataclass
class ContractResult:
    name: str
    passed: bool
    return_code: int
    summary: str


def rebuild_objects() -> None:
    con = get_connection()
    try:
        ensure_schemas(con)
        for migration_path in MIGRATION_PATHS:
            run_migration(con, str(migration_path))
    finally:
        con.close()


def _run_contract_process(contract_path: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            str(SODA_EXE),
            "contract",
            "verify",
            "-c",
            str(contract_path),
            "-ds",
            str(CONFIG_PATH),
        ],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        errors="replace",
    )


def verify_contract(contract_path: Path) -> ContractResult:
    process = _run_contract_process(contract_path)
    if process.returncode != 0:
        process = _run_contract_process(contract_path)
    output = process.stdout.strip() or process.stderr.strip() or "no output"
    summary_line = output.splitlines()[-1] if output.splitlines() else output
    return ContractResult(
        name=contract_path.relative_to(REPO_ROOT).as_posix(),
        passed=process.returncode == 0,
        return_code=process.returncode,
        summary=summary_line,
    )


def main() -> int:
    print("Soda Contracts validation")
    print("Applying migrations:")
    for migration_path in MIGRATION_PATHS:
        print(f"  - {migration_path}")
    rebuild_objects()
    print("Warehouse objects built")
    print()

    print("Verifying Soda contracts:")
    results = [verify_contract(contract_path) for contract_path in CONTRACT_PATHS]
    failures = [result for result in results if not result.passed]

    for result in results:
        status = "PASS" if result.passed else "FAIL"
        print(f"[{status}] {result.name}")
        print(f"  return_code: {result.return_code}")
        print(f"  summary: {result.summary}")

    print()
    print(f"Contracts run: {len(results)}")
    print(f"Passed: {len(results) - len(failures)}")
    print(f"Failed: {len(failures)}")

    if failures:
        print()
        print("Failed contracts:")
        for result in failures:
            print(f"  - {result.name}")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
