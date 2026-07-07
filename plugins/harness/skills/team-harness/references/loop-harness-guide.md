# Loop Harness Guide — 루프 하네스 구축 레퍼런스

루프 엔지니어링 = "에이전트를 프롬프트하는 사람"이 아니라 "에이전트를 프롬프트하는 시스템(루프)을 설계하는 사람"이 되는 것. 이 문서는 단일 패스 팀을 넘어 **반복 루프**를 직접 구성하는 방법을 다룬다.

> 핵심 명제: **"완료 판정은 모델이 아니라 하네스가 한다(Completion lives outside the model)."** 모델은 자기 작업을 후하게 평가하므로, 정지 조건은 결정론적 게이트 + 독립 검증자에 둔다.

---

## 1. 루프 엔진 4종 — 무엇을 언제

| 엔진 | 메커니즘 | 적합 | 비적합 |
|------|---------|------|--------|
| **Stop훅 재주입** | Stop 훅이 종료를 가로채(exit 2) 작업을 재주입 → 현재 세션 안에서 자기참조 루프 | 세션 내 "테스트 그린까지" 자율 반복 | 무인/장기 배치 |
| **headless `claude -p` 셸 루프** | 외부 `while` 루프가 매 반복 `claude -p` 호출, `--resume`로 세션 이어가거나 컨텍스트 리셋 | CI·크론·무인 배치, 컨텍스트 리셋형(Ralph) | 대화형 협업 |
| **Workflow 도구** | 결정론적 스크립트가 서브에이전트를 fan-out/pipeline + loop-until-dry | 다단계 오케스트레이션, 병렬 검증 | 단순 단일 반복 |
| **스케줄(Automations)** | `/loop`(세션·1분~) / Routines `/schedule`(클라우드 크론·1시간~) / Cron 도구 | 야간 점검, 이벤트 대응(CI 실패) | 즉시 1회 작업 |

> **Automations가 "한 번 실행"을 "루프"로 만든다.** 스케줄 없이는 루프가 아니라 일회성 실행이다.

### 트리거 축과의 교차 — Anthropic 공식 loops 분류 매핑

