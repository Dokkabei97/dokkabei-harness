---
name: test
description: "Project analysis and automated test code/environment generation for unit, integration, e2e, and performance testing"
category: testing
complexity: advanced
mcp-servers: [playwright]
personas: []
---

# /test - Test Code and Environment Generator

## Triggers
- New project requiring test infrastructure setup from scratch
- Test coverage improvement needs for existing codebase
- E2E test automation requirements with Playwright integration
- Performance/load testing environment setup with k6
- CI/CD pipeline test integration and configuration needs
- Migration to new test framework or restructuring test architecture

## Usage
```
/test [target] [options]

Options:
  --type unit|integration|e2e|performance  Test type to generate (default: unit)
  --mode standard|tdd                      Test generation mode (default: standard)
  --output <path>                          Output directory for test files
  --framework <name>                       Force specific test framework
  --target <path>                          Scope of files to generate tests for
  --coverage                               Include coverage configuration
  --parallel                               Configure parallel test execution
  --ci                                     Generate CI/CD workflow files
  --mock                                   Include mock setup (default: true for unit/integration)
  --config-only                            Generate only configuration, no test code

TDD Options (--mode tdd):
  --spec <description>                     Specification to convert to tests
  --spec-file <path>                       File containing specifications (yaml, json, md)
  --cycle red|green|refactor               Start from specific TDD phase (default: red)
  --watch                                  Enable TDD watch mode with cycle guidance
  --strict                                 Enforce TDD cycle order validation
  --iterations <number>                    Number of TDD cycles to scaffold (default: 1)

E2E Options (--type e2e):
  --browser chromium|firefox|webkit|all    Playwright browser (default: chromium)
  --headless                               Headless mode (default: true)
  --base-url <url>                         Base URL for tests

Performance Options (--type performance):
  --vus <number>                           Virtual users (default: 10)
  --duration <time>                        Test duration (default: 30s)
  --threshold <metrics>                    Performance thresholds
```

## Behavioral Flow

### Standard Flow
1. **Discover**: Detect project language, framework, and existing test structure
2. **Analyze**: Identify test targets (functions, classes, endpoints, pages)
3. **Configure**: Generate test framework configuration files
4. **Generate**: Create test skeleton code with appropriate patterns
5. **Document**: Provide execution instructions and next steps

### Type-Specific Flows

#### Unit Test Flow
1. Scan source files for testable units (functions, classes, methods)
2. Detect existing test framework or select language-appropriate default
3. Generate test configuration (jest.config, vitest.config, pytest.ini, etc.)
4. Create test file skeletons with describe/it or test function structure
5. Add mock setup for dependencies if --mock enabled

#### Integration Test Flow
1. Identify service boundaries and external dependencies
2. Analyze API endpoints, database connections, message queues
3. Generate test database configuration and docker-compose.test.yml
4. Create integration test files with proper setup/teardown
5. Generate fixture files and test data templates

#### E2E Test Flow
1. Analyze application routes and page structure
2. Detect development server configuration
3. Generate playwright.config.ts with browser settings
4. Create Page Object Model files for identified pages
5. Generate test scenarios for critical user flows

#### Performance Test Flow
1. Identify API endpoints and user scenarios
2. Analyze authentication mechanisms
3. Generate k6 scripts (load, stress, spike, soak tests)
4. Configure thresholds and metrics collection
5. Create documentation for result interpretation

#### TDD Test Flow (--mode tdd)
TDD mode follows the Red-Green-Refactor cycle for test-driven development.

**TDD Cycle:**
```
┌─────────────────────────────────────────────────────────┐
│   ┌─────┐    Write Test    ┌───────┐    Test Fails     │
│   │START│ ───────────────> │  RED  │ ────────────────┐ │
│   └─────┘                  └───────┘                 │ │
│                                                       │ │
│   ┌──────────┐   Tests Pass  ┌───────┐   Write Code  │ │
│   │ REFACTOR │ <──────────── │ GREEN │ <─────────────┘ │
│   └──────────┘               └───────┘                  │
│        │                                                │
│        └────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────┘
```

**Flow Steps:**
1. **Spec**: Parse specification from `--spec`, `--spec-file`, or interactive input
2. **Red**: Generate failing tests with expects but no implementation
3. **Verify-Red**: Provide commands to confirm tests fail
4. **Green**: Generate minimal implementation to pass tests
5. **Verify-Green**: Provide commands to confirm tests pass
6. **Refactor**: Suggest code improvements maintaining test passage
7. **Document**: Generate TDD guide and cycle summary

**Red Phase (Failing Tests):**
- Generate test files with descriptive test cases
- Include `expect(true).toBe(false)` placeholders
- Add `// TDD Phase: RED` comments for clarity
- No implementation imports (or stub imports)

