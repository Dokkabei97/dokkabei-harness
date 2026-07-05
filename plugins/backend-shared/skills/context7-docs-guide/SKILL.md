---
name: context7-docs-guide
description: |
  Context7 최신 문서 조회 규약 — 버전 민감 API 판단 기준, resolve-library-id → query-docs 절차, 미설치 시 graceful degrade, 스택별 적용 지점, 조회 비용 트레이드오프
  Protocol for fetching up-to-date library docs via Context7 — criteria for version-sensitive APIs, the resolve-library-id → query-docs procedure, graceful degrade when not installed, per-stack usage points, and lookup cost tradeoffs. Use when: verifying current framework APIs, resolving version-sensitive library usage, deciding whether to query Context7.
---

# Context7 최신 문서 조회 규약

코드 생성 시 학습 데이터의 구버전 API 환각을 막기 위해 Context7 MCP로 최신 공식 문서를
조회하는 언어중립 공통 규약. 스택 플러그인(kotlin-spring, python-fastapi, go-mux, nextjs)은
이 규약을 참조만 하고, 판단 기준·절차·degrade 규칙은 이 문서 한 곳에서 관리한다.

## 1. 조회 규약

**버전 민감 API는 코드 생성 전 Context7 조회(resolve-library-id → query-docs)를 수행한다.**

### 조회 절차

```
1. resolve-library-id: 라이브러리명 → Context7 호환 ID 해석
   (e.g., "next.js" → "/vercel/next.js")
2. query-docs: 해석된 ID + 구체적 질의로 문서 조회
   (기능명·버전을 질의에 명시 — "Spring Boot 3.x security DSL")
3. 조회 결과를 생성 코드에 반영하고, 근거 버전을 보고에 명시
```

### 언제 조회하고 언제 생략하는가

| 판단 기준 | 조회 | 생략 |
|---|---|---|
| 프레임워크 릴리스 1년 이내 기능 | ✅ | |
| 메이저 버전 경계 (v1→v2, 2.x→3.x 마이그레이션) | ✅ | |
| 자주 바뀌는 설정 DSL (빌드 설정, application.yml/next.config 신규 키) | ✅ | |
| deprecated 여부가 불확실한 API | ✅ | |
| 표준 라이브러리 (Kotlin/Python/Go stdlib, JS 내장 API) | | ✅ |
| 수년간 안정된 API (JPA 기본 어노테이션, SQL 문법, HTTP 시맨틱) | | ✅ |
| 프로젝트 내부 코드·컨벤션 | | ✅ (기존 코드 Read가 우선) |

판단이 애매하면: 대상 API가 메이저 버전 경계에 걸쳐 있으면 조회, 아니면 생략한다.

### 조회 횟수 규칙

- 조회는 **작업당 라이브러리별 1회**로 묶는다 (기능별 반복 조회 금지)
- 같은 세션에서 이미 조회한 라이브러리는 재조회하지 않는다

---

## 2. Graceful Degrade — 미설치/조회 불가 시

Context7 도구(`resolve-library-id`)가 세션 도구 목록에 없거나 호출이 실패해도
**작업을 중단하지 않는다.** 조회를 생략하고 학습 지식 기반으로 생성을 진행하되,
아래 두 가지를 반드시 남긴다.

**1) 생성 코드의 버전 민감 지점에 확인 권고 주석**

```kotlin
// NOTE(version-check): Spring Boot 3.x 기준으로 작성 — Context7 미조회. 공식 문서로 시그니처 확인 권장
```

```python
# NOTE(version-check): Pydantic v2 기준으로 작성 — Context7 미조회. 공식 문서로 확인 권장
```

**2) 최종 보고(Report)에 미조회 사실 1줄 요약**

```
Context7 미조회 — 버전 확인 권고 주석 N건 (사유: MCP 미설치)
```

`resolve-library-id` 결과가 모호한 경우(후보 신뢰도 낮음, 라이브러리 매칭 실패)에도
추측으로 진행하지 말고 이 degrade 규약으로 전환한다.

---

## 3. 설치 안내

공식 설치 구문 (context7.com/docs 기준, 2026-07 확인):

```sh
# Local (stdio, npx 실행)
claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp --api-key YOUR_API_KEY

# Remote (HTTP)
claude mcp add --scope user --header "CONTEXT7_API_KEY: YOUR_API_KEY" --transport http context7 https://mcp.context7.com/mcp
```

- API 키는 context7.com 대시보드에서 무료 발급 (키 없이도 동작하나 rate limit 낮음)
- 설치 확인: `claude mcp list` 또는 세션 도구 목록에 `resolve-library-id` 존재 여부
- 구버전 서버는 `query-docs` 대신 `get-library-docs` 이름을 쓸 수 있다 — 동일 규약 적용

---

## 4. 스택별 적용 지점

각 스택 생성 명령에서 조회가 필요한 대표 버전 민감 영역:

| 스택 (명령) | 버전 민감 영역 예시 | 조회 질의 예 |
|---|---|---|
| kotlin-spring (`/spring-gen`) | Spring Boot 3.x 설정 프로퍼티, Spring Security 6 lambda DSL, Hibernate 6 타입 매핑 | "Spring Boot 3.x SecurityFilterChain DSL" |
| python-fastapi (`/fastapi-gen`) | Pydantic v2 (`model_validate`/`ConfigDict`), SQLAlchemy 2.0 스타일, FastAPI lifespan | "Pydantic v2 field_validator" |
| go-mux (`/go-gen`) | Go 1.22+ `net/http.ServeMux` 패턴 매칭(메서드·와일드카드), `log/slog` | "Go 1.22 ServeMux method routing" |
| nextjs (`/nextjs-gen`) | Next.js App Router API (async `params`/`cookies`), 캐싱 기본값 변경, Server Actions | "Next.js 15 async request APIs" |

---

## 5. 트레이드오프 — 조회 비용 vs 정확도

| 항목 | 비용 | 이득 |
|---|---|---|
| 토큰 | 조회당 수천~수만 토큰 컨텍스트 소비 | 구버전 API 환각으로 인한 재작업(컴파일 실패 → 재생성 루프) 절감 |
| 지연 | 호출당 수 초 | 버전 불일치 디버깅 시간 절감 |

**원칙: 조회가 이득인 곳(버전 민감 API)에만 쓰고, 표준 라이브러리·안정 API는 생략한다.**
섹션 1의 판단 표가 기준이며, 모든 코드 생성에 일괄 조회하는 것은 규약 위반이다.
