---
name: pytest
description: Run Python tests with pytest. Supports running all tests, specific files, or with coverage.
allowed_tools: ["Bash", "Read", "Edit", "Grep", "Glob"]
---

# Pytest Command

Run Python tests and optionally fix failures.

## Usage Examples

- `/pytest` - Run all tests
- `/pytest tests/test_user.py` - Run specific file
- `/pytest -k "test_create"` - Run tests matching pattern
- `/pytest --cov` - Run with coverage report

## Workflow

1. **Detect Test Configuration**
   Check for pytest configuration:
   - `pyproject.toml` → `[tool.pytest.ini_options]`
   - `pytest.ini`
   - `setup.cfg` → `[tool:pytest]`

2. **Run Tests**
   ```bash
   # Default: verbose output
   pytest -v

   # With coverage (if --cov flag provided)
   pytest -v --cov=app --cov-report=term-missing

   # Specific file or pattern
   pytest -v <file_or_pattern>
   ```

3. **Analyze Results**
   - Count passed/failed/skipped
   - Identify failing tests
   - Check for import errors vs assertion failures

4. **Optional: Fix Failures**
   If tests fail, offer to:
   - Analyze the failure reason
   - Apply minimal fixes
   - Re-run to verify

## Test Types

| Flag | Description |
|------|-------------|
| `-v` | Verbose output |
| `-x` | Stop on first failure |
| `-k "pattern"` | Run matching tests |
| `--cov=app` | Coverage report |
| `--tb=short` | Short tracebacks |
| `-n auto` | Parallel (pytest-xdist) |

## Common Issues & Fixes

### Import Errors
```bash
# Check PYTHONPATH is set
pytest --collect-only
```

### Async Tests Not Running
```toml
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
```

### Fixture Not Found
- Check `conftest.py` exists in tests/
- Verify fixture scope matches usage

## Success Criteria

- All tests pass (or expected failures documented)
- No import errors
- Coverage meets threshold (if configured)

## Report Format

After running:
```
Tests: X passed, Y failed, Z skipped
Coverage: XX%
Duration: X.Xs
```
