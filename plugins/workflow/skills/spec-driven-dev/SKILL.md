---
name: spec-driven-dev
description: Use this skill when starting a new feature, project, or significant change. Enforces spec-before-code discipline with a gated workflow (SPECIFY → PLAN → TASKS → IMPLEMENT) to prevent scope drift and rework.
---

# Spec-Driven Development

코드 작성 전에 스펙을 먼저 정의하는 게이트 워크플로우. 모호한 요구사항을 구체적 성공 기준으로 변환하고, 각 단계마다 사람의 검토를 거쳐 진행한다.

## When to Activate

- 새 기능이나 프로젝트를 시작할 때
- 기존 시스템에 중요한 변경을 가할 때
- 요구사항이 모호하거나 암묵적 가정이 많을 때
- 여러 사람이 협업하는 작업일 때

## When NOT to Use

- 단순 버그 수정 (증상 → 재현 테스트 → 수정이면 충분)
- 1~2줄 설정 변경
- 이미 명확한 스펙이 있는 작업

---

## The Gated Workflow

```
SPECIFY ──→ PLAN ──→ TASKS ──→ IMPLEMENT
    │           │         │          │
    ▼           ▼         ▼          ▼
 [사람 검토]  [사람 검토]  [사람 검토]  [검증]
```

> 각 단계의 산출물이 사람에게 승인되어야 다음 단계로 진행한다.

---

### Phase 1: SPECIFY (명세)

#### 가정 즉시 명시화
비사소한 작업을 시작할 때 가정을 먼저 적는다:

```
ASSUMPTIONS I'M MAKING:
- 이 API는 인증된 사용자만 호출할 수 있다
- 데이터는 PostgreSQL에 저장한다 (Citus 분산 아님)
- 응답 시간 목표는 P95 < 200ms이다
- Kafka 이벤트 발행은 MVP 범위에 포함하지 않는다
```

#### 6개 핵심 영역 스펙

**1. Objective** — 무엇을 왜 만드는가

```markdown
사용자가 주문 내역을 날짜/상태별로 필터링하여 조회할 수 있다.
이를 통해 CS 문의 없이 스스로 주문 상태를 확인할 수 있다.
```

**2. Commands** — 빌드/테스트/실행 명령어

```bash
# Kotlin/Spring Boot
./gradlew build                    # 빌드
./gradlew test                     # 전체 테스트
./gradlew test --tests "*Order*"   # 특정 테스트
./gradlew bootRun                  # 로컬 실행
./gradlew ktlintCheck              # 린트

# Python/FastAPI
pytest                             # 전체 테스트
pytest -k "test_order"             # 특정 테스트
uvicorn app.main:app --reload      # 로컬 실행
ruff check .                       # 린트
alembic upgrade head               # 마이그레이션
```

**3. Project Structure** — 소스/테스트/문서 위치

```
# Kotlin/Spring Boot
src/main/kotlin/com/example/
├── controller/    # REST/GraphQL 엔드포인트
├── service/       # 비즈니스 로직
├── repository/    # DB 접근 (JPA/R2DBC)
├── model/         # Entity, DTO
└── config/        # 설정 클래스

src/test/kotlin/com/example/
├── unit/          # 단위 테스트
├── integration/   # 통합 테스트 (@WebMvcTest, @DataJpaTest)
└── e2e/           # E2E 테스트 (@SpringBootTest)

# Python/FastAPI
app/
├── routers/       # API 라우터
├── services/      # 비즈니스 로직
├── models/        # SQLAlchemy 모델
├── schemas/       # Pydantic 스키마
└── deps.py        # Depends 의존성

tests/
├── unit/
├── integration/
└── conftest.py
```

**4. Code Style** — 실제 코드 스니펫으로 표현

```kotlin
// Kotlin: data class로 DTO 정의, companion object에 팩토리
data class OrderResponse(
    val id: Long,
    val status: OrderStatus,
    val totalAmount: BigDecimal,
) {
    companion object {
        fun from(entity: OrderEntity) = OrderResponse(
            id = entity.id,
            status = entity.status,
            totalAmount = entity.totalAmount,
        )
    }
}
```

**5. Testing Strategy**

| 유형 | 프레임워크 | 위치 | 비율 |
|------|-----------|------|------|
| Unit | Kotest + MockK / pytest | `test/unit/` | ~80% |
| Integration | @WebMvcTest, @DataJpaTest / httpx + TestClient | `test/integration/` | ~15% |
| E2E | @SpringBootTest / pytest + docker | `test/e2e/` | ~5% |

