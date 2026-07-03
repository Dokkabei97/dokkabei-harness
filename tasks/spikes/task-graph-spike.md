# Task Master · beads 패턴 스파이크 — feature-loop tasks.json 강화 판정

- **성격**: 채택/기각 판정 스파이크 (분석 전용 — 코드 변경 없음)
- **판정일**: 2026-07-03
- **대상**: `plugins/feature-loop/`의 tasks.json 스키마와 그 집행점 3종
- **비교 도구**: [eyaltoledano/claude-task-master](https://github.com/eyaltoledano/claude-task-master) · [steveyegge/beads](https://github.com/steveyegge/beads)
- **1차 소스**: 두 저장소 README, task-master `docs/task-structure.md`, beads `docs/FAQ.md` (조회일 기준) + 로컬 파일 실측(아래 인용은 전부 Read 확인)

---

## (a) 핵심 메커니즘 요약과 현행 스키마 대비

### feature-loop 현행 (로컬 실측)

스키마는 4필수 + 1자유 필드의 평면 배열이다 (`task-decomposition` 스킬이 정본):

```json
{ "tasks": [ { "id": "T-01", "title": "...", "acceptance": ["Given-When-Then ..."], "passes": false, "notes": "(선택, 게이트 비검사)" } ] }
```

집행점과 규약 (실측 근거):

| 집행점 | 파일 | 검사 내용 |
|--------|------|-----------|
| Stage B 결정론 게이트 | `hooks/gates/gate-tasks.sh` | 필수 4필드 존재, id `^T-[0-9]{2}$`·중복 금지, title/acceptance 비어있지 않음, task 수 2~`FLOOP_TASKS_MAX`(기본 10), `--initial` 시 passes 전건 false |
| maker/checker 분리 | `hooks/tasks-guard.sh` (PostToolUse) | `passes:true` task마다 `.planning/verified/{id}` 마커 검사 — 없으면 jq로 false 원복 + exit 2 |
| 루프 정지 판정 | `hooks/floop-loop-stop-hook.sh` | `jq '[.tasks[].passes]\|all'` AND 게이트 그린 AND baseline 회귀 0 AND verified 마커 재검사 AND promise |
| task 선택 | `floop-loop-protocol` 표준 사이클 1단계 | `jq -r '[.tasks[] \| select(.passes == false)][0].id'` — **배열 순서 첫 미완 1개** |
| 의존 표현 | `task-planner.md` §2 / `task-decomposition` 스킬 | "선행 의존이 있으면 순서를 **id 연번에 반영**(T-01 모델 → T-02 그 위 API)" — 명시 필드 없음 |
| 재분해 | `floop-loop-protocol` 에스컬레이션 표 | BLOCKED(스코프 결함) → task-planner 재투입으로 tasks.json 수정 |
| 상태 저장 | `feature-loop-orchestrator` §Architecture | "`.planning/` + git history = 상태" + task별 `feat: T-xx` 1커밋 규약 |

핵심 설계 성질: **스키마의 모든 검사 대상 필드가 jq 한 줄로 결정론 판정 가능**하고, 상태 모델은 `passes` bool 하나를 파일 마커(verified/)와 훅 3종이 둘러싸 진실성을 강제한다. 스키마 = 결정론 집행 계약이다.

### claude-task-master (1차 소스: README + docs/task-structure.md)

- **스키마**: `id`(number) / `title` / `description` / `status`(`pending`·`in-progress`·`done`·`review`·`deferred`·`cancelled` 6종) / **`dependencies`**(task id 배열, 예 `[2,3]`) / `priority`(`high`·`medium`·`low`) / `details` / `testStrategy` / **`subtasks`**(동일 구조 중첩)
- **워크플로우**: `parse-prd`로 PRD → 초기 태스크 그래프 생성 → `task-master next`가 **의존성을 고려해 다음 착수 task를 산출** → `analyze-complexity`가 task별 **1~10 복잡도 스코어 + 권장 subtask 수 + 확장 프롬프트**를 리포트(`task-complexity-report.json`)로 생성 → `expand`/`expand_all`이 스코어 기반으로 task를 subtask로 **재분해**
- 성격: 수십 task 규모 PRD 주도 개발의 계층형 그래프 관리자. 판정(다음 task·복잡도)은 도구+AI가 수행.

### steveyegge/beads (1차 소스: README + docs/FAQ.md)

- **정체**: "a persistent, structured memory for coding agents" — "replaces messy markdown plans with a dependency-aware graph". 마크다운 계획 파일의 대체를 명시적으로 표방.
- **상태 모델**: `in_progress`(`bd update <id> --status in_progress`, `--claim`은 assignee+in_progress 원자 설정)·`closed` 확인. open/blocked는 문맥상 존재("tasks with no open blockers")하나 공식 전체 열거는 README/FAQ에서 미확인.
- **의존 유형 4종**(FAQ 명시): `blocks` / `related` / `parent-child` / **`discovered-from`**(에이전트가 작업 중 발견한 파생 작업 추적). 현행 README는 지식그래프 링크(`relates_to`, `duplicates`, `supersedes`, `replies_to`)까지 확장.
- **ready-work**: `bd ready` = "tasks with no open blockers" — **전이적(transitive) 블로킹을 오프라인 ~10ms에 계산**. 에이전트가 매 세션 "지금 착수 가능한 것"을 질의하는 진입점.
- **저장**: 조회 시점 README 기준 **Dolt 백엔드**(cell-level merge, `refs/dolt/data`로 push/pull) + `.beads/issues.jsonl` export. **해시 기반 ID(`bd-a1b2`)로 멀티 에이전트/멀티 브랜치 머지 충돌 방지**. `bd remember`/`bd prime`로 세션 간 인사이트 재주입, closed task 요약 압축(memory decay).
- 성격: 기능 단위가 아니라 **저장소 수명 전체·멀티 에이전트 동시 작업**을 겨냥한 이슈 DB.

### 대비표

| 축 | Task Master | beads | feature-loop 현행 |
|----|-------------|-------|-------------------|
| 단위·규모 | task+subtasks 계층, PRD 전체 | issue, 레포 수명 전체 | 평면 task **2~10개**, 기능 요청 1건 |
| id | number 연번 | 해시(`bd-a1b2`) — 머지 충돌 방지 | `^T-[0-9]{2}$` 연번 |
| 상태 | status 6종 | open/in_progress/closed(+blocked) | `passes` bool + verified 마커 + BLOCKED.md |
| 의존 | `dependencies[]` 명시 | 의존 유형 4종, 전이적 | **id 연번 암묵 순서** (배열 순서 선택) |
| 다음 작업 | `next` (도구 판정) | `bd ready` (blocker 0 계산) | jq 첫 미완 1개 (결정론) |
| 복잡도·재분해 | 1~10 스코어 → `expand` | 우선순위(P0~)만 | 1 task=1반복 사이징 규율 + **BLOCKED→TP 재분해** |
| 저장 | tasks.json 파일 | Dolt DB + JSONL export | `.planning/` 파일 + git history |
| 완료 판정 주체 | 도구/모델 | 도구/모델 | **결정론 훅** (gate-tasks·tasks-guard·Stop훅) |

---

## (b) 차용 후보별 판정

판정 기준: (1) 개인 하네스 규모(task 2~10, 한두 세션, 단일 브랜치 루프)에서 실질 가치가 있는가, (2) "스키마의 모든 필드는 jq로 결정론 검증 가능해야 한다"는 현 설계 성질을 훼손하지 않는가, (3) 집행점 파급 비용 대비 남는 것이 있는가.

### ① `depends_on` 필드 — **기각** (조건부 재고: 병렬 레인 도입 확정 시)

**가치 주장 검토**:
- *순서 보장*: 이미 충족되어 있다. 선택 로직은 세 곳이 동일 규약("배열 순서 첫 미완 1개" — `floop-loop-protocol` 사이클 1단계, `feature-builder.md` §task 선택 "tasks.json 순서·선행 의존 우선", `bin/floop-headless.sh` 131행)이고, task-planner가 "선행 의존을 id 연번에 반영"하도록 규율된다. **순차 실행에서 연번 순서는 위상정렬과 동치**다 — depends_on이 추가로 보장하는 순서는 없다.
- *병렬 레인*: depends_on이 값을 갖는 유일한 시나리오이나, 현 실행 모델이 원천적으로 순차다. Stage C maker는 "메인 세션이 규율을 체화해 직접 수행(Stop훅이 메인 세션 종료를 가로채는 구조)"(`feature-loop-orchestrator` §Architecture)이고 한 반복=정확히 task 1개다. 병렬화는 스키마가 아니라 **실행 모델(worktree 서브에이전트 동시 디스패치 + 머지 규약 + 게이트 동시성)부터** 바꿔야 하는 문제로, 스키마 선행 도입은 아무도 읽지 않는 죽은 필드가 된다.

**파급 실측**: 채택 시 수정 대상이 최소 7개 파일이다 — gate-tasks.sh(참조 무결성·사이클 검사 추가 — jq만으로 일반 사이클 검사는 비자명), task-planner.md, task-decomposition SKILL.md(정본 스키마·검증식), floop-loop-protocol SKILL.md(선택 jq), floop-loop-stop-hook.sh(재주입 메시지의 미완 안내), bin/floop-headless.sh, feature-builder.md. 2~10개 task 규모에서 이 비용으로 얻는 것은 "이미 성립하는 순서 보장의 명시화"뿐이다.

**보조 관찰**: 의존을 사람이 읽게 남기고 싶다면 이미 존재하는 자유 필드로 충분하다 — `notes`는 "자유 확장(게이트 비검사)"(task-planner.md)이므로 `"notes": "선행: T-01"` 관행은 **스키마 변경·파급 0**으로 지금 당장 가능하다.

### ② 복잡도 스코어 (analyze-complexity + expand) — **기각**

- **결정론 검증 불가**: 복잡도 스코어는 모델이 생성하는 숫자다. gate-tasks.sh는 "필드가 존재하고 1~10 범위"까지는 검사할 수 있어도 **그 값이 맞는지는 어떤 훅도 판정할 수 없다**. "완료 판정은 모델이 아니라 하네스가 한다"는 핵심 명제(feature-loop-orchestrator)의 반대 방향으로, 검증 불가능한 모델 주장 메타데이터를 결정론 계약 안에 들이는 일이다.
- **사이징은 이미 이중 방어 중**: 사전 — task-planner의 수직 슬라이스 규율("한 task에 동사 3개 이상이면 분할", 1 task=1반복) + feature-verifier의 분해 반증(범위 비대 지적, Stage B checker). 사후 — no-progress(실패 시그니처 연속 2회)·circuit breaker(동일 task 3연속 실패) 가드레일 → BLOCKED.md → "스코프 결함이면 task-planner 재투입"(floop-loop-protocol 에스컬레이션 표). **이 사후 재분해가 expand의 경험적 대응물**이며, 예측 스코어(사전 추정)보다 실측 실패라는 강한 근거로 작동한다.
- Task Master의 expand는 `subtasks` 중첩 계층을 전제하지만, feature-loop의 평면 2~10개 제약은 의도된 스코프 가드다("10 초과면 한 세션 컨텍스트 비대 — 여러 /floop-new로 분리", task-decomposition §스코프 가이드). 계층 도입은 이 가드를 우회하는 뒷문이 된다.

### ③ ready-work 산출 (bd ready) — **기각** (①의 종속 결론)

- depends_on이 없는 현행 스키마에서 "ready 집합"은 정의상 **미완 task 전체**로 퇴화하고, "다음 1개"는 현행 jq 한 줄이 이미 결정론적으로 산출한다. Stop훅 재주입도 미완 id 목록 + "우선순위 최상 task 1개만 선택" 지시(floop-loop-stop-hook.sh 276~277행)로 같은 역할을 수행 중이다.
- beads의 bd ready가 해결하는 문제는 "수백 이슈 중 착수 가능한 것 골라내기 + 전이적 blocker 계산"인데, 2~10개 순차 task에서는 계산할 그래프 자체가 없다.
- 단, 후보 자체의 구현 비용은 4건 중 가장 낮다(jq 몇 줄 — (c)에 예시). **①이 채택되는 미래가 오면 반드시 함께 도입**해야 하는 페어다(의존 필드만 있고 ready 산출이 없으면 선택 로직이 의존을 무시한다).

### ④ git 기반 상태 저장 (beads 스타일) — **기각** (동등물 기보유 + 의존성 역행)

- feature-loop는 이미 git 기반이다: "`.planning/` + git history = 상태"(orchestrator §Architecture), task마다 `feat: T-xx` 1커밋 일괄(구현+tasks.json+progress.md), 재개 프로토콜이 `git log --oneline -10`으로 이력을 재생성한다. **beads가 마크다운/JSON 계획 파일에서 벗어나려던 그 지점을, feature-loop는 훅 3종으로 계획 파일을 강제 정합시키는 방식으로 이미 해결**했다.
- beads의 차별 가치 — 해시 ID 머지 충돌 방지, Dolt cell-level merge, 멀티 에이전트 동시 쓰기, memory decay — 는 전부 **멀티 브랜치·멀티 에이전트·레포 수명 스케일**의 문제다. 개인 하네스의 단일 세션 순차 루프에는 그 문제가 발생하지 않고, `.planning/`은 기능 1건 수명으로 끝나므로 압축(decay)할 이력도 쌓이지 않는다.
- Dolt(또는 SQLite) 런타임 의존 추가는 현 설계 원칙과 정면 충돌한다: 모든 훅이 jq+bash만 요구하고 jq 부재 시조차 graceful degrade(floop-loop-stop-hook.sh 29행, tasks-guard.sh 23행)하도록 짜여 있다. 외부 DB는 이 이식성·결정론을 깨는 방향이다.
- 유일하게 흥미로운 개념은 `discovered-from`(작업 중 발견된 파생 작업 추적)이나, 루프 중 task 추가는 G1 승인 모델·`gate-tasks.sh --initial` 검증과 충돌한다. 현행은 이 상황을 BLOCKED.md 기록 → TP 재분해(G1 변경 요지 보고)로 이미 흡수하고 있어 별도 메커니즘이 불필요하다.

---

## (c) 채택 시 마이그레이션 경로 — 스키마 v2 (①+③ 페어, 병렬 레인 도입이 확정된 미래 전용)

판정은 기각이지만, 재고 트리거 발동 시의 경로를 고정해 둔다.

### 스키마 v2

```json
{
  "tasks": [
    { "id": "T-01", "title": "...", "acceptance": ["..."], "passes": false },
    { "id": "T-02", "title": "...", "acceptance": ["..."], "passes": false,
      "depends_on": ["T-01"], "notes": "..." }
  ]
}
```

- `depends_on`: **선택 필드**(문자열 id 배열). **부재 = 의존 없음 = v1 동작** — 기존 tasks.json은 무수정 통과.
- **전방 참조 금지 규칙**: depends_on은 **자기보다 앞선 연번만** 참조 가능. 이 한 줄 규칙이 (i) 사이클을 원천 배제해 jq 일반 사이클 검사(비자명)를 불필요하게 만들고, (ii) v1의 "의존은 연번에 반영" 규약과 자연 정합하며, (iii) v1 선택 로직(배열 순서)이 v2 그래프의 유효한 위상정렬임을 보장한다.

### gate-tasks.sh 추가 검증식 (jq 3줄)

```bash
# depends_on 존재 시 배열·문자열 검사 + 참조 무결성 (실존 id만)
jq -e '(.tasks | map(.id)) as $ids | [.tasks[] | (.depends_on // []) | all(.[]?; IN($ids[]))] | all'
# 자기 참조 금지
jq -e '[.tasks[] | select(has("depends_on")) | .id as $i | .depends_on | all(.[]?; . != $i)] | all'
# 전방 참조 금지 (사이클 원천 배제) — 연번 비교
jq -e '[.tasks[] | (.id | ltrimstr("T-") | tonumber) as $n |
        (.depends_on // []) | all(.[]?; (ltrimstr("T-") | tonumber) < $n)] | all'
```

### ready 선택 jq v2 (floop-loop-protocol 사이클 1단계 대체)

```bash
jq -r '.tasks as $all | [$all[] | select(.passes == false)
       | select(all((.depends_on // [])[]; . as $d | any($all[]; .id == $d and .passes == true)))
      ][0].id' .planning/tasks.json
```

부재 시 `(.depends_on // [])`이 빈 배열 → 전건 통과 → v1과 동일한 "배열 순서 첫 미완"으로 퇴화. **하위 호환이 코드 분기 없이 성립**한다.

### 예상 파급 파일 (실측 기반, 우선순위순)

| # | 파일 | 변경 내용 |
|---|------|-----------|
| 1 | `plugins/feature-loop/hooks/gates/gate-tasks.sh` | 위 검증식 3개 추가 |
| 2 | `plugins/feature-loop/skills/task-decomposition/SKILL.md` | 정본 스키마·검증식·전방 참조 규칙 |
| 3 | `plugins/feature-loop/agents/task-planner.md` | 산출 스키마에 depends_on 규율 추가 |
| 4 | `plugins/feature-loop/skills/floop-loop-protocol/SKILL.md` | 사이클 1단계 jq를 ready 질의로 교체 |
| 5 | `plugins/feature-loop/hooks/floop-loop-stop-hook.sh` | 재주입 메시지의 미완 task 안내를 ready/의존 대기 구분 |
| 6 | `plugins/feature-loop/bin/floop-headless.sh` | 131행 선택 규약 동기화 |
| 7 | `plugins/feature-loop/agents/feature-builder.md` | task 선택 규율 기술 갱신 |
| 8 | `plugins/feature-loop/commands/floop-run.md` · `floop-status.md` | 표현 갱신(미완 최우선 → ready 최우선, 상태 표시) |

무파급: `tasks-guard.sh`(passes/마커 로직만) · `capture-baseline.sh` · `test-guard.sh` · `hooks.json` · `feature-verifier.md`(스키마 인용 1줄 수준).

---

## (d) 최종 권고

**4건 전부 현시점 기각을 권고한다.** feature-loop의 경쟁력은 스키마의 표현력이 아니라 "jq 한 줄로 완전 판정 가능한 최소 스키마 + 그것을 둘러싼 결정론 집행점 3개(gate-tasks·tasks-guard·Stop훅)"라는 성질에 있고, Task Master와 beads는 각각 수십 task 계층 그래프·레포 수명 멀티 에이전트 이슈 DB라는 **다른 규모의 문제**를 푸는 도구다. 개인 하네스의 실측 규모(task 2~10, 한두 세션, 단일 브랜치 순차 루프)에서 depends_on은 이미 성립하는 연번 순서 보장의 중복이고, 복잡도 스코어는 훅이 검증할 수 없는 모델 주장이며, ready-work는 계산할 그래프가 없고, git 기반 저장은 이미 보유한 동등물의 무거운 재구현이다 — 스키마 복잡화 비용이 가치를 명백히 초과한다. 유일한 재고 트리거는 **Stage C 병렬 레인(worktree 서브에이전트 동시 구현)을 실제 도입하기로 결정하는 시점**이며, 그때는 (c)의 v2 경로로 depends_on+ready 페어를 전방 참조 금지 규칙과 함께 일괄 도입하라(그 전의 선행 도입은 죽은 필드와 게이트 복잡화만 남긴다). 그때까지 의존 힌트가 필요하면 게이트 비검사 필드인 `notes`에 "선행: T-xx" 관행으로 기록하는 것으로 충분하다.

---

### 리서치 한계 (정직 고지)

- beads의 상태 전체 열거(공식 목록)는 README·FAQ에서 명시 확인 실패 — `in_progress`·`closed`는 명령 예시로 확인, open/blocked는 문맥 추정.
- beads 저장 백엔드는 조회 시점 README 기준 Dolt로 기술했다(초기 버전의 JSONL+SQLite 캐시 구조에서 진화한 것으로 보임). `.beads/issues.jsonl`은 현행 기준 export이지 정본이 아니다.
- Task Master 복잡도 리포트의 내부 필드명은 문서에 미상세 — 스코어 범위(1~10)·권장 subtask 수·확장 프롬프트 포함까지만 확인.
