---
description: Enforce test-driven development workflow. Scaffold interfaces, generate tests FIRST, then implement minimal code to pass. Ensure 80%+ coverage.
---

# TDD Command

This command invokes the **tdd-guide** agent to enforce test-driven development methodology.

## What This Command Does

1. **Scaffold Interfaces** - Define types/interfaces first
2. **Generate Tests First** - Write failing tests (RED)
3. **Implement Minimal Code** - Write just enough to pass (GREEN)
4. **Refactor** - Improve code while keeping tests green (REFACTOR)
5. **Verify Coverage** - Ensure 80%+ test coverage

## When to Use

Use `/tdd` when:
- Implementing new features
- Adding new functions/components
- Fixing bugs (write test that reproduces bug first)
- Refactoring existing code
- Building critical business logic

## How It Works

The tdd-guide agent will:

1. **Define interfaces** for inputs/outputs
2. **Write tests that will FAIL** (because code doesn't exist yet)
3. **Run tests** and verify they fail for the right reason
4. **Write minimal implementation** to make tests pass
5. **Run tests** and verify they pass
6. **Refactor** code while keeping tests green
7. **Check coverage** and add more tests if below 80%

## TDD Cycle

```
RED → GREEN → REFACTOR → REPEAT

RED:      Write a failing test
GREEN:    Write minimal code to pass
REFACTOR: Improve code, keep tests passing
REPEAT:   Next feature/scenario
```

## Example Usage

Choose the example for your project's language:

### TypeScript/JavaScript (Jest/Vitest)

```
User: /tdd I need a function to calculate market liquidity score

Agent (tdd-guide):
# TDD Session: Market Liquidity Score Calculator

## Step 1: Define Interface (SCAFFOLD)

```typescript
// lib/liquidity.ts
export interface MarketData {
  totalVolume: number
  bidAskSpread: number
  activeTraders: number
  lastTradeTime: Date
}

export function calculateLiquidityScore(market: MarketData): number {
  // TODO: Implementation
  throw new Error('Not implemented')
}
```

## Step 2: Write Failing Test (RED)

```typescript
// lib/liquidity.test.ts
import { calculateLiquidityScore } from './liquidity'

describe('calculateLiquidityScore', () => {
  it('should return high score for liquid market', () => {
    const market = {
      totalVolume: 100000,
      bidAskSpread: 0.01,
      activeTraders: 500,
      lastTradeTime: new Date()
    }

    const score = calculateLiquidityScore(market)

    expect(score).toBeGreaterThan(80)
    expect(score).toBeLessThanOrEqual(100)
  })

  it('should return low score for illiquid market', () => {
    const market = {
      totalVolume: 100,
      bidAskSpread: 0.5,
      activeTraders: 2,
      lastTradeTime: new Date(Date.now() - 86400000) // 1 day ago
    }

    const score = calculateLiquidityScore(market)

    expect(score).toBeLessThan(30)
    expect(score).toBeGreaterThanOrEqual(0)
  })

  it('should handle edge case: zero volume', () => {
    const market = {
      totalVolume: 0,
      bidAskSpread: 0,
      activeTraders: 0,
      lastTradeTime: new Date()
    }

    const score = calculateLiquidityScore(market)

    expect(score).toBe(0)
  })
})
```

## Step 3: Run Tests - Verify FAIL

```bash
npm test lib/liquidity.test.ts

FAIL lib/liquidity.test.ts
  ✕ should return high score for liquid market (2 ms)
    Error: Not implemented

1 test failed, 0 passed
```

✅ Tests fail as expected. Ready to implement.

## Step 4: Implement Minimal Code (GREEN)

```typescript
// lib/liquidity.ts
export function calculateLiquidityScore(market: MarketData): number {
  // Handle zero volume edge case
  if (market.totalVolume === 0) {
    return 0
  }

  // Calculate component scores (0-100 scale)
  const volumeScore = Math.min(market.totalVolume / 1000, 100)
  const spreadScore = Math.max(100 - (market.bidAskSpread * 1000), 0)
  const traderScore = Math.min(market.activeTraders / 10, 100)

  // Recent activity bonus
  const hoursSinceLastTrade = (Date.now() - market.lastTradeTime.getTime()) / (1000 * 60 * 60)
  const recencyScore = Math.max(100 - (hoursSinceLastTrade * 10), 0)

  // Weighted average
  const score = (
    volumeScore * 0.4 +
    spreadScore * 0.3 +
    traderScore * 0.2 +
    recencyScore * 0.1
  )

  return Math.min(Math.max(score, 0), 100) // Clamp to 0-100
}
```

## Step 5: Run Tests - Verify PASS

```bash
npm test lib/liquidity.test.ts

PASS lib/liquidity.test.ts
  ✓ should return high score for liquid market (3 ms)
  ✓ should return low score for illiquid market (2 ms)
  ✓ should handle edge case: zero volume (1 ms)

3 tests passed
```

✅ All tests passing!

## Step 6: Refactor (IMPROVE)

```typescript
// lib/liquidity.ts - Refactored with constants and better readability
const WEIGHTS = {
  VOLUME: 0.4,
  SPREAD: 0.3,
  TRADERS: 0.2,
  RECENCY: 0.1,
} as const

const SCALE_FACTORS = {
  VOLUME: 1000,
  SPREAD: 1000,
  TRADERS: 10,
  RECENCY_PENALTY: 10,
} as const

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max)
}