**6. Boundaries** — Always do / Ask first / Never do

| Always Do | Ask First | Never Do |
|-----------|-----------|----------|
| 입력값 검증 (Bean Validation/Pydantic) | DB 스키마 변경 (Flyway/Alembic) | 프로덕션 DB 직접 접속 |
| 에러 응답에 RFC 7807 형식 사용 | 새 외부 의존성 추가 | 인증 우회 경로 추가 |
| 변경된 로직에 테스트 추가 | CORS/보안 설정 변경 | 하드코딩된 시크릿 |

#### 성공 기준 재구성
모호한 요구사항을 측정 가능한 기준으로 변환:

```
❌ "주문 조회를 빠르게 해주세요"
✅ "주문 조회 API P95 응답 시간 < 200ms, 최근 30일 주문 대상, 커서 기반 페이지네이션"

❌ "검색 결과가 더 정확했으면"
✅ "검색 쿼리 'iPhone 케이스'에 대해 상위 5개 결과의 nDCG@5 ≥ 0.8"
```

---

### Phase 2: PLAN (기술 계획)

스펙이 승인되면 기술 구현 계획을 수립:
- 필요한 컴포넌트와 구현 순서 (의존성 그래프 기반)
- 리스크 식별 (외부 API 연동, 데이터 마이그레이션 등)
- 병렬/직렬 구분 (Flyway 마이그레이션은 반드시 순차적)
- 검증 체크포인트

→ `planning-guide` 스킬을 활용하여 상세 계획 수립

---

### Phase 3: TASKS (태스크 분해)

계획이 승인되면 실행 가능한 태스크로 분해:
- 각 태스크는 수직 슬라이스 (Entity + Service + Controller + Test)
- 태스크당 ~5파일 이하, XS~L 크기
- 수용 기준과 검증 단계 필수 포함

→ `planning-guide` 스킬의 Task Breakdown 프로세스 활용

---

### Phase 4: IMPLEMENT (구현)

태스크가 승인되면 구현 시작:
- TDD 원칙 적용 (`tdd-workflow` 스킬)
- 한 번에 하나의 태스크만 완료
- 각 태스크 완료 후 테스트 실행 및 커밋

---

## Keeping the Spec Alive

스펙은 살아있는 문서다:
- 구현 중 스펙과 달라지면 **스펙을 먼저 업데이트**하고 사람 승인을 받는다
- 스펙은 저장소에 파일로 저장: `docs/specs/YYYY-MM-DD-feature-name.md`
- GitLab MR description에 스펙 파일 링크를 포함한다

---

## Common Rationalizations

| Rationalization | Reality |
|----------------|---------|
| "이건 간단해서 스펙 불필요" | 간단한 태스크도 수용 기준은 필요하다. 2줄 스펙이면 충분하다 |
| "코딩 후에 스펙 쓰겠다" | 그건 문서화이지 명세가 아니다. 코드 전 명확성 강제가 스펙의 가치다 |
| "스펙이 속도를 늦춘다" | 15분 스펙이 수시간 재작업을 방지한다 |
| "요구사항은 어차피 변한다" | 그래서 스펙은 살아있는 문서다. 오래된 스펙도 없는 것보다 낫다 |
| "사용자가 원하는 걸 안다" | 명확한 요청에도 암묵적 가정이 있다. 스펙이 그걸 드러낸다 |

## Red Flags

- 작성된 요구사항 없이 코드 시작
- "done"의 의미가 정의되지 않은 상태에서 "그냥 시작"
- 스펙에 없는 기능 구현 (스코프 크리프)
- 문서화 없는 아키텍처 결정
- 구현 중 스펙 업데이트 없이 방향 전환

## Verification

- [ ] 스펙이 6개 핵심 영역 모두 커버
- [ ] 사람이 스펙을 검토하고 승인함
- [ ] 성공 기준이 구체적이고 측정 가능함
- [ ] Boundaries (Always/Ask First/Never) 정의됨
- [ ] 스펙이 저장소에 파일로 저장됨
- [ ] MR description에 스펙 링크 포함

---

## Related

- `planning-guide` — 아이디어 정제와 태스크 분해
- `tdd-workflow` — Phase 4에서 TDD 적용
- `/review-mr` — 구현 결과 리뷰
