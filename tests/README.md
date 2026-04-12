# Data Warehouse Tests

This directory contains comprehensive test coverage for the PawsFirst veterinary warehouse.

## Test Structure

### `conftest.py`
Shared pytest fixtures and configuration:
- `test_connection`: Isolated test database for unit tests
- `production_connection`: Read-only connection to production warehouse for integration tests
- `sample_*_data`: Fixture factories for test data

### `test_silver_transforms.py`
Unit tests for silver layer transformations:
- View creation and structure
- Data deduplication
- Type conversion
- Name mapping and remapping
- Data quality rules

### `test_gold_requirements.py`
Unit tests for gold layer requirement views:
- **Requirement 1**: Clinic Appointment Volume (metrics calculation)
- **Requirement 2**: Referral Funnel (stage monotonicity)
- **Requirement 3**: Revenue vs Budget (target comparisons)
- **Requirement 4**: Provider Utilization (threshold flagging)
- **Requirement 5**: Duplicate Patient Detection (matching signals)
- **Requirement 6**: Patient Retention (cohort calculations)

### `test_integration.py`
Integration tests against production warehouse:
- All requirement views exist and are populated
- Foundation dimensions populated
- Foundation facts populated
- All metrics properly bounded and constrained
- Data quality and business rule validation

## Running Tests

### Run all tests
```bash
pytest
```

### Run specific test file
```bash
pytest tests/test_gold_requirements.py
```

### Run specific test
```bash
pytest tests/test_integration.py::TestProductionWarehouse::test_all_requirement_views_exist
```

### Run with verbose output
```bash
pytest -v
```

### Run with coverage report
```bash
pytest --cov=flows --cov-report=html
```

### Run only unit tests (fast)
```bash
pytest tests/test_silver_transforms.py tests/test_gold_requirements.py
```

### Run only integration tests (against production)
```bash
pytest tests/test_integration.py
```

## Test Philosophy

- **Unit tests** create isolated test databases for fast, repeatable testing
- **Integration tests** run against production to verify end-to-end correctness
- **Fixtures** provide reusable test data and connection management
- **No cleanup needed** - test databases are automatic isolated and cleaned up

## Adding New Tests

When adding a new feature:

1. Add unit test with mock data in test database
2. Add integration test to verify against production
3. Use descriptive test names: `test_requirement_N_[feature_being_tested]`
4. Document expected behavior in docstring
5. Run full test suite before committing

## CI/CD Integration

These tests are designed to run in CI pipelines:
```yaml
# Example GitHub Actions workflow
- name: Run tests
  run: pytest --junitxml=results.xml
```
