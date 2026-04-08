"""
Terminal-friendly warehouse dashboard.

Provides a quick visual confirmation that the gold layer is populated and
that each business requirement view returns sensible output.

Usage:
    ./.venv/Scripts/python.exe scripts/demo_dashboard.py
"""

from __future__ import annotations

from pathlib import Path

import duckdb

REPO_ROOT = Path(__file__).parent.parent
DB_PATH = REPO_ROOT / "data" / "pawsfirst.duckdb"


def print_section(title: str) -> None:
    line = "=" * len(title)
    print()
    print(line)
    print(title)
    print(line)


def print_table(headers: list[str], rows: list[tuple]) -> None:
    string_rows = [[str(value) for value in row] for row in rows]
    widths = [len(header) for header in headers]

    for row in string_rows:
        for index, value in enumerate(row):
            widths[index] = max(widths[index], len(value))

    header_line = " | ".join(
        header.ljust(widths[index]) for index, header in enumerate(headers)
    )
    divider = "-+-".join("-" * width for width in widths)

    print(header_line)
    print(divider)
    for row in string_rows:
        print(" | ".join(value.ljust(widths[index]) for index, value in enumerate(row)))


def fetch_rows(con: duckdb.DuckDBPyConnection, query: str) -> list[tuple]:
    return con.execute(query).fetchall()


