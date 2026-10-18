# QA 에이전트 설계 가이드

빌드 하네스에 QA 에이전트를 포함할 때의 지침. 실제 프로젝트에서 발견된 버그와 그 원인을 바탕으로, QA가 놓치기 쉬운 결함을 찾아내는 방법을 다룬다.

---

## 목차

1. [QA가 놓치는 결함 패턴](#1-missed-defects)
2. [통합 정합성 검증](#2-integration-coherence)
3. [QA 에이전트 설계 원칙](#3-design-principles)
4. [워크플로로 수행하는 QA (v2)](#4-workflow-qa)
5. [팀 내 QA 배치 패턴](#5-qa-placement)
6. [검증 체크리스트 템플릿](#6-checklist)
7. [QA 에이전트 정의 템플릿](#7-agent-template)
8. [verify-flow 연동](#8-verify-flow)
9. [실제 사례: 발견된 버그와 원인](#9-cases)

---

<a id="1-missed-defects"></a>

## 1. QA가 놓치는 결함 패턴

### 1-1. 경계면 불일치 (Boundary Mismatch)

가장 빈번한 결함. 두 컴포넌트가 **각각은 올바르게 구현되어 있지만, 연결 지점에서 계약이 어긋나는** 경우다.

| 연결 지점 | 불일치 예시 | 놓치는 이유 |
|--------|-----------|-----------|
| API 응답 → 프런트엔드 훅 | API는 `{ projects: [...] }` 반환, 훅은 `Project[]` 기대 | 각각만 검증하고 서로 비교하지 않음 |
| API 응답 필드명 → 타입 정의 | API `thumbnailUrl`(camelCase), 타입 `thumbnail_url`(snake_case) | 제네릭 타입 단언은 컴파일러가 감지 못함 |
| 파일 경로 → 링크 `href` | 페이지는 `/dashboard/create`, 링크는 `/create` | 파일 구조와 `href`를 대조하지 않음 |
| 상태 전이 맵 → 실제 `status` 갱신 | 맵에는 전이가 있으나 상태를 바꾸는 코드 누락 | 맵 존재만 확인, 갱신 코드 미추적 |
| API 엔드포인트 → 프런트엔드 훅 | API는 있으나 호출하는 훅이 없음 | API·훅 목록을 1:1 대조하지 않음 |
| 즉시 응답 → 비동기 처리 결과 | API는 즉시 `{ status }` 반환, 프런트는 최종 결과 필드 접근 | 즉시 응답과 최종 응답을 구분하지 않음 |

### 1-2. 정적 리뷰만으로 찾기 어려운 이유

- **제네릭 타입의 한계**: `fetchJson<Project[]>()`는 실제 응답이 `{ projects: [...] }`여도 컴파일을 통과한다.
- **빌드 성공 ≠ 런타임 정상**: 타입 단언·`any`·제네릭을 쓴 코드는 빌드는 되어도 실행 중 실패할 수 있다.
- **존재 확인 ≠ 계약 확인**: "API가 있는가?"와 "API 응답이 호출 측 기대와 일치하는가?"는 전혀 다른 검증이다.

---

<a id="2-integration-coherence"></a>

## 2. 통합 정합성 검증 (Integration Coherence Verification)

QA 에이전트에는 컴포넌트를 **서로 대조하는 검증**을 반드시 넣는다. 아래 예시는 Next.js 기준이지만 원칙은 어떤 스택에도 적용된다(Kotlin/Spring의 DTO ↔ 클라이언트, FastAPI의 Pydantic 스키마 ↔ 소비자 등). 생산자 코드와 소비자 코드를 함께 열어 양쪽 계약을 비교한다.

### 2-1. API 응답 ↔ 프런트엔드 훅 타입

```
1. API 라우트의 응답 직렬화 지점(NextResponse.json() 등)에서 응답 구조를 추출한다.
2. 대응하는 훅/클라이언트의 기대 타입(fetchJson<T>의 T 등)을 확인한다.
3. 응답 구조와 T를 비교한다. API가 { data: [...] }를 반환하면 훅이 .data를 꺼내는지까지 확인한다.
```

특히 페이지네이션 래핑 응답을 배열로 받는 경우, snake_case ↔ camelCase 변환 누락, 즉시 응답(202)과 최종 응답의 구조 차이를 확인한다.

### 2-2. 파일 경로 ↔ 링크·라우터 경로

```
1. 라우팅 파일 구조에서 URL 패턴을 추출한다. (group)은 제거, [param]은 동적 세그먼트로 처리.
2. 코드의 모든 href=, router.push(, redirect( 값을 수집한다.
3. 각 링크가 실제 존재하는 경로와 일치하는지 확인한다.
```

### 2-3. 상태 전이 맵 ↔ 코드 완전성

```
1. 상태 전이 맵에서 허용된 전이 목록을 추출한다.
2. status를 갱신하는 코드를 모두 검색한다.
3. 코드의 전이가 맵에 정의되어 있는지 확인한다 (허용되지 않은 전이 0).
4. 맵에는 있으나 코드에서 실행되지 않는 전이를 찾는다 (고아 전이 0).
5. 특히 중간 상태 → 최종 상태 전이 누락을 확인한다.
```

### 2-4. API 엔드포인트 ↔ 프런트엔드 훅 1:1 매핑

```
1. HTTP 메서드별 엔드포인트 목록을 추출한다.
2. 클라이언트의 fetch 호출 URL 목록을 추출한다.
3. 호출되지 않는 엔드포인트가 관리용 API인지, 호출 코드 누락인지 판단한다.
```

---

<a id="3-design-principles"></a>

## 3. QA 에이전트 설계 원칙

### 3-1. 도구 세트: 읽기 전용(Explore)으로는 부족하다

`Explore` 유형은 파일 읽기만 가능하다. QA는 `Grep`으로 패턴을 찾고 `Bash`로 스크립트를 돌려 대조를 자동화해야 하므로 `general-purpose` 또는 `Bash`·`Grep`을 포함한 커스텀 에이전트를 쓴다. 에이전트 정의에 "검증 → 보고 → 수정 요청" 절차를 명시한다.

**수정 권한(`Edit`)은 역할에 따라 결정한다.** 루프 하네스의 checker처럼 판정 신뢰가 핵심인 QA는 `Edit`을 주지 않고 담당 에이전트에게 수정을 요청만 한다 — maker/checker 도구 수준 분리([loop-harness-guide.md §2](loop-harness-guide.md#2-정지-조건--모델-밖에서-판정)). 본 마켓플레이스의 `mvp-verifier`·`feature-verifier`가 이 방식이다.

### 3-2. 존재 확인이 아니라 교차 비교

| 존재 확인형 (약함) | 교차 비교형 (강함) |
|---------------|---------------|
| API 엔드포인트가 있는가? | API 응답 구조와 대응 훅의 타입이 일치하는가? |
| 상태 전이 맵이 정의되어 있는가? | 모든 `status` 갱신 코드가 전이 맵과 일치하는가? |
| 페이지 파일이 있는가? | 코드의 모든 링크가 실제 페이지를 가리키는가? |
| strict mode를 쓰는가? | 제네릭 타입 단언으로 타입 안전성을 우회한 곳이 없는가? |

### 3-3. 양쪽 동시 읽기

경계면 버그는 한쪽 코드만 읽어서는 찾을 수 없다. Producer(API/백엔드)와 Consumer(프런트엔드/훅)를, 상태 전이 맵과 갱신 코드를, 파일 구조와 링크 경로를 **반드시 함께** 연다. 에이전트 정의에도 이 원칙을 명시한다.

### 3-4. 증분적 QA (Incremental QA)

전체 완성 후에만 QA를 돌리면 버그가 누적되어 수정 비용이 늘고, 초기 계약 불일치가 후속 모듈로 전파된다. 모듈(예: API 엔드포인트 하나)을 완성할 때마다 대응 소비자와 즉시 대조한다. 팀 하네스에서는 각 멤버의 산출물이 다음 멤버에게 전달되기 **전에** 검증한다.

---

<a id="4-workflow-qa"></a>

## 4. 워크플로로 수행하는 QA (v2)

검증할 연결 지점을 목록으로 만들 수 있으면 QA도 `Workflow`로 구성할 수 있다(실행 모드 A — 사용자 명시 동의 필요, 첫 실행은 경계 수를 작게).

```javascript
// 연결 지점별 검사 → 발견 항목마다 반대 관점에서 재검증
const FINDINGS = { type: 'object', required: ['findings'], properties: {
  findings: { type: 'array', items: { type: 'object',
    required: ['title', 'file', 'evidence'], properties: {
      title: { type: 'string' }, file: { type: 'string' }, evidence: { type: 'string' } } } } } }
const VERDICT = { type: 'object', required: ['status', 'reason'], properties: {
  status: { type: 'string', enum: ['confirmed', 'refuted', 'uncertain'] },
  reason: { type: 'string' } } }
const boundaries = args.boundaries  // 사전 조사로 추출: [{api: '...', consumer: '...'}, ...]
const found = await pipeline(
  boundaries,
  b => agent(`양쪽을 함께 읽고 계약 불일치를 찾아라: ${b.api} ↔ ${b.consumer}`,
    { agentType: 'qa-inspector', phase: '검사', schema: FINDINGS }),
  r => parallel((r?.findings ?? []).map(f => () =>
    agent(`이 불일치가 실제 실행 오류를 일으키는지 반대 관점에서 검증하라: ${JSON.stringify(f)}`,
      { phase: '재검증', schema: VERDICT }).then(verdict => ({ ...f, verdict }))))
)
const confirmed = found.flat().filter(Boolean)
  .filter(f => f.verdict?.status === 'confirmed')
return { confirmed }
```

발견 항목을 반대 관점에서 재검증해 `confirmed`만 남기면, 그럴듯하지만 실제로는 문제가 아닌 지적이 걸러져 최종 QA 보고서의 신뢰도가 올라간다.

---

<a id="5-qa-placement"></a>

## 5. 팀 내 QA 배치 패턴

### 패턴 A: 전담 QA 멤버 (실행 모드 B)

팀에 QA 전용 에이전트를 지속형 멤버로 둔다. Producer-Reviewer 패턴과 결합한다. 생성자와 QA는 `Agent(name:)`로 띄우고 `SendMessage({to:"<name>"})`로 이름 지정 통신하며, 진행 상태는 `TaskCreate`/`TaskUpdate` 공유 작업 목록으로 추적한다.

```
[생성자] → 산출물 → [QA 에이전트] → SendMessage(to: 생성자, 수정 요청) → [생성자]
```

### 패턴 B: 단계 후 QA (실행 모드 C 또는 A)

각 단계 완료 후 QA 서브에이전트를 1회 위임한다. 단계 수와 경계 목록이 고정되어 있으면 §4처럼 워크플로로 옮긴다.

```
단계 1 완료 → Agent(qa-agent, input: 단계 1 산출물) → 검증 보고서
단계 2 시작 (검증 통과 시)
```

### 패턴 C: 교차 QA (Cross-Agent QA)

멤버들이 서로의 산출물을 교차 검증한다. 한 에이전트가 자기 산출물을 평가하는 편향을 구조적으로 피한다.

```
security-reviewer    ──→ performance-reviewer 산출물 검증
performance-reviewer ──→ test-reviewer 산출물 검증
```

---

<a id="6-checklist"></a>

## 6. 검증 체크리스트 템플릿

웹 애플리케이션을 검사하는 QA 에이전트 정의에 아래 통합 정합성 체크리스트를 넣는다.

```markdown
### 통합 정합성 검증 (웹 앱)

#### API ↔ 프런트엔드 연결
- [ ] 모든 API 라우트의 응답 구조와 대응 훅의 제네릭 타입이 일치하는가
- [ ] 래핑된 응답({ items: [...] })에서 훅이 실제 데이터를 꺼내는가
- [ ] snake_case ↔ camelCase 변환이 일관되게 적용되는가
- [ ] 즉시 응답(202)과 최종 응답의 구조를 프런트엔드가 구분하는가
- [ ] 모든 API 엔드포인트에 대응 훅이 있고 실제로 호출되는가

#### 라우팅 정합성
- [ ] 코드의 모든 href/router.push 값이 실제 페이지 파일 경로와 일치하는가
- [ ] 라우트 그룹 (group)이 URL에서 빠진다는 점을 반영했는가
- [ ] 동적 세그먼트([id])에 올바른 매개변수가 들어가는가

#### 상태 머신 정합성
- [ ] 정의된 모든 상태 전이가 코드에서 실행되는가 (고아 전이 0)
- [ ] 코드의 모든 status 갱신이 전이 맵에 정의되어 있는가 (비허용 전이 0)
- [ ] 중간 상태 → 최종 상태 전이가 누락되지 않았는가
- [ ] 프런트엔드 분기(if status === "X")의 X가 실제 도달 가능한 상태인가

#### 데이터 흐름 정합성
- [ ] DB 스키마 필드명과 API 응답 필드명의 매핑이 일관되는가
- [ ] 프런트엔드 타입 정의와 API 응답 필드명이 일치하는가
- [ ] 선택적 필드의 null/undefined 처리가 양쪽에서 일관되는가
```

---

<a id="7-agent-template"></a>

## 7. QA 에이전트 정의 템플릿

`/create-flow`의 team-agent 템플릿과 같은 골격이다. description은 레포 규약대로 이중언어(한국어 원문 → 영어 요약 + `Use when:`, ≤1,400자)로 쓴다.

```markdown
---
name: qa-inspector
description: |
  명세 준수 여부와 모듈 간 통합 정합성(API↔훅, 경로↔링크, 상태 전이↔코드), 디자인 품질을 교차 검증하는 QA 에이전트.
  Cross-checks spec compliance, inter-module integration coherence, and design quality.
  Use when: a module or phase is complete and its boundaries must be verified before handoff.
tools: [Read, Grep, Glob, Bash]   # Edit 미보유 — 수정은 담당 에이전트에 요청
model: opus  # 교차 검증·반증은 깊은 분석이 필요
---

# QA Inspector

## 핵심 역할
명세대로 구현되었는지 확인하고 **모듈 간 통합 정합성**을 검증한다.

## 검증 우선순위
1. **통합 정합성** (최우선) — 경계면 불일치가 런타임 오류의 주원인이다
2. **기능 명세 준수** — API, 상태 머신, 데이터 모델
3. **디자인 품질** — 색상, 타이포그래피, 반응형
4. **코드 품질** — 미사용 코드, 네이밍

## 검증 방법: 양쪽 동시 읽기
| 검증 대상 | 생산자 | 소비자 |
|----------|-------|-------|
| API 응답 구조 | 응답 직렬화 지점 | 클라이언트 기대 타입 |
| 라우팅 | 라우팅 파일 구조 | href, router.push 값 |
| 상태 전이 | 전이 맵 | status 갱신 코드 |
| DB → API → UI | DB 컬럼명 | API 응답 필드 → 타입 정의 |

## Team Communication Protocol
- 첫 보고에서 **실제로 사용 가능한 도구 목록**을 보고한다.
- 문제를 발견하면 담당 에이전트에게 `SendMessage({to:"<name>"})`로 구체적 수정 사항을 요청한다(파일:줄 + 수정 방법). 전체 공지(broadcast)는 쓰지 않는다.
- 경계면 문제는 양쪽 담당 에이전트 각각에게 이름 지정으로 알린다.
- 진행 상태는 `TaskUpdate`로 공유 작업 목록에 반영한다.
- 리더에게는 통과 / 실패 / 미검증 항목을 구분한 검증 보고서를 보낸다.
```

---

<a id="8-verify-flow"></a>

## 8. verify-flow 연동

QA 에이전트의 발견 사항은 verify-flow 규칙 카테고리와 매핑해 Health Score에 반영할 수 있다.

- 구조적 결함 → TEAM-* / ORC-* 규칙 위반
- 보안 결함 → SEC-* 규칙 위반
- 품질 결함 → QUA-* 규칙 위반

QA 에이전트 정의 자체는 `/verify-flow`의 AGT-* 규칙으로 검증한다.

---

<a id="9-cases"></a>

## 9. 실제 사례: 발견된 버그와 원인

| 버그 | 연결 지점 | 원인 |
|------|----------|------|
| `projects?.filter is not a function` | API → 훅 | API는 `{projects:[]}` 반환, 훅은 배열 기대 |
| 대시보드 모든 링크 404 | 파일 경로 → `href` | `/dashboard/` 접두사 누락 |
| 썸네일 이미지 미표시 | API → UI 컴포넌트 | `thumbnailUrl` vs `thumbnail_url` 불일치 |
| 선택한 값이 저장되지 않음 | API → 훅 | API는 있으나 대응 훅 없음 |
| 생성 페이지가 계속 대기 상태 | 상태 전이 → 코드 | 최종 상태로 바꾸는 코드 누락 |
| `data.failedIndices` 접근 시 크래시 | 즉시 응답 → 프런트엔드 | 즉시 응답에서 백그라운드 처리 결과에 접근 |
| 완료 후 상세 페이지 404 | 파일 경로 → `href` | 라우트 접두사 불일치 |