export function calculateLiquidityScore(market: MarketData): number {
  if (market.totalVolume === 0) return 0

  const volumeScore = Math.min(market.totalVolume / SCALE_FACTORS.VOLUME, 100)
  const spreadScore = clamp(100 - (market.bidAskSpread * SCALE_FACTORS.SPREAD), 0, 100)
  const traderScore = Math.min(market.activeTraders / SCALE_FACTORS.TRADERS, 100)

  const hoursSinceLastTrade = (Date.now() - market.lastTradeTime.getTime()) / (1000 * 60 * 60)
  const recencyScore = clamp(100 - (hoursSinceLastTrade * SCALE_FACTORS.RECENCY_PENALTY), 0, 100)

  const weightedScore =
    volumeScore * WEIGHTS.VOLUME +
    spreadScore * WEIGHTS.SPREAD +
    traderScore * WEIGHTS.TRADERS +
    recencyScore * WEIGHTS.RECENCY

  return clamp(weightedScore, 0, 100)
}
```

## Step 7: Verify Tests Still Pass

```bash
npm test lib/liquidity.test.ts

PASS lib/liquidity.test.ts
  ✓ should return high score for liquid market (3 ms)
  ✓ should return low score for illiquid market (2 ms)
  ✓ should handle edge case: zero volume (1 ms)

3 tests passed
```

✅ Refactoring complete, tests still passing!

## Step 8: Check Coverage

```bash
npm test -- --coverage lib/liquidity.test.ts

File           | % Stmts | % Branch | % Funcs | % Lines
---------------|---------|----------|---------|--------
liquidity.ts   |   100   |   100    |   100   |   100

Coverage: 100% ✅ (Target: 80%)
```

✅ TDD session complete!
```

---

### Kotlin (Kotest)

```
User: /tdd I need a function to calculate market liquidity score

Agent (tdd-guide):
# TDD Session: Market Liquidity Score Calculator (Kotlin)

## Step 1: Define Data Class (SCAFFOLD)

```kotlin
// src/main/kotlin/com/example/Liquidity.kt
data class MarketData(
    val totalVolume: Long,
    val bidAskSpread: Double,
    val activeTraders: Int,
    val lastTradeTime: Instant
)

fun calculateLiquidityScore(market: MarketData): Double {
    TODO("Not implemented")
}
```

## Step 2: Write Failing Test (RED)

```kotlin
// src/test/kotlin/com/example/LiquidityTest.kt
import io.kotest.core.spec.style.BehaviorSpec
import io.kotest.matchers.doubles.shouldBeGreaterThan
import io.kotest.matchers.doubles.shouldBeLessThan
import io.kotest.matchers.doubles.shouldBeLessThanOrEqual
import io.kotest.matchers.doubles.shouldBeGreaterThanOrEqual
import io.kotest.matchers.shouldBe
import java.time.Instant

