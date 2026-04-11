---
name: tdd-workflow
description: Use this skill when writing new features, fixing bugs, or refactoring code. Enforces test-driven development with 80%+ coverage including unit, integration, and E2E tests. Supports TypeScript (Jest/Vitest/Playwright) and Kotlin (Kotest/MockK/Spring Boot Test).
---

# Test-Driven Development Workflow

This skill ensures all code development follows TDD principles with comprehensive test coverage.

## When to Activate

- Writing new features or functionality
- Fixing bugs or issues
- Refactoring existing code
- Adding API endpoints
- Creating new components

## Core Principles

### 1. Tests BEFORE Code
ALWAYS write tests first, then implement code to make tests pass.

### 2. The Beyonce Rule
> **"If you liked it, you should have put a test on it."**

인프라 변경, 리팩토링, 마이그레이션은 당신의 버그를 잡아줄 책임이 없다. 변경이 코드를 깨뜨렸는데 테스트가 없었다면, 그것은 당신의 책임이다.

### 3. Coverage Requirements — Test Pyramid

```
        ╱╲
       ╱  ╲         E2E Tests (~5%)
      ╱    ╲
     ╱──────╲
    ╱        ╲      Integration Tests (~15%)
   ╱          ╲
  ╱────────────╲
 ╱              ╲   Unit Tests (~80%)
╱────────────────╲
```

| 유형 | 비율 | 특성 | 실행 시간 |
|------|------|------|-----------|
| Unit | ~80% | 순수 로직, side effect 없음, 프로세스 내 실행 | < 50ms/test |
| Integration | ~15% | DB/API 연동, 외부 의존성 포함 | < 5s/test |
| E2E | ~5% | 전체 사용자 플로우, 브라우저/네트워크 포함 | < 30s/test |

**결정 가이드:** Side effect 없는 순수 로직인가? → Unit. DB/외부 서비스 연동인가? → Integration. 사용자 시나리오 전체인가? → E2E.

### 4. Test Double 선호도 계층

```
선호도 (높음 → 낮음):
1. Real implementation  → 가장 높은 신뢰도, 실제 버그 감지
2. Fake                 → 의존성의 in-memory 구현 (예: in-memory DB)
3. Stub                 → 고정 데이터 반환, 행위 없음
4. Mock (interaction)   → 메서드 호출 검증 — 최소한으로 사용
```

> **Mock은 다음 조건에서만 사용한다:** 실제 구현이 너무 느리거나, 비결정적(non-deterministic)이거나, 제어할 수 없는 side effect가 있을 때. **Over-mocking은 프로덕션에서 깨지는 테스트를 만든다.**

