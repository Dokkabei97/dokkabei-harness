---
name: deprecation-guide
description: Use this skill when deprecating old systems, migrating consumers to new implementations, or removing zombie code. Covers the deprecation decision framework, migration patterns (Strangler/Adapter/Feature Flag), and safe removal process.
---

# Deprecation & Migration Guide

시스템/모듈/API 폐기와 소비자 마이그레이션을 위한 체계적 프로세스. 대체 없는 폐기를 방지하고, 안전한 점진적 이관을 보장한다.

## When to Activate

- 기존 시스템/모듈/API를 새 구현으로 교체할 때
- 사용되지 않는 코드나 서비스를 정리할 때
- 외부 라이브러리/프레임워크를 버전 업그레이드할 때
- 레거시 코드 제거를 계획할 때
- "좀비 코드"를 발견했을 때

---

## Core Principles

### 1. Code Is a Liability
코드의 가치는 코드 자체가 아니라 제공하는 **기능**에 있다. 더 적은 코드로 동일한 기능을 제공할 수 있다면, 기존 코드는 부채다.

### 2. Hyrum's Law
> "사용자가 충분히 많으면, API의 모든 관찰 가능한 동작에 누군가가 의존한다."

공지만으로는 부족하다. 버그, 타이밍, 비문서화 부작용까지 의존될 수 있으므로 **능동적 마이그레이션**이 필요하다.

### 3. 설계 시점에 폐기를 계획하라
3년 후 이 코드를 제거하는 방법을 설계 시점에 고려한다: 클린 인터페이스, 피처 플래그, 최소 표면적.

---

## The Deprecation Decision

폐기 결정 전 5가지 질문:

| # | 질문 | 판단 기준 |
|---|------|----------|
| 1 | 이 시스템이 아직 고유한 가치를 제공하는가? | 대체 불가능한 기능이 있으면 폐기 보류 |
| 2 | 몇 명의 소비자가 의존하는가? | 마이그레이션 범위 정량화 |
| 3 | 대체 시스템이 존재하는가? | **없으면 먼저 구축** — 대체 없는 폐기 금지 |
| 4 | 각 소비자의 마이그레이션 비용은? | 자동화 가능하면 수행, 수동이면 유지보수 비용과 비교 |
| 5 | 폐기하지 않을 때의 유지보수 비용은? | 보안 리스크, 엔지니어 시간, 복잡성 기회비용 |

### Compulsory vs Advisory

| 유형 | 사용 시점 | 메커니즘 |
|------|----------|---------|
| **Advisory** (권고) | 이관 선택적, 구시스템 안정적 | 경고 로그, 문서, 사용자 자체 일정 이관 |
| **Compulsory** (강제) | 보안 이슈, 진행 차단, 비용 감당 불가 | 확정 기한 + 마이그레이션 도구/문서/지원 제공 필수 |

---

## The Migration Process

### Step 1: Build the Replacement
**동작하는 대안 없이 폐기하지 마라.**
- 모든 핵심 유스케이스 커버
- 문서 작성
- 프로덕션 검증 완료

### Step 2: Announce and Document

```markdown
## Deprecation Notice: [시스템/모듈명]

- **Status**: Deprecated (2024-04-01)
- **Replacement**: [새 시스템/모듈명] — [링크]
- **Removal Date**: 2024-07-01 (3개월 유예)
- **Reason**: [폐기 이유]
- **Migration Guide**: [가이드 링크]
- **담당자**: @username
```

공지 채널: GitLab Issue, NAVER WORKS 메시지, 코드 내 `@Deprecated` 어노테이션

```kotlin
@Deprecated(
    message = "Use NewOrderService instead. Removal planned for 2024-07-01.",
    replaceWith = ReplaceWith("newOrderService.createOrder(request)")
)
fun createOrder(request: OrderRequest): OrderResponse { /* ... */ }
```

```python
import warnings

def create_order(request):
    warnings.warn(
        "create_order is deprecated. Use new_order_service.create() instead. "
        "Removal planned for 2024-07-01.",
        DeprecationWarning, stacklevel=2,
    )
    # ...
```

### Step 3: Migrate Incrementally

소비자를 하나씩 이관:
1. 접점 식별 (어디서 호출하는가?)
2. 새 시스템으로 교체
3. 동작 검증 (테스트 실행)
4. 구 참조 제거
5. 회귀 없음 확인

