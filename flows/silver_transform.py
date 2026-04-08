"""
PawsFirst Veterinary Warehouse — Silver Staging Views

Creates cleaned, deduplicated staging views in the silver schema.

Usage:
    PYTHONPATH=. uv run python flows/silver_transform.py
"""

from __future__ import annotations

import time
from pathlib import Path

from prefect import flow, get_run_logger, task

from flows.common import ensure_schemas, get_connection, run_migration

MIGRATION_PATH = Path(__file__).parent.parent / "sql" / "migrations" / "0002_create_silver_views.sql"


@task(
    name="Create silver views",
    retries=1,
    retry_delay_seconds=5,
    tags=["silver", "transform"],
)
def create_silver_views() -> dict:
    """Create all silver staging views."""
    logger = get_run_logger()
    con = get_connection()
    views = [
        "stg_vet_clinic",
        "stg_vet_owner",
        "stg_vet_patient",
        "stg_vet_provider",
        "stg_vet_appointment",
        "stg_vet_invoice",
        "stg_vet_budget_target",
        "stg_vet_referral",
    ]

    results = {}

    try:
        ensure_schemas(con)
        run_migration(con, str(MIGRATION_PATH))
        logger.info("Silver migration applied successfully")

        for view_name in views:
            try:
                row_count = con.execute(
                    f"SELECT COUNT(*) FROM silver.{view_name}"
                ).fetchone()[0]
                logger.info(f"Created silver.{view_name} ({row_count:,} rows)")
                results[view_name] = {"status": "success", "rows": row_count}
            except Exception as e:
                logger.error(f"Failed to create silver.{view_name}: {e}")
                results[view_name] = {"status": "failed", "error": str(e)}
    finally:
        con.close()

    return results


@flow(
    name="pawsfirst-silver-transform",
    description="Create silver staging views from bronze data",
    retries=0,
    timeout_seconds=120,
)
def silver_transform() -> dict:
    """Create all silver staging views."""
    logger = get_run_logger()
    start_time = time.time()

    logger.info("Starting silver transform")
    results = create_silver_views()

    duration = time.time() - start_time
    failed = [k for k, v in results.items() if v.get("status") == "failed"]

    logger.info(f"Silver transform complete in {duration:.1f}s")
    if failed:
        logger.warning(f"Failed views: {failed}")

    return {
        "status": "success" if not failed else "partial_failure",
        "views": results,
        "duration_seconds": round(duration, 1),
    }


if __name__ == "__main__":
    result = silver_transform()
    print(f"\nResult: {result['status']}")
    for name, info in result["views"].items():
        status = info["status"]
        rows = info.get("rows", "N/A")
        print(f"  silver.{name}: {rows} rows ({status})")
