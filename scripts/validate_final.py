"""
Final validation script.

Runs the iteration validators in sequence and prints a compact summary.

Usage:
    ./.venv/Scripts/python.exe scripts/validate_final.py
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import subprocess
import sys
import time

REPO_ROOT = Path(__file__).parent.parent
PYTHON_EXE = REPO_ROOT / ".venv" / "Scripts" / "python.exe"
VALIDATORS = [
    REPO_ROOT / "scripts" / "validate_iteration_1.py",
    REPO_ROOT / "scripts" / "validate_iteration_2.py",
    REPO_ROOT / "scripts" / "validate_iteration_3.py",
    REPO_ROOT / "scripts" / "validate_iteration_4.py",
    REPO_ROOT / "scripts" / "validate_iteration_6.py",
]
MAX_ATTEMPTS = 2


@dataclass
class ValidationResult:
    name: str
    passed: bool
    return_code: int
    summary: str


def run_validator(validator_path: Path) -> ValidationResult:
    last_result: ValidationResult | None = None

    for attempt in range(1, MAX_ATTEMPTS + 1):
        process = subprocess.run(
            [str(PYTHON_EXE), str(validator_path)],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
            errors="replace",
        )
        output = process.stdout.strip() or process.stderr.strip() or "no output"
        summary_line = output.splitlines()[-1] if output.splitlines() else output

        last_result = ValidationResult(
            name=validator_path.name,
            passed=process.returncode == 0,
            return_code=process.returncode,
            summary=summary_line,
        )

        if last_result.passed:
            return last_result

        if attempt < MAX_ATTEMPTS:
            time.sleep(1)

    return last_result or ValidationResult(
        name=validator_path.name,
        passed=False,
        return_code=1,
        summary="no output",
    )


def main() -> int:
    print("Final validation")
    print("Running iteration validators:")
    for validator in VALIDATORS:
        print(f"  - {validator.name}")
    print()

    results = [run_validator(validator) for validator in VALIDATORS]
    failures = [result for result in results if not result.passed]

    for result in results:
        status = "PASS" if result.passed else "FAIL"
        print(f"[{status}] {result.name}")
        print(f"  return_code: {result.return_code}")
        print(f"  summary: {result.summary}")

    print()
    print(f"Validators run: {len(results)}")
    print(f"Passed: {len(results) - len(failures)}")
    print(f"Failed: {len(failures)}")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
