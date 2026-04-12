"""
Pytest configuration and shared fixtures for warehouse tests.

Provides:
- Test database connections (isolated from production)
- Schema setup/teardown
- Sample data loading
- Migration helpers
"""

from __future__ import annotations

import pytest
import duckdb
from pathlib import Path
from typing import Generator

REPO_ROOT = Path(__file__).parent.parent
TEST_DB_PATH = REPO_ROOT / ".test_pawsfirst.duckdb"


@pytest.fixture(scope="session")
def test_db_path() -> Path:
    """Return path to test database."""
    return TEST_DB_PATH


@pytest.fixture
def test_connection(test_db_path: Path) -> Generator[duckdb.DuckDBPyConnection, None, None]:
    """
    Provide an isolated test database connection.
    
    Connection is fresh for each test and cleaned up afterwards.
    """
    # Remove any existing test database
    if test_db_path.exists():
        test_db_path.unlink()
    
    con = duckdb.connect(str(test_db_path))
    
    # Create schemas
    for schema in ("bronze", "silver", "gold"):
        con.execute(f"CREATE SCHEMA {schema}")
    
    yield con
    
    con.close()
    
    # Cleanup
    if test_db_path.exists():
        test_db_path.unlink()


@pytest.fixture
def production_connection() -> Generator[duckdb.DuckDBPyConnection, None, None]:
    """Provide connection to production warehouse for integration tests."""
    prod_db = REPO_ROOT / "data" / "pawsfirst.duckdb"
    con = duckdb.connect(str(prod_db), read_only=True)
    yield con
    con.close()


@pytest.fixture
def sample_clinic_data() -> list[dict]:
    """Sample clinic data for testing."""
    return [
        {
            "clinic_id": 1,
            "clinic_name": "Test Clinic A",
            "clinic_area": "Northeast",
            "clinic_state": "MA",
            "reporting_clinic_id": 1,
        },
        {
            "clinic_id": 2,
            "clinic_name": "Test Clinic B",
            "clinic_area": "Southeast",
            "clinic_state": "NC",
            "reporting_clinic_id": 2,
        },
    ]


@pytest.fixture
def sample_patient_data() -> list[dict]:
    """Sample patient data for testing."""
    return [
        {
            "patient_id": 101,
            "patient_name": "Buddy",
            "species": "Canine",
            "breed": "Labrador",
            "date_of_birth": "2020-01-15",
            "clinic_id": 1,
            "reporting_clinic_id": 1,
        },
        {
            "patient_id": 102,
            "patient_name": "Whiskers",
            "species": "Feline",
            "breed": "Siamese",
            "date_of_birth": "2021-06-20",
            "clinic_id": 1,
            "reporting_clinic_id": 1,
        },
    ]


@pytest.fixture
def sample_appointment_data() -> list[dict]:
    """Sample appointment data for testing."""
    return [
        {
            "appointment_id": 1001,
            "patient_id": 101,
            "clinic_id": 1,
            "provider_id": 501,
            "appointment_scheduled_date": "2024-01-10",
            "appointment_status": "completed",
        },
        {
            "appointment_id": 1002,
            "patient_id": 101,
            "clinic_id": 1,
            "provider_id": 501,
            "appointment_scheduled_date": "2024-01-17",
            "appointment_status": "completed",
        },
        {
            "appointment_id": 1003,
            "patient_id": 102,
            "clinic_id": 1,
            "provider_id": 502,
            "appointment_scheduled_date": "2024-01-15",
            "appointment_status": "cancelled",
        },
    ]