> **The Churn Rule**: 인프라/라이브러리 소유자가 사용자 마이그레이션 책임을 진다 (또는 하위 호환 업데이트를 제공한다). "사용자가 알아서 이관하겠지"는 안 된다.

### Step 4: Remove the Old System

모든 소비자 이관 확인 후:
1. 사용량 제로 확인 (메트릭/로그)
2. 코드 삭제
3. 관련 테스트/문서/설정 삭제
4. 폐기 공지 제거
5. Flyway/Alembic으로 불필요한 테이블/컬럼 정리 (expand-contract)

---

## Migration Patterns

### 1. Strangler Pattern
신구 시스템 병렬 운영 후 트래픽을 점진적으로 이관:

```
구 시스템 ─── 100% ──→ 90% ──→ 50% ──→ 0% (제거)
                ↓        ↓        ↓
신 시스템 ───  0%  ──→ 10% ──→ 50% ──→ 100%
```

적합: 대규모 시스템 교체, API 버전 전환

### 2. Adapter Pattern
구 인터페이스를 유지하되 내부를 신구현으로 위임:

```kotlin
// 구 인터페이스를 유지하면서 내부는 새 구현 사용
class LegacyOrderService(
    private val newOrderService: NewOrderService
) : OldOrderAPI {
    override fun getOrder(id: String): OldOrderResponse {
        val order = newOrderService.findById(id.toLong())
        return OldOrderResponse.fromNew(order)  // 변환
    }
}
```

적합: API 소비자가 많아 인터페이스 즉시 변경이 불가능할 때

### 3. Feature Flag Migration
피처 플래그로 소비자별 전환:

```kotlin
fun processOrder(order: Order): Result {
    return if (featureToggle.isEnabled("use-new-order-processor")) {
        newOrderProcessor.process(order)
    } else {
        legacyOrderProcessor.process(order)
    }
}
```

적합: 점진적 전환, A/B 비교, 빠른 롤백이 필요할 때

---

## Zombie Code 식별

| Signal | 증상 |
|--------|------|
| 6개월+ 커밋 없음 | 활성 소비자는 있지만 유지보수되지 않음 |
| 담당자/팀 없음 | 소유권이 불분명 |
| 실패하는 테스트 방치 | 아무도 수정하지 않는 빨간 테스트 |
| 취약점 미업데이트 | 알려진 CVE가 있는 의존성 방치 |
| 유령 문서 | 더 이상 존재하지 않는 시스템을 참조 |

> Zombie code를 발견하면: 소유자 확인 → 폐기 여부 결정 → 위 프로세스 적용

---

## Common Rationalizations

| Rationalization | Reality |
|----------------|---------|
| "아직 동작하는데 왜 제거?" | 유지보수 없는 코드는 보안 부채와 복잡성을 조용히 누적한다 |
| "나중에 필요할 수도" | 필요하면 재구축 가능. "혹시 몰라" 유지가 재구축보다 비용 크다 |
| "마이그레이션이 너무 비싸다" | 2~3년 유지보수 비용과 비교하라. 장기적으로 마이그레이션이 더 저렴하다 |
| "사용자가 알아서 이관할 것" | 안 한다. 도구, 문서, 인센티브를 제공하거나 직접 이관하라 (Churn Rule) |
| "두 시스템 모두 유지 가능" | 동일 기능의 두 시스템은 유지보수/테스트/문서/온보딩 비용이 2배다 |

## Red Flags

- 대체 없는 폐기 공지
- 마이그레이션 도구/문서 없는 기한 설정
- 수년간 진전 없는 "소프트" 폐기
- 소유자 없고 활성 소비자 있는 좀비 코드
- 폐기된 시스템에 새 기능 추가
- 현재 사용량 측정 없이 코드 제거

## Verification

- [ ] 대체 시스템이 프로덕션 검증됨
- [ ] 마이그레이션 가이드 존재 (구체적 단계 + 코드 예시)
- [ ] 모든 활성 소비자 이관 완료 (메트릭/로그로 확인)
- [ ] 구 코드, 테스트, 문서, 설정 완전 제거
- [ ] 코드베이스에 폐기된 시스템 참조 잔존 없음

---

## Related

- `shipping-guide` — 새 시스템 배포 시 피처 플래그와 롤아웃 전략
- `code-simplification-guide` — 폐기 후 남은 코드 정리
- `/review-mr` — 마이그레이션 MR 리뷰
