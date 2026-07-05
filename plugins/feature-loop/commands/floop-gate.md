---
name: floop-gate
description: |
  현 Stage 게이트 수동 (재)실행 — 마스터 파일에서 Stage를 판별해 해당 결정론 게이트 스크립트(gates/*.sh)를 Bash로 실행하고 baseline 회귀를 점검한 뒤, feature-verifier를 디스패치해 ✅ 통과/⚠️ 실패/❓ 모호로 보고
  Manually (re)runs the current Stage gate: determines the Stage from the master file, executes the matching deterministic gate script (gates/*.sh) via Bash, checks for baseline regressions, then dispatches feature-verifier and reports pass/fail/ambiguous. Use when: re-running a failed feature-loop gate, or re-checking gate status after manual fixes.
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /floop-gate - 현 Stage 게이트 수동 실행

현재 Stage의 결정론 게이트와 checker 검증을 수동으로 (재)실행한다. 게이트 스크립트는 훅에 등록되어
있지 않으므로(설계상 오케스트레이터/커맨드가 Bash 호출) Stage 전이 외 시점에 산출물을 손본 뒤
재검증하거나, 실패 원인을 좁히고 싶을 때 사용한다. 판정·보고만 수행하며 Stage 전이나 산출물 수정은 하지 않는다.

## Triggers
- 게이트 실패로 중단된 뒤 산출물(tasks.json·구현)을 수정하고 통과 여부를 재확인할 때
- Stage 전이 없이 현 산출물이 게이트 기준을 충족하는지 점검하고 싶을 때
- 루프 진입 전 gate-cmd가 실제로 그린인지, baseline 대비 회귀가 없는지 독립 확인하고 싶을 때
- checker(반증) 관점의 평가를 결정론 게이트와 함께 다시 받고 싶을 때

## Usage
```
/floop-gate

옵션 없음 — 마스터 파일의 ## Stage를 판별해 해당 게이트를 자동 선택한다.
```

## Behavioral Flow

### Phase 1: Stage 판별
1. **마스터 판독**: `.planning/floop-*.md`의 `## Stage` 확인 (미존재 시 `/floop-new` 안내 후 종료)
2. **매핑 결정**: Stage → 게이트 스크립트 + checker 선택

   | Stage | 결정론 게이트 | checker 디스패치 |
   |-------|----------------|------------------|
   | B 분해 | `gate-tasks.sh` (tasks.json jq 스키마 + task 수 2~10) | `feature-verifier` — 분해 반증 |
   | C 개발 | `.planning/gate-cmd` 로드 실행(exit code 우선) + **baseline.json 회귀 점검** + `jq -e '[.tasks[].passes] \| all'` | `feature-verifier` — 현 task AC·회귀 반증 |

   (Stage A 인테이크는 게이트 없음 — 해당 시 "게이트 대상 아님" 보고)

### Phase 2: 결정론 게이트 실행
1. **스크립트 실행**: Stage B는 `${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-tasks.sh` 실행. Stage C는 `.planning/gate-cmd`의 명령을 로드해 실행(`LOOP_TEST_CMD` env 우선)
2. **baseline 회귀 점검 (Stage C)**: gate-cmd 출력에서 현재 실패 수를 추출해 `.planning/baseline.json`의 기준선과 대조 — baseline green이면 exit 0 = 회귀 0, baseline red이면 현재 fail_count ≤ 기준선이어야 회귀 0
3. **판정 수집**: exit code 우선 판정(출력 grep은 보조), 실패 시 출력 tail을 원인 분석용으로 보존

### Phase 3: checker 디스패치
1. **에이전트 호출**: `feature-verifier`를 Task로 디스패치 — 반증 관점(반증 실패 시 통과, 구체 근거 필수) + Stage C는 회귀 반증(baseline 대조) 포함
2. **결과 통합**: 결정론 게이트·baseline 회귀·checker 소견을 대조 — 전부 통과 / 어느 하나 실패 / 판단 상충을 구분

### Phase 4: ✅/⚠️/❓ 보고
1. **분류**:
   - ✅ 통과: 결정론 게이트 그린 + 회귀 0 + checker 반증 실패 → 1줄 보고 (Stage 전이는 오케스트레이터/사용자 몫)
   - ⚠️ 실패: 원인·시도·해결 옵션 보고 (예: 누락 필드, gate-cmd 실패 테스트명, 회귀로 늘어난 테스트)
   - ❓ 모호: 결정론 그린이나 checker가 실질 문제 제기 등 상충 시 — 권장안과 함께 사용자 판단 요청
2. **후속 안내**: 실패 시 수정 담당(TP/FB) 제안, Stage C면 `/floop-run` 재개 또는 `/floop-stop` 후 수정 안내

## Tool Coordination
- **Read/Glob**: 마스터 `## Stage` 판별, `.planning/gate-cmd`·tasks.json·baseline.json 확인
- **Bash**: `${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-tasks.sh` 실행, gate-cmd 명령 실행, jq all-passes 질의, 회귀 fail_count 대조
- **Task**: feature-verifier(Stage B 분해 반증 / Stage C task AC·회귀 반증) 디스패치
- **Grep**: 실패 출력에서 원인 라인 추출 (보조 판정)

## Examples

### Stage B 게이트 재실행 (tasks.json 수정 후)
```
/floop-gate
# Stage B 판별 → gate-tasks.sh: jq 스키마 ✓, task 4개(2~10) ✓
# feature-verifier 분해 반증: T-03에 회귀 보존 AC 누락 지적 → 반증 성립
# ❓ 모호: 결정론 그린이나 checker 지적 — "T-03에 '기존 동일 동작' AC 추가 권장" 보고
```

### Stage C 게이트 독립 확인 (루프 밖, 회귀 점검)
```
/floop-gate
# .planning/gate-cmd 로드 → `./gradlew test` 실행: exit 0
# baseline green 대조 → 회귀 0 ✓ / jq all-passes: false (T-03, T-04 미완)
# feature-verifier가 최근 task T-02 AC·회귀 반증: 통과
# ✅ 부분 통과: 테스트 그린·회귀 0·T-02 verified 정합, 잔여 2 task → /floop-run 재개 안내
```

### Stage C 회귀 적발
```
/floop-gate
# gate-cmd 실행: exit 1, OrderServiceTest 신규 실패 1건
# baseline green(fail_count=0) 대조 → 현재 1 > 0 = 회귀
# ⚠️ 실패: 원인=회귀 1건(OrderServiceTest) / 옵션=feature-builder가 구현 수정으로 기존 동작 복구(기존 테스트 수정 금지)
```

## Boundaries

**Will:**
- 마스터 `## Stage` 기준으로 게이트 스크립트와 checker를 정확히 매핑·실행
- exit code 우선의 결정론 판정 + baseline 회귀 점검 + checker 반증 소견을 통합해 ✅/⚠️/❓ 보고
- 실패 시 원인·시도·해결 옵션, 모호 시 권장안 제시 (게이트 정책 상속)
- Stage C에서 gate-cmd·회귀·all-passes·verified 정합을 루프 밖에서 독립 검증

**Will Not:**
- 게이트 결과에 따른 Stage 전이·status 변경·산출물 수정 (판정과 보고만)
- 실패한 게이트의 기준 완화나 우회 통과, baseline 임의 상향
- verified 마커 생성·삭제 대행 (마커는 feature-verifier의 반증 실패 시에만 생성)

## Related
- `feature-loop-orchestrator` — 게이트 정책·Stage 상태기계
- `/floop-new` — Stage A~B 진행 중 게이트가 내장 실행되는 경로
- `/floop-run` — Stage C에서 루프 엔진이 매 반복 게이트를 자동 판정
- `/floop-status` — 실행 없는 읽기 전용 현황 확인
