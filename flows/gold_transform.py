"""
PawsFirst Veterinary Warehouse - Gold Foundation Build

Creates shared gold dimensions and facts from silver staging views.

Usage:
    PYTHONPATH=. uv run python flows/gold_transform.py
"""

from __future__ import annotations

import time
from pathlib import Path

from prefect import flow, get_run_logger, task

from flows.common import ensure_schemas, get_connection, run_migration

MIGRATION_PATHS = [
    Path(__file__).parent.parent / "sql" / "migrations" / "0003_create_gold_foundation.sql",
    Path(__file__).parent.parent / "sql" / "migrations" / "0004_gold_requirement_1_clinic_appointment.sql",
    Path(__file__).parent.parent / "sql" / "migrations" / "0005_gold_requirement_2_referral_funnel.sql",
    Path(__file__).parent.parent / "sql" / "migrations" / "0006_gold_requirement_3_revenue_budget.sql",
    Path(__file__).parent.parent / "sql" / "migrations" / "0007_gold_requirement_4_provider_utilization.sql",
    Path(__file__).parent.parent / "sql" / "migrations" / "0008_gold_requirement_5_duplicate_patients.sql",
    Path(__file__).parent.parent / "sql" / "migrations" / "0009_gold_requirement_6_patient_retention.sql",
]


@task(
    name="Build gold foundation",
    retries=1,
    retry_delay_seconds=5,
    tags=["gold", "transform"],
)
def build_gold_foundation() -> dict:
    """Apply the gold migrations and return row counts for core gold objects."""
    logger = get_run_logger()
    con = get_connection()
    tables = [
        "dim_core_clinic",
        "dim_clin_patient",
        "fact_clin_appointment",
        "fact_fin_invoice",
        "fact_pipe_referral_stage",
        "ref_core_budget_target",
    ]
    views = [
        "v_ops_clinic_appointment_weekly",
        "v_pipe_referral_funnel_monthly",
        "v_fin_revenue_budget_monthly",
        "v_ops_provider_utilization_weekly",
        "v_clin_duplicate_patients_exceptions",
        "v_clin_patient_retention_monthly",
    ]
    results = {}

    try:
        ensure_schemas(con)
        for migration_path in MIGRATION_PATHS:
            run_migration(con, str(migration_path))
            logger.info(f"Applied gold migration: {migration_path.name}")

        for object_name in tables:
            row_count = con.execute(
                f"SELECT COUNT(*) FROM gold.{object_name}"
            ).fetchone()[0]
            logger.info(f"Built gold.{object_name} ({row_count:,} rows)")
            results[object_name] = {"status": "success", "rows": row_count}

        for view_name in views:
            row_count = con.execute(
                f"SELECT COUNT(*) FROM gold.{view_name}"
            ).fetchone()[0]
            logger.info(f"Built gold.{view_name} ({row_count:,} rows)")
            results[view_name] = {"status": "success", "rows": row_count}
    finally:
        con.close()

    return results


@flow(
    name="pawsfirst-gold-transform",
    description="Build shared gold warehouse objects from silver staging views",
    retries=0,
    timeout_seconds=180,
)
def gold_transform() -> dict:
    """Create the shared gold warehouse foundation and analytical views."""
    logger = get_run_logger()
    start_time = time.time()

    logger.info("Starting gold transform")
    results = build_gold_foundation()

    duration = time.time() - start_time

    logger.info(f"Gold transform complete in {duration:.1f}s")

    return {
        "status": "success",
        "objects": results,
        "duration_seconds": round(duration, 1),
    }


if __name__ == "__main__":
    result = gold_transform()
    print(f"\nResult: {result['status']}")
    for name, info in result["objects"].items():
        print(f"  gold.{name}: {info['rows']:,} rows ({info['status']})")
