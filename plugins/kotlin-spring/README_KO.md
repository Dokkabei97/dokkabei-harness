> [English](README.md) · **한국어**

# kotlin-spring

> Kotlin + Spring Boot 프로젝트에서 관용적인 CRUD 계층 코드를 생성하고, 프레임워크 진단·원칙·네이밍·관용 패턴을 한 벌로 묶은 백엔드 특화 플러그인.

## 개요

`kotlin-spring`은 Kotlin + Spring Boot 스택에 특화된 코드 생성·진단·레퍼런스 도구 모음이다. 도메인명 하나로 Entity → Repository → Service → Controller → DTO → Test 전체 계층을 프로젝트 기존 컨벤션에 맞춰 스캐폴딩하는 것이 핵심 기능이며(`/spring-gen` + `spring-developer`), 여기에 프레임워크 레벨 문제를 진단하는 전문 에이전트(`spring-boot-guide`)와 개발 원칙·네이밍·관용 패턴을 필요한 순간 붙여주는 스킬들이 결합된다.

코드 생성은 "먼저 분석하고 그다음 생성한다"는 규율을 따른다. `build.gradle.kts`·`application.yml`과 기존 소스를 스캔해 패키지 구조, DTO 패턴, 테스트 프레임워크(Kotest/JUnit·MockK), 에러 처리 방식, Audit 패턴을 추출한 뒤 그 컨벤션대로 코드를 낸다. Java 관용구(`Optional`, getter/setter, `!!`)를 배제한 Kotlin First 스타일을 강제하고, 비즈니스 로직은 임의 구현하지 않고 `TODO(human)` 마커로 남긴다.

언어중립 백엔드 공통 관심사(REST/GraphQL API 계약, DB 마이그레이션 안전성, 헥사고날 아키텍처, 관측성/캐싱/이벤트/회복탄력성/보안)는 이 플러그인이 다루지 않고 `backend-shared` 플러그인에 위임한다. Kotlin/Spring 특화 부분만 담당하므로 둘을 함께 설치해 조합하는 것을 전제로 한다.

## 구성요소

### 커맨드

- `/spring-gen [도메인명]` — Kotlin Spring Boot CRUD 전체 계층을 스캐폴딩한다. Discovery(컨벤션 분석) → Generation(계층별 생성) → Verification(컴파일·테스트) 3단계로 진행하며, `--fields`, `--layers`, `--no-test`, `--reactive`(WebFlux + R2DBC), `--soft-delete`, `--audit` 옵션으로 생성 범위와 패턴을 조절한다.

### 에이전트

- `spring-developer` — 코드 생성 전문 에이전트. `/spring-gen`의 실제 생성 엔진으로, 프로젝트 컨벤션을 추출(Decision Matrix)해 관용적 Kotlin 전체 CRUD 스택을 만든다. 도구는 Read/Grep/Glob/Bash/Write/Edit, 스킬 `kotlin-spring-guide`를 참조한다.
- `spring-boot-guide` — Spring Boot(Kotlin) 프레임워크 진단 전문가(읽기 전용: Read/Grep/Glob/Bash). DI/빈 충돌, `@Transactional` 전파·프록시(self-invocation) 이슈, Spring Security, Data JPA/R2DBC, N+1, 테스트 슬라이스, 자동설정, Spring for GraphQL 문제를 진단하고 패턴을 권장한다.

### 스킬

