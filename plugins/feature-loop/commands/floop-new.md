---
name: floop-new
description: "feature-loop 하네스 진입점 — 기존 코드베이스에서 자연어 기능 요청 한 줄을 받아 Stage A(인테이크+스택감지+baseline 캡처)→Stage B(코드베이스 분석 기반 작업 분해+G1 승인)를 게이트 기반으로 실행하고 개발 루프 가동 여부를 확인. 브라운필드 전용(빈 레포는 /mvp-new 위임)"
category: workflow
complexity: advanced
mcp-servers: []
personas: []
---

# /floop-new - feature-loop 진입점 (Stage A~B)

`feature-loop-orchestrator` 스킬을 진입시켜 자연어 기능 요청을 **기존 코드베이스 위에서** baseline 캡처 →
작업 분해(tasks.json)까지 게이트 기반 상태기계로 끌고 간다. 이 커맨드는 진입점이며, Stage 로직 전체는
`feature-loop-orchestrator`가 수행한다. **브라운필드 전용** — 빈/신규 레포의 기획부터 시작은 `/mvp-new`에 위임한다.

## Triggers
- "이 기능 추가해줘", "X 리팩토링", "이 코드베이스에 Y 붙여줘" — 이미 코드가 있는 프로젝트의 기능 작업
- 자연어 요청을 여러 task로 분해해 회귀 없이 반복 구현해야 할 때
- 빈 레포에서 PRD-driven으로 시작해야 하면 `/mvp-new`로 전환

## Usage
```
/floop-new "<기능 요청 한 줄>" [옵션]

Options:
  --auto              사용자 게이트(★G1 작업 목록 승인)를 추천안으로 자동 채택·기록 (실험용)
  --gate-cmd "<cmd>"  결정론 게이트 명령을 명시 지정 (스택 자동 감지를 덮어씀, 예: "pytest -q tests/unit")
  --e2e-cmd "<cmd>"   (선택) E2E 수용 게이트 명령 — .planning/e2e-gate-cmd에 기록
  --tasks-max <n>     tasks.json task 수 상한 (기본 10, 게이트 허용 범위 2~10)
```

## Behavioral Flow

### Phase 1: 사전 점검
1. **브라운필드 확인**: 기존 코드베이스(소스 트리·빌드 파일)가 **존재해야** 한다. 빈/신규 레포(소스 없음)에서 호출되면 중단하고 `/mvp-new`(그린필드 하네스)를 안내
2. **기존 feature-loop 감지**: `.planning/floop-*.md`가 이미 존재하면(레포당 1개 전제) 새로 만들지 않고 `/floop-run` 재개 또는 `/floop-status` 확인을 안내
3. **옵션 해석**: `--auto`/`--gate-cmd`/`--e2e-cmd`/`--tasks-max`를 검증해 오케스트레이터에 전달

### Phase 2: Stage A — 인테이크 + baseline 캡처 (오케스트레이터 위임)
1. **요청 고정**: `.planning/request.md`에 원본 요청 불변 기록 + 마스터 `floop-{id}.md` 생성(`## Goal` 불변, `status: in_progress`)
2. **스택 자동 감지 → gate-cmd 결정**: `--gate-cmd` 명시 시 그 값 우선. 아니면 빌드 파일로 감지 — `build.gradle(.kts)`/`pom.xml`→`./gradlew test`, `pyproject.toml`/`requirements.txt`→`pytest -q`, `package.json`+`next.config.*`→`pnpm test`, `go.mod`→`go test ./...`. 모호하면 사용자에게 확인. → `.planning/gate-cmd`에 1줄 기록. `--e2e-cmd` 지정 시 `.planning/e2e-gate-cmd` 기록
3. **baseline 캡처**: `${CLAUDE_PLUGIN_ROOT}/hooks/gates/capture-baseline.sh` 실행 → `.planning/baseline.json`. baseline green이면 "클린 기준선" 1줄, red면 "기존 실패 N개 — 회귀 게이트는 신규 실패 0으로 동작" 경고 (기존 실패 선수정 권고하되 강제 안 함)

