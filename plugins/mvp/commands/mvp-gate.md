---
name: mvp-gate
description: "현 Stage 게이트 수동 (재)실행 — 마스터 파일에서 Stage를 판별해 해당 결정론 게이트 스크립트(gates/*.sh)를 Bash로 실행하고, 해당 checker 에이전트를 디스패치한 뒤 ✅ 통과/⚠️ 실패/❓ 모호로 보고"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /mvp-gate - 현 Stage 게이트 수동 실행

현재 Stage의 결정론 게이트와 checker 검증을 수동으로 (재)실행한다. 게이트 스크립트는 훅에 등록되어
있지 않으므로(설계상 오케스트레이터/커맨드가 Bash 호출) Stage 전이 외 시점에 산출물을 손본 뒤
재검증하거나, 실패 원인을 좁히고 싶을 때 사용한다. 판정·보고만 수행하며 Stage 전이나 산출물 수정은 하지 않는다.

## Triggers
- 게이트 실패로 중단된 뒤 산출물(prd.md·design-spec.md·골격)을 수정하고 통과 여부를 재확인할 때
- Stage 전이 없이 현 산출물이 게이트 기준을 충족하는지 점검하고 싶을 때
- 루프 진입 전 gate-cmd가 실제로 그린인지 독립적으로 확인하고 싶을 때
- checker(반증/교차검증) 관점의 평가를 결정론 게이트와 함께 다시 받고 싶을 때

## Usage
```
/mvp-gate

옵션 없음 — 마스터 파일의 ## Stage를 판별해 해당 게이트를 자동 선택한다.
Stage별 매핑(결정론 게이트 + checker)은 Behavioral Flow의 표를 따른다.
```

## Behavioral Flow

### Phase 1: Stage 판별
1. **마스터 판독**: `.planning/mvp-*.md`의 `## Stage` 확인 (미존재 시 `/mvp-new` 안내 후 종료)
2. **매핑 결정**: Stage → 게이트 스크립트 + checker 선택

   | Stage | 결정론 게이트 | checker 디스패치 |
   |-------|----------------|------------------|
   | 1 기획 | `gate-prd.sh` (필수 섹션 grep + prd.json jq 스키마 + 스토리 3~10) | `mvp-verifier` — PRD 반증 |
   | 2 디자인 | `gate-design.sh` (전 story id의 `[story: S-xx]` 등장) | `product-strategist` — 커버리지 매트릭스 검증 |
   | 3 스캐폴딩 | `gate-scaffold.sh` (gate-cmd 그린 + 초기 커밋 + .planning 필수 파일) | 없음 — 결정론 게이트 단독 (구조 문제 시 `tech-architect` 재투입 권고만) |
   | 4 개발 | `.planning/gate-cmd` 로드 실행(exit code 우선) + `jq -e '[.stories[].passes] | all'` | `mvp-verifier` — 현 스토리 AC 반증 |

   (Stage 0 인테이크는 게이트 없음 — 해당 시 "게이트 대상 아님" 보고)

### Phase 2: 결정론 게이트 실행
1. **스크립트 실행**: `${CLAUDE_PLUGIN_ROOT}/hooks/gates/` 아래 해당 게이트를 Bash로 실행 (Stage 4는 `.planning/gate-cmd`의 명령을 로드해 실행, `LOOP_TEST_CMD` env가 있으면 우선)
2. **판정 수집**: exit code 우선 판정(출력 grep은 보조 — 오탐 방지), 실패 시 출력 tail을 원인 분석용으로 보존

### Phase 3: checker 디스패치
1. **에이전트 호출**: Stage 매핑의 checker를 Task로 디스패치 — 반증 관점(자기발견 제외, 반증 실패 시 통과) 평가 수행
2. **결과 통합**: 결정론 게이트 결과와 checker 소견을 대조 — 둘 다 통과 / 어느 한쪽 실패 / 판단 상충을 구분

### Phase 4: ✅/⚠️/❓ 보고
1. **분류**:
   - ✅ 통과: 결정론 게이트 그린 + checker 반증 실패 → 1줄 보고 (Stage 전이는 오케스트레이터/사용자 몫)
   - ⚠️ 실패: 원인·시도한 것·해결 옵션 보고 (예: 누락 story id 목록, gate-cmd 실패 테스트명)
   - ❓ 모호: 결정론 그린이나 checker가 실질 문제 제기 등 상충 시 — 권장안과 함께 사용자 판단 요청
2. **후속 안내**: 실패 시 수정 담당(PS/UX/TA/MB) 제안, Stage 4면 `/mvp-run` 재개 또는 `/mvp-stop` 후 수정 안내

## Tool Coordination
- **Read/Glob**: 마스터 `## Stage` 판별, `.planning/gate-cmd`·prd.json·design-spec.md 확인
- **Bash**: `${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-prd.sh`·`gate-design.sh`·`gate-scaffold.sh` 실행, gate-cmd 명령 실행, jq all-passes 질의
- **Task**: mvp-verifier(Stage 1·4) / product-strategist(Stage 2) checker 디스패치
- **Grep**: 실패 출력에서 원인 라인 추출 (보조 판정)

## Examples

### Stage 1 게이트 재실행 (PRD 수정 후)
```
/mvp-gate
# Stage 1 판별 → gate-prd.sh 실행: 필수 섹션 ✓, jq 스키마 ✓, 스토리 6개(3~10) ✓
# mvp-verifier 반증: 측정 불가 지표 1건 지적 → 반증 성립
# ❓ 모호: 결정론 그린이나 checker 지적 상충 — "S-04 AC를 측정 가능 문장으로 수정 권장" 보고
```

### Stage 2 게이트 (매핑 누락 적발)
```
/mvp-gate
# gate-design.sh 실행: S-05가 design-spec.md에 [story: S-05]로 미등장
# ⚠️ 실패: 원인=매핑 누락 1건 / 옵션=ux-designer 재디스패치 또는 수동 태그 추가 후 재실행
```

### Stage 4 게이트 독립 확인 (루프 밖)
```
/mvp-gate
# .planning/gate-cmd 로드 → `pytest -q` 실행: exit 0 (그린)
# jq all-passes: false (S-06, S-07 미완) → mvp-verifier가 최근 스토리 S-05 AC 반증: 통과
# ✅ 부분 통과 보고: 테스트 그린·S-05 verified 정합, 잔여 2 스토리 → /mvp-run 재개 안내
```

## Boundaries

**Will:**
- 마스터 `## Stage` 기준으로 게이트 스크립트와 checker를 정확히 매핑·실행
- exit code 우선의 결정론 판정과 checker 반증 소견을 통합해 ✅/⚠️/❓로 보고
- 실패 시 원인·시도·해결 옵션, 모호 시 권장안 제시 (게이트 정책 상속)
- Stage 4에서 gate-cmd·all-passes·verified 정합을 루프 밖에서 독립 검증

**Will Not:**
- 게이트 결과에 따른 Stage 전이·status 변경·산출물 수정 (판정과 보고만)
- 실패한 게이트의 기준 완화나 우회 통과
- verified 마커 생성·삭제 대행 (마커는 mvp-verifier의 반증 실패 시에만 생성)

## Related
- `mvp-orchestrator` — 게이트 정책·Stage 상태기계 (references/gate-policy.md에 스크립트 명세)
- `/mvp-new` — Stage 0~3 진행 중 게이트가 내장 실행되는 경로
- `/mvp-run` — Stage 4에서 루프 엔진이 매 반복 게이트를 자동 판정
- `/mvp-status` — 실행 없는 읽기 전용 현황 확인