class LiquidityTest : BehaviorSpec({

    Given("a liquid market with high volume and activity") {
        val market = MarketData(
            totalVolume = 100_000L,
            bidAskSpread = 0.01,
            activeTraders = 500,
            lastTradeTime = Instant.now()
        )

        When("calculating liquidity score") {
            val score = calculateLiquidityScore(market)

            Then("should return high score above 80") {
                score shouldBeGreaterThan 80.0
                score shouldBeLessThanOrEqual 100.0
            }
        }
    }

    Given("an illiquid market with low volume") {
        val market = MarketData(
            totalVolume = 100L,
            bidAskSpread = 0.5,
            activeTraders = 2,
            lastTradeTime = Instant.now().minusSeconds(86400)
        )

        When("calculating liquidity score") {
            val score = calculateLiquidityScore(market)

            Then("should return low score below 30") {
                score shouldBeLessThan 30.0
                score shouldBeGreaterThanOrEqual 0.0
            }
        }
    }

    Given("a market with zero volume") {
        val market = MarketData(
            totalVolume = 0L,
            bidAskSpread = 0.0,
            activeTraders = 0,
            lastTradeTime = Instant.now()
        )

        When("calculating liquidity score") {
            val score = calculateLiquidityScore(market)

            Then("should return zero") {
                score shouldBe 0.0
            }
        }
    }
})
```

## Step 3: Run Tests - Verify FAIL

```bash
./gradlew test --tests "com.example.LiquidityTest"

> Task :test FAILED
LiquidityTest > should return high score for liquid market FAILED
    kotlin.NotImplementedError: An operation is not implemented: Not implemented

1 test failed
```

## Step 4: Implement Minimal Code (GREEN)

```kotlin
// src/main/kotlin/com/example/Liquidity.kt
import java.time.Duration
import java.time.Instant
import kotlin.math.max
import kotlin.math.min

fun calculateLiquidityScore(market: MarketData): Double {
    if (market.totalVolume == 0L) return 0.0

    val volumeScore = min(market.totalVolume / 1000.0, 100.0)
    val spreadScore = max(100.0 - (market.bidAskSpread * 1000), 0.0)
    val traderScore = min(market.activeTraders / 10.0, 100.0)

    val hoursSinceLastTrade = Duration.between(market.lastTradeTime, Instant.now()).toHours()
    val recencyScore = max(100.0 - (hoursSinceLastTrade * 10), 0.0)

    val score = volumeScore * 0.4 +
                spreadScore * 0.3 +
                traderScore * 0.2 +
                recencyScore * 0.1

    return score.coerceIn(0.0, 100.0)
}
```

## Step 5: Run Tests - Verify PASS

```bash
./gradlew test --tests "com.example.LiquidityTest"

BUILD SUCCESSFUL
3 tests passed
```

## Step 6: Check Coverage

```bash
./gradlew test jacocoTestReport

# View report at build/reports/jacoco/test/html/index.html
Coverage: 100% ✅
```

✅ TDD session complete!
```

---

### Python (pytest)

```
User: /tdd I need a function to calculate market liquidity score

Agent (tdd-guide):
# TDD Session: Market Liquidity Score Calculator (Python)

## Step 1: Define Data Class (SCAFFOLD)

```python
# app/liquidity.py
from dataclasses import dataclass
from datetime import datetime

@dataclass(frozen=True)
class MarketData:
    total_volume: int
    bid_ask_spread: float
    active_traders: int
    last_trade_time: datetime

def calculate_liquidity_score(market: MarketData) -> float:
    """Calculate market liquidity score (0-100)."""
    raise NotImplementedError("Not implemented")
```

## Step 2: Write Failing Test (RED)

```python
# tests/test_liquidity.py
import pytest
from datetime import datetime, timedelta
from app.liquidity import MarketData, calculate_liquidity_score

class TestCalculateLiquidityScore:

    def test_should_return_high_score_for_liquid_market(self):
        market = MarketData(
            total_volume=100_000,
            bid_ask_spread=0.01,
            active_traders=500,
            last_trade_time=datetime.now()
        )

        score = calculate_liquidity_score(market)

        assert score > 80
        assert score <= 100

    def test_should_return_low_score_for_illiquid_market(self):
        market = MarketData(
            total_volume=100,
            bid_ask_spread=0.5,
            active_traders=2,
            last_trade_time=datetime.now() - timedelta(days=1)
        )

        score = calculate_liquidity_score(market)

        assert score < 30
        assert score >= 0

    def test_should_handle_zero_volume(self):
        market = MarketData(
            total_volume=0,
            bid_ask_spread=0.0,
            active_traders=0,
            last_trade_time=datetime.now()
        )

        score = calculate_liquidity_score(market)

        assert score == 0
