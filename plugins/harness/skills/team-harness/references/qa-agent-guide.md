# QA Agent Design Guide

## Core Problem: Boundary Mismatch

QA가 놓치는 결함의 핵심: "두 컴포넌트가 각각 올바르게 구현되어 있지만, 연결 지점에서 계약이 어긋나는" 경계면 불일치.

### Why It Happens
- TypeScript 제네릭 캐스팅으로 타입 안전성 우회
- 빌드 성공 ≠ 런타임 정상 동작
- 개별 검증과 교차 검증의 차이 간과

---

## Validation Focus Areas

### 1. API Response ↔ Frontend Type
API 응답 shape과 프론트엔드 훅 타입의 **교차 비교**.
- API의 response DTO 필드와 프론트엔드의 타입 정의를 동시에 열어 비교
- 필드명 케이싱 불일치 (camelCase vs snake_case) 탐지

### 2. File Path ↔ Router Path
`href`/`router.push` 값과 실제 페이지 파일 경로의 매핑 검증.

### 3. State Transition Map ↔ Code
상태 전이 맵과 실제 `.update({ status })` 코드의 완전성 추적.
- 정의된 전이 중 코드에서 누락된 경로 탐지

### 4. API Endpoint ↔ Frontend Hook
모든 API 엔드포인트에 대응하는 프론트엔드 훅이 존재하는지 1:1 매핑.
- 미사용 API (구현된 훅 없음) 탐지
- 고아 상태 전이 (코드에서 호출하지 않는 상태 변경) 탐지

---

## Design Principles

### 양쪽 동시 읽기 원칙
"반드시 양쪽 코드를 동시에 열어" 비교한다.
- Producer(API/백엔드)와 Consumer(프론트엔드/훅)를 동시에 리뷰
- 한쪽만 보면 경계면 불일치를 놓침

### 교차 비교 (Cross-Comparative)
존재 여부만 확인하는 것이 아니라, 양쪽의 **계약이 일치하는지** 검증.

### 증분적 QA
전체 완성 후가 아니라, 각 모듈 완료 시점에 검증.
- 초기에 발견하면 수정 비용 낮음
- 팀 모드에서는 각 팀원의 산출물이 다음 팀원에게 전달되기 전에 검증

---

## Bug Pattern Examples

| 패턴 | 설명 | 탐지 방법 |
|------|------|----------|
| Response shape mismatch | API가 `{data: [...]}` 반환, 프론트가 `[...]` 기대 | 응답 타입 교차 비교 |
| Route path error | `/projects/[id]` 페이지 존재, 링크는 `/project/[id]` | 경로 매핑 검증 |
| Field casing mismatch | API: `created_at`, 프론트: `createdAt` | 필드명 비교 |
| Missing API hook | API 엔드포인트 존재, 프론트 훅 미구현 | 1:1 매핑 |
| Orphan state transition | 상태 전이 정의됨, 코드에서 호출 없음 | 전이맵-코드 비교 |

---

## QA Agent in Team Context

팀 내 QA 에이전트 배치 패턴:

### Pattern A: Dedicated QA Member
팀에 QA 전용 에이전트를 포함. Producer-Reviewer 패턴과 결합.
```
[생성자] → 산출물 → [QA 에이전트] → 피드백 → [생성자]
```

### Pattern B: Post-Phase QA
각 Phase 완료 후 QA 서브에이전트로 검증.
```
Phase 1 완료 → Agent(qa-agent, input: Phase 1 산출물) → 검증 보고서
Phase 2 시작 (검증 통과 시)
```

### Pattern C: Cross-Agent QA
팀원들이 서로의 산출물을 교차 검증.
```
security-reviewer ──→ performance-reviewer 산출물 검증
performance-reviewer ──→ test-reviewer 산출물 검증
```

---

## Integration with verify-flow

QA 에이전트의 발견 사항은 verify-flow의 규칙과 매핑:
- 구조적 결함 → TEAM/ORC 규칙 위반
- 보안 결함 → SEC 규칙 위반
- 품질 결함 → QUA 규칙 위반

Health Score에 QA 발견 사항 반영 가능.