위 표는 **"어떻게 반복하나"(실행 메커니즘)** 축이다. Anthropic이 공식 분류한 loops
([Getting started with loops](https://claude.com/blog/getting-started-with-loops))는
**"언제 시작·정지하나"(트리거)** 축 — 둘은 직교하며 서로를 완성한다. 우리 엔진이 각 유형을 어떻게 구현하는지:

| Anthropic 유형 (트리거) | 정지 기준 | 본 하네스 구현 (메커니즘) |
|------|--------|------|
| **Turn-based** | Claude가 완료 판단 | 의도적으로 하네스 **밖**(순수 대화) — 게이트 불필요한 단발 작업 |
| **Goal-based** (`/goal`) | 목표 달성 OR max turns | **Stop훅 재주입** — gate-cmd 결정론 게이트 + promise + max_iter (`/loop-run`·mvp·feature-loop) |
| **Time-based** (`/loop`·`/schedule`) | 사용자 취소 OR 완료 | **스케줄(Automations)** — `/loop`·Routines·Cron |
| **Proactive** | 태스크별 목표 달성(무인) | **headless `claude -p` 셸 루프** + Workflow 도구(무인 fan-out) |

> 핵심 차이: Anthropic이 **원칙**(정량 검증·회의적 evaluator·turn cap)으로 제시한 것을, 본 하네스는
> **강제 장치**로 못 박는다 — 게이트를 Stop훅 exit code가 집행하고(§2-1), checker는 Edit 미보유로
> 도구 수준 분리하며(§2-2), 가드레일 3종을 필수화한다(§4). "완료 판정은 모델이 아니라 하네스가 한다."

### 네이티브 라우팅 규약 — 판정 주체는 하나

- **goal 축은 택일**: 검증 명령·산출물 구조가 필요 없는 단발 목표는 네이티브 `/goal`로 충분하다.
  결정론 게이트·maker/checker·마커가 필요할 때만 본 하네스 루프. **중첩 금지** —
  `.planning/loop-active` 활성 중 네이티브 `/goal`·`/loop` 가동은 재주입·판정 주체를 둘로 만든다.
- **스케줄 축은 감싸기**: 네이티브 `/schedule`(Routines)·Cron이 "언제"를 맡고 본 하네스가
  "무엇을+판정"을 맡는 조합은 권장 — headless 러너의 `headless-active` 락이 중첩 실행을 거부한다
  (레시피: mvp headless-recipe §실행·재개·스케줄).
- **모델 판정 리뷰는 루프 밖**: 네이티브 `/code-review`·`workflow:review-mr` 등 모델 판정 리뷰는
  루프 **정지 판정에 불사용** — 게이트는 결정론만. 게이트 그린 이후의 품질 리뷰로만 쓴다.

---

## 2. 정지 조건 — 모델 밖에서 판정

세 가지를 **결합**한다. 하나만으로는 신뢰할 수 없다.

### (1) 결정론적 게이트 (1차)
테스트·린터·타입체커·빌드·CI를 통과해야만 완료로 인정. 확률적 LLM 출력을 결정론적 제약으로 감싼다.

### (2) 회의적 Evaluator (maker/checker 분리)
- 문제: 모델은 자기 작업을 후하게 평가한다("beige" 솔루션).
- 해법: 생성자(maker)와 **별개의** 회의적 검증자(checker) 서브에이전트. "이게 틀렸다면 왜?"로 반증 시도.
- Anthropic 관찰: *"독립 evaluator를 회의적으로 튜닝하는 것이, 생성자가 자기 작업을 비판하게 만드는 것보다 훨씬 다루기 쉽다."*
- 편향 차단 강화: 교차 모델 리뷰(Worker=Claude, Reviewer=GPT/Gemini)로 confirmation loop를 구조적으로 깬다.

### (3) Completion promise
에이전트가 명시적 완료 토큰(`<promise>DONE</promise>`, `ALL_TASKS_COMPLETE`)을 출력해야만 종료 허용. 정확 문자열 일치(정규식 ❌). 출력 없으면 루프 지속.

### no-progress 감지 (정지의 또 다른 축)
재시도해도 직전과 **동일한 실패**(실패 테스트 수·에러 메시지 동일)면 즉시 중단. 무의미한 재시도와 비용 낭비를 막는다.

---

## 3. 메모리 & 재개 프로토콜

**모델은 실행 간 모든 것을 잊는다 → 상태는 컨텍스트가 아니라 디스크에.**

표준 위치: `.planning/{harness}-{id}.md`
- `## Goal` (불변 목표)
- `## Checklist` (체크박스 — 진행 상태)
- `## Iteration` (루프 카운터)
- `## Feedback` (직전 Evaluator 비평)

**git history = 상태**: 새 세션/에이전트가 `git log` + progress 파일로 빠르게 따라잡고, 롤백·실험 브랜치가 가능하다.

**재개 프로토콜 (매 세션 시작 시):**
1. `pwd` 및 `.planning/` 파일 읽기 — `status: in_progress`면 복구 모드
2. `git log`로 직전 진행 파악
3. 체크리스트에서 **최우선 미완료 1개** 선택 (한 번에 하나만)
4. 작업 → 검증 → 통과 시 체크 + descriptive 커밋 + progress 갱신(다음 세션용 깨끗한 핸드오프)

> compaction(컨텍스트 압축)만으로는 부족하다. 매 세션 **아티팩트에서 이해를 재생성**해야 한다.

---

## 4. 가드레일 — 비용·무한루프 차단 (필수)

| 가드 | 기본값 | 동작 |
|------|--------|------|
| **Max iterations** | 10 | 도달 시 강제 종료 + 미완 보고. completion promise만으론 부족(과제가 예상보다 어려우면 무한 spin) |
| **No-progress** | 연속 2회 | 동일 실패 반복 시 중단, `BLOCKED.md`에 시도·차단 원인 기록 |
| **비용/시간 상한** | 작업별 명시 | 임계 초과 임박 시 현 단계 완료 후 중단 |

> ⚠️ 실제 사고: Stop 훅이 `claude`를 호출하는 무한 루프로 **$3600/day** 청구 사례. 연속 실행 ~$10/hr(Sonnet), 5병렬 ~$50/hr. **시간/반복 상한은 선택이 아니라 필수.**

> 가드 발동 순서: 실패가 **동일하게** 반복되면 no-progress(기본 2회)가 max-iter보다 먼저 멈춘다. 실패 양상이 매번 달라지는 경우에만 max-iter가 backstop으로 작동한다. 둘 다 둬야 "stuck"과 "느린 진전" 양쪽을 막는다.

---

## 5. 레시피 (anatomy)

### A. Ralph 루프 — 최소 단위 (컨텍스트 리셋형)
```bash
#!/bin/bash
MAX=${1:-10}; i=0
while [ $i -lt $MAX ]; do
  cat .planning/task.md | claude -p --permission-mode dontAsk
  grep -q "ALL_TASKS_COMPLETE" .planning/progress.md && break
  ((i++))
done
```
- 매 반복 컨텍스트 리셋, 파일시스템 아티팩트만 영속. 새 에이전트가 매번 전체 스펙을 새로 로드.
- 본 마켓플레이스엔 `ralph-loop` 플러그인(Stop훅 기반 구현)이 이미 설치돼 있음 — 외부 의존 없이 쓰려면 §B/flow-scaffolding 템플릿 사용.

### B. Stop훅 검증 게이트 루프 (세션 내 자기반복)
Stop 훅이 종료 시도를 가로채 (1) 테스트 실행 (2) completion promise 확인 (3) max iteration 확인 후 미충족이면 exit 2로 차단하며 재주입. 구현은 flow-scaffolding `templates/loop-stop-hook.sh`.

### C. 2-Phase 하네스 (Anthropic 공식, 장기 작업)
- **Phase 1 Initializer (1회)**: `init.sh`(구동) + `progress.md` + `feature_list.json`(`{description, steps, passes:false}`) + 초기 커밋. 규칙: **테스트 삭제·수정 금지.**
- **Phase 2 Coding (매 세션)**: §3 재개 프로토콜대로 미완 feature 1개 → 작업 → 브라우저 자동화(Playwright MCP)로 E2E 검증 → 통과해야 `passes:true` → 커밋.

### D. PRD-Driven 루프
`prd.json`(스토리별 `passes` boolean) → 미완료 최우선 스토리 선택 → 구현 → typecheck/test → 통과 시 커밋·마킹 → 전부 true까지. 각 스토리 내부는 Plan→Work→Review→Ship 4단계.

### E. Orchestration 루프 (루프가 루프를 감독)
Planner(스프린트 계약 협상) → Generator(구현) → Evaluator(회의적 검증·반복). 스케줄/백그라운드로 다수 specialist를 병렬 디스패치하고 자연스러운 break point에서 폴링.

---

## 6. 설계 체크리스트

루프 하네스를 설계했다면 아래가 전부 명시됐는지 확인한다:
- [ ] 루프 엔진 1종 선택 (§1)
- [ ] 정지 조건 3결합: 결정론적 게이트 + 회의적 Evaluator + completion promise (§2)
- [ ] no-progress 감지 정의 (§2)
- [ ] 메모리 위치 `.planning/` + 재개 프로토콜 (§3)
- [ ] 가드레일 3종: max iter + no-progress + 비용/시간 상한 (§4)
- [ ] (병렬 변경 시) worktree 격리

## 출처
- Addy Osmani — Loop Engineering: https://addyosmani.com/blog/loop-engineering/
- Anthropic — Getting started with loops (loops 공식 4분류: turn/goal/time/proactive): https://claude.com/blog/getting-started-with-loops
- Anthropic — Effective harnesses for long-running agents: https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- Anthropic — Building effective agents: https://www.anthropic.com/research/building-effective-agents
- Claude Code Hooks 레퍼런스: https://code.claude.com/docs/en/hooks
- Ralph 구현체: github.com/snarktank/ralph, github.com/iannuttall/ralph
