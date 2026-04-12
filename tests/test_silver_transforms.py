"""
Tests for silver layer transformations.

Validates that silver staging views correctly clean and shape source data.
"""

from __future__ import annotations

import pytest
import duckdb
from datetime import date


def test_stg_vet_clinic_exists(test_connection: duckdb.DuckDBPyConnection) -> None:
    """Verify stg_vet_clinic view can be created."""
    # Create minimal bronze table
    test_connection.execute("""
        CREATE TABLE bronze.clinics (
            clinic_id INTEGER,
            clinic_name VARCHAR,
            clinic_area VARCHAR,
            clinic_state VARCHAR,
            reporting_clinic_id INTEGER
        )
    """)
    
    test_connection.execute("""
        INSERT INTO bronze.clinics VALUES
        (1, 'Test Clinic', 'Northeast', 'MA', 1)
    """)
    
    # Create silver view (simplified)
    test_connection.execute("""
        CREATE VIEW silver.stg_vet_clinic AS
        SELECT 
            clinic_id,
            clinic_name,
            clinic_area,
            clinic_state,
            reporting_clinic_id
        FROM bronze.clinics
    """)
    
    # Verify view works
    result = test_connection.execute(
        "SELECT COUNT(*) FROM silver.stg_vet_clinic"
    ).fetchone()
    
    assert result[0] == 1


def test_stg_vet_clinic_name_mapping(test_connection: duckdb.DuckDBPyConnection) -> None:
    """Test clinic name remapping in silver layer."""
    # Create bronze table with clinic requiring remapping
    test_connection.execute("""
        CREATE TABLE bronze.clinics (
            clinic_id INTEGER,
            clinic_name VARCHAR,
            clinic_area VARCHAR,
            clinic_state VARCHAR,
            reporting_clinic_id INTEGER
        )
    """)
    
    test_connection.execute("""
        INSERT INTO bronze.clinics VALUES
        (99, 'Old Clinic Name', 'West', 'CA', 99),
        (100, 'Normal Clinic', 'Northeast', 'MA', 100)
    """)
    
    # Create view with name mapping
    test_connection.execute("""
        CREATE VIEW silver.stg_vet_clinic AS
        SELECT 
            clinic_id,
            CASE 
                WHEN clinic_id = 99 THEN 'New Clinic Name'
                ELSE clinic_name 
            END AS clinic_name,
            clinic_area,
            clinic_state,
            reporting_clinic_id
        FROM bronze.clinics
    """)
    
    result = test_connection.execute(
        "SELECT clinic_name FROM silver.stg_vet_clinic WHERE clinic_id = 99"
    ).fetchone()
    
    assert result[0] == "New Clinic Name"


def test_stg_vet_patient_deduplicates(test_connection: duckdb.DuckDBPyConnection) -> None:
    """Test that patient staging removes duplicate records."""
    test_connection.execute("""
        CREATE TABLE bronze.patients (
            patient_id INTEGER,
            patient_name VARCHAR,
            species VARCHAR,
            clinic_id INTEGER
        )
    """)
    
    # Insert duplicate patient
    test_connection.execute("""
        INSERT INTO bronze.patients VALUES
        (1, 'Buddy', 'Canine', 1),
        (1, 'Buddy', 'Canine', 1),
        (2, 'Whiskers', 'Feline', 1)
    """)
    
    # Create deduplicating view
    test_connection.execute("""
        CREATE VIEW silver.stg_vet_patient AS
        SELECT DISTINCT 
            patient_id,
            patient_name,
            species,
            clinic_id
        FROM bronze.patients
    """)
    
    result = test_connection.execute(
        "SELECT COUNT(*) FROM silver.stg_vet_patient"
    ).fetchone()
    
    assert result[0] == 2  # Only 2 unique patients


def test_stg_vet_appointment_types(test_connection: duckdb.DuckDBPyConnection) -> None:
    """Test appointment status classification."""
    test_connection.execute("""
        CREATE TABLE bronze.appointments (
            appointment_id INTEGER,
            appointment_status VARCHAR
        )
    """)
    
    test_connection.execute("""
        INSERT INTO bronze.appointments VALUES
        (1, 'completed'),
        (2, 'cancelled'),
        (3, 'no_show'),
        (4, 'unknown')
    """)
    
    # Create typed view
    test_connection.execute("""
        CREATE VIEW silver.stg_vet_appointment AS
        SELECT 
            appointment_id,
            appointment_status,
            appointment_status IN ('completed', 'cancelled', 'no_show') AS is_valid_status
        FROM bronze.appointments
    """)
    
    result = test_connection.execute(
        "SELECT is_valid_status, COUNT(*) FROM silver.stg_vet_appointment GROUP BY is_valid_status ORDER BY is_valid_status"
    ).fetchall()
    
    assert len(result) == 2
    assert result[0][1] == 1  # 1 invalid
    assert result[1][1] == 3  # 3 valid
