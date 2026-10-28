---
name: dto-design-patterns
description: |
  DTO/Request/Response 설계·리뷰 — 팀 규칙(channel 필수 non-null, Map<String, Any> 지양, Entity 직접 응답 금지, 컬렉션 nullable 금지, 조건 객체 파라미터) + 직렬화 함정(Jackson Kotlin 명시적 null, Spring 의 unknown 필드 무시, Go nil slice→null, int64 ID 의 JS 정밀도, Pydantic v2 Optional 필수화).
  Team DTO contract rules (required channel, no Map payloads, no entity exposure) plus serialization pitfalls across Kotlin/Jackson, Go encoding/json and Pydantic v2.
  Use when: writing or reviewing DTOs, request/response models, Kafka payload classes, or JSON serialization mappings.
---

# DTO 설계 — 팀 규칙 + 직렬화 함정

DTO 는 경계를 건너는 데이터의 계약이다. 이 스킬은 **팀 고유 규칙**과 **언어별 직렬화 함정**만 담는다.
프로젝트 CLAUDE.md / `.claude/rules` 가 다르게 정하면 프로젝트가 우선한다.

## 1. 팀 규칙

| ID | 규칙 | 리뷰 신호 |
|---|---|---|
| DTO-T-01 | **`channel` 은 서비스상 필수 — Request·필터·이벤트 페이로드에서 non-null** 로 선언하고 기본값을 두지 않는다 | `channel: Channel?`, `req.channel ?: error(...)`, `channel: Channel = Channel.DEFAULT` |
| DTO-T-02 | 구조를 아는 페이로드는 data class(Go struct, Pydantic model). `Map<String, Any>` 는 진짜 동적인 부분(메타데이터)에만 | `payload["id"] as? Long`, 도메인/application 레이어의 `Map<*, *>` 파라미터 |
| DTO-T-03 | 비즈니스 필수 = non-null, 진짜 선택 = nullable + 기본값 `null`, 기본값이 있는 옵션은 non-null + 기본값 | `page: Int?` 후 `?: 1` |
| DTO-T-04 | 응답에 `@Entity`/ORM 모델을 그대로 내보내지 않는다. 도메인에서 non-null 인 값은 응답에서도 non-null | `ResponseEntity<UserEntity>`, 응답 필드 전부 `?` |
| DTO-T-05 | 컬렉션 필드는 nullable 대신 빈 컬렉션 기본값 (`emptyList()`), Go 는 nil slice 를 빈 slice 로 (DTO-S-03) | `tags: List<String>?` |
| DTO-T-06 | "나중에 늘어날 수도" 로 모든 필드를 nullable/String 으로 두지 않는다. 확장이 **현실**이면 sealed interface 로 분기 | 5개 이상 nullable 조합 + 조합 검증 없음 |
| DTO-T-07 | 조건이 둘 이상 모일 수 있는 조회 파라미터는 처음부터 조건 객체(`ProductQueryVariables`) | `query(ids, status, channel)` 시그니처 증식 |
| DTO-T-08 | 외부 API 응답은 신뢰 경계: 전용 DTO 로 받고, 도메인 변환 지점에서 검증(blank·범위·시간대) | 외부 응답 `Map`/원문 String 이 서비스 계층까지 전달 |

```kotlin
data class SearchAdminCatalogRequest(
    val channel: Channel,                              // DTO-T-01
    val keyword: String? = null,                       // 진짜 선택
    val paging: SearchPaging = SearchPaging.DEFAULT,   // 기본값 있는 옵션
)

sealed interface AggregationRequest {                  // DTO-T-06: 확장이 현실일 때만
    val channel: Channel
    data class CategoryCount(override val channel: Channel, val category: Category) : AggregationRequest
    data class BrandCount(override val channel: Channel, val brandId: Long) : AggregationRequest
}
```

## 2. 직렬화 함정 (DTO-S) → [references/serialization.md](references/serialization.md)

| 증상/코드 신호 | 항목 |
|---|---|
| `"field": null` 전송 시 400, 누락은 정상 (Kotlin + Jackson) | DTO-S-01 |
| 오타 필드·스키마 변경이 조용히 무시됨, Jackson 3/Boot 4 이행 | DTO-S-02 |
| Go 응답 `"items": null`, PATCH 로 0/false 불가, `omitempty` 미동작 | DTO-S-03 |
| 프론트에서 64비트 ID 끝자리 변형·재조회 404 | DTO-S-04 |
| Pydantic v2 이행 후 누락 필드 422 | DTO-S-05 |

## 3. 리뷰 체크리스트

- [ ] channel 이 non-null 필수인가 (DTO-T-01)
- [ ] Map 페이로드·Entity 응답·nullable 컬렉션이 없는가 (T-02, T-04, T-05)
- [ ] 외부 응답 → 도메인 변환에 검증이 있는가 (T-08)
- [ ] 명시적 null·unknown 필드·빈 컬렉션 직렬화 결과가 계약과 맞는가 (S-01~S-03)
- [ ] 64비트 ID 가 JS 소비자에게 숫자로 나가지 않는가 (S-04)

## 관련

- `kotlin-spring:kotlin-spring-guide` references/team-conventions.md — 목적 중심 네이밍, enum 통일, 변환 함수 동사형(팀 리뷰 규칙)
- `api-designer` 에이전트 — REST/GraphQL 계약 설계 전반
