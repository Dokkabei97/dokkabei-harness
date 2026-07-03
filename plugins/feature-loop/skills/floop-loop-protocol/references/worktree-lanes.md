# Worktree Lanes — worktree 단계 로드맵 (stage① 격리 → stage② 병렬 레인 → stage③ Agent Teams 파일럿)

feature-loop Stage C의 실행 모델은 현재 **단일 세션 순차 루프**(한 반복 = task 정확히 1개)다. worktree 도입은
아래 3단계로만 진행하며, 각 stage는 이전 stage의 판정 기준을 통과해야 착수한다. 정본 판정 근거는
`tasks/spikes/task-graph-spike.md`(Task Master·beads 스파이크)다 — **stage②가 요구하는 스키마 확장
(depends_on·ready)은 현재 기각 상태**이며, 이 문서는 재고 트리거 발동 시의 경로를 미리 고정해 둔다.

## 단계 총괄

| stage | 이름 | 현재 상태 | 실행 모델 변화 | 스키마 변화 |
|-------|------|----------|---------------|------------|
| ① | worktree 격리 | **구현됨** — `/floop-new --worktree` | 없음 — 순차 루프 불변, 실행 위치만 격리 | 없음 |
| ② | 병렬 레인 | **기각** (재고 트리거 발동 시에만 재검토) | worktree 서브에이전트 동시 디스패치 + 머지 규약 + 게이트 동시성 | tasks.json `parallel_group` + depends_on/ready 페어 |
| ③ | Agent Teams 파일럿 | **보류** (실험 브랜치 한정) | 팀 오케스트레이션 + TaskCompleted 훅 마커 검사 | 없음 (② 스키마 위에서) |

---

## stage① — worktree 격리 (구현됨)

`/floop-new --worktree`가 Stage A를 `../<repo>-floop-<slug>` + 전용 브랜치(`floop/<slug>`)에서 시작한다.

- **격리만, 순차 루프 불변**: 표준 사이클·게이트·Stop훅 정지조건·가드레일 전부 동일. worktree 안에서 보면
  일반 프로젝트와 완전히 같다 — `.planning/`이 worktree 내부에 있을 뿐이다.
- **얻는 것**: 메인 트리 오염 0(`.planning/` 산출물은 worktree 디렉토리 내부에만 존재, `feat: T-xx` 중간 커밋은
  전용 브랜치에 격리), 루프 가동 중에도 메인 트리에서 다른 작업 가능, 실패 시 폐기 비용 =
  `git worktree remove --force` 1회(`.planning/`이 의도적 untracked 산출물이라 `--force`가 정상 경로).
- **경로 계약**: 모든 훅·게이트가 `${CLAUDE_PROJECT_DIR:-.}` 기준으로 `.planning/`을 찾는다. 따라서
  **Stage C 세션은 worktree 루트를 작업 디렉토리로 시작**해야 하며, 메인 트리 세션에서 worktree 프로젝트의
  루프를 돌리면 훅이 엉뚱한 `.planning/`을 판정한다(부재 시 안전핀 exit 0 → 루프 엔진 무력화).
- **종료 절차**: `status: done` → `workflow:shipping-guide`로 머지 안내 위임 → 머지 완료 확인 후 메인 트리에서
  `git worktree remove --force <경로>` + 브랜치 정리(`git branch -d floop/<slug>`). **`--force`가 정상 경로다** —
  `.planning/`(gate-cmd·baseline.json·verified/ 등)은 의도적으로 커밋하지 않는 untracked 산출물이라,
  `--force` 없는 remove는 `contains modified or untracked files`(exit 128)로 반드시 거부된다.

| 항목 | 내용 |
|------|------|
| 선행 조건 | 없음 — 메인 트리가 git 저장소이고 `git worktree add` 가능한 상태면 즉시 사용 |
| 판정 기준(운용 건전성) | worktree 루프 완주 시 메인 트리 diff 0(오염은 worktree 내부에만 존재) · 훅 오판정(잘못된 `.planning/` 참조) 0 · `remove --force` 후 잔존물 0 |
| 실패 시 처치 | 대부분 세션 위치 오류 — worktree 루트에서 세션 재시작. 잔존 worktree는 `git worktree list` 확인 후 `remove --force`(untracked `.planning/` 때문에 `--force` 필수). remove가 그래도 실패하면 `git worktree unlock <경로>` 후 재시도 |

## stage② — 병렬 레인 (기각 — 재고 트리거 하에서만)

tasks.json에 `parallel_group`(동시 착수 가능한 task 묶음)을 도입하고, 레인별 worktree 격리 서브에이전트가
같은 그룹의 task를 동시 구현하는 모델. **현재 기각 상태**다.