```

## Step 3: Run Tests - Verify FAIL

```bash
pytest tests/test_liquidity.py -v

FAILED tests/test_liquidity.py::TestCalculateLiquidityScore::test_should_return_high_score_for_liquid_market
    NotImplementedError: Not implemented

1 failed
```

## Step 4: Implement Minimal Code (GREEN)

```python
# app/liquidity.py
from datetime import datetime

def calculate_liquidity_score(market: MarketData) -> float:
    """Calculate market liquidity score (0-100)."""
    if market.total_volume == 0:
        return 0.0

    volume_score = min(market.total_volume / 1000, 100)
    spread_score = max(100 - (market.bid_ask_spread * 1000), 0)
    trader_score = min(market.active_traders / 10, 100)

    hours_since_last_trade = (datetime.now() - market.last_trade_time).total_seconds() / 3600
    recency_score = max(100 - (hours_since_last_trade * 10), 0)

    score = (
        volume_score * 0.4 +
        spread_score * 0.3 +
        trader_score * 0.2 +
        recency_score * 0.1
    )

    return max(0, min(score, 100))
```

## Step 5: Run Tests - Verify PASS

```bash
pytest tests/test_liquidity.py -v

PASSED tests/test_liquidity.py::TestCalculateLiquidityScore::test_should_return_high_score_for_liquid_market
PASSED tests/test_liquidity.py::TestCalculateLiquidityScore::test_should_return_low_score_for_illiquid_market
PASSED tests/test_liquidity.py::TestCalculateLiquidityScore::test_should_handle_zero_volume

3 passed
```

## Step 6: Check Coverage

```bash
pytest --cov=app --cov-report=term-missing tests/test_liquidity.py

Name                 Stmts   Miss  Cover   Missing
--------------------------------------------------
app/liquidity.py        15      0   100%
--------------------------------------------------
TOTAL                   15      0   100%
```

✅ TDD session complete!
```

---

## Test Commands by Language

| Language | Run Tests | With Coverage | Specific Test |
|----------|-----------|---------------|---------------|
| TypeScript/JS | `npm test` | `npm test -- --coverage` | `npm test -- file.test.ts` |
| Kotlin | `./gradlew test` | `./gradlew test jacocoTestReport` | `./gradlew test --tests "ClassName"` |
| Python | `pytest` | `pytest --cov` | `pytest tests/test_file.py` |

## TDD Best Practices

**DO:**
- ✅ Write the test FIRST, before any implementation
- ✅ Run tests and verify they FAIL before implementing
- ✅ Write minimal code to make tests pass
- ✅ Refactor only after tests are green
- ✅ Add edge cases and error scenarios
- ✅ Aim for 80%+ coverage (100% for critical code)

**DON'T:**
- ❌ Write implementation before tests
- ❌ Skip running tests after each change
- ❌ Write too much code at once
- ❌ Ignore failing tests
- ❌ Test implementation details (test behavior)
- ❌ Mock everything (prefer integration tests)

## Test Types to Include

**Unit Tests** (Function-level):
- Happy path scenarios
- Edge cases (empty, null, max values)
- Error conditions
- Boundary values

**Integration Tests** (Component-level):
- API endpoints
- Database operations
- External service calls
- React components with hooks

**E2E Tests** (use `/e2e` command):
- Critical user flows
- Multi-step processes
- Full stack integration

## Coverage Requirements

- **80% minimum** for all code
- **100% required** for:
  - Financial calculations
  - Authentication logic
  - Security-critical code
  - Core business logic

## Important Notes

**MANDATORY**: Tests must be written BEFORE implementation. The TDD cycle is:

1. **RED** - Write failing test
2. **GREEN** - Implement to pass
3. **REFACTOR** - Improve code

Never skip the RED phase. Never write code before tests.

## Integration with Other Commands

- Use `/plan` first to understand what to build
- Use `/tdd` to implement with tests
- Use `/build-and-fix` if build errors occur
- Use `/code-review` to review implementation
- Use `/test-coverage` to verify coverage

## Related Agents

This command invokes the `tdd-guide` agent located at:
`~/.claude/agents/tdd-guide.md`

And can reference the `tdd-workflow` skill at:
`~/.claude/skills/tdd-workflow/`
