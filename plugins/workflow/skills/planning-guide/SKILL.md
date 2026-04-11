---
name: planning-guide
description: Use this skill when refining vague ideas into concrete plans or breaking down features into implementable tasks. Covers idea refinement, dependency mapping, vertical slicing, and task sizing for Kotlin/Python backend teams.
---

# Planning Guide — 아이디어 정제부터 태스크 분해까지

모호한 아이디어를 구체적 계획과 실행 가능한 태스크로 변환하는 체계적 프로세스.

## When to Activate

- 모호하거나 넓은 범위의 요구사항을 받았을 때
- 새 기능이나 시스템 변경을 계획할 때
- "이거 해주세요"만 있고 구체적 범위가 없을 때
- 큰 작업을 실행 가능한 단위로 분해할 때
- 기능 개발 전 계획을 세워야 할 때

---

## Phase 1: Understand & Expand (아이디어 정제)

### Step 1: "How Might We" 재구성
모호한 요구사항을 문제 진술로 재구성한다.

```
요구사항: "주문 시스템이 좀 느려요"
→ "How Might We: 주문 생성 API의 P95 응답 시간을 500ms 이하로 줄일 수 있을까?"

요구사항: "검색이 잘 안 돼요"
→ "How Might We: 사용자가 3글자 이상 입력하면 200ms 이내에 관련 결과를 표시할 수 있을까?"
```

### Step 2: 핵심 질문 5가지
아이디어 정제 시 반드시 답해야 할 질문:
1. **누구를 위한 것인가?** (대상 사용자/소비자)
2. **성공 기준은 무엇인가?** (측정 가능한 지표)
3. **제약 조건은 무엇인가?** (시간, 기술, 데이터, 인프라)
4. **이전에 시도한 것은?** (실패 이유, 기존 접근법)
5. **왜 지금인가?** (긴급도, 비즈니스 동기)

### Step 3: 방향 평가
2~3개 가능한 접근법을 도출하고 3가지 기준으로 평가:

| 기준 | 질문 |
|------|------|
| **사용자 가치** | 이 접근법이 사용자의 문제를 실질적으로 해결하는가? |
| **실현 가능성** | 현재 기술 스택과 팀 역량으로 합리적 시간 내 구현 가능한가? |
| **유지보수성** | 6개월 후에도 이해하고 수정할 수 있는 구조인가? |

### Step 4: 가정 명시화
검증되지 않은 가정을 반드시 명시한다:

```
ASSUMPTIONS I'M MAKING:
- 주문 API 병목은 DB 쿼리 때문이다 (프로파일링 필요)
- 현재 인덱스 구조를 변경해도 다른 쿼리에 영향이 없다
- 트래픽 패턴은 피크 시간에도 현재 커넥션 풀로 충분하다
```

### Step 5: 원페이저 산출물

```markdown
## [기능/프로젝트명] 계획서

### Problem Statement
[HMW 형식의 문제 진술]

### Recommended Direction
[선택한 접근법과 이유]

### Key Assumptions to Validate
- [ ] [가정 1] — 검증 방법: [...]
- [ ] [가정 2] — 검증 방법: [...]

### MVP Scope
[최소 기능 범위]

### Not Doing (and Why)
- [제외 항목 1]: [이유]
- [제외 항목 2]: [이유]

### Open Questions
- [미해결 질문]
```

---

## Phase 2: Dependency Mapping (의존성 분석)

코드 작성 없이 **읽기 전용 모드**로 진입한다. 스펙을 읽고, 기존 패턴을 파악하고, 의존성을 매핑한다.

### 의존성 그래프 (백엔드 기준)

```
DB Schema (Flyway/Alembic)
    │
    ▼
JPA Entity / SQLAlchemy Model
    │
    ▼
Repository / DAO
    │
    ▼
Service Layer (비즈니스 로직)
    │
    ▼
Controller / Router (REST/GraphQL)
    │
    ▼
Integration Test
    │
    ▼
API 문서 (OpenAPI / GraphQL SDL)
```

> **상향식(Bottom-up) 구현**: 의존성 그래프의 아래(DB)에서 위(Controller)로 구현한다. 상위 레이어는 하위 레이어가 준비된 후에 구현.

---

## Phase 3: Task Breakdown (태스크 분해)

### 수직 슬라이싱 (Vertical Slicing)

