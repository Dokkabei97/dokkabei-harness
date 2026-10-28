# 팀 결정 사항 — Kotlin 네이밍·코드 리뷰 규칙

> 범용 Kotlin/Spring 관용구(data class, null safety, 레이어 의존 방향 등)는 여기 두지 않는다 — 모델이 이미 안다.
> 이 파일은 **검색팀 테크리더 리뷰에서 반복 지적된 팀 고유 결정**만 담는다.
> 우선순위: 프로젝트 `CLAUDE.md` / `.claude/rules/` > 이 파일 > 일반 관용구. 프로젝트 규칙과 충돌하면 프로젝트를 따른다.
> (레포 이력: dokkabei-harness 저장소의 `archive/components/kotlin-spring/skills/naming-conventions/` 에 원본 예제가 있다 — 설치본에는 없다. 규칙은 아래 표로 충분하다.)

## 네이밍 (리뷰 규칙 요약)

| 상황 | 팀 규칙 | 근거 |
|---|---|---|
| 외부 노출 Boolean | `isExpired`(목적) — `expiredAt`(구현)은 내부 필드로 숨김 | 호출부에 판단 로직 중복 방지 |
| Enum 상수 | 성질만 담는다 `POPULARITY` — `POPULARITY_SCORE`/`_RANK` 금지 | 구현(score→rank)이 바뀌어도 이름 불변, 외부 저장값 마이그레이션 회피 |
| 변환 함수 | `to~` = 단순 표현 전환만(`toEpochMicros`). 매핑·검증·조립이 있으면 `convertTo~`/`mapTo~`/`buildFrom~` | 이름에서 비용·실패 가능성 노출 |
| `const val` | `UPPER_SNAKE_CASE` (companion 포함). 런타임 `val` 은 camelCase | |
| 파라미터 이름 | 함수 내부 역할(`defaultInstant`) — 호출부 변수명(`collectedAt`) 복사 금지. 호출부 명확성은 named argument 로 | |
| 도메인 용어 | `~Info`/`~Data`/`~Wrapper`/`~Util` 범용 접미사 지양. `Single~`/`Simple~` 은 대비 대상이 있을 때만 | |
| 파라미터 타입 | 구조가 알려진 `Map<String, Any>` 금지 → data class. 진짜 동적(설정 로더·generic 어댑터)만 예외 | |
| 확장 함수 | 도메인 타입에만. `String.toKeyword()`, `Long.toProductId()` 같은 primitive 확장 금지 → companion `from()` | 자동완성 오염·컨텍스트 손실 |

## 코드 생성 기본값 (`/spring-gen`·`spring-developer` 가 프로젝트 컨벤션을 못 찾았을 때만)

- 테스트: Kotest(BehaviorSpec 기본, 간결한 단위는 FunSpec) + MockK, Spring 슬라이스 목은 `@MockkBean`(springmockk).
  프로젝트가 JUnit5/Mockito 면 그쪽을 따른다.
- 에러: `ErrorCode` enum(`status`, `code`, `message`) + `BusinessException(errorCode)` 계층, 코드는 도메인 접두 3자리
  (`ORD-001`). 커스텀 예외는 **RuntimeException 상속**(SPR-TX-03).
- 서비스: 클래스 레벨 `@Transactional(readOnly = true)` + 쓰기 메서드만 `@Transactional`.
- 비즈니스 로직은 구현하지 않고 `TODO(human)` 로 남긴다.

## 리뷰 시 의사결정 순서 (네이밍)

1. 처음 보는 동료가 맥락 없이 의미를 추론할 수 있는가
2. 외부 인터페이스인가 내부 구현인가 (목적 vs 구현)
3. 시간이 지나도 유효한 성질을 담았는가
4. 같은 도메인의 유사 이름과 구분되는가