def main() -> int:
    if not DB_PATH.exists():
        print(f"Database not found: {DB_PATH}")
        return 1

    con = duckdb.connect(str(DB_PATH))

    try:
        print("PawsFirst Warehouse Dashboard")
        print(f"Database: {DB_PATH}")

        print_section("Gold Object Row Counts")
        count_rows = fetch_rows(
            con,
            """
            SELECT object_name, row_count
            FROM (
                SELECT 'gold.dim_core_clinic' AS object_name, COUNT(*) AS row_count
                FROM gold.dim_core_clinic
                UNION ALL
                SELECT 'gold.dim_clin_patient', COUNT(*)
                FROM gold.dim_clin_patient
                UNION ALL
                SELECT 'gold.fact_clin_appointment', COUNT(*)
                FROM gold.fact_clin_appointment
                UNION ALL
                SELECT 'gold.fact_fin_invoice', COUNT(*)
                FROM gold.fact_fin_invoice
                UNION ALL
                SELECT 'gold.fact_pipe_referral_stage', COUNT(*)
                FROM gold.fact_pipe_referral_stage
                UNION ALL
                SELECT 'gold.ref_core_budget_target', COUNT(*)
                FROM gold.ref_core_budget_target
                UNION ALL
                SELECT 'gold.v_ops_clinic_appointment_weekly', COUNT(*)
                FROM gold.v_ops_clinic_appointment_weekly
                UNION ALL
                SELECT 'gold.v_pipe_referral_funnel_monthly', COUNT(*)
                FROM gold.v_pipe_referral_funnel_monthly
                UNION ALL
                SELECT 'gold.v_fin_revenue_budget_monthly', COUNT(*)
                FROM gold.v_fin_revenue_budget_monthly
                UNION ALL
                SELECT 'gold.v_ops_provider_utilization_weekly', COUNT(*)
                FROM gold.v_ops_provider_utilization_weekly
                UNION ALL
                SELECT 'gold.v_clin_duplicate_patients_exceptions', COUNT(*)
                FROM gold.v_clin_duplicate_patients_exceptions
                UNION ALL
                SELECT 'gold.v_clin_patient_retention_monthly', COUNT(*)
                FROM gold.v_clin_patient_retention_monthly
            )
            ORDER BY object_name
            """,
        )
        print_table(["Object", "Rows"], count_rows)

        print_section("Requirement 1: Clinic Appointment Volume")
        req_1_rows = fetch_rows(
            con,
            """
            SELECT
                clinic_name,
                clinic_region,
                appointment_week_start_date,
                total_appointments,
                ROUND(completion_rate, 3) AS completion_rate,
                is_underperforming
            FROM gold.v_ops_clinic_appointment_weekly
            ORDER BY appointment_week_start_date DESC, total_appointments DESC, clinic_name
            LIMIT 10
            """,
        )
        print_table(
            [
                "Clinic",
                "Region",
                "Week",
                "Appointments",
                "Completion Rate",
                "Underperforming",
            ],
            req_1_rows,
        )

        print_section("Requirement 2: Referral Funnel")
        req_2_rows = fetch_rows(
            con,
            """
            SELECT
                clinic_name,
                referral_source,
                referral_month_start_date,
                inquiries_count,
                registrations_count,
                active_patients_count,
                ROUND(inquiry_to_consultation_rate, 3) AS inquiry_to_consultation_rate
            FROM gold.v_pipe_referral_funnel_monthly
            ORDER BY referral_month_start_date DESC, inquiries_count DESC, clinic_name
            LIMIT 10
            """,
        )
        print_table(
            [
                "Clinic",
                "Source",
                "Month",
                "Inquiries",
                "Registrations",
                "Active",
                "Inquiry->Consult",
            ],
            req_2_rows,
        )

        print_section("Requirement 3: Revenue vs Budget")
        req_3_rows = fetch_rows(
            con,
            """
            SELECT
                clinic_name,
                invoice_month_start_date,
                ROUND(total_revenue_amount, 2) AS total_revenue_amount,
                ROUND(target_revenue_amount, 2) AS target_revenue_amount,
                ROUND(revenue_variance_amount, 2) AS revenue_variance_amount,
                ROUND(collection_rate, 3) AS collection_rate
            FROM gold.v_fin_revenue_budget_monthly
            ORDER BY invoice_month_start_date DESC, total_revenue_amount DESC, clinic_name
            LIMIT 10
            """,
        )
        print_table(
            [
                "Clinic",
                "Month",
                "Revenue",
                "Target",
                "Variance",
                "Collection Rate",
            ],
            req_3_rows,
        )

        print_section("Requirement 4: Provider Utilization")
        req_4_rows = fetch_rows(
            con,
            """
            SELECT
                provider_name,
                clinic_name,
                appointment_week_start_date,
                service_name,
                appointments_count,
                completed_minutes,
                is_below_minimum_threshold
            FROM gold.v_ops_provider_utilization_weekly
            ORDER BY appointment_week_start_date DESC, appointments_count DESC, provider_name
            LIMIT 10
            """,
        )
        print_table(
            [
                "Provider",
                "Clinic",
                "Week",
                "Service",
                "Appointments",
                "Completed Minutes",
                "Below Threshold",
            ],
            req_4_rows,
        )

        print_section("Requirement 5: Duplicate Patient Exceptions")
        req_5_rows = fetch_rows(
            con,
            """
            SELECT
                clinic_name_left,
                REPLACE(match_reasons, ' | ', ', ') AS match_reasons,
                patient_id_left,
                patient_name_left,
                patient_id_right,
                patient_name_right,
                CASE
                    WHEN match_reason_count >= 3 THEN 'high'
                    WHEN match_reason_count = 2 THEN 'medium'
                    ELSE 'low'
                END AS confidence_label
            FROM gold.v_clin_duplicate_patients_exceptions
            ORDER BY match_reason_count DESC, clinic_name_left, patient_id_left, patient_id_right
            LIMIT 10
            """,
        )
        print_table(
            [
                "Clinic",
                "Signal",
                "Patient 1",
                "Name 1",
                "Patient 2",
                "Name 2",
                "Confidence",
            ],
            req_5_rows,
        )

        print_section("Requirement 6: Patient Retention Cohorts")
        req_6_rows = fetch_rows(
            con,
            """
            SELECT
                clinic_name,
                referral_source,
                cohort_month_start_date,
                cohort_size,
                returned_within_30_days_count,
                returned_within_60_days_count,
                ROUND(retention_90_day_rate, 3) AS retention_90_day_rate
            FROM gold.v_clin_patient_retention_monthly
            ORDER BY cohort_month_start_date DESC, cohort_size DESC, clinic_name
            LIMIT 10
            """,
        )
        print_table(
            [
                "Clinic",
                "Source",
                "Cohort Month",
                "New Patients",
                "Retained 30d",
                "Retained 60d",
                "Retained 90d Rate",
            ],
            req_6_rows,
        )

        print_section("Sanity Summary")
        sanity_rows = fetch_rows(
            con,
            """
            SELECT metric, value
            FROM (
                SELECT 'appointment_fact_rows' AS metric, COUNT(*)::VARCHAR AS value
                FROM gold.fact_clin_appointment
                UNION ALL
                SELECT 'invoice_fact_rows', COUNT(*)::VARCHAR
                FROM gold.fact_fin_invoice
                UNION ALL
                SELECT 'referral_stage_rows', COUNT(*)::VARCHAR
                FROM gold.fact_pipe_referral_stage
                UNION ALL
                SELECT 'duplicate_patient_flags', COUNT(*)::VARCHAR
                FROM gold.v_clin_duplicate_patients_exceptions
                UNION ALL
                SELECT 'retention_cohorts', COUNT(*)::VARCHAR
                FROM gold.v_clin_patient_retention_monthly
            )
            ORDER BY metric
            """,
        )
        print_table(["Metric", "Value"], sanity_rows)

        print()
        print("Dashboard complete.")
        print("If the sections above show populated rows, the warehouse is working as expected.")
        return 0
    finally:
        con.close()


if __name__ == "__main__":
    raise SystemExit(main())