**Green Phase (Minimal Implementation):**
- Analyze test files to infer required interfaces
- Generate minimal code to pass all tests
- Include `// TODO` comments for future enhancement
- Allow hardcoded values (to be refactored later)

**Refactor Phase (Code Improvement):**
- Analyze implementation for code smells
- Suggest extraction of interfaces and abstractions
- Recommend improvements ordered by risk level
- Verify refactoring maintains test passage

**Interactive Mode:**
When `--spec` or `--spec-file` is not provided, TDD mode enters interactive mode:
```
> No specification provided. Entering interactive mode.

? What feature are you implementing? [User login functionality]
? What should happen when successful? [Return JWT token with user info]
? What edge cases should be tested?
  [x] Invalid password
  [x] User not found
  [x] Account locked
  [ ] Add custom case
```

## Framework Detection Logic

### Detection Priority
1. Check existing test configuration files
2. Analyze package manager files (package.json, pom.xml, go.mod, etc.)
3. Scan for framework-specific imports in source files
4. Apply language default if no framework detected

### Language Detection Table
| Indicator | Language |
|-----------|----------|
| package.json | JavaScript/TypeScript |
| tsconfig.json | TypeScript |
| pom.xml, build.gradle | Java/Kotlin |
| go.mod | Go |
| requirements.txt, pyproject.toml | Python |
| Cargo.toml | Rust |
| Gemfile | Ruby |

### Framework Mapping Table
| Language | Unit | Integration | E2E | Performance |
|----------|------|-------------|-----|-------------|
| TypeScript/JavaScript | Jest, Vitest, Mocha | Supertest, MSW | Playwright | k6 |
| Python | pytest, unittest | pytest, httpx | Playwright | k6, locust |
| Go | testing, testify | httptest | Playwright | k6, vegeta |
| Java | JUnit 5, TestNG | Spring Test, RestAssured | Playwright | k6, Gatling |
| Kotlin | JUnit 5, Kotest | Spring Test | Playwright | k6, Gatling |
| Rust | cargo test | cargo test | Playwright | k6 |

## Test Type Details

### --type unit (Default)

**Purpose**: Generate unit test infrastructure for isolated component testing

**Generated Structure**:
```
__tests__/
├── unit/
│   ├── [module]/
│   │   └── [file].test.ts
│   └── setup.ts
├── jest.config.ts (or vitest.config.ts)
└── package.json (devDependencies update)
```

**Configuration Template (Jest)**:
```typescript
export default {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/__tests__/unit'],
  testMatch: ['**/*.test.ts'],
  coverageDirectory: 'coverage',
  collectCoverageFrom: ['src/**/*.ts', '!src/**/*.d.ts'],
};
```

**Scripts Added**:
- `test` - Run all unit tests
- `test:watch` - Run tests in watch mode
- `test:coverage` - Run tests with coverage report

### --type integration

**Purpose**: Generate integration test setup for service and API testing

**Generated Structure**:
```
__tests__/
├── integration/
│   ├── api/
│   │   └── [endpoint].integration.test.ts
│   ├── database/
│   │   └── [repository].integration.test.ts
│   ├── fixtures/
│   │   └── testData.json
│   └── setup/
│       ├── testDatabase.ts
│       └── mockServer.ts
├── docker-compose.test.yml
└── .env.test
```

**docker-compose.test.yml Template**:
```yaml
version: '3.8'
services:
  test-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
      POSTGRES_DB: test_db
    ports:
      - "5433:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U test"]
      interval: 5s
      timeout: 5s
      retries: 5
```

**Scripts Added**:
- `test:integration` - Run integration tests
- `test:integration:docker` - Run with Docker services

### --type e2e

**Purpose**: Generate Playwright-based E2E test environment

**Generated Structure**:
```
e2e/
├── tests/
│   ├── auth/
│   │   ├── login.spec.ts
│   │   └── logout.spec.ts
│   ├── pages/
│   │   └── home.spec.ts
│   └── flows/
│       └── userJourney.spec.ts
├── fixtures/
│   └── testData.ts
├── pages/
│   ├── basePage.ts
│   └── loginPage.ts
└── playwright.config.ts
```

**playwright.config.ts Template**:
```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e/tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
  ],
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
  },
});
```

**Page Object Model Template**:
```typescript
import { Page, Locator } from '@playwright/test';

export class BasePage {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  async navigate(path: string) {
    await this.page.goto(path);
  }
}
```

**Scripts Added**:
- `test:e2e` - Run E2E tests
- `test:e2e:headed` - Run with visible browser
- `test:e2e:debug` - Run in debug mode

### --type performance

**Purpose**: Generate k6-based performance test environment