### Phase 3: Stage B — 작업 분해 (TP 작성 → FV 반증 → G1)
1. **TP 디스패치**: `task-planner`가 코드베이스를 탐색(Grep/Glob)해 영향 범위·재사용 지점 파악 후 tasks.json 초안(`{id:T-xx,title,acceptance[],passes:false}`) 작성 — 수직 슬라이스, Given-When-Then AC, 회귀 보존 AC 포함
2. **FV 반증**: `feature-verifier`가 "이 분해가 틀렸다면 왜?" 관점으로 반증 — 범위 비대·검증 불가 AC·회귀 보존 AC 누락·정착 불가 (최대 2라운드, 반증 실패 시 통과)
3. **결정론 게이트**: `gate-tasks.sh --initial` 실행 — tasks.json jq 스키마 + passes 전건 false + task 수 2~10(`--tasks-max <n>` 지정 시 `FLOOP_TASKS_MAX=<n>` env 전달)
4. **★G1 작업 목록 승인**: 사용자 게이트(항상). 분해 task 목록 + 영향 파일 + 회귀 위험을 제시. `--auto`면 추천안 자동 승인 후 마스터 `## Gates`에 스탬프

### Phase 4: 루프 가동 확인
1. **요약 보고**: Stage A~B 산출물(.planning/ 파일 목록·gate-cmd·baseline 상태·task n개) 1화면 요약
2. **가동 질의**: Stage C 개발 루프 진입 여부 확인 — 즉시 가동이면 `/floop-run` 절차로 연결, 아니면 재개 방법 안내 후 status 유지

게이트 정책(공통): 통과 = 1줄 보고 후 자동 진행 / 실패 = 중단 + 원인·시도·옵션 보고 / 모호 = 중단 + 권장안 보고.

## Tool Coordination
- **Skill**: `feature-loop-orchestrator` 로드 — Stage A~C 상태기계·게이트 정책·협업 호출의 단일 진실 공급원. 분해 표준은 `task-decomposition`
- **Task**: task-planner / feature-verifier 디스패치
- **Bash**: 빌드 파일 감지(`ls`/Glob), `${CLAUDE_PLUGIN_ROOT}/hooks/gates/capture-baseline.sh`·`gate-tasks.sh` 실행
- **Read/Glob**: 기존 feature-loop(.planning/floop-*.md)·코드베이스 유무 감지
- **Write/Edit**: request.md·마스터 파일·gate-cmd·(선택)e2e-gate-cmd 기록, `## Gates` G1 스탬프

## Examples

### 기본 진입 (G1 사용자 승인)
```
/floop-new "회원가입에 이메일 형식·중복 검증 추가"
# Phase 1: 기존 Spring 코드베이스 확인(build.gradle.kts) → gate-cmd="./gradlew test"
# Stage A: baseline 캡처 → green (클린 기준선)
# Stage B: task-planner 분해(T-01~T-03) → FV 반증 1라운드 → gate-tasks.sh ✅ → ★G1 승인 대기
# 종료: 루프 가동 여부 질의 (가동 시 /floop-run 연결)
```

### 게이트 명령 명시 + 빠른 반복
```
/floop-new "검색 결과 캐싱 추가" --gate-cmd "pytest -q tests/search" --tasks-max 4
# 전체 테스트 대신 검색 모듈만 게이트로 → baseline 캡처도 해당 명령으로
# task 수 4개 이내로 컷
```

### 빈 레포에서 호출
```
/floop-new "투표 봇"
# 소스 트리 없음 → 브라운필드 아님
# "/mvp-new \"<아이디어>\"로 그린필드 하네스를 사용하세요" 안내 후 종료
```

## Boundaries

**Will:**
- Stage A~B를 `feature-loop-orchestrator` 상태기계에 위임해 게이트 기반으로 실행
- 스택 자동 감지로 gate-cmd 결정, baseline 캡처로 회귀 기준선 고정
- 사용자 게이트 정확히 1개(★G1 작업 목록)만 운영하고 승인 스탬프를 마스터에 기록
- `.planning/` 메모리(마스터·request.md·tasks.json·gate-cmd·baseline.json) 초기화

**Will Not:**
- Stage C 개발 루프 직접 가동 (→ `/floop-run` — 본 커맨드는 가동 여부 확인까지만)
- 빈/신규 레포의 그린필드 기획 (→ `/mvp-new`)
- 게이트 실패 상태에서 다음 Stage 진행, 또는 G1을 사용자 확인 없이 통과(`--auto` 제외)
- 코드·테스트 작성 (분해까지만 — 구현은 Stage C feature-builder)

## Related
- `feature-loop-orchestrator` — Stage A~C 상태기계·게이트 정책·협업 호출 (위임 대상)
- `task-decomposition` — Stage B 분해 표준
- `/floop-run` — Stage C 개발 루프 시작/재개
- `/floop-gate` — 현 Stage 게이트 수동 재실행