### 5. DAMP Over DRY (테스트 코드 한정)
프로덕션 코드에서 DRY(Don't Repeat Yourself)는 옳다. 그러나 테스트에서는 **DAMP(Descriptive And Meaningful Phrases)**가 낫다.

각 테스트는 완전한 이야기를 말해야 하며, 공유 헬퍼를 추적하지 않아도 이해할 수 있어야 한다.

```kotlin
// BAD: Over-DRY — 헬퍼를 따라가야 이해 가능
class OrderTest : BehaviorSpec({
    Given("standard order") {
        val order = createStandardOrder()  // 무슨 주문인지 알 수 없음
        When("processing") { /* ... */ }
    }
})

// GOOD: DAMP — 테스트가 스스로 설명
class OrderTest : BehaviorSpec({
    Given("an order with 3 items totaling 50,000원") {
        val order = Order(
            items = listOf(item(10_000), item(20_000), item(20_000)),
            customer = Customer(tier = GOLD)
        )
        When("processing") { /* ... */ }
    }
})
```

### 6. Test Types

#### Unit Tests
- Individual functions and utilities
- Component logic
- Pure functions
- Helpers and utilities

#### Integration Tests
- API endpoints
- Database operations
- Service interactions
- External API calls

#### E2E Tests (Playwright)
- Critical user flows
- Complete workflows
- Browser automation
- UI interactions

#### Kotlin-Specific Test Types

| Test Style | Framework | Use Case |
|-----------|-----------|----------|
| `BehaviorSpec` | Kotest | Given/When/Then BDD-style tests |
| `FunSpec` | Kotest | Simple function-level unit tests |
| `StringSpec` | Kotest | One-liner concise tests |
| `@WebMvcTest` | Spring Boot Test | Controller layer tests (MockMvc) |
| `@SpringBootTest` | Spring Boot Test | Full integration tests (TestRestTemplate) |
| `@DataJpaTest` | Spring Boot Test | Repository/JPA layer tests |

## Prove-It Pattern (Bug Fix TDD)

버그가 보고되면, **수정을 시작하지 마라.** 먼저 버그를 재현하는 테스트를 작성하라.

```
Bug report arrives
       │
       ▼
  Write a test that reproduces the bug
       │
       ▼
  Test FAILS (confirming the bug exists)
       │
       ▼
  Implement the fix
       │
       ▼
  Test PASSES (proving the fix works)
       │
       ▼
  Run full test suite (no regressions)
```

```kotlin
// Step 1: 버그를 재현하는 테스트 작성
class OrderDiscountTest : FunSpec({
    test("GOLD 등급 고객에게 10% 할인이 적용되어야 한다 - BUG-1234") {
        val order = Order(
            items = listOf(Item(price = 10_000)),
            customer = Customer(tier = GOLD)
        )

        val total = orderService.calculateTotal(order)

        // 버그: 할인이 적용되지 않아 10,000원이 반환됨
        total shouldBe 9_000  // RED: 이 테스트가 실패해야 버그가 확인됨
    }
})

// Step 2: 수정 구현 → 테스트 통과 (GREEN)
// Step 3: 전체 테스트 실행 → 회귀 없음 확인
```

> **서브에이전트 활용**: 복잡한 버그의 경우, 서브에이전트에게 재현 테스트 작성을 위임하면 수정 구현과 분리된 독립적 테스트를 얻을 수 있다. 수정 내용을 모르는 상태에서 작성된 테스트가 더 견고하다.

---

## TDD Workflow Steps

### Step 1: Write User Journeys
```
As a [role], I want to [action], so that [benefit]

Example:
As a user, I want to search for markets semantically,
so that I can find relevant markets even without exact keywords.
```

### Step 2: Generate Test Cases
For each user journey, create comprehensive test cases:

```typescript
describe('Semantic Search', () => {
  it('returns relevant markets for query', async () => {
    // Test implementation
  })

  it('handles empty query gracefully', async () => {
    // Test edge case
  })

  it('falls back to substring search when Redis unavailable', async () => {
    // Test fallback behavior
  })

  it('sorts results by similarity score', async () => {
    // Test sorting logic
  })
})
```

### Step 3: Run Tests (They Should Fail)
```bash
npm test
# Tests should fail - we haven't implemented yet
```

### Step 4: Implement Code
Write minimal code to make tests pass:

```typescript
// Implementation guided by tests
export async function searchMarkets(query: string) {
  // Implementation here
}
```

### Step 5: Run Tests Again
```bash
npm test
# Tests should now pass
```

### Step 6: Refactor
Improve code quality while keeping tests green:
- Remove duplication
- Improve naming
- Optimize performance
- Enhance readability

### Step 7: Verify Coverage
```bash
npm run test:coverage
# Verify 80%+ coverage achieved
```

### Kotlin TDD Workflow Steps

#### Step 1: Define Data Classes and Interfaces
```kotlin
// src/main/kotlin/com/example/model/MarketData.kt
data class MarketData(
    val totalVolume: Double,
    val bidAskSpread: Double,
    val activeTraders: Int,
    val lastTradeTime: java.time.Instant
)

// src/main/kotlin/com/example/service/LiquidityService.kt
interface LiquidityService {
    fun calculate(marketId: Long): Double
}
```

#### Step 2: Write Failing Test (RED)
```kotlin
// src/test/kotlin/com/example/service/LiquidityServiceTest.kt
import io.kotest.core.spec.style.BehaviorSpec
import io.kotest.matchers.doubles.shouldBeGreaterThan
import io.kotest.matchers.shouldBe
import io.mockk.*

class LiquidityServiceTest : BehaviorSpec({
    val repository = mockk<MarketRepository>()
    val service = LiquidityServiceImpl(repository)

    Given("a highly liquid market") {
        every { repository.findById(1L) } returns Optional.of(
            MarketEntity(id = 1L, totalVolume = 100_000.0, bidAskSpread = 0.01, activeTraders = 500)
        )

        When("calculating liquidity score") {
            val score = service.calculate(1L)

            Then("score should be above 80") {
                score shouldBeGreaterThan 80.0
            }
        }
    }

    Given("a market with zero volume") {
        every { repository.findById(2L) } returns Optional.of(
            MarketEntity(id = 2L, totalVolume = 0.0, bidAskSpread = 0.0, activeTraders = 0)
        )

        When("calculating liquidity score") {
            val score = service.calculate(2L)

            Then("score should be zero") {
                score shouldBe 0.0
            }
        }
    }
})
```

#### Step 3: Run Tests (They Should Fail)
```bash
./gradlew test
# > Task :test FAILED
# LiquidityServiceTest > Given a highly liquid market When calculating ... FAILED
#   kotlin.NotImplementedError: An operation is not implemented
```

#### Step 4: Implement Code (GREEN)
```kotlin
// src/main/kotlin/com/example/service/LiquidityServiceImpl.kt
@Service
class LiquidityServiceImpl(
    private val repository: MarketRepository
) : LiquidityService {
    override fun calculate(marketId: Long): Double {
        val market = repository.findById(marketId)
            .orElseThrow { IllegalArgumentException("Market not found: $marketId") }

        if (market.totalVolume == 0.0) return 0.0

        val volumeScore = (market.totalVolume / 1000.0).coerceAtMost(100.0)
        val spreadScore = (100.0 - market.bidAskSpread * 1000.0).coerceIn(0.0, 100.0)
        val traderScore = (market.activeTraders / 10.0).coerceAtMost(100.0)

        return (volumeScore * 0.4 + spreadScore * 0.3 + traderScore * 0.3)
            .coerceIn(0.0, 100.0)
    }
}
```

#### Step 5: Run Tests Again (PASS)
```bash
./gradlew test
# > Task :test
# LiquidityServiceTest > Given a highly liquid market When calculating ... PASSED
# LiquidityServiceTest > Given a market with zero volume When calculating ... PASSED
# BUILD SUCCESSFUL
```

#### Step 6: Refactor
```kotlin
@Service
class LiquidityServiceImpl(
    private val repository: MarketRepository
) : LiquidityService {

    companion object {
        private const val VOLUME_SCALE = 1000.0
        private const val SPREAD_SCALE = 1000.0
        private const val TRADER_SCALE = 10.0
        private const val MAX_SCORE = 100.0
    }

    override fun calculate(marketId: Long): Double {
        val market = repository.findById(marketId)
            .orElseThrow { IllegalArgumentException("Market not found: $marketId") }

        if (market.totalVolume == 0.0) return 0.0

        return weightedScore(
            volumeScore = (market.totalVolume / VOLUME_SCALE).coerceAtMost(MAX_SCORE),
            spreadScore = (MAX_SCORE - market.bidAskSpread * SPREAD_SCALE).coerceIn(0.0, MAX_SCORE),
            traderScore = (market.activeTraders / TRADER_SCALE).coerceAtMost(MAX_SCORE)
        )
    }

    private fun weightedScore(volumeScore: Double, spreadScore: Double, traderScore: Double): Double =
        (volumeScore * 0.4 + spreadScore * 0.3 + traderScore * 0.3).coerceIn(0.0, MAX_SCORE)
}
```

#### Step 7: Verify Coverage
```bash
./gradlew test jacocoTestReport
# HTML report: build/reports/jacoco/test/html/index.html
# Verify 80%+ line/branch coverage
```

## Testing Patterns

### Kotlin Unit Test Pattern (BehaviorSpec + MockK)
```kotlin
import io.kotest.core.spec.style.BehaviorSpec
import io.kotest.matchers.doubles.shouldBeGreaterThan
import io.kotest.matchers.doubles.shouldBeLessThan
import io.kotest.matchers.shouldBe
import io.mockk.*

class LiquidityServiceBehaviorTest : BehaviorSpec({
    val repository = mockk<MarketRepository>()
    val service = LiquidityServiceImpl(repository)

    beforeEach { clearAllMocks() }

    Given("a highly liquid market") {
        val market = MarketEntity(
            id = 1L, totalVolume = 100_000.0,
            bidAskSpread = 0.01, activeTraders = 500
        )
        every { repository.findById(1L) } returns Optional.of(market)

        When("calculating liquidity score") {
            val score = service.calculate(1L)

            Then("score should be above 80") {
                score shouldBeGreaterThan 80.0
            }
            Then("repository should be called once") {
                verify(exactly = 1) { repository.findById(1L) }
            }
        }
    }

    Given("a market with zero volume") {
        val market = MarketEntity(
            id = 2L, totalVolume = 0.0,
            bidAskSpread = 0.0, activeTraders = 0
        )
        every { repository.findById(2L) } returns Optional.of(market)

        When("calculating liquidity score") {
            val score = service.calculate(2L)

            Then("score should be zero") {
                score shouldBe 0.0
            }
        }
    }
})
```

### Kotlin Unit Test Pattern (FunSpec)
```kotlin
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.doubles.shouldBeGreaterThan

class LiquidityCalculatorTest : FunSpec({
    test("returns high score for liquid market") {
        val data = MarketData(
            totalVolume = 100_000.0,
            bidAskSpread = 0.01,
            activeTraders = 500,
            lastTradeTime = java.time.Instant.now()
        )

        val score = LiquidityCalculator.calculate(data)

        score shouldBeGreaterThan 80.0
    }

    test("returns 0 for zero volume market") {
        val data = MarketData(
            totalVolume = 0.0,
            bidAskSpread = 0.0,
            activeTraders = 0,
            lastTradeTime = java.time.Instant.now()
        )

        LiquidityCalculator.calculate(data) shouldBe 0.0
    }

    test("clamps score between 0 and 100") {
        val extremeData = MarketData(
            totalVolume = 999_999_999.0,
            bidAskSpread = 0.0001,
            activeTraders = 10_000,
            lastTradeTime = java.time.Instant.now()
        )

        val score = LiquidityCalculator.calculate(extremeData)

        score shouldBe 100.0
    }
})
```

### Unit Test Pattern (Jest/Vitest)
```typescript
import { render, screen, fireEvent } from '@testing-library/react'
import { Button } from './Button'

describe('Button Component', () => {
  it('renders with correct text', () => {
    render(<Button>Click me</Button>)
    expect(screen.getByText('Click me')).toBeInTheDocument()
  })

  it('calls onClick when clicked', () => {
    const handleClick = jest.fn()
    render(<Button onClick={handleClick}>Click</Button>)

    fireEvent.click(screen.getByRole('button'))

    expect(handleClick).toHaveBeenCalledTimes(1)
  })

  it('is disabled when disabled prop is true', () => {
    render(<Button disabled>Click</Button>)
    expect(screen.getByRole('button')).toBeDisabled()
  })
})
```

### API Integration Test Pattern
```typescript
import { NextRequest } from 'next/server'
import { GET } from './route'

describe('GET /api/markets', () => {
  it('returns markets successfully', async () => {
    const request = new NextRequest('http://localhost/api/markets')
    const response = await GET(request)
    const data = await response.json()

    expect(response.status).toBe(200)
    expect(data.success).toBe(true)
    expect(Array.isArray(data.data)).toBe(true)
  })

  it('validates query parameters', async () => {
    const request = new NextRequest('http://localhost/api/markets?limit=invalid')
    const response = await GET(request)

    expect(response.status).toBe(400)
  })

  it('handles database errors gracefully', async () => {
    // Mock database failure
    const request = new NextRequest('http://localhost/api/markets')
    // Test error handling
  })
})
```

### Kotlin Controller Test (@WebMvcTest)
```kotlin
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post
import com.ninjasquad.springmockk.MockkBean
import io.mockk.every

@WebMvcTest(MarketController::class)
class MarketControllerTest @Autowired constructor(
    val mockMvc: MockMvc
) {
    @MockkBean lateinit var marketService: MarketService

    @Test
    fun `GET markets returns 200 with list`() {
        every { marketService.findAll() } returns listOf(
            MarketDto(id = 1, name = "Election 2024", score = 92.0),
            MarketDto(id = 2, name = "Super Bowl", score = 78.0)
        )

        mockMvc.get("/api/markets")
            .andExpect {
                status { isOk() }
                jsonPath("$.size()") { value(2) }
                jsonPath("$[0].name") { value("Election 2024") }
            }
    }

    @Test
    fun `GET market by id returns 404 when not found`() {
        every { marketService.findById(999) } returns null

        mockMvc.get("/api/markets/999")
            .andExpect {
                status { isNotFound() }
            }
    }

    @Test
    fun `POST market with invalid body returns 400`() {
        mockMvc.post("/api/markets") {
            contentType = org.springframework.http.MediaType.APPLICATION_JSON
            content = """{"name": ""}"""
        }.andExpect {
            status { isBadRequest() }
        }
    }
}
```

### Kotlin Full Integration Test (@SpringBootTest)
```kotlin
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.client.TestRestTemplate
import org.springframework.boot.test.web.client.getForEntity
import org.springframework.http.HttpStatus

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class MarketFlowIntegrationTest @Autowired constructor(
    val restTemplate: TestRestTemplate
) {
    @Test
    fun `full market lifecycle - create, read, update, delete`() {
        // CREATE
        val createResponse = restTemplate.postForEntity(
            "/api/markets",
            CreateMarketRequest(name = "Test Market", description = "E2E test"),
            MarketDto::class.java
        )
        createResponse.statusCode shouldBe HttpStatus.CREATED
        val marketId = createResponse.body!!.id

        // READ
        val getResponse = restTemplate.getForEntity<MarketDto>("/api/markets/$marketId")
        getResponse.statusCode shouldBe HttpStatus.OK
        getResponse.body!!.name shouldBe "Test Market"

        // UPDATE
        restTemplate.put("/api/markets/$marketId",
            UpdateMarketRequest(name = "Updated Market"))
        val updated = restTemplate.getForEntity<MarketDto>("/api/markets/$marketId")
        updated.body!!.name shouldBe "Updated Market"

        // DELETE
        restTemplate.delete("/api/markets/$marketId")
        val deleted = restTemplate.getForEntity<MarketDto>("/api/markets/$marketId")
        deleted.statusCode shouldBe HttpStatus.NOT_FOUND
    }
}
```

### E2E Test Pattern (Playwright)
```typescript
import { test, expect } from '@playwright/test'

test('user can search and filter markets', async ({ page }) => {
  // Navigate to markets page
  await page.goto('/')
  await page.click('a[href="/markets"]')

  // Verify page loaded
  await expect(page.locator('h1')).toContainText('Markets')

  // Search for markets
  await page.fill('input[placeholder="Search markets"]', 'election')

  // Wait for debounce and results
  await page.waitForTimeout(600)

  // Verify search results displayed
  const results = page.locator('[data-testid="market-card"]')
  await expect(results).toHaveCount(5, { timeout: 5000 })

  // Verify results contain search term
  const firstResult = results.first()
  await expect(firstResult).toContainText('election', { ignoreCase: true })

  // Filter by status
  await page.click('button:has-text("Active")')

  // Verify filtered results
  await expect(results).toHaveCount(3)
})

test('user can create a new market', async ({ page }) => {
  // Login first
  await page.goto('/creator-dashboard')

  // Fill market creation form
  await page.fill('input[name="name"]', 'Test Market')
  await page.fill('textarea[name="description"]', 'Test description')
  await page.fill('input[name="endDate"]', '2025-12-31')

  // Submit form
  await page.click('button[type="submit"]')

  // Verify success message
  await expect(page.locator('text=Market created successfully')).toBeVisible()

  // Verify redirect to market page
  await expect(page).toHaveURL(/\/markets\/test-market/)
})
```

### Kotlin Test File Organization

```
project-root/
├── build.gradle.kts
├── src/
│   ├── main/kotlin/com/example/
│   │   ├── controller/
│   │   │   └── MarketController.kt
│   │   ├── service/
│   │   │   ├── LiquidityService.kt          # Interface
│   │   │   └── LiquidityServiceImpl.kt      # Implementation
│   │   ├── repository/
│   │   │   └── MarketRepository.kt
│   │   └── model/
│   │       ├── MarketData.kt                # Data class
│   │       └── MarketEntity.kt
│   └── test/kotlin/com/example/
│       ├── unit/
│       │   └── service/
│       │       └── LiquidityServiceTest.kt  # Kotest FunSpec/BehaviorSpec
│       ├── integration/
│       │   ├── controller/
│       │   │   └── MarketControllerTest.kt  # @WebMvcTest
│       │   └── repository/
│       │       └── MarketRepositoryTest.kt  # @DataJpaTest
│       └── e2e/
│           └── MarketFlowTest.kt            # @SpringBootTest + TestRestTemplate
```

## Test File Organization

```
src/
├── components/
│   ├── Button/
│   │   ├── Button.tsx
│   │   ├── Button.test.tsx          # Unit tests
│   │   └── Button.stories.tsx       # Storybook
│   └── MarketCard/
│       ├── MarketCard.tsx
│       └── MarketCard.test.tsx
├── app/
│   └── api/
│       └── markets/
│           ├── route.ts
│           └── route.test.ts         # Integration tests
└── e2e/
    ├── markets.spec.ts               # E2E tests
    ├── trading.spec.ts
    └── auth.spec.ts
```

### Kotlin Mocking with MockK

#### Service Mock
```kotlin
import io.mockk.*

class LiquidityServiceTest : FunSpec({
    val repository = mockk<MarketRepository>()
    val service = LiquidityServiceImpl(repository)

    beforeEach { clearAllMocks() }

    test("calculate returns weighted score") {
        every { repository.findById(1L) } returns Optional.of(
            MarketEntity(id = 1L, totalVolume = 100_000.0, bidAskSpread = 0.01)
        )

        val score = service.calculate(1L)

        score shouldBeGreaterThan 80.0
        verify(exactly = 1) { repository.findById(1L) }
        confirmVerified(repository)
    }
})
```

#### Coroutine Mock
```kotlin
import io.mockk.coEvery
import io.mockk.coVerify

class AsyncServiceTest : FunSpec({
    val client = mockk<WebClient>()

    test("fetches market data asynchronously") {
        coEvery { client.fetchMarketData("BTC") } returns MarketData(
            symbol = "BTC", price = 50000.0
        )

        val result = client.fetchMarketData("BTC")

        result.symbol shouldBe "BTC"
        coVerify { client.fetchMarketData("BTC") }
    }
})
```

#### SpringMockK (@MockkBean)
```kotlin
import com.ninjasquad.springmockk.MockkBean

@WebMvcTest(MarketController::class)
class MarketControllerMockTest {
    @Autowired lateinit var mockMvc: MockMvc
    @MockkBean lateinit var marketService: MarketService

    @Test
    fun `returns market by id`() {
        every { marketService.findById(1L) } returns MarketDto(
            id = 1L, name = "Test Market", score = 85.0
        )

        mockMvc.get("/api/markets/1")
            .andExpect {
                status { isOk() }
                jsonPath("$.name") { value("Test Market") }
            }

        verify { marketService.findById(1L) }
    }
}
```

## Mocking External Services

### Supabase Mock
```typescript
jest.mock('@/lib/supabase', () => ({
  supabase: {
    from: jest.fn(() => ({
      select: jest.fn(() => ({
        eq: jest.fn(() => Promise.resolve({
          data: [{ id: 1, name: 'Test Market' }],
          error: null
        }))
      }))
    }))
  }
}))
```

### Redis Mock
```typescript
jest.mock('@/lib/redis', () => ({
  searchMarketsByVector: jest.fn(() => Promise.resolve([
    { slug: 'test-market', similarity_score: 0.95 }
  ])),
  checkRedisHealth: jest.fn(() => Promise.resolve({ connected: true }))
}))
```

### OpenAI Mock
```typescript
jest.mock('@/lib/openai', () => ({
  generateEmbedding: jest.fn(() => Promise.resolve(
    new Array(1536).fill(0.1) // Mock 1536-dim embedding
  ))
}))
```

## Test Coverage Verification

### Run Coverage Report
```bash
npm run test:coverage
```

### Coverage Thresholds
```json
{
  "jest": {
    "coverageThresholds": {
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

### Kotlin Coverage (JaCoCo)

#### Run JaCoCo Coverage Report
```bash
./gradlew test jacocoTestReport
# HTML report: build/reports/jacoco/test/html/index.html
```

#### build.gradle.kts — JaCoCo Configuration
```kotlin
plugins {
    jacoco
}

jacoco {
    toolVersion = "0.8.11"
}

tasks.jacocoTestReport {
    dependsOn(tasks.test)
    reports {
        xml.required.set(true)
        html.required.set(true)
    }
}

tasks.jacocoTestCoverageVerification {
    violationRules {
        rule {
            limit {
                minimum = "0.80".toBigDecimal() // 80% minimum
            }
        }
        rule {
            element = "CLASS"
            includes = listOf("com.example.service.*")
            limit {
                counter = "BRANCH"
                minimum = "0.80".toBigDecimal()
            }
        }
    }
}
```

#### Kotlin Test Dependencies (build.gradle.kts)
```kotlin
dependencies {
    // Kotest
    testImplementation("io.kotest:kotest-runner-junit5:5.8.0")
    testImplementation("io.kotest:kotest-assertions-core:5.8.0")
    testImplementation("io.kotest.extensions:kotest-extensions-spring:1.1.3")
    // MockK
    testImplementation("io.mockk:mockk:1.13.9")
    testImplementation("com.ninja-squad:springmockk:4.0.2")
    // Spring Boot Test (exclude Mockito)
    testImplementation("org.springframework.boot:spring-boot-starter-test") {
        exclude(group = "org.mockito")
    }
    // JaCoCo (plugin-based, no explicit dependency needed)
}

tasks.withType<Test> {
    useJUnitPlatform() // Required for Kotest
}
```

### Kotlin Testing Mistakes to Avoid

#### ❌ WRONG: Using Mockito Instead of MockK
```kotlin
// Mockito is Java-centric, doesn't support Kotlin features well
@Mock lateinit var service: LiquidityService // Breaks with final classes
```

#### ✅ CORRECT: Use MockK for Kotlin
```kotlin
// MockK supports Kotlin natively (final classes, coroutines, extension functions)
val service = mockk<LiquidityService>()
```

#### ❌ WRONG: @SpringBootTest for Every Test
```kotlin
// Loads entire application context - slow!
@SpringBootTest
class SimpleUtilTest { /* ... */ }
```

#### ✅ CORRECT: Use Appropriate Test Slice
```kotlin
// Unit test - no Spring context needed
class SimpleUtilTest : FunSpec({ /* ... */ })

// Controller only - use @WebMvcTest
@WebMvcTest(MarketController::class)
class MarketControllerTest { /* ... */ }

// Repository only - use @DataJpaTest
@DataJpaTest
class MarketRepositoryTest { /* ... */ }
```

#### ❌ WRONG: Not Cleaning Up MockK State
```kotlin
// Mocks leak between tests
every { service.calculate(any()) } returns 95.0
```

#### ✅ CORRECT: Use clearAllMocks or confirmVerified
```kotlin
afterEach {
    clearAllMocks()
}
```

## Test Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| Implementation 세부사항 테스트 | 리팩토링 시 테스트 깨짐 | 입력과 출력(behavior)을 테스트 |
| Flaky 테스트 | 테스트 신뢰도 하락 | 결정적(deterministic) assertion 사용 |
| 프레임워크 코드 테스트 | 시간 낭비 | **자신의 코드만** 테스트 |
| Snapshot 남용 | 아무도 리뷰하지 않음 | 꼭 필요한 경우에만 사용 |
| 테스트 격리 없음 | 한 테스트 실패 → 연쇄 실패 | 각 테스트가 자체 상태 관리 |
| Over-mocking | 프로덕션에서 깨짐 | Real > Fake > Stub > Mock 순서 |

## Common Rationalizations

| Rationalization | Reality |
|----------------|---------|
| "코드 완성 후 테스트 작성할게" | 안 할 것이다. 사후 테스트는 구현을 검증하지, 동작을 검증하지 않는다 |
| "이건 너무 단순해서 테스트 불필요" | 단순한 코드도 복잡해진다. 테스트는 기대 동작을 문서화한다 |
| "테스트가 개발을 느리게 한다" | 지금은 느려지지만, 코드를 변경할 때마다 속도를 높여준다 |
| "수동으로 테스트했다" | 수동 테스트는 지속되지 않는다 |
| "프로토타입일 뿐이다" | 프로토타입은 프로덕션 코드가 된다 |

---

## Common Testing Mistakes to Avoid

### ❌ WRONG: Testing Implementation Details
```typescript
// Don't test internal state
expect(component.state.count).toBe(5)
```

### ✅ CORRECT: Test User-Visible Behavior
```typescript
// Test what users see
expect(screen.getByText('Count: 5')).toBeInTheDocument()
```

### ❌ WRONG: Brittle Selectors
```typescript
// Breaks easily
await page.click('.css-class-xyz')
```

### ✅ CORRECT: Semantic Selectors
```typescript
// Resilient to changes
await page.click('button:has-text("Submit")')
await page.click('[data-testid="submit-button"]')
```

### ❌ WRONG: No Test Isolation
```typescript
// Tests depend on each other
test('creates user', () => { /* ... */ })
test('updates same user', () => { /* depends on previous test */ })
```

### ✅ CORRECT: Independent Tests
```typescript
// Each test sets up its own data
test('creates user', () => {
  const user = createTestUser()
  // Test logic
})

test('updates user', () => {
  const user = createTestUser()
  // Update logic
})
```

## Continuous Testing

### Watch Mode During Development
```bash
npm test -- --watch
# Tests run automatically on file changes
```

### Pre-Commit Hook
```bash
# Runs before every commit
npm test && npm run lint
```

### CI/CD Integration
```yaml
# GitHub Actions
- name: Run Tests
  run: npm test -- --coverage
- name: Upload Coverage
  uses: codecov/codecov-action@v3
```

### Kotlin Continuous Testing

```bash
# Watch mode (Gradle continuous build)
./gradlew test --continuous

# Run specific test class
./gradlew test --tests "com.example.service.LiquidityServiceTest"

# Run tests matching pattern
./gradlew test --tests "*Liquidity*"

# Lint check before commit
./gradlew ktlintCheck test
```

#### Kotlin CI/CD Integration (GitHub Actions)
```yaml
# .github/workflows/test-kotlin.yml
name: Kotlin Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '21'
      - name: Run tests with coverage
        run: ./gradlew test jacocoTestReport
      - name: Check coverage threshold
        run: ./gradlew jacocoTestCoverageVerification
      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          files: build/reports/jacoco/test/jacocoTestReport.xml
```

---

## Best Practices

1. **Write Tests First** - Always TDD
2. **One Assert Per Test** - Focus on single behavior
3. **Descriptive Test Names** - Explain what's tested
4. **Arrange-Act-Assert** - Clear test structure
5. **Mock External Dependencies** - Isolate unit tests
6. **Test Edge Cases** - Null, undefined, empty, large
7. **Test Error Paths** - Not just happy paths
8. **Keep Tests Fast** - Unit tests < 50ms each
9. **Clean Up After Tests** - No side effects
10. **Review Coverage Reports** - Identify gaps

## Success Metrics

- 80%+ code coverage achieved
- All tests passing (green)
- No skipped or disabled tests
- Fast test execution (< 30s for unit tests)
- E2E tests cover critical user flows
- Tests catch bugs before production

---

**Remember**: Tests are not optional. They are the safety net that enables confident refactoring, rapid development, and production reliability.