# TDD: LegacyApiTest 통합 테스트 완성

## Context

`LegacyApiTest.kt`는 현재 빈 FunSpec 테스트 클래스로, 실제 개발서버(`119.205.208.36:8080`)의 레거시 API를 호출하는 통합 테스트를 작성해야 합니다.

## 의존성 제약

`legacy-api` 모듈에는 `application:index` 의존성이 없으므로 DTO 클래스 사용 불가 → `Map`/`List<Map>`으로 바디 구성.

## 수정 파일

| 파일 | 변경 |
|------|------|
| `outbound/client/legacy-api/src/test/kotlin/.../LegacyApiTest.kt` | 6개 테스트 케이스 작성 |

## 테스트 케이스 (6개)

### PDM 서비스 (연동상품)
| # | 테스트 | HTTP Method | Body 형태 |
|---|--------|------------|-----------|
| 1 | PDM - CREATE | POST | `LinkedProductRequest` 형태 Map |
| 2 | PDM - UPDATE | PUT | `LinkedProductRequest` 형태 Map |
| 3 | PDM - DELETE | DELETE | `LinkedProductRequest` 형태 Map |

### TCMPNY_LINK 서비스 (비연동상품)
| # | 테스트 | HTTP Method | Body 형태 |
|---|--------|------------|-----------|
| 4 | TCMPNY_LINK - CREATE | POST | `UnlinkedProductRequest` 형태 Map |
| 5 | TCMPNY_LINK - UPDATE | PUT | `UnlinkedProductRequest` 형태 Map |
| 6 | TCMPNY_LINK - DELETE | DELETE | `UnlinkedProductDeleteRequest` 형태 Map |

각 테스트는 `shouldNotThrowAny`로 실제 API 호출 성공 여부를 검증합니다. Kotest `context` 블록으로 PDM / TCMPNY_LINK를 그룹핑합니다.

## 검증

```bash
./gradlew :outbound:client:legacy-api:test --tests "*LegacyApiTest"
```