**Generated Structure**:
```
performance/
├── scripts/
│   ├── load-test.js
│   ├── stress-test.js
│   ├── spike-test.js
│   └── soak-test.js
├── scenarios/
│   ├── api-endpoints.js
│   └── user-journey.js
├── config/
│   ├── thresholds.js
│   └── options.js
├── utils/
│   ├── auth.js
│   └── helpers.js
└── README.md
```

**k6 Load Test Template**:
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 10 },  // Ramp up
    { duration: '5m', target: 10 },  // Stay at 10 users
    { duration: '2m', target: 0 },   // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const res = http.get('http://localhost:3000/api/health');
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  sleep(1);
}
```

**k6 Stress Test Template**:
```javascript
export const options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '5m', target: 100 },
    { duration: '2m', target: 200 },
    { duration: '5m', target: 200 },
    { duration: '2m', target: 0 },
  ],
};
```

**Commands**:
- `k6 run performance/scripts/load-test.js`
- `k6 run performance/scripts/stress-test.js`
- `k6 run --out json=results.json performance/scripts/load-test.js`

### --mode tdd

**Purpose**: Generate TDD-style tests following Red-Green-Refactor cycle

**Generated Structure**:
```
__tests__/
├── tdd/
│   ├── red/
│   │   └── [feature].test.ts
│   ├── specs/
│   │   └── [feature].spec.yaml
│   └── README.md
src/
└── [feature]/
    └── [Implementation].ts
```

**Spec File Format (YAML)**:
```yaml
feature: User Authentication
scenarios:
  - name: Successful login
    expected: User receives an auth token
  - name: Failed login - wrong password
    expected: System throws InvalidCredentialsError
  - name: Failed login - user not found
    expected: System throws UserNotFoundError
```

**Red Phase Template (TypeScript)**:
```typescript
// TDD Phase: RED - Tests should FAIL until implementation is complete

describe('{{ClassName}}', () => {
  describe('{{methodName}}', () => {
    it('should {{expectedBehavior}}', () => {
      // Arrange
      // TODO: Set up test fixtures

      // Act
      // TODO: Call the method under test

      // Assert
      expect(true).toBe(false); // RED: Replace with actual assertion
    });

    it.todo('should handle edge case: {{edgeCase}}');
  });
});
```

**Red Phase Template (Python)**:
```python
# TDD Phase: RED - Tests should FAIL until implementation is complete

import pytest

class Test{{ClassName}}:
    """TDD Phase: RED - All tests should fail initially"""

    def test_{{method_name}}_should_{{expected_behavior}}(self):
        # Arrange
        # TODO: Set up test fixtures

        # Act
        # TODO: Call the method under test

        # Assert
        assert False, "RED: Replace with actual assertion"

    @pytest.mark.skip(reason="TDD: Not yet implemented")
    def test_{{method_name}}_edge_case_{{edge_case}}(self):
        pass
```

**Red Phase Template (Go)**:
```go
// TDD Phase: RED - Tests should FAIL until implementation is complete

package {{package}}_test

import (
    "testing"
)

func Test{{FunctionName}}_Should{{ExpectedBehavior}}(t *testing.T) {
    // Arrange
    // TODO: Set up test fixtures

    // Act
    // TODO: Call the function under test

    // Assert
    t.Fatal("RED: Replace with actual assertion")
}
```

**Green Phase Template (TypeScript)**:
```typescript
// TDD Phase: GREEN - Minimal implementation to pass tests

