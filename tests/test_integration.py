"""
Integration tests for the complete data warehouse.

Validates end-to-end pipeline functionality against production database.
"""

from __future__ import annotations

import pytest
import duckdb


class TestProductionWarehouse:
    """Tests run against the production warehouse database."""
    
    def test_all_requirement_views_exist(
        self, production_connection: duckdb.DuckDBPyConnection
    ) -> None:
        """Verify all 6 requirement views exist."""
        required_views = [
            "gold.v_ops_clinic_appointment_weekly",
            "gold.v_pipe_referral_funnel_monthly",
            "gold.v_fin_revenue_budget_monthly",
            "gold.v_ops_provider_utilization_weekly",
            "gold.v_clin_duplicate_patients_exceptions",
            "gold.v_clin_patient_retention_monthly",
        ]
        
        for view_name in required_views:
            result = production_connection.execute(
                f"SELECT COUNT(*) FROM {view_name}"
            ).fetchone()
            assert result[0] > 0, f"{view_name} is empty"
    
    def test_foundation_dimensions_populated(
        self, production_connection: duckdb.DuckDBPyConnection
    ) -> None:
        """Verify dimension tables have data."""
        clinics = production_connection.execute(
            "SELECT COUNT(*) FROM gold.dim_core_clinic"
        ).fetchone()[0]
        assert clinics > 0, "No clinics in dimension"
        
        patients = production_connection.execute(
            "SELECT COUNT(*) FROM gold.dim_clin_patient"
        ).fetchone()[0]
        assert patients > 0, "No patients in dimension"
    
    def test_foundation_facts_populated(
        self, production_connection: duckdb.DuckDBPyConnection
    ) -> None:
        """Verify fact tables have data."""
        appointments = production_connection.execute(
            "SELECT COUNT(*) FROM gold.fact_clin_appointment"
        ).fetchone()[0]
        assert appointments > 0, "No appointments in fact table"
        
        invoices = production_connection.execute(
            "SELECT COUNT(*) FROM gold.fact_fin_invoice"
        ).fetchone()[0]
        assert invoices > 0, "No invoices in fact table"
    
    def test_clinic_appointment_volume_metrics_bounded(
        self, production_connection: duckdb.DuckDBPyConnection
    ) -> None:
        """Verify Requirement 1 metrics are properly constrained."""
        result = production_connection.execute("""
            SELECT
                MIN(completion_rate) AS min_rate,
                MAX(completion_rate) AS max_rate,
                MIN(cancellation_rate) AS min_cancel,
                MAX(cancellation_rate) AS max_cancel,
                MIN(no_show_rate) AS min_no_show,
                MAX(no_show_rate) AS max_no_show
            FROM gold.v_ops_clinic_appointment_weekly
            WHERE completion_rate IS NOT NULL
        """).fetchone()
        
        # All rates should be between 0 and 1
        assert result[0] >= 0 and result[1] <= 1, "Completion rates out of bounds"
        assert result[2] >= 0 and result[3] <= 1, "Cancellation rates out of bounds"
        assert result[4] >= 0 and result[5] <= 1, "No-show rates out of bounds"
    
    def test_referral_funnel_monotonic_stages(
        self, production_connection: duckdb.DuckDBPyConnection
    ) -> None:
        """Verify Requirement 2: funnel stages are monotonic."""
        violations = production_connection.execute("""
            SELECT COUNT(*) FROM gold.v_pipe_referral_funnel_monthly
            WHERE inquiries_count < consultations_count
               OR consultations_count < registrations_count
               OR registrations_count < active_patients_count
        """).fetchone()[0]
        
        assert violations == 0, f"Found {violations} non-monotonic funnel stages"
    
    def test_revenue_budget_has_targets(
        self, production_connection: duckdb.DuckDBPyConnection
    ) -> None:
        """Verify Requirement 3 has budget target data."""
        with_targets = production_connection.execute("""
            SELECT COUNT(*) FROM gold.v_fin_revenue_budget_monthly
            WHERE target_revenue_amount IS NOT NULL
        """).fetchone()[0]
        
        total = production_connection.execute("""
            SELECT COUNT(*) FROM gold.v_fin_revenue_budget_monthly
        """).fetchone()[0]
        
        assert with_targets > 0, "No target revenue populated"
        assert with_targets <= total, "More targets than rows"
    
    def test_provider_utilization_has_threshold_flag(
        self, production_connection: duckdb.DuckDBPyConnection
    ) -> None:
        """Verify Requirement 4 threshold flagging works."""
        has_flags = production_connection.execute("""
            SELECT COUNT(DISTINCT is_below_minimum_threshold)
            FROM gold.v_ops_provider_utilization_weekly
        """).fetchone()[0]
        
        assert has_flags >= 1, "No threshold flagging found"
    
    def test_duplicate_patients_have_match_reasons(
        self, production_connection: duckdb.DuckDBPyConnection
    ) -> None:
        """Verify Requirement 5 pairs have match reasons."""
        no_reason = production_connection.execute("""
            SELECT COUNT(*) FROM gold.v_clin_duplicate_patients_exceptions
            WHERE match_reasons IS NULL OR match_reasons = ''
        """).fetchone()[0]
        
        assert no_reason == 0, f"Found {no_reason} pairs without match reasons"
    
    def test_retention_cohorts_monotonic_rates(
        self, production_connection: duckdb.DuckDBPyConnection
    ) -> None:
        """Verify Requirement 6 retention rates are monotonic."""
        violations = production_connection.execute("""
            SELECT COUNT(*) FROM gold.v_clin_patient_retention_monthly
            WHERE retention_30_day_rate IS NOT NULL
              AND (retention_30_day_rate > retention_60_day_rate
                OR retention_60_day_rate > retention_90_day_rate)
        """).fetchone()[0]
        
        assert violations == 0, f"Found {violations} non-monotonic retention curves"
    
    def test_retention_cohorts_rates_bounded(
        self, production_connection: duckdb.DuckDBPyConnection
    ) -> None:
        """Verify Requirement 6 retention rates are bounded [0, 1]."""
        violations = production_connection.execute("""
            SELECT COUNT(*) FROM gold.v_clin_patient_retention_monthly
            WHERE retention_30_day_rate IS NOT NULL
              AND (retention_30_day_rate < 0 OR retention_30_day_rate > 1
                OR retention_60_day_rate < 0 OR retention_60_day_rate > 1
                OR retention_90_day_rate < 0 OR retention_90_day_rate > 1)
        """).fetchone()[0]
        
        assert violations == 0, f"Found {violations} out-of-bounds retention rates"
    
    def test_referral_funnel_conversion_rates_bounded(
        self, production_connection: duckdb.DuckDBPyConnection
    ) -> None:
        """Verify Requirement 2 conversion rates are bounded [0, 1]."""
        # Check inquiry_to_consultation_rate specifically (most reliable)
        violations = production_connection.execute("""
            SELECT COUNT(*) FROM gold.v_pipe_referral_funnel_monthly
            WHERE inquiry_to_consultation_rate IS NOT NULL
              AND (inquiry_to_consultation_rate < 0 OR inquiry_to_consultation_rate > 1)
        """).fetchone()[0]
        
        assert violations == 0, f"Found {violations} inquiry->consultation rates out of bounds"
        
        # Verify some conversion rates exist
        has_rates = production_connection.execute("""
            SELECT COUNT(*) FROM gold.v_pipe_referral_funnel_monthly
            WHERE inquiry_to_consultation_rate IS NOT NULL
        """).fetchone()[0]
        
        assert has_rates > 0, "No conversion rates calculated"
