> [English](README.md) · **한국어**

# go-mux

> Go 표준 라이브러리 `net/http` mux(Go 1.22+ ServeMux) 기반 백엔드의 코드 생성·API 설계·개발 가이드를 묶은 특화 플러그인.

## 개요

go-mux는 서드파티 라우터(chi, gin, gorilla) 없이 Go 표준 `net/http` ServeMux와 `database/sql`로 백엔드를 구성하는 프로젝트를 위한 플러그인이다. 도메인 모델 하나로부터 Model → Repository → Service → Handler → DTO → Test 전 계층을 프로젝트의 기존 컨벤션에 맞춰 스캐폴딩하고, RESTful API를 설계·구현하며, 계층 규율·DB 접근·테스트 전략을 담은 종합 가이드를 코드 작성 시 자동으로 참조한다.

핵심 설계 의도는 "관용적 Go(idiomatic Go)"와 "계층 규율" 두 가지다. 생성 전 항상 대상 프로젝트를 먼저 분석해 패키지 레이아웃, 핸들러 패턴, DB 드라이버, 테스트 프레임워크를 추출한 뒤 그 컨벤션을 그대로 따르며, Java/Python식 비관용 패턴은 배제한다. 언어 무관 백엔드 공통 패턴(API 계약 원칙, DB 마이그레이션, 헥사고날 아키텍처, 관측성·보안 등)은 이 플러그인이 다루지 않고 `backend-shared` 플러그인에 위임한다 — 두 플러그인을 함께 쓰는 것을 전제로 한다.

## 구성요소

### 에이전트

- `go-mux-developer` — Go + stdlib `net/http` mux 코드 생성 전문 에이전트. 프로젝트 구조·컨벤션을 먼저 분석(Discovery → Convention Extraction)한 뒤 Model·Repository·Service·Handler·DTO·Test 전체 계층을 bottom-up으로 생성하고, `go build`/`go vet`/`go test`로 검증한다. 관용적 Go 이디엄(인터페이스 수용·구조체 반환, `%w` 에러 래핑, `context.Context` 전파, 테이블 주도 테스트)을 적용하고 비관용 패턴은 회피한다.

### 커맨드

- `/go-gen` — 도메인명을 입력하면 CRUD 전체 계층(Model, Repository, Service, Handler, DTO, Test)을 자동 생성한다. `--fields`, `--layers`, `--no-test`, `--db`, `--soft-delete`, `--audit` 옵션으로 필드·생성 계층·DB 드라이버·소프트 삭제·감사 필드를 제어한다.
- `/go-api-design` — 요구사항으로부터 REST API 엔드포인트를 설계하고 Handler·DTO·에러 핸들링·미들웨어 코드를 생성한다. 리소스 식별 → 명세 설계 → 코드 생성 3단계로 진행하며, `--version`, `--auth`, `--pagination`(cursor/offset), `--middleware`(logging/recovery/cors/auth) 옵션과 API 명세표 출력을 제공한다.

### 스킬

- `go-mux-guide` — Go + stdlib `net/http` mux 개발 종합 가이드. 코드 작성 시 자동 참조되며, 관용적 Go 원칙·계층 규율(의존 방향 위→아래)·에러 처리 3단계 방어·컨텍스트 전파와 아키텍처/레이아웃/DB 드라이버/테스트 프레임워크 선택 기준을 제공한다. 상세 레퍼런스로 계층별 패턴(`references/layer-patterns.md`), DB 패턴(`references/db-patterns.md`), 테스트 패턴(`references/testing-patterns.md`)을 포함한다.

## 사용법

- CRUD 스캐폴딩: `/go-gen Order` 또는 `/go-gen Product --fields "Name:string, Price:float64, Stock:int"` — 도메인 전체 계층을 생성한다. 특정 계층만 필요하면 `/go-gen Payment --layers "model,repo,service"`.
- API 설계: `/go-api-design 주문 관리` 또는 `/go-api-design 사용자 관리 --middleware logging,recovery,auth` — 엔드포인트 설계와 함께 Handler/DTO/에러/미들웨어 코드를 만든다.
- 커맨드는 내부적으로 `go-mux-developer` 에이전트와 `go-mux-guide` 스킬을 활용한다. "Order 핸들러 만들어줘", "결제 API 설계해줘" 같은 자연어 요청으로도 트리거되며, Go stdlib mux 프로젝트가 대상일 때 동작한다.
- 비즈니스 로직이 필요한 지점은 임의로 구현하지 않고 `// TODO(human)` 마커를 남긴다. 기존 파일은 명시적 요청 없이 수정하지 않으며, `go.mod` 의존성 추가도 별도 확인을 거친다.

## 의존성

- `requires` / `dependencies`: `backend-shared`. 언어 무관 백엔드 공통 패턴을 담당하므로 함께 설치해 사용한다.
- 버전 민감 API(Go 1.22+ ServeMux 패턴 매칭 등)는 `backend-shared:context7-docs-guide` 규약에 따라 Context7 MCP로 문서를 조회한 뒤 생성한다. Context7 미설치 시 해당 단계는 생략된다.

## 참고

- 대상 스택은 Go 표준 `net/http` ServeMux(Go 1.22+ 메서드 기반 라우팅)와 `database/sql`이다. chi·gin·gorilla 등 서드파티 라우터를 쓰는 프로젝트는 대상이 아니며(프로젝트가 이미 사용 중인 경우 제외), 필요 시 다른 에이전트가 적합하다.
- DB 드라이버는 프로젝트 감지를 기본으로 하며 `database/sql`, `pgx`, `sqlx`를 지원한다.
- 생성 코드는 항상 검증(build/vet/test)을 거치되, 최종 컴파일·테스트 통과 책임은 실제 프로젝트 환경에 달려 있으므로 결과를 확인하고 반영한다.
