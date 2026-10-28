> [English](README.md) · **한국어**

# python-fastapi

> **스페셜리스트 레이어** 중심의 Python + FastAPI 번들. 강한 시니어 제너럴리스트도 놓치는 함정(이벤트루프 블로킹, 40 토큰 스레드풀, psycopg 풀·PgBouncer prepared statement, Pydantic·응답 직렬화 비용, GIL/free-threaded, 메모리·GC, uvicorn 배포, PostGIS 인덱스)과, 코드를 쓰기 전에 프로젝트의 실제 스택을 감지하는 생성기로 구성된다.

## 개요

진입 스킬 `python-fastapi-guide` 는 증상 → 항목 트리아지 인덱스다. `references/` 의 각 항목은 ID(`FA-*`, `PY-*`)·적용 조건·신호·메커니즘·처방·반례·검증 방법·근거를 가지므로, 프로젝트 규칙(`CLAUDE.md`/`.claude/rules/`)이 적용 조건에 맞는 항목만 골라 담을 수 있다. 강제가 아니라 가이드다.

스택은 단정하지 않는다. 생성·조언 전에 쿼리 계층(SQLAlchemy ORM vs psycopg 3/asyncpg 원시 SQL), 마이그레이션 도구(Alembic/dbmate/없음), sync/async, 버전(FastAPI 0.130 직렬화 경계, Python 3.14.5 GC 경계), 기동 방식을 감지한다. 언어중립 백엔드 패턴은 `backend-shared` 가 담당한다.

## 구성 요소

### 커맨드 (사용자 직접 호출 전용 — `disable-model-invocation: true`)

- `/fastapi-gen` — 쿼리 계층·마이그레이션 도구를 감지한 뒤 (Migration) → (ORM Model) → Schema → Repository → Service → Router → Test 를 기존 컨벤션대로 생성. SQLAlchemy 예시와 함께 원시 SQL(psycopg 3) 리포지토리·dbmate 마이그레이션 예시 포함.
- `/fastapi-api-design` — 요구사항을 REST 리소스로 매핑해 Router + Schema + 에러 처리를 생성. 기존 API 관례와 쿼리 계층을 먼저 확인.

### 에이전트

- `fastapi-developer` — 코드 생성 에이전트. `python-fastapi-guide` 를 사전 로드하고, 스택을 먼저 감지한 뒤 스페셜리스트 점검 항목을 적용해 생성.
- `fastapi-guide` — 읽기 중심 진단 에이전트(model: sonnet). `python-fastapi-guide` 를 사전 로드해 지연·풀·메모리·직렬화·배포·PostGIS 문제를 근본 원인까지 추적하고 검증 명령을 제시. 파일을 수정하지 않도록 지시돼 있다(Bash 는 읽기 전용 진단용, 변경은 diff 로 제안).

### 스킬

- `python-fastapi-guide` — 스페셜리스트 트리아지 진입 스킬(`paths`: `**/*.py`, `**/pyproject.toml` 작업 시 활성). 레퍼런스:
  - `async-concurrency.md`(FA-ASYNC, FA-THREAD, FA-BG), `psycopg-postgres.md`(PY-PG, PY-MIG), `pydantic-serialization.md`(FA-PYD, FA-RESP), `runtime-memory-gc.md`(PY-GIL, PY-MEM, PY-GC), `deployment-uvicorn.md`(FA-SRV), `postgis.md`(PY-GIS)
  - 범용 레퍼런스: `fastapi-idioms.md`(구 `fastapi-patterns` 스킬, 2026-10 병합), `layer-patterns.md`, `sqlalchemy-patterns.md`(ORM 프로젝트 전용), `testing-patterns.md`

## 사용법

- `/fastapi-gen Order`, `/fastapi-gen Product --fields "name:str, price:Decimal" --audit`, `/fastapi-api-design Order API --pagination cursor`.
- 진단: "부하 걸면 이 엔드포인트가 멈춰", "스케일아웃 후 PoolTimeout", "반경 검색이 전부 나와" → `fastapi-guide` 또는 스킬의 트리아지 표.
- 반복 적용할 항목은 항목 ID + 조건 + 프로젝트 사실로 `.claude/rules/` 에 기록(`workflow:project-rules` 가 설치돼 있으면 사용).

## 의존성

- **requires: `backend-shared`**. 버전 민감 API 는 `backend-shared:context7-docs-guide` 규약으로 Context7 조회(미설치 시 생략).

## 참고

- 생성 도구는 기존 파일을 무단 수정하지 않고 의존성을 임의로 추가하지 않는다.
- `fastapi-patterns` 스킬은 `archive/components/python-fastapi/skills/fastapi-patterns/` 로 이동(내용은 `references/fastapi-idioms.md` 로 병합).
