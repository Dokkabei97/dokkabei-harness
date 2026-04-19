---
name: bean-check
description: "DI 설정 검증 — 순환 의존성, 누락된 Bean, @Transactional 오용, Depends 체인 분석, GraphQL DataLoader 검증 (Spring Boot/FastAPI)"
category: validation
complexity: intermediate
mcp-servers: []
personas: []
---

# /bean-check - DI/트랜잭션 설정 검증

## Triggers
- 애플리케이션 시작 시 Bean 관련 에러가 발생할 때
- 트랜잭션이 예상대로 동작하지 않는 문제를 진단할 때
- 새로운 서비스를 추가한 후 DI 구성이 올바른지 확인하고 싶을 때
- GraphQL resolver에서 N+1 문제가 의심될 때
- 프로젝트 전반의 DI/트랜잭션 건강 상태를 점검할 때

## Usage
```
/bean-check [대상] [옵션]

Options:
  --lang kotlin|python|auto     대상 언어 (기본: auto)
  --focus di|transaction|scope|graphql|all  검증 영역 (기본: all)
  --fix                         자동 수정 제안 포함
```

## Behavioral Flow

### 검증 플로우
1. **Discover**: 프로젝트 파일 스캔, Bean/Provider 등록 맵 구축
   - Kotlin: `@Component`, `@Service`, `@Repository`, `@Configuration` 스캔
   - Python: `Depends()`, `@inject`, Provider 등록 패턴 스캔
2. **Scan**: focus 영역별 패턴 검사
   - **di**: 순환 의존성, 누락 Bean, 모호한 주입(`@Qualifier` 누락), Depends 순환
   - **transaction**: `@Transactional` on private fun, self-invocation, readOnly 누락, propagation 오용
   - **scope**: `@Scope("prototype")` in singleton holder, `@RequestScope` 오용
   - **graphql**: DataLoader 미사용(N+1 위험), `@BatchMapping` 누락, resolver 스레드 안전성
3. **Evaluate**: 발견 항목 심각도 분류 (Critical / High / Medium / Low)
4. **Report**: 구조화된 리포트 출력
5. **Fix**: (--fix) 자동 수정 코드 제안

## Detection Patterns

### Spring Boot (Kotlin)
| 패턴 | 심각도 | 설명 |
|------|--------|------|
| `@Transactional` on `private fun` | 🔴 Critical | 프록시 AOP 무효화 |
| `this.method()` → `@Transactional` 메서드 호출 | 🔴 Critical | self-invocation 바이패스 |
| 순환 의존성: A→B→A | 🔴 Critical | 애플리케이션 시작 실패 |
| 주입 대상에 `@Component`/`@Service` 누락 | 🔴 Critical | NoSuchBeanDefinition 에러 |
| SELECT 전용 메서드에 `readOnly = true` 누락 | 🟡 Medium | 성능 최적화 누락 |
| 같은 인터페이스 구현체 여럿에 `@Qualifier` 없음 | 🟡 High | 모호한 주입 |
| `@Scope("prototype")` Bean을 singleton이 주입 | 🟡 High | 스코프 불일치 |

### FastAPI (Python)
| 패턴 | 심각도 | 설명 |
|------|--------|------|
| `async def` 핸들러에서 동기 `session.execute()` | 🔴 Critical | 이벤트 루프 블로킹 |
| Depends 순환 체인 | 🔴 Critical | 의존성 해결 실패 |
| `time.sleep()` in async 컨텍스트 | 🟡 High | 이벤트 루프 블로킹 |
| yield dependency에서 return 누락 | 🟡 Medium | 리소스 정리 실패 가능 |
| `Depends` 중첩 깊이 > 5 | 🟡 Medium | 복잡도 과다 |

### GraphQL
| 패턴 | 심각도 | 설명 |
|------|--------|------|
| 리스트 부모 resolver에서 DB 쿼리 | 🟡 High | N+1 쿼리 문제 |
| 관련 엔티티 로딩에 `@BatchMapping` 미사용 | 🟡 High | N+1 쿼리 문제 |
| DataLoader에 캐싱 미적용 | 🟡 Medium | 불필요한 중복 쿼리 |

## Tool Coordination
- **Glob**: 프로젝트 전체 파일 탐색
- **Grep**: Bean 어노테이션, 의존성 주입 패턴 검색
- **Read**: 의존성 체인 추적, 코드 상세 분석
- **Bash**: 컴파일 검증, 정적 분석 도구 실행

## Examples

### 전체 프로젝트 스캔
```
/bean-check
# 프로젝트 전체 DI + 트랜잭션 + 스코프 + GraphQL 검증
# 종합 리포트 출력
```

### 트랜잭션 집중 검증
```
/bean-check src/main/kotlin/ --focus transaction
# @Transactional 관련 문제만 집중 스캔
# private 메서드, self-invocation, readOnly 누락 등
```

### Python DI 검증 + 자동 수정
```
/bean-check app/ --lang python --focus di --fix
# Depends 체인 분석, 순환 의존성 탐지
# 수정 코드 제안 포함
```

### GraphQL DataLoader 검증
```
/bean-check --focus graphql
# N+1 패턴 감지, BatchMapping 누락 확인
# DataLoader 캐싱 설정 점검
```

## Output Format
```
## Bean Check 검증 결과

### 요약
- 스캔 파일: 47개
- 발견 항목: 8건 (Critical: 2, High: 3, Medium: 3)

### 상세 결과
| 심각도 | 카테고리 | 파일:라인 | 문제 | 제안 |
|--------|---------|----------|------|------|
| 🔴 Critical | transaction | OrderService.kt:45 | private fun에 @Transactional | public으로 변경 또는 별도 Bean 분리 |
| 🔴 Critical | di | PaymentService.kt:12 | 순환 의존성 감지 (→ OrderService → PaymentService) | 인터페이스 분리 또는 이벤트 기반 디커플링 |
| 🟡 High | graphql | ProductResolver.kt:30 | 리스트 resolver에서 개별 DB 조회 (N+1) | @BatchMapping + DataLoader 적용 |
| 🟡 Medium | transaction | UserService.kt:22 | findAll()에 readOnly 미지정 | @Transactional(readOnly = true) 추가 |
```

## Boundaries

**Will:**
- 정적 코드 분석 기반의 DI/트랜잭션/스코프 문제 탐지
- 순환 의존성 체인 시각화 및 해결 방안 제시
- GraphQL resolver의 N+1 패턴 감지
- 심각도 기반 우선순위 리포트 제공
- 자동 수정 코드 제안 (--fix 옵션)

**Will Not:**
- 런타임 Bean 생성(조건부 `@ConditionalOnProperty` 등)의 동적 판단
- 실제 애플리케이션 실행을 통한 통합 테스트
- 코드 자동 수정 적용 (제안만 제공, 적용은 사용자 판단)
- 외부 라이브러리 내부 Bean 분석

## Related
- `/graphql-check` — GraphQL 스키마/성능/보안 종합 검증
- `/api-test` — 발견된 문제 수정 후 테스트 작성
- `/migrate` — 트랜잭션과 관련된 DB 마이그레이션 검토