**수평 슬라이싱 금지:**
```
❌ Task 1: 모든 Entity 생성
❌ Task 2: 모든 Repository 생성
❌ Task 3: 모든 Service 생성
❌ Task 4: 모든 Controller 생성
```

**수직 슬라이싱 권장:**
```
✅ Task 1: 주문 생성 (Entity + Repository + Service + Controller + Test)
✅ Task 2: 주문 조회 (Repository 메서드 + Service + Controller + Test)
✅ Task 3: 주문 취소 (Service 로직 + Controller + Test)
```

> 각 수직 슬라이스는 **독립적으로 테스트 가능한 기능**을 전달해야 한다.

### Task Sizing

| 크기 | 파일 수 | 범위 | 예시 |
|------|---------|------|------|
| **XS** | 1 | 단일 함수/설정 변경 | 유효성 검사 규칙 추가 |
| **S** | 1~2 | 단일 엔드포인트/쿼리 | API 엔드포인트 1개 추가 |
| **M** | 3~5 | 한 기능 슬라이스 | 주문 생성 플로우 |
| **L** | 5~8 | 다중 컴포넌트 기능 | 필터링+페이징 검색 |
| **XL** | 8+ | **분해 필요** | 더 작은 태스크로 분리 |

**분해 기준** — 다음 중 하나라도 해당하면 더 분해:
- 2시간 이상 소요 예상
- 수용 기준 3개 초과
- 독립 서브시스템 2개 이상 접촉
- 태스크 제목에 "and" 포함

### Task 템플릿

```markdown
### Task N: [태스크 제목]
- **Description**: [무엇을 왜 하는가]
- **Acceptance Criteria**:
  - [ ] [기준 1]
  - [ ] [기준 2]
- **Verification**:
  - `./gradlew test --tests "OrderServiceTest"` 통과
  - `./gradlew build` 성공
- **Dependencies**: Task N-1 완료 필요
- **Files**: `OrderEntity.kt`, `OrderService.kt`, `OrderController.kt`, `OrderServiceTest.kt`
- **Size**: M (~3-5 파일)
```

### 체크포인트
매 2~3개 태스크마다 체크포인트를 설정:
- [ ] 모든 테스트 통과 (`./gradlew test` / `pytest`)
- [ ] 빌드 성공 (`./gradlew build`)
- [ ] GitLab CI 파이프라인 통과
- [ ] 사람 리뷰 (필요 시)

---

## Common Rationalizations

| Rationalization | Reality |
|----------------|---------|
| "진행하면서 알아내겠다" | 엉킨 결과물과 재작업의 원인. 10분 계획이 수시간 절약한다 |
| "태스크는 뻔하다" | 그래도 적어라. 명시적 태스크가 숨겨진 의존성과 엣지케이스를 드러낸다 |
| "계획은 오버헤드다" | 계획이 곧 태스크다. 계획 없는 구현은 그냥 타이핑이다 |
| "머릿속에 다 담을 수 있다" | 컨텍스트 윈도우는 유한하다. 작성된 계획은 세션 경계를 넘어 생존한다 |
| "이건 간단해서 계획 불필요" | 간단한 태스크도 수용 기준은 필요하다. 2줄 계획이면 충분하다 |

---

## Red Flags

- 작성된 태스크 리스트 없이 구현 시작
- 수용 기준 없는 "기능 구현" 태스크
- 계획에 검증 단계 없음
- 모든 태스크가 XL 크기
- 수평 슬라이싱으로 분해 (모든 Entity → 모든 Service → 모든 Controller)
- 의존성 순서 미고려
- "누구를 위한 것인가?" 질문 건너뛰기

## Verification

- [ ] 문제 진술(HMW)이 명확하게 정의됨
- [ ] 대상 사용자와 성공 기준이 정의됨
- [ ] 가정이 명시되고 검증 방법이 있음
- [ ] 모든 태스크에 수용 기준과 검증 단계 존재
- [ ] 태스크가 수직 슬라이싱으로 분해됨 (태스크당 ~5파일 이하)
- [ ] 의존성 순서가 올바르고 체크포인트가 설정됨
- [ ] 사람이 계획을 검토 및 승인함

---

## Related

- `spec-driven-dev` — 이 계획을 공식 스펙 문서로 발전시킬 때
- `/review-mr` — 계획에 따른 구현 결과를 리뷰할 때
- `/handoff` — 계획과 진행 상황을 다른 세션에 인계할 때