**기각 근거** (`tasks/spikes/task-graph-spike.md` (b)①·(d)절): 현행 실행 모델이 원천적으로 순차
(한 반복 = task 1개, Stop훅이 메인 세션 종료를 가로채는 구조)여서, 병렬화는 스키마가 아니라
**실행 모델부터** 바꿔야 하는 문제다. 실행 모델 변경 없이 스키마만 선행 도입하면
"아무도 읽지 않는 죽은 필드"가 된다.

**재고 트리거**: Stage C 병렬 레인(worktree 서브에이전트 동시 구현)을 실제 도입하기로 결정하는 시점.
그때는 스파이크 (d)절 권고대로 — **"depends_on+ready 페어를 전방 참조 금지 규칙과 함께 일괄 도입,
`tasks/spikes/task-graph-spike.md` (c)절 v2 경로"** — 를 따른다. `parallel_group`은 이 페어 위에서만
정의된다(의존이 전부 해소된 ready 집합이 곧 병렬 후보 레인).

**도입 조건 (전부 충족해야 착수)**:

1. stage① 운용 실적 — `--worktree` 루프 완주 3회 이상 + stage① 판정 기준 전건 그린
2. 실행 모델 설계 선행 — 레인별 worktree 디스패치 규약 + 레인 간 머지 규약(충돌 처리 주체) +
   게이트 동시성(레인별 gate-cmd 실행이 서로 간섭하지 않을 것) 문서화
3. 스키마 v2 일괄 도입 — (c)절 경로 그대로: depends_on(선택 필드·전방 참조 금지)·gate-tasks.sh 검증식
   3개·ready 선택 jq. `parallel_group`은 그 위의 파생(서로 의존 없는 ready task 묶음)

| 항목 | 내용 |
|------|------|
| 선행 조건 | 위 도입 조건 1~3 전부 + G1 승인 모델과의 정합(그룹 단위 승인) 설계 |
| 판정 기준 | 2레인 병렬이 순차 대비 벽시계 시간 실측 단축 · 레인 머지 충돌로 인한 수동 개입 0 · 회귀 게이트(②ᴿ) 오탐 0 · verified 마커 규약이 레인별로 성립 |
| 실패 시 처치 | stage①로 롤백(순차 루프) — v2 스키마는 하위 호환(depends_on 부재 = v1 동작)이라 tasks.json 재작성 불요 |

## stage③ — Agent Teams 파일럿 (보류)

Agent Teams(팀 오케스트레이션)로 레인별 팀메이트가 task를 구현하고, **TaskCompleted 훅이 verified 마커를
검사**하는 최소 실험. tasks-guard(PostToolUse)의 팀 실행 모델 버전이 성립하는지 개념 검증이 목적이다.

- **최소 실험 설계**: TaskCompleted 훅에서 완료 주장 task id의 `.planning/verified/{id}` 마커 부재 시 차단 —
  "passes:true 전환은 verified 마커 선행" 규약이 팀 실행 모델에서도 성립하는지만 본다.
- **범위 제한**: **실험 브랜치 한정**. 기본 루프(프로덕션)로의 승격은 보류 — Stop훅 순차 루프가
  기본값으로 유지된다.

| 항목 | 내용 |
|------|------|
| 선행 조건 | stage② 판정 기준 통과 + TaskCompleted 훅의 마커 검사·차단이 기술적으로 성립함을 별도 스파이크로 확인 |
| 판정 기준 | 실험 브랜치에서 마커 없는 완료 주장이 훅에 100% 차단 · 순차 루프 대비 판정 신뢰도(사기 적발) 동등 이상 |
| 실패 시 처치 | 실험 브랜치 폐기 — 프로덕션 루프 무영향(파일럿이 기본 경로를 건드리지 않는 것이 실험 설계의 전제) |

## References

- `tasks/spikes/task-graph-spike.md` — 정본: (b)① depends_on 기각 근거 · (c)절 스키마 v2 마이그레이션 경로 · (d)절 재고 트리거
- `/floop-new` 커맨드 `--worktree 분기` — stage① 진입점 (경로 계약·세션 위치 주의·정리 절차)
- `feature-builder` 에이전트 — "서브에이전트 디스패치는 병렬 task 구현 시 worktree 격리 모드에 한정" (stage② 실행 모델의 접점)
- harness 플러그인 `team-harness` 스킬 `references/orchestrator-template.md` — TaskCompleted 훅 등록 예시 (stage③)
- `workflow:shipping-guide` — worktree 브랜치 머지 안내 위임 대상
