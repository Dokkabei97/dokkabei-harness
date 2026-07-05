# python-fastapi

> Python + FastAPI 백엔드 개발에 특화된 코드 생성·설계·가이드 번들. 도메인 정의부터 전체 CRUD 계층과 REST API를 프로젝트 컨벤션에 맞춰 스캐폴딩하고, 관용 패턴과 의사결정 기준을 함께 제공한다.

## 개요

이 플러그인은 Python + FastAPI 스택을 위한 개발 도구 모음이다. 도메인명 하나로 SQLAlchemy Model → Pydantic Schema → Repository → Service → Router → Test 전 계층을 생성하는 스캐폴딩(`fastapi-gen`), REST 리소스 설계에 집중하는 API 설계(`fastapi-api-design`), 코드 생성 전문 에이전트(`fastapi-developer`)와 프레임워크 진단 에이전트(`fastapi-guide`), 그리고 관용 패턴 레퍼런스(`fastapi-patterns`)와 개발 원칙/의사결정 가이드(`python-fastapi-guide`)로 구성된다.

핵심 설계 원칙은 **Pythonic First**, **Layer Discipline**(의존 방향은 항상 Router→Service→Repository로 하향), **Fail Fast**(Pydantic·도메인·DB 제약의 3중 방어), **Convention over Configuration**이다. 모든 생성 도구는 코드를 쓰기 전에 먼저 기존 프로젝트 구조(sync/async, SQLAlchemy 1.x/2.0, 모듈 레이아웃, 테스트 스타일)를 분석해 컨벤션을 그대로 따른다. 언어중립 백엔드 공통 패턴(API 계약, DB 마이그레이션 안전성, 관측성/캐싱/이벤트/회복탄력성/보안)은 이 플러그인이 아니라 `backend-shared` 플러그인이 담당하며, 두 플러그인을 함께 쓰는 것을 전제로 한다.

## 구성요소

### 커맨드

- `/fastapi-gen` — 도메인명을 입력하면 SQLAlchemy Model·Pydantic Schema·Repository·Service·Router·Test 전체 CRUD 계층을 프로젝트 컨벤션에 맞춰 bottom-up으로 생성한다. `--fields`, `--layers`, `--no-test`, `--async`, `--soft-delete`, `--audit` 옵션 지원.
- `/fastapi-api-design` — 요구사항을 REST 리소스/동작으로 매핑해 엔드포인트·요청/응답 스키마·에러 코드를 설계하고 Router + Schema + Exception 코드를 생성한다. `--version`, `--auth`, `--pagination`(cursor/offset), `--error-style`(rfc7807/custom) 옵션 지원.

### 에이전트

- `fastapi-developer` — Python + FastAPI 코드 생성 전문 에이전트. 프로젝트 컨벤션을 분석한 뒤 전체 계층을 관용적(type hints, async/await, Pydantic V2, match/case)으로 생성하고, 생성 후 pytest·타입체크·린트로 검증한다. `python-fastapi-guide` 스킬을 활용한다.
- `fastapi-guide` — FastAPI 프레임워크 전문가 에이전트(model: sonnet). Depends DI 체인, Pydantic v2 검증, async SQLAlchemy 세션·로딩 전략, Alembic, 미들웨어, BackgroundTasks, lifespan, Strawberry GraphQL 통합을 진단·조언한다. 비동기 정확성을 최우선으로 삼는 읽기 중심(Read/Grep/Glob/Bash) 에이전트.

### 스킬

- `fastapi-patterns` — FastAPI 관용 패턴 레퍼런스. Depends DI, Pydantic v2, async SQLAlchemy, Alembic, 미들웨어, Strawberry GraphQL, lifespan, httpx 클라이언트, BaseSettings까지 실행 가능한 코드 스니펫으로 정리.
- `python-fastapi-guide` — 개발 원칙/의사결정 가이드. Pythonic First·Layer Discipline·Fail Fast 원칙과 아키텍처/스택/테스트 프레임워크 선택 기준을 제공하며, `references/layer-patterns.md`(계층별 패턴), `references/sqlalchemy-patterns.md`(모델 설계·N+1 방지·마이그레이션), `references/testing-patterns.md`(pytest·Mock·httpx·Factory Boy) 세 개의 참조 문서를 포함한다.

## 사용법

- 커맨드는 슬래시로 직접 호출한다. 예: `/fastapi-gen Order`, `/fastapi-gen Product --fields "name:str, price:Decimal" --async --audit`, `/fastapi-api-design 주문 API --auth jwt --pagination cursor`.
- 에이전트는 작업 성격에 따라 자동 위임되거나 명시적으로 호출된다. "Order CRUD 만들어줘"처럼 코드 생성이 필요하면 `fastapi-developer`, "Depends 순환 문제 진단", "async 세션 누수" 같은 프레임워크 이슈면 `fastapi-guide`가 트리거된다.
- 스킬은 관련 작업 맥락에서 자동 참조된다. FastAPI 코드를 쓰거나 리뷰할 때 `python-fastapi-guide`의 원칙이, 구체 구현 패턴이 필요할 때 `fastapi-patterns`가 로드된다.
- 생성 도구의 공통 흐름은 Discovery(프로젝트 컨벤션 분석) → Generation(계층 생성) → Verification(pytest/타입체크/린트) 3단계이며, 비즈니스 로직 구현이 필요한 지점은 `# TODO(human)` 마커로 남긴다.

## 의존성

- **requires: `backend-shared`** — API 계약·마이그레이션·보안 등 언어중립 백엔드 공통 패턴은 `backend-shared` 플러그인이 제공하므로 함께 설치해야 한다. 버전 민감 API(Pydantic v2 등)는 `backend-shared:context7-docs-guide` 규약에 따라 Context7 MCP로 최신 문서를 조회한 뒤 생성한다(미설치 시 생략).

## 참고

- 코드 생성 도구는 기존 파일을 무단 수정하지 않으며, `pyproject.toml`에 의존성을 임의로 추가하지 않는다(별도 확인 필요).
- Non-Pythonic 패턴(`Optional[]`, `type()` 비교, mutable default 등)은 생성하지 않으며, 프로젝트가 async 스택이면 `AsyncSession` + `async def`로 생성한다.
- Context7 MCP는 선택 사항이다. 설치되어 있지 않으면 버전 문서 조회 단계를 생략하고 진행한다.
