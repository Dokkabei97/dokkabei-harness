> [English](README.md) · **한국어**

# go-mux

> Go 런타임·성능 스페셜리스트 지식(map·슬라이스·GC·동시성·net/http·pprof/PGO·database/sql, 78개 항목)과 Go 표준 `net/http` mux(Go 1.22+ ServeMux) 기반 코드 생성·API 설계를 묶은 플러그인. 이름은 go-mux 지만 Go 전반을 다룬다.

## 개요

go-mux는 서드파티 라우터(chi, gin, gorilla) 없이 Go 표준 `net/http` ServeMux와 `database/sql`로 백엔드를 구성하는 프로젝트를 위한 플러그인이다. 도메인 모델 하나로부터 Model → Repository → Service → Handler → DTO → Test 전 계층을 프로젝트의 기존 컨벤션에 맞춰 스캐폴딩하고, RESTful API를 설계·구현하며, 계층 규율·DB 접근·테스트 전략을 담은 종합 가이드를 코드 작성 시 자동으로 참조한다.

핵심 설계 의도는 "관용적 Go(idiomatic Go)"와 "계층 규율" 두 가지다. 생성 전 항상 대상 프로젝트를 먼저 분석해 패키지 레이아웃, 핸들러 패턴, DB 드라이버, 테스트 프레임워크를 추출한 뒤 그 컨벤션을 그대로 따르며, Java/Python식 비관용 패턴은 배제한다. 언어 무관 백엔드 공통 패턴(Context7 문서 조회 규약, DTO 설계 등)은 이 플러그인이 다루지 않고 `backend-shared` 플러그인에 위임한다 — 두 플러그인을 함께 쓰는 것을 전제로 한다.

## 구성요소

### 에이전트

- `go-mux-developer` — Go + stdlib `net/http` mux 코드 생성·리뷰 전문 에이전트. go.mod `go`/`toolchain` 라인·빌드 이미지·배포 limit 같은 사실을 먼저 확인하고, 리뷰/성능 진단 모드에서는 스페셜리스트 항목 ID 로 소견을 보고한다. 프로젝트 구조·컨벤션을 먼저 분석(Discovery → Convention Extraction)한 뒤 Model·Repository·Service·Handler·DTO·Test 전체 계층을 bottom-up으로 생성하고, `go build`/`go vet`/`go test`로 검증한다. 관용적 Go 이디엄(인터페이스 수용·구조체 반환, `%w` 에러 래핑, `context.Context` 전파, 테이블 주도 테스트)을 적용하고 비관용 패턴은 회피한다.

### 커맨드

- `/go-gen` — 도메인명을 입력하면 CRUD 전체 계층(Model, Repository, Service, Handler, DTO, Test)을 자동 생성한다. `--fields`, `--layers`, `--no-test`, `--db`, `--soft-delete`, `--audit` 옵션으로 필드·생성 계층·DB 드라이버·소프트 삭제·감사 필드를 제어한다.
- `/go-api-design` — 요구사항으로부터 REST API 엔드포인트를 설계하고 Handler·DTO·에러 핸들링·미들웨어 코드를 생성한다. 리소스 식별 → 명세 설계 → 코드 생성 3단계로 진행하며, `--version`, `--auth`, `--pagination`(cursor/offset), `--middleware`(logging/recovery/cors/auth) 옵션과 API 명세표 출력을 제공한다.

### 스킬

- `go-mux-guide` — Go 런타임·성능 스페셜리스트 트리아지 + stdlib mux 가이드. 증상(OOMKill, GC CPU, 고루틴 증가, TIME_WAIT, 풀 대기 등) → 항목 ID 표로 필요한 레퍼런스만 읽게 한다. 각 항목은 적용 조건·신호·메커니즘·처방·반례·검증·근거(공식 문서/소스)를 가지며, `workflow:project-rules` 로 프로젝트별 선별이 가능하다.
  - 스페셜리스트: `maps.md`(GO-MAP), `slices-strings.md`(GO-SLC), `gc-memory.md`(GO-GC), `concurrency.md`(GO-CON), `net-http.md`(GO-HTTP), `observability.md`(GO-OBS), `database-sql.md`(GO-DB), `toolchain-versions.md`(GO-VER)
  - 스캐폴딩 컨벤션: `layer-patterns.md`, `db-patterns.md`, `testing-patterns.md`

## 사용법

- CRUD 스캐폴딩: `/go-gen Order` 또는 `/go-gen Product --fields "Name:string, Price:float64, Stock:int"` — 도메인 전체 계층을 생성한다. 특정 계층만 필요하면 `/go-gen Payment --layers "model,repo,service"`.
- API 설계: `/go-api-design 주문 관리` 또는 `/go-api-design 사용자 관리 --middleware logging,recovery,auth` — 엔드포인트 설계와 함께 Handler/DTO/에러/미들웨어 코드를 만든다.
- `/go-gen`, `/go-api-design` 은 사용자가 `/` 로 직접 호출하는 생성기다(`disable-model-invocation: true` — 모델이 자동 발화하지 않음). 자연어 요청("Order 핸들러 만들어줘")은 `go-mux-developer` 에이전트와 `go-mux-guide` 스킬이 처리한다.
- 성능·메모리 리뷰: "이 핸들러 GC 부담 봐줘", "고루틴이 계속 늘어" 같은 요청에서 `go-mux-guide` 트리아지 표 → 해당 항목 → 검증 방법(pprof/trace/benchstat) 순으로 진행한다.
- 비즈니스 로직이 필요한 지점은 임의로 구현하지 않고 `// TODO(human)` 마커를 남긴다. 기존 파일은 명시적 요청 없이 수정하지 않으며, `go.mod` 의존성 추가도 별도 확인을 거친다.

## 의존성

- `requires` / `dependencies`: `backend-shared`. 언어 무관 백엔드 공통 패턴을 담당하므로 함께 설치해 사용한다.
- 버전 민감 API(Go 1.22+ ServeMux 패턴 매칭 등)는 `backend-shared:context7-docs-guide` 규약에 따라 Context7 MCP로 문서를 조회한 뒤 생성한다. Context7 미설치 시 해당 단계는 생략된다.

## 참고

- 대상 스택은 Go 표준 `net/http` ServeMux(Go 1.22+ 메서드 기반 라우팅)와 `database/sql`이다. chi·gin·gorilla 등 서드파티 라우터를 쓰는 프로젝트는 대상이 아니며(프로젝트가 이미 사용 중인 경우 제외), 필요 시 다른 에이전트가 적합하다.
- DB 드라이버·마이그레이션 도구·Go 버전은 단정하지 않고 프로젝트(go.mod, 기존 코드, CI 이미지)에서 감지한다. `database/sql`, `pgx`, `sqlx`를 지원한다.
- 스페셜리스트 항목의 수치·기본값은 Go 1.27.3 소스와 1.22~1.27 릴리스노트로 확인했다(2026-10).
- 생성 코드는 항상 검증(build/vet/test)을 거치되, 최종 컴파일·테스트 통과 책임은 실제 프로젝트 환경에 달려 있으므로 결과를 확인하고 반영한다.
