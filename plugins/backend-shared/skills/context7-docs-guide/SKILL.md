---
name: context7-docs-guide
description: |
  Context7 최신 문서 조회 규약 — 버전 민감 API(메이저 경계·신규 설정 키·deprecated 의심)일 때만 resolve-library-id → query-docs, 미설치 시 버전 확인 주석으로 degrade. 스택 가이드 스킬이 가리키는 공용 규약.
  Short convention for when to look up version-sensitive library APIs in Context7 and how to degrade gracefully when it is not installed.
  Use when: unsure whether a library API changed across a major version, deciding whether to query Context7, or a stack guide points here.
---

# Context7 조회 규약

학습 데이터의 구버전 API 환각을 줄이기 위한 규약. 스택 가이드 스킬(kotlin-spring·go-mux·python-fastapi·nextjs)과 프로젝트 CLAUDE.md 포인터(project-rules 생성)가 이 규약을 가리킨다.

## 조회할 때 / 생략할 때

| 조회 | 생략 |
|---|---|
| 릴리스 1년 이내 기능, 메이저 경계(Spring Boot 3→4, Pydantic v1→v2, Next.js 메이저) | 표준 라이브러리(Kotlin/Go/Python stdlib) |
| 자주 바뀌는 설정 DSL·신규 설정 키 | 수년간 안정된 API(SQL, HTTP 시맨틱, JPA 기본 어노테이션) |
| deprecated 여부가 불확실한 API | 프로젝트 내부 코드 — 기존 코드 Read 가 우선 |

애매하면: 프로젝트가 쓰는 버전(빌드 파일·lock 파일로 확인)이 메이저 경계에 걸쳐 있으면 조회.

## 절차

1. `resolve-library-id` 로 라이브러리 ID 해석 (구버전 서버는 `get-library-docs` 이름일 수 있음)
2. `query-docs` 에 기능명 + **프로젝트의 실제 버전**을 넣어 조회
3. 반영한 근거 버전을 결과 보고에 1줄로

작업당 라이브러리별 1회로 묶고, 같은 세션에서 조회한 라이브러리는 재조회하지 않는다.

## 미설치·조회 실패 시

중단하지 않고 학습 지식으로 진행하되, 버전 민감 지점에 주석을 남기고 보고에 1줄 요약한다.

```kotlin
// NOTE(version-check): Spring Boot 3.x 기준 — Context7 미조회. 공식 문서로 시그니처 확인 권장
```

```
Context7 미조회 — 버전 확인 권고 주석 N건 (사유: MCP 미설치)
```

## 설치 (context7.com/docs, 2026-07 확인)

```sh
claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp --api-key YOUR_API_KEY
# 또는 원격
claude mcp add --scope user --header "CONTEXT7_API_KEY: YOUR_API_KEY" --transport http context7 https://mcp.context7.com/mcp
```
