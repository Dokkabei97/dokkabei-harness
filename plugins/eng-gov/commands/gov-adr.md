---
name: gov-adr
description: |
  아키텍처 결정 기록(ADR) 작성/supersede 커맨드 — MADR 형식으로 docs/decisions/NNNN-<slug>.md를 작성하고(governance-templates 참조), 결정을 강제 가능한 fitness function 후보로 변환 제안한 뒤, adr-checker(Edit 미보유 checker)로 결정-코드 정합성을 반증하고 gate-adr.sh로 파일명·status enum·supersede 링크 무결성을 결정론 검사한다. 결정을 바꿀 때는 기존 ADR을 편집하지 않고 새 ADR을 만들어 옛 것을 status: superseded + superseded-by로 대체한다(이력 append-only 보존). Use when 아키텍처/기술 결정을 기록하거나 기존 결정을 대체(supersede)할 때.
  Architecture Decision Record command: writes docs/decisions/NNNN-<slug>.md in MADR format (per governance-templates), proposes fitness-function conversions of the decision, then falsifies decision-vs-code consistency with adr-checker (a no-Edit checker) and deterministically checks filename, status enum, and supersede-link integrity via gate-adr.sh. Superseding never edits the old ADR — it adds a new one and marks the old status: superseded + superseded-by (append-only history). Use when: recording an architecture/tech decision or superseding an existing one.
category: workflow
complexity: intermediate
mcp-servers: []
personas: []
---

# /gov-adr — 아키텍처 결정 기록

MADR 형식 ADR을 작성/supersede한다. 형식 표준은 `governance-templates` 스킬(`references/madr-template.md`)이 정본이며, 이 커맨드는 작성 흐름과 검증 디스패치만 담당한다.

## Triggers
- 아키텍처·기술 스택·설계 원칙 결정을 문서로 남길 때
- 기존 결정이 바뀌어 supersede가 필요할 때
- "이 결정 ADR로 남겨줘", "아키텍처 결정 기록" 요청

## Usage
```
/gov-adr "<결정 제목>" [옵션]
Options:
  --supersede <NNNN>   기존 ADR을 대체하는 새 ADR 작성(옛 것 status 전환)
  --status <enum>      proposed|accepted|superseded|deprecated (기본 accepted)
```

## Behavioral Flow

### Phase 0: 사전 점검
- `docs/decisions/` 존재 확인. 없으면 중단하고 `/gov-init` 안내.
- 다음 ADR 번호 = 기존 최대 번호 + 1 (4자리 0패딩).

### Phase 1: ADR 작성 (MADR)
1. `governance-templates`의 MADR 템플릿으로 `docs/decisions/NNNN-<kebab-slug>.md` 작성.
2. 필수 요소: `status:` enum, `date:`, Context/Problem, Decision Drivers, Considered Options(2+), Decision Outcome, Consequences(좋음/나쁨).
3. **fitness function 변환 제안**: 결정이 강제 가능하면(의존 방향·금지 라이브러리 등) `fitness-function-guide`의 패턴으로 `.dependency-cruiser`/`.importlinter` 룰 후보를 제시한다. 변환 불가면 그 사실을 ADR에 명시.

### Phase 2: supersede 처리 (--supersede)
1. 새 ADR의 Context에 "supersedes NNNN" 명시.
2. **옛 ADR을 편집**해 `status: superseded` + `superseded-by: <새 번호>`로 전환(supersede만 예외적으로 기존 파일 status 갱신).
3. 결정 내용 자체는 옛 파일에 그대로 보존(이력 append-only).

### Phase 3: adr-checker 반증
`adr-checker` 에이전트 디스패치 — 결정 위반 코드 패턴·stale 결정·근거 없는 accepted·fitness 변환 누락을 반증(Edit 미보유, verdict는 `.planning/gov/adr/verdict.json`). BLOCK 판정은 사용자에게 보고하고 수정 유도. import 위반 같은 결정론 검사는 gate-fitness 몫이므로 checker에 요구하지 않는다.

### Phase 4: gate-adr 판정
`bash ${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-adr.sh` — 파일명 `^NNNN-`·status enum·번호 유일성·supersede 링크 실재를 검사. 통과 1줄 보고 / 실패 시 위반 항목·수정안 보고.

## Tool Coordination
- **Skill**: `governance-templates`(MADR 형식·경로), `fitness-function-guide`(변환 패턴)
- **Task**: `adr-checker` 디스패치(결정-코드 반증)
- **Bash**: `gate-adr.sh` 실행, 다음 번호 계산
- **Write/Edit**: ADR 파일 작성, supersede 시 옛 ADR status 전환

## Boundaries

**Will:** MADR ADR 작성, supersede 이력 append-only 처리, fitness 변환 제안, adr-checker 반증 + gate-adr 판정.
**Will Not:**
- 기존 ADR 결정 내용 재작성(supersede 시 status 전환만)
- 일반 아키텍처 품질 리뷰(→ `analyze:arch-review`)
- import 위반 결정론 검사 중복(→ gate-fitness)
