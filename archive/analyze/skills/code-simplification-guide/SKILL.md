---
name: code-simplification-guide
description: Use this skill when simplifying, refactoring, or cleaning up existing code. Provides principles, opportunity categories, and a step-by-step process for safe code simplification across Kotlin, Python, and TypeScript/JavaScript.
---

# Code Simplification Guide

코드 단순화를 위한 원칙, 기회 식별, 프로세스 가이드. 리팩토링 시 동작을 보존하면서 가독성과 유지보수성을 높이는 체계적 접근법을 제공한다.

## When to Activate

- 기존 코드의 복잡도를 줄이거나 가독성을 개선할 때
- 리팩토링 작업을 수행할 때
- 코드 리뷰에서 단순화 기회를 식별할 때
- 레거시 코드를 현대적 패턴으로 전환할 때
- Dead code 정리가 필요할 때

## When NOT to Use

- 새 기능을 추가하면서 동시에 리팩토링하려 할 때 (분리해야 함)
- 테스트 없이 코드를 변경하려 할 때
- 성능 최적화가 목적일 때 (`/perf-review` 사용)
- 원본 코드의 의도를 파악하지 못한 상태일 때

---

## 5 Principles

### 1. Preserve Behavior Exactly
단순화의 목표는 **동작을 변경하지 않고** 코드를 개선하는 것이다. 테스트가 수정되어야 한다면, 그것은 단순화가 아니라 기능 변경이다.

### 2. Follow Project Conventions
프로젝트의 기존 컨벤션(네이밍, 구조, 패턴)을 따른다. "더 나은" 패턴이라도 프로젝트 일관성을 깨뜨리면 안 된다.

### 3. Prefer Clarity Over Cleverness
```kotlin
// BAD: 영리하지만 읽기 어려움
val result = items.fold(mutableMapOf<String, Int>()) { acc, item ->
    acc.apply { merge(item.category, 1, Int::plus) }
}

// GOOD: 명확하고 읽기 쉬움
val result = items.groupBy { it.category }.mapValues { it.value.size }
```

```python
# BAD: 한 줄이지만 파악하기 어려움
data = {k: v for d in [defaults, overrides] for k, v in d.items() if v is not None}

# GOOD: 의도가 명확함
data = {**defaults}
data.update({k: v for k, v in overrides.items() if v is not None})
```

### 4. Maintain Balance
과도한 단순화도 문제다. 3줄짜리 코드를 1줄로 압축하면서 가독성을 해치지 마라.

### 5. Scope to What Changed
변경 범위를 한정한다. 리팩토링하면서 관련 없는 코드까지 건드리면 diff가 오염되고 리뷰가 어려워진다.

> **"리팩토링과 기능 추가는 별도 PR이다."** 하나의 변경에서 리팩토링과 기능 추가를 동시에 하는 것은 두 개의 변경이다.

---

## Chesterton's Fence

> "무언가를 제거하기 전에, 왜 그것이 거기 있는지 이해하라."

코드가 불필요해 보일 때 바로 삭제하지 마라. 먼저:
1. `git blame`으로 누가 왜 추가했는지 확인
2. 관련 커밋 메시지와 PR을 읽어 원래 맥락 파악
3. 연관된 테스트가 있는지 확인
4. 이유를 파악한 후에야 제거 또는 유지 결정

```bash
# 해당 코드의 변경 이력 확인
git blame -L 45,60 src/service/OrderService.kt
git log --oneline -5 -- src/service/OrderService.kt
```

**적용 예시:**
```kotlin
// 이 sleep이 왜 있지? 제거해도 되나?
Thread.sleep(100)  // FIXME: 왜 있는지 확인 필요

// git blame 결과: "fix: 외부 API rate limit 대응 (2024-03)"
// → 제거하면 안 됨. rate limit 위반 가능.
// → 개선: sleep 대신 retry with backoff 패턴으로 교체
```

---

## Simplification Opportunities

### Category 1: Structural Complexity

| Signal | Pattern | Simplification |
|--------|---------|----------------|
| 깊은 중첩 (3단계+) | nested if/else/try | Early return / Guard clause |
| 긴 함수 (50줄+) | 하나의 함수에 여러 책임 | Extract method |
| Boolean 파라미터 | `fun process(dryRun: Boolean)` | 별도 메서드 분리 또는 sealed class |
| 복잡한 조건식 | `if (a && !b \|\| c && d)` | 의미 있는 변수명으로 추출 |
| 긴 파라미터 목록 (5개+) | `fun create(a, b, c, d, e, f)` | Parameter object / data class |

```kotlin
// BAD: 깊은 중첩
fun processOrder(order: Order): Result {
    if (order.isValid()) {
        if (order.hasStock()) {
            if (order.payment.isApproved()) {
                return ship(order)
            } else {
                return Result.failure("Payment not approved")
            }
        } else {
            return Result.failure("Out of stock")
        }
    } else {
        return Result.failure("Invalid order")
    }
}

// GOOD: Guard clause로 평탄화
fun processOrder(order: Order): Result {
    if (!order.isValid()) return Result.failure("Invalid order")
    if (!order.hasStock()) return Result.failure("Out of stock")
    if (!order.payment.isApproved()) return Result.failure("Payment not approved")
    return ship(order)
}
```

### Category 2: Naming & Readability

| Signal | Pattern | Simplification |
|--------|---------|----------------|
| 제네릭 이름 | `data`, `result`, `temp`, `item` | 도메인 의미를 담은 이름 |
| 오해를 유발하는 이름 | `isValid`가 실제로는 변환 수행 | 실제 동작에 맞게 이름 변경 |
| 약어 남용 | `calcOrdTotAmt()` | `calculateOrderTotalAmount()` |
| 주석으로 설명하는 코드 | `// 사용자 활성 상태 체크` + 복잡한 조건 | 코드 자체를 자명하게 |