- `kotlin-spring-guide` — 개발 원칙·의사결정 가이드. Kotlin First, 레이어 규율(위→아래 의존), Fail Fast(3중 방어), Convention over Configuration 원칙과 아키텍처/스택/테스트 프레임워크 선택 기준을 제공한다. 세부 레퍼런스로 `references/layer-patterns.md`(계층별 패턴), `references/jpa-patterns.md`(Entity 설계·N+1 방지·연관관계·영속성 컨텍스트), `references/testing-patterns.md`(Kotest·MockK·@WebMvcTest·@DataJpaTest)를 포함한다.
- `spring-boot-patterns` — 실제 구현 코드 예제 중심 관용 패턴 레퍼런스. `@Transactional` 시맨틱(propagation/isolation/readOnly/rollbackFor·프록시 함정), Spring Data JPA 쿼리(메서드 쿼리·JPQL·QueryDSL·@EntityGraph·Page/Slice), `@ControllerAdvice`(RFC 7807 ProblemDetail)·에러 코드 체계, Bean Validation(그룹 검증·커스텀 Validator), 설정 바인딩(@ConfigurationProperties·relaxed binding), Spring for GraphQL(@BatchMapping·DataLoader), Coroutines 통합, WebClient 패턴을 다룬다.
- `naming-conventions` — Kotlin 네이밍 관용구. 목적 중심 vs 구현 중심(`isExpired` vs `expiredAt`), Enum 이름 불변성(`POPULARITY` vs `POPULARITY_SCORE`), 변환 함수 동사형(`convertTo~` vs `to~`), `const val` 대문자, 파라미터는 함수 입장 기준, 도메인 용어 일관성(`~Info`/`~Data` 지양), `Map<String, Any>` 파라미터 지양, primitive 확장함수 지양을 규칙과 체크리스트로 정리한다.

## 사용법

CRUD 스캐폴딩은 `/spring-gen`으로 직접 호출한다. 도메인명 뒤에 옵션을 붙여 필드·계층·스택을 지정한다.

```
# Order 도메인의 전체 CRUD 계층 생성
/spring-gen Order

# 필드를 정의해 Product 계층 생성
/spring-gen Product --fields "name:String, price:BigDecimal, stock:Int"

# Controller 없이 Entity/Repository/Service만
/spring-gen Payment --layers "entity,repo,service"

# WebFlux + R2DBC 리액티브 스택 (suspend/Flow)
/spring-gen Notification --reactive

# soft delete + audit 필드 적용
/spring-gen Member --soft-delete --audit
```

에이전트와 스킬은 별도 명령 없이 맥락에서 동작한다. `spring-developer`는 `/spring-gen` 실행 시 생성을 수행하고, `spring-boot-guide`는 트랜잭션/DI/GraphQL 등 프레임워크 진단이 필요할 때 활용된다. 스킬(`kotlin-spring-guide`·`spring-boot-patterns`·`naming-conventions`)은 Kotlin + Spring 코드를 작성·리뷰·리팩터링하는 순간 자동으로 로드되어 원칙과 패턴 예제, 네이밍 판단 기준을 보강한다. 원칙·의사결정은 `kotlin-spring-guide`, 구체적 구현 코드 예제는 `spring-boot-patterns`로 역할이 나뉜다.

## 의존성

- **requires / dependencies**: `backend-shared`. 언어중립 백엔드 공통 패턴(API 계약, 마이그레이션, 헥사고날, 관측성/캐싱/이벤트/회복탄력성/보안, DTO·테스트 패턴)은 `backend-shared`가 담당하므로 함께 설치해 조합한다.
- Python/FastAPI 특화가 필요하면 `python-fastapi` 플러그인이 대응된다.

## 참고

- `/spring-gen`은 기존 파일을 무단 수정하지 않으며, 비즈니스 로직은 임의 구현하지 않고 `TODO(human)` 마커로 표시한다.
- `build.gradle.kts` 의존성 추가는 사용자 확인 없이 하지 않고, 프로젝트에 없는 의존성을 요구하는 코드도 생성하지 않는다.
- Java 스타일 Kotlin(`Optional.get()`, getter/setter, `!!`, Java Stream)은 생성하지 않는다.
- 컴파일·테스트 실행(`./gradlew compileKotlin`, `./gradlew test`)은 검증 단계에서 수행하며, 생성 코드가 프로젝트 컨벤션과 일치하는지 확인한 뒤 리포트로 정리한다.
- 버전 민감 API(Spring Boot 3.x 설정 등)는 `backend-shared:context7-docs-guide` 규약에 따라 Context7 조회 후 반영하며, 미설치 시 생략한다.
