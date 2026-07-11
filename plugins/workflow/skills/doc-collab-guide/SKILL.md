---
name: doc-collab-guide
description: |
  기획서·제안서·보고서 등 긴 문서를 사용자와 공동 작성할 때 사용. 공식 doc-coauthoring 스킬(anthropics/skills) 의존 설치 안내, 아웃라인 승인 게이트(mvp G1 차용)를 정의한다. Use when: "문서 같이 쓰자", "제안서/기획서/보고서 초안", "공동 작성", co-authoring documents, proposals, long-form docs. 위임 경계 — 법률 문서는 /draft-legal-doc, 피치덱은 /pitch-deck, PRD는 mvp prd-authoring 우선. 이 스킬은 그 외 일반 장문 문서 전용.
  Defines the co-authoring protocol for long-form documents (plans, proposals, reports) — install guidance for the official doc-coauthoring skill (anthropics/skills) and an outline approval gate (mvp G1). Use when: co-writing or drafting proposals, planning docs, reports, long documents; legal docs, pitch decks, and PRDs are delegated elsewhere.
---

# Doc Collab Guide — 긴 문서 공동 작성 규약

공식 `doc-coauthoring` 스킬을 얇게 연계해 기획서·제안서·보고서류 장문 문서를 사용자와 단계적으로 공동 작성하기 위한 규약. 도구 설치·진행 게이트만 정의하고, 문서 작성 기법 자체는 공식 스킬에 위임한다.

## When to Activate

- 기획서·제안서·보고서·의사결정 문서 등 3섹션 이상의 장문 문서를 사용자와 함께 쓸 때
- 사용자가 초안 전체가 아니라 단계적 협업(아웃라인 → 섹션별 확정)을 원할 때
- 산출물이 .md 또는 .docx 문서 자체일 때 (코드 산출 작업이면 해당 없음)

## 도메인 경계 — 그쪽 문서는 그쪽 커맨드 우선

| 문서 유형 | 우선 경로 | 이 스킬 |
|-----------|----------|---------|
| 계약서·내용증명·합의서·통지서 | legal `/draft-legal-doc` | 사용 안 함 |
| 피치덱·린캔버스·성장계획 | startup `/pitch-deck` 등 | 사용 안 함 |
| PRD·MVP 스펙 | mvp `prd-authoring` | 사용 안 함 |
| 기술 스펙(구현 전제) | workflow `spec-driven-dev` | 사용 안 함 |
| 그 외 일반 기획서·제안서·보고서 | **이 스킬** | 사용 |

도메인 커맨드가 있는 문서는 그쪽 구조·법리·게이트가 우선한다. 이 스킬을 겹쳐 쓰지 않는다.

## 공식 스킬 의존 설치

anthropics/skills 저장소 웹 확인 기준(2026-07): `doc-coauthoring`은 `example-skills` 플러그인 소속, docx 내보내기는 `document-skills` 소속. 마켓플레이스 이름은 `anthropic-agent-skills`.

```
/plugin marketplace add anthropics/skills
/plugin install example-skills@anthropic-agent-skills    # doc-coauthoring 포함
/plugin install document-skills@anthropic-agent-skills   # docx/pdf/pptx/xlsx 내보내기 (선택)
```

- 공식 스킬의 3단계(Context Gathering → Refinement & Structure → Reader Testing)는 아래 진행 규약의 1·3·4단계를 보강하는 보조 도구다.
- 미설치 상태여도 아래 규약만으로 진행 가능하다. 설치를 강제하지 말고, 세션에서 스킬이 보이지 않으면 위 구문을 사용자에게 1회 안내한다.

## 진행 규약

| 단계 | 내용 | 게이트 |
|------|------|--------|
| 1. 목적/독자 확정 | 이 문서로 누가 무엇을 결정·행동하게 만들 것인지 1~2문장으로 합의 | 없음 (합의 전 다음 단계 금지) |
| 2. 아웃라인 승인 | 섹션 목록 + 섹션별 핵심 주장 1줄 + 분량 추정 제시 | **★사용자 게이트** (mvp G1 차용) |
| 3. 섹션별 작성 | 승인된 아웃라인 순서대로 한 섹션씩 작성·확인 | 섹션당 사용자 확인 1회 |
| 4. 리뷰 (반증 관점) | "이 문서가 독자를 설득하지 못한다면 왜?" — 반론·누락 근거·과장 탐지 | 반증에 구체적 근거 요구 |
| 5. 산출 | 사용자와 합의한 경로로 최종본 산출 | 경로 사용자 확인 |

**아웃라인 게이트 (2단계)** — mvp G1 스코프 승인 패턴 차용:
- 승인 전 본문 작성 금지. 자율 통과 금지. "대충 이렇게 갈게요" 후 진행은 위반이다.
- 아웃라인 수정 요청이 오면 반영본을 다시 제시하고 재승인을 받는다.
- 3단계 진행 중 아웃라인 변경이 필요해지면(섹션 추가·삭제·순서 변경) 변경 요지를 1줄 보고하고 승인 후 반영한다 — 게이트 승인 사항이기 때문이다.

**리뷰 (4단계)**: 작성자 시점이 아니라 회의적 독자 시점으로 전환한다. 최소 점검 3가지 — ① 핵심 주장에 근거 없는 섹션 ② 독자의 예상 반론 중 미대응 항목 ③ 결론이 1단계에서 합의한 목적과 어긋나는 지점.

## Verification

- [ ] 목적/독자 합의문이 대화에 기록됨 (1단계)
- [ ] 아웃라인 사용자 승인이 명시적으로 존재함 — 승인 전 본문 없음 (2단계)
- [ ] 리뷰에서 반증 3가지 점검 수행 (4단계)
- [ ] 최종 산출 경로가 사용자와 합의됨 (5단계)

## Related

- 공식 `doc-coauthoring` (example-skills@anthropic-agent-skills) — 컨텍스트 수집·리더 테스트 기법
- 공식 `docx` (document-skills@anthropic-agent-skills) — Word 내보내기
- `/draft-legal-doc` (legal) · `/pitch-deck` (startup) · `prd-authoring` (mvp) — 도메인 문서는 그쪽 우선
- `planning-guide` — 문서가 아니라 기능 계획을 세울 때