```python
# BAD: 이름이 동작을 설명하지 못함
def process(d):
    r = []
    for i in d:
        if i['s'] == 'A':
            r.append(i)
    return r

# GOOD: 이름만으로 의도 파악 가능
def filter_active_users(users: list[dict]) -> list[dict]:
    return [user for user in users if user['status'] == 'ACTIVE']
```

### Category 3: Redundancy

| Signal | Pattern | Simplification |
|--------|---------|----------------|
| Dead code | 호출되지 않는 함수, 도달 불가능한 분기 | 삭제 (Chesterton's Fence 확인 후) |
| 불필요한 추상화 | 단 하나의 구현만 있는 인터페이스 | 인터페이스 제거, 직접 사용 |
| 과도한 래핑 | 단순 위임만 하는 wrapper | wrapper 제거 |
| 중복 코드 | 3회 이상 반복되는 패턴 | Extract function (3회 미만은 유지) |
| 사용되지 않는 import | 미사용 import 문 | 정리 |

```kotlin
// BAD: 단순 위임만 하는 불필요한 래퍼
class OrderServiceWrapper(private val orderService: OrderService) {
    fun findById(id: Long) = orderService.findById(id)
    fun save(order: Order) = orderService.save(order)
    fun delete(id: Long) = orderService.delete(id)
}

// GOOD: OrderService를 직접 사용
// OrderServiceWrapper 삭제, 호출부에서 OrderService 직접 주입
```

---

## Rule of 500

> **500줄 이상의 리팩토링은 수동으로 하지 마라.**

대규모 리팩토링에서 수동 편집은 오류 확률이 높고 리뷰 피로를 유발한다:
- IDE의 리팩토링 도구를 사용 (Rename, Extract, Inline 등)
- 정규표현식 기반 일괄 치환
- AST 변환 도구 활용 (ktlint, autopep8, jscodeshift 등)

| 변경 규모 | 접근법 |
|-----------|--------|
| ~50줄 | 수동 편집 OK |
| ~200줄 | IDE 리팩토링 도구 권장 |
| ~500줄+ | 자동화 도구 필수, 수동 편집 금지 |

---

## 4-Step Simplification Process

### Step 1: Understand Before Touching
- 변경 대상 코드를 **완전히 이해**한 후에 수정 시작
- `git blame` + 커밋 히스토리로 코드의 맥락 파악 (Chesterton's Fence)
- 기존 테스트를 실행하여 현재 동작 확인
- 의문점이 있으면 작성자에게 확인 (가능한 경우)

### Step 2: Identify Opportunities
위의 3개 카테고리(Structural, Naming, Redundancy) 테이블을 참조하여 단순화 기회 식별:
- 파일별로 발견된 기회를 목록화
- 각 기회의 영향도(Impact)와 위험도(Risk) 평가
- 우선순위 결정: High Impact + Low Risk부터

### Step 3: Apply Incrementally
- **한 번에 하나의 단순화만** 적용
- 각 변경 후 테스트 실행하여 동작 보존 확인
- 커밋 단위를 작게 유지 (변경 의도가 명확하도록)
- 리팩토링과 기능 변경을 절대 섞지 않는다

### Step 4: Verify Result
- [ ] 모든 기존 테스트 통과
- [ ] 새로운 테스트가 필요하지 않음 (동작이 변경되지 않았으므로)
- [ ] 단순화된 코드가 원본보다 읽기 쉬움
- [ ] 단순화된 코드가 원본보다 길어지지 않음
- [ ] diff가 깔끔하고 리뷰 가능한 크기임

---

## Common Rationalizations

| Rationalization | Reality |
|----------------|---------|
| "동작하니까 건드리지 말자" | 읽기 어려운 코드는 버그 수정 시 더 큰 비용을 유발한다 |
| "줄 수가 적으면 항상 좋다" | 1줄짜리 nested ternary는 5줄 if/else보다 읽기 어렵다 |
| "관련 없는 코드도 같이 정리하자" | 범위를 벗어난 단순화는 noisy diff와 regression 위험을 만든다 |
| "타입이 있으니 자기 문서화된다" | 타입은 구조를 문서화하지, 의도를 문서화하지 않는다 |
| "이 추상화가 나중에 유용할 수도" | 투기적 추상화를 유지하지 마라. 지금 쓰이지 않으면 제거한다 |
| "원래 작성자가 이유가 있었을 것이다" | git blame을 확인하라 — Chesterton's Fence를 적용한 후 판단하라 |
| "기능 추가하면서 리팩토링도 하자" | 리팩토링과 기능 추가는 별도 PR이다 |

---

## Red Flags

- 테스트 수정이 필요한 "단순화" → 동작을 변경한 것이다
- 원본보다 길어진 "단순화" → 복잡도가 증가한 것이다
- 여러 파일에 걸친 대규모 rename → 자동화 도구를 쓰지 않았다면 위험
- 인터페이스/추상화 제거 후 확장 포인트 상실 → Chesterton's Fence 위반
- 리팩토링 PR에 새 기능이 섞여 있음 → 범위 초과

---

## Integration with Other Tools

- `/analyze` — 코드 품질/복잡도 문제를 탐지한 후 이 가이드로 단순화
- `/arch-review` — 아키텍처 위반을 발견한 후 구조적 단순화 적용
- `/perf-review` — 성능 안티패턴 수정과 단순화를 분리하여 진행

---

**Remember**: 단순화의 목표는 "적은 코드"가 아니라 "이해하기 쉬운 코드"다. 측정 기준은 줄 수가 아니라 가독성이다.
