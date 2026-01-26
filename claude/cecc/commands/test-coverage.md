# Test Coverage

Analyze test coverage and generate missing tests across TypeScript, Kotlin, and Python projects.

## Coverage Commands by Language

| Language | Command | Report Location |
|----------|---------|-----------------|
| TypeScript/JS | `npm test -- --coverage` | `coverage/` |
| Kotlin (Gradle) | `./gradlew test jacocoTestReport` | `build/reports/jacoco/test/html/` |
| Python | `pytest --cov --cov-report=html` | `htmlcov/` |

## Workflow

1. **Detect project type** and run appropriate coverage command:
   - `package.json` → `npm test -- --coverage`
   - `build.gradle.kts` → `./gradlew test jacocoTestReport`
   - `pyproject.toml` → `pytest --cov --cov-report=term-missing`

2. **Analyze coverage report**:
   - TypeScript: `coverage/coverage-summary.json`
   - Kotlin: `build/reports/jacoco/test/jacocoTestReport.xml`
   - Python: `.coverage` file or terminal output

3. **Identify files below 80% coverage threshold**

4. **For each under-covered file**:
   - Analyze untested code paths
   - Generate unit tests for functions
   - Generate integration tests for APIs
   - Generate E2E tests for critical flows

5. **Verify new tests pass**

6. **Show before/after coverage metrics**

7. **Ensure project reaches 80%+ overall coverage**

## Coverage Configuration

### TypeScript/JavaScript (Jest)
```json
// package.json
{
  "jest": {
    "coverageThreshold": {
      "global": {
        "branches": 80,
        "functions": 80,
        "lines": 80,
        "statements": 80
      }
    }
  }
}
```

### Kotlin (JaCoCo)
```kotlin
// build.gradle.kts
tasks.jacocoTestCoverageVerification {
    violationRules {
        rule {
            limit {
                minimum = 0.8.toBigDecimal()
            }
        }
    }
}
```

### Python (pytest-cov)
```toml
# pyproject.toml
[tool.coverage.report]
fail_under = 80
exclude_lines = [
    "pragma: no cover",
    "if TYPE_CHECKING:",
]
```

## Focus On

- Happy path scenarios
- Error handling
- Edge cases (null, undefined, empty, zero)
- Boundary conditions
- Async/concurrent code paths

## Coverage Requirements

- **80% minimum** for all code
- **100% required** for:
  - Financial calculations
  - Authentication logic
  - Security-critical code
  - Core business logic

## Related Commands

- `/tdd` - Test-driven development workflow
- `/pytest` - Run Python tests
- `/gradle-fix` - Fix Gradle build errors
