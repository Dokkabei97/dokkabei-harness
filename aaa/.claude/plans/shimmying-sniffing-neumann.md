# TDD 테스트 작성: outbound-adapter/legacy

## Context

`outbound-adapter/legacy` 모듈은 신규 검색 시스템의 상품 데이터를 레거시 API로 동기화하는 어댑터입니다. 현재 소스 파일 1개(`LegacySyncRepositoryImpl.kt`, 46줄)만 존재하고 **테스트가 전혀 없는 상태(0% 커버리지)**입니다. `outbound-adapter/proxy/src/test/` 패턴(Kotest FunSpec + MockK)을 기반으로 유닛 테스트를 작성합니다.

## 변경 대상 파일

### 1. build.gradle.kts - 테스트 의존성 추가
**파일**: `outbound-adapter/legacy/build.gradle.kts`

```kotlin
// 추가할 테스트 의존성
testImplementation("org.springframework.boot:spring-boot-starter-test")
testImplementation("io.kotest:kotest-runner-junit5-jvm")
testImplementation("io.kotest:kotest-assertions-core-jvm")
testImplementation("io.mockk:mockk:1.13.13")
```

> `kotest-extensions-spring`은 불필요 (Spring context 로딩 없는 순수 유닛 테스트이므로)

### 2. 테스트 파일 생성
**파일**: `outbound-adapter/legacy/src/test/kotlin/com/cowave/search/outbound_adapter/legacy/LegacySyncRepositoryImplTest.kt`

**테스트 스펙**: Kotest `FunSpec` + MockK (프로젝트 컨벤션 준수)

## 테스트 케이스

### pushLinkedProducts (서비스명: "PDM")
| 케이스 | Operation | 기대 HttpMethod |
|--------|-----------|----------------|
| CREATE 연동상품 동기화 | CREATE | POST |
| UPDATE 연동상품 동기화 | UPDATE | PUT |
| DELETE 연동상품 동기화 | DELETE | DELETE |

### pushUnlinkedProducts (서비스명: "TCMPNY_LINK")
| 케이스 | Operation | 기대 HttpMethod |
|--------|-----------|----------------|
| CREATE 비연동상품 동기화 | CREATE | POST |
| UPDATE 비연동상품 동기화 | UPDATE | PUT |
| DELETE 비연동상품 동기화 | DELETE | DELETE |

### pushUnlinkedProductDeletes (서비스명: "TCMPNY_LINK", 고정 DELETE)
| 케이스 | 기대 HttpMethod |
|--------|----------------|
| 비연동상품 삭제 동기화 | DELETE (고정) |

### 테스트 구조
- `context("pushLinkedProducts")` / `context("pushUnlinkedProducts")` / `context("pushUnlinkedProductDeletes")`로 그룹화
- MockK `coEvery`/`coVerify`로 suspend 함수 mock/verify
- `slot<T>()`으로 실제 전달된 파라미터 캡처 및 검증

## TDD 사이클

1. **RED**: 테스트 파일 생성 → `./gradlew :outbound-adapter:legacy:test` 실행 → 실패 확인
2. **GREEN**: 이미 구현체가 존재하므로 테스트가 바로 통과할 것 (기존 코드에 대한 회귀 테스트)
3. **REFACTOR**: 필요 시 테스트 구조 개선

> 참고: 기존 코드에 테스트를 추가하는 경우이므로 전통적 TDD 순서(RED→GREEN)보다는 **회귀 테스트 확보**가 목적입니다.

## 검증 방법

```bash
# 테스트 실행
./gradlew :outbound-adapter:legacy:test

# 전체 빌드 검증
./gradlew :outbound-adapter:legacy:build
```