export class {{ClassName}} {
  {{methodName}}({{params}}): {{returnType}} {
    // Minimal implementation to pass tests
    // TODO: Replace with actual implementation
    return {{minimalReturn}};
  }
}
```

**TDD Watch Mode Configuration**:
```typescript
// tdd.config.ts
export default {
  testPattern: '**/*.test.{ts,js}',
  sourcePattern: 'src/**/*.{ts,js}',
  tddCycle: {
    autoDetectPhase: true,
    showGuidance: true,
  },
};
```

**Scripts Added**:
- `test:tdd` - Run tests in TDD watch mode with cycle guidance
- `test:tdd:red` - Run only red phase tests
- `test:tdd:coverage` - Run TDD tests with coverage

## Tool Coordination
- **Glob**: File discovery and project structure analysis
- **Grep**: Pattern detection for frameworks and test targets
- **Read**: Source code inspection and configuration analysis
- **Bash**: Package installation commands and environment setup
- **Write**: Test file and configuration generation

## Key Patterns
- **Framework Detection**: Automatic language and test framework identification
- **Convention Matching**: Align with existing project test conventions
- **Skeleton Generation**: Create runnable test templates with proper structure
- **Configuration First**: Establish test infrastructure before code generation
- **Progressive Enhancement**: Support incremental test addition

## Examples

### Basic Unit Test Setup
```
/test
# Generates unit test infrastructure for entire project
# Uses detected framework or language default
```

### Specific Directory with Coverage
```
/test src/services --type unit --coverage
# Unit tests for services directory
# Includes coverage configuration
```

### Integration Tests with Docker
```
/test --type integration --ci
# Integration test setup with Docker Compose
# Generates CI/CD workflow for test automation
```

### E2E Tests for Specific Browser
```
/test --type e2e --browser all --base-url http://localhost:3000
# Playwright E2E tests configured for all browsers
# Custom base URL for test environment
```

### Performance Testing Setup
```
/test --type performance --vus 50 --duration 5m
# k6 performance tests with 50 virtual users
# 5-minute test duration
```

### Configuration Only
```
/test --type unit --config-only
# Generate only test configuration files
# No test code generated
```

### Combined Options
```
/test src/api --type integration --coverage --parallel --ci
# Integration tests for API directory
# With coverage, parallel execution, and CI configuration
```

### TDD Mode - Basic
```
/test --mode tdd
# Enter interactive mode to gather specifications
# Generate failing tests (Red phase)
```

### TDD Mode - With Specification
```
/test --mode tdd --spec "User can login with email and password"
# Parse specification and generate failing tests
# Creates test skeleton with expected behaviors
```

### TDD Mode - From Spec File
```
/test --mode tdd --spec-file features/auth.yaml --type unit
# Load multiple scenarios from YAML specification
# Generate comprehensive test suite
```

### TDD Mode - Green Phase
```
/test --mode tdd --cycle green --target __tests__/tdd/red/login.test.ts
# Analyze existing failing tests
# Generate minimal implementation to pass tests
```

### TDD Mode - Refactor Phase
```
/test --mode tdd --cycle refactor --target src/auth
# Analyze current implementation
# Suggest refactoring improvements
```

### TDD Mode - Watch Mode
```
/test --mode tdd --watch --type unit
# Start TDD watch mode with cycle guidance
# Auto-detect current phase and provide next steps
```

### TDD Mode - Strict
```
/test --mode tdd --strict --spec "Calculate order total with discounts"
# Enforce TDD cycle order
# Warn if tests pass in Red phase
```

### TDD Mode - Multiple Iterations
```
/test --mode tdd --iterations 3 --spec-file features/checkout.yaml
# Scaffold 3 consecutive TDD cycles
# Generate tests for multiple scenarios
```

## Output Format

### Summary Output
```
## Test Environment Setup Summary

### Project Analysis
- Language: TypeScript
- Framework: Next.js 14
- Existing Tests: Jest (5 files detected)
- Test Type: unit

### Generated Files
  __tests__/
  ├── unit/
  │   ├── components/Button.test.tsx
  │   ├── hooks/useAuth.test.ts
  │   └── utils/helpers.test.ts
  ├── jest.config.ts
  └── jest.setup.ts

### Configuration Updates
- Added devDependencies to package.json:
  - jest: ^29.x
  - @types/jest: ^29.x
  - @testing-library/react: ^14.x
  - @testing-library/jest-dom: ^6.x

### Next Steps
1. Install dependencies: `npm install`
2. Run tests: `npm test`
3. Run with coverage: `npm test -- --coverage`

### Test Commands Added
- `npm test` - Run all tests
- `npm test:watch` - Run tests in watch mode
- `npm test:coverage` - Run tests with coverage report
```

## Boundaries

**Will:**
- Automatically detect project language, framework, and existing test structure
- Generate appropriate test framework configuration files
- Create test skeleton code with proper patterns and conventions
- Set up Docker Compose for integration test environments
- Configure Playwright for E2E testing with Page Object Model
- Generate k6 performance test scripts with various test types
- Update package.json or equivalent with test dependencies and scripts
- Generate CI/CD workflow files when requested
- Match existing project conventions for naming and structure
- Generate failing test skeletons from specifications (TDD Red phase)
- Parse spec files in YAML, JSON, or Markdown format (TDD mode)
- Generate minimal implementation code to pass tests (TDD Green phase)
- Provide refactoring suggestions based on code analysis (TDD Refactor phase)
- Configure TDD watch mode with cycle guidance
- Support interactive specification gathering (TDD mode)

**Will Not:**
- Execute tests (generation only)
- Write detailed business logic test cases (skeletons only)
- Provision actual external services (configuration only)
- Modify existing test code or refactor tests
- Guarantee test coverage targets
- Run performance tests against production environments
- Install dependencies automatically (provides commands)
- Generate mock data beyond basic templates
- Enforce TDD cycle order at runtime (guidance only)
- Automatically move files between TDD phases
- Generate production-ready business logic (minimal implementation only)
- Validate specifications for correctness or completeness
