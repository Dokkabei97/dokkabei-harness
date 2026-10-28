---
name: evolve
description: |
  하네스 진화 스킬 — 사용 중인 하네스의 실행 결과와 피드백을 수집·일반화해 기존 에이전트·스킬·
  오케스트레이터에 한 번에 하나씩 반영하고, 초기 구성 대비 델타를 git 커밋 이력(무엇을·왜)으로
  남긴다. 관찰 신호(같은 수정 요청 반복, 반복 실패, 오케스트레이터 우회 수동 작업, v1 유물)가
  있으면 피드백이 없어도 선제 제안한다. 반영 후 /verify-flow 검증과 트리거 재검증을 수행한다.
  Use when: "하네스 회고", "하네스 진화", "하네스 개선", "하네스 피드백 반영", "결과가 아쉬웠어
  하네스 고쳐줘", "이 피드백 하네스에 반영해줘", "하네스 레슨 정리", 하네스 실행 후 개선이 필요할 때.
  위임 경계: 하네스 신규 구축·에이전트 추가/삭제·구조 재설계는 harness:team-harness, 현재 세션의
  교정·교훈 자산화(tasks/lessons.md)는 workflow:retro 소관.
  Evolves an existing harness from its run results: collects and generalizes feedback, applies one change at a time to existing agents, skills, or orchestrators, records each delta in git commit history, and re-validates via /verify-flow and trigger tests; proactively proposes changes from observed signals. Use when: retrospecting or improving a harness after use, applying harness feedback — new builds or restructuring go to harness:team-harness, session lessons go to workflow:retro.
metadata:
  version: 1.0.0
  category: workflow
  origin: revfactory/harness v2.1.0 skills/evolve (Apache-2.0)
---

# Harness Evolve — 하네스 진화

하네스는 고정물이 아니라 진화하는 시스템이다. 이 스킬은 "무엇이 먹혔고 무엇이 안 먹혔는가"의 델타를 포착해 하네스에 되먹여, 다음 실행이 측정 가능하게 더 나아지도록 한다.

```
초기 하네스 ──▶ 실 사용 ──▶ 현재 하네스
                              │ (evolve로 델타 포착)
                              ▼
                    피드백 일반화 → 에이전트·스킬·오케스트레이터에 1건씩 반영
                              │
                              ▼
                    커밋 본문에 무엇을·왜 기록 → 다음 실행은 더 나은 초안에서 시작
```

## 범위

| 요청 | 소관 |
|------|------|
| 기존 구성의 조정 (지시·기준·순서·description·규모) | **evolve** |
| 에이전트 신규 추가/삭제, 아키텍처·실행 모드 재설계 | `harness:team-harness` (Phase 0 확장 절차) |
| 현재 세션의 교정·실수를 교훈으로 자산화 | `workflow:retro` |

evolve는 여러 실행에 걸친 **하네스 컴포넌트**의 개선을, retro는 **이번 세션**의 교정을 다룬다. 범위 밖이면 해당 스킬로 안내하고 멈춘다.

## Phase 1: 델타 수집

1. 하네스 구성을 읽는다 — 프로젝트 `.claude/agents/`·`.claude/skills/` 또는 플러그인 레이아웃 `plugins/*/agents/`·`plugins/*/skills/`, 그리고 `CLAUDE.md`의 하네스 트리거
2. git 이력으로 초기 구성 대비 무엇이 언제 왜 바뀌었는지 파악한다 — 커밋 본문이 변경 이력 원장이다
   ```
   git log --format='%h %ad %s%n%b' --date=short -- <하네스 경로> CLAUDE.md
   ```
3. `_workspace/`가 있으면 최근 실행의 중간 산출물을 훑는다
   - 오케스트레이터가 정의한 경로에 산출물이 실제로 있는가 (없으면 워크플로가 우회됐거나 죽은 코드)
   - 산출물이 스킬이 명시한 형식·기준을 따르는가
4. `tasks/lessons.md`가 있으면 이 하네스에 관한 항목만 확인한다 (retro가 남긴 교정 중 하네스 컴포넌트로 승격할 것)
5. observe 계측이 있으면 그 집계를 관찰 신호로 읽는다 — 없으면 건너뜀 (→ [observe 연동](#observe-연동-로컬) 1~3)
6. 사용자에게 피드백을 요청한다 (이미 제공했다면 생략). 강요하지 않되, 아래 신호가 있으면 선제적으로 제안한다

**관찰 기반 진화 신호 (피드백이 없어도 제안):**
- 같은 유형의 수정 요청이 2회 이상 반복된 흔적
- 에이전트가 같은 원인으로 반복 실패·재시도한 패턴
- 사용자가 오케스트레이터를 우회해 수동으로 작업한 흔적 → 트리거 실패 의심, description 확장 후보
- 오케스트레이터에 v1 유물(`TeamCreate`/`TeamDelete`/`team_name`/실험 플래그) → `harness:team-harness`의 v2 전환 절차 안내

## Phase 2: 피드백 분류 및 수정 대상 매핑

| 피드백 유형 | 수정 대상 | 예시 |
|-----------|----------|------|
| 결과물 품질 | 해당 에이전트의 스킬 | "분석이 너무 피상적" → 스킬에 깊이 기준 추가 |
| 에이전트 역할 | 에이전트 정의 `.md` | "보안 관점이 빠짐" → 역할 보강 (신규 에이전트가 필요하면 team-harness) |
| 워크플로 순서 | 오케스트레이터 스킬 | "검증을 먼저 해야" → Phase 순서 변경 |
| 팀 구성 | 오케스트레이터 + 에이전트 | "이 단계 담당이 모호해" → 역할 경계·배정 조정. 에이전트 병합·분리(추가/삭제)는 → team-harness |
| 트리거 누락·오발동 | 스킬 description | "이 표현으로 하면 작동 안 함" → description 확장·경계 명시 |
| 실행 모드 부적합 | → team-harness | "매번 같은 팬아웃인데 느려" → 모드 전환은 구조 재설계이므로 team-harness로 안내 (evolve는 신호와 근거만 넘김) |
| 규모/비용 | 오케스트레이터 | "토큰을 너무 써" → 기본 규모 축소, `budget` 연동 |
| 모델 부적합 | 에이전트 `model:` | "단순 수집인데 느리고 비싸" → 업무 티어 재선택 + 이유 주석 |

## Phase 3: 일반화 및 반영

1. **피드백을 일반화한다** — 특정 사례에만 맞는 좁은 수정은 오버피팅이다. "이번 보고서 서론이 길었다" → "서론은 10% 이내"가 아니라, 왜 길어졌는지(분량 배분 기준 부재)를 찾아 원리 수준으로 고친다
2. **Why를 함께 쓴다** — 수정한 지시에 이유를 병기한다. 이유를 알면 에이전트가 엣지 케이스에서도 올바르게 판단한다
3. **퇴행 방지** — 대상 파일의 `git log -p -- <파일>`로 이전 수정의 사유를 확인한다. 이번 수정이 과거 수정을 되돌리는 방향이면 사용자에게 상충을 알리고 확인받는다 (과거에 "너무 길다"로 줄였는데 이번엔 "너무 짧다"면 — 둘 다 만족하는 기준을 찾는 것이 정답)
4. **변경안을 먼저 보여준다** — 대상 파일·현재 문구·수정안·일반화 근거를 제시하고 사용자 승인 후 적용한다
5. **한 번에 하나씩** — 변경 1건을 적용하면 곧바로 Phase 4를 실행하고 다음 변경으로 넘어간다
6. **기존 파일의 언어를 유지한다** — 반영하는 문장은 대상 파일에 이미 쓰인 언어로 쓴다

## Phase 4: 검증 및 이력 기록

1. 수정한 컴포넌트를 검증한다 — `/verify-flow <경로>` (프론트매터, 섹션, 참조 일관성, 토큰 예산)
2. description을 고쳤다면 트리거를 재검증한다 — should-trigger 3개 이상 + near-miss 3개 이상 (명백히 무관한 요청이 아니라 헷갈리는 경계 사례로). 방법: `harness:team-harness`의 `references/skill-testing-guide.md`
3. `CLAUDE.md` 트리거와 실제 파일이 일치하는지 확인한다
4. 변경 1건 = 커밋 1건으로 기록한다 (사용자 동의 후). 본문에 무엇을·왜·피드백 출처를 적는다
   ```
   fix(harness-{domain}): content-writer 스킬에 톤 기준 추가

   피드백: "너무 딱딱하다" (2회 반복)
   일반화: 독자 유형별 톤 기준이 스킬에 없었음 → 독자 유형 → 톤 매핑 추가
   ```
   플러그인 레포라면 `plugin.json` ↔ `marketplace.json` 버전을 함께 올린다. 설치된 캐시(`~/.claude/plugins/cache`)는 직접 고치지 않는다 — 원본 레포만 수정한다
   observe 추천에서 출발한 변경이면 본문 끝 trailer 에 `Observe-Rec: <id>`를 붙인다 (→ [observe 연동](#observe-연동-로컬) 4)

## Phase 5: 진화 보고

- 포착한 델타 요약 (초기 구성 → 현재, git 이력 근거)
- 이번에 반영한 변경과 그 일반화 근거 (커밋 해시)
- 반영하지 않기로 한 피드백과 이유
- 다음 실행에서 기대되는 개선점과 확인 방법 — observe 추천을 반영했다면 applied·전후 효과 확인법 (→ [observe 연동](#observe-연동-로컬) 5)

## 원칙

- **델타는 자산이다** — 변경 이력이 쌓일수록 같은 도메인의 다음 하네스가 "출시 상태에 더 가까운 초안"에서 시작한다. 이력을 지우지 않는다 (squash·rebase로 사유를 날리지 않는다)
- **일반화 없는 반영 금지** — 사례 하나에 규칙 하나를 1:1로 추가하면 스킬이 규칙 더미가 된다. 원리로 압축한다
- **한 번에 하나씩** — 여러 변경을 몰아서 적용하면 어떤 변경이 효과였는지 알 수 없다

## observe 연동 (로컬)

> 로컬 추가 절 — 업스트림(revfactory/harness)에 없다. 동기화 때 이 절과 Phase 1·4·5 의 참조 한 줄씩을 보존한다.
> harness 는 observe 에 의존하지 않는다 — 집계기나 트레이스가 없으면 이 절 전체를 조용히 건너뛴다.

1. **탐지** — 레포 소스(플러그인 레포 안일 때)를 먼저, 없으면 설치 캐시의 최신 버전을 쓴다. 캐시는 읽기·실행만 한다
   ```bash
   ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
   OBS="$ROOT/plugins/observe/bin/observe-report.js"
   # 캐시 레이아웃: <cache>/<마켓>/observe/<버전>/bin/observe-report.js — 버전 기준 최신 1개
   [ -f "$OBS" ] || OBS=$(find ~/.claude/plugins/cache -path '*/observe/*/bin/observe-report.js' 2>/dev/null \
     | awk -F/ '{print $(NF-2) "\t" $0}' | sort -V | tail -1 | cut -f2)
   # 집계기 없음, 또는 트레이스(.tracer/ · 구 .claude/skill-trace.jsonl) 없음 → 이 절 건너뜀
   [ -n "$OBS" ] && { [ -d "$ROOT/.tracer" ] || [ -f "$ROOT/.claude/skill-trace.jsonl" ]; } && echo "$OBS" || echo skip
   ```
2. **읽기** — `(cd "$ROOT" && node "$OBS" --json --no-record)` (`--no-record`: 추천 기록도 쓰지 않는 읽기 전용 실행). `meta.trace_missing` 이
   참이면 건너뛴다. 구버전 observe(1.x)에는 `recommendations`·턴 결과가 없다 — 없는 키의 신호는 빼고 나머지만 쓴다
3. **신호 매핑** — Phase 1 관찰 신호로 읽어 Phase 2 표의 수정 대상으로 잇는다. 숫자는 후보일 뿐이라 근거를 읽고 판정한다

   | observe 키 | 관찰 신호 | Phase 2 행 |
   |-----------|----------|-----------|
   | `followups[]`(교정 후보 쌍 — `target`·`next_prompt`), `skills[]`·`agents[]` 의 `outcome.corrected` | 같은 수정 요청 반복 | 결과물 품질·에이전트 역할 |
   | `skills[]`·`agents[]` 의 `outcome.failed` | 반복 실패 | 결과물 품질·에이전트 역할 |
   | `recommendations.items[]` 의 `orchestrate`(기존 오케스트레이터가 흡수할 연쇄일 때), `signal.chain` 이 있는 `missed` | 오케스트레이터 우회 | 워크플로 순서·트리거 누락 |
   | `recommendations.items[]` 의 `missed`·`tune`(`evidence` ref, `tune.terms`·`terms`, `reason: no_use_when`) | 트리거 누락 | 트리거 누락·오발동 |

   범위 밖은 안내만 한다 — 흡수할 오케스트레이터가 없는 `orchestrate`(새 오케스트레이터)는 `harness:team-harness`,
   `inventory.lifecycle` 의 `stale`·`archive_candidates`(사장 자산)는 `workflow:deprecation-guide`.
   observe 의 수락·거절 응답(`--accept` 등)은 evolve 가 대신 쓰지 않는다 — `/observe-report` Phase 6 소관
4. **커밋** — observe 추천(`id` = `rec_<12hex>`)에서 출발한 변경이면 Phase 4 커밋 본문 마지막 문단(trailer 블록)에
   `Observe-Rec: <id>` 를 붙인다. 여러 개면 한 줄에 하나, `Co-Authored-By` 같은 다른 trailer 와 빈 줄 없이 같은 문단에 둔다.
   1변경 = 1커밋은 그대로다 — 한 추천을 여러 커밋에 걸쳐 반영하면 커밋마다 같은 trailer 를 단다. 본문에는 근거 ref·숫자만 쓰고
   프롬프트 원문은 옮기지 않는다 (observe 원문은 레포 밖으로 내보내지 않는 경계)
   ```
   fix(observe-demo): alpha description 에 Use when 보강

   근거: observe missed 5세션 (ref s1#p3 외)
   일반화: 배포 점검 요청 어휘가 description 에 없었음 → Use when 절 추가

   Observe-Rec: rec_0123456789ab
   ```
5. **보고** (Phase 5) — 다음 `/observe-report`(또는 2번 명령)에서 `recommendations.applied.items[]` 에 그 id 가 커밋 SHA 와 함께
   나오고 다시 제안되지 않는다(`recommendations.suppressed` 의 `reason: applied`). `effect` 는 마지막 반영 커밋 전/후 같은 길이 창
   (기본 30일, `--effect-days`)의 대상 스킬 호출 비율이다 — `status: ok` 면 `before.rate`→`after.rate`·`delta` 를 보고하고,
   `표본 부족`(어느 쪽이든 매칭 턴 < `min`)이면 "창이 찬 뒤 재확인"으로 적는다. trailer 는 측정 레포의 HEAD 에서 닿는 커밋만 읽힌다 —
   다른 레포(설치 플러그인의 원본 레포 등)에 커밋했거나 id 를 잘못 쓰면 그 리포트의 `applied.unknown` 에 남거나 잡히지 않는다

## Boundaries

**Will:**
- 하네스 구성·git 이력·`_workspace/`·사용자 피드백에서 델타를 수집하고 관찰 신호로 선제 제안
- 승인된 변경을 기존 컴포넌트에 1건씩 적용하고 `/verify-flow`·트리거 테스트로 검증
- 변경마다 사유를 담은 커밋 메시지 작성

**Will Not:**
- 에이전트 신규 추가/삭제·아키텍처 재설계 (→ `harness:team-harness`)
- 세션 교정의 교훈 기록 (→ `workflow:retro`)
- 승인 없이 여러 변경을 일괄 적용하거나, 설치 캐시를 수정하거나, 이력을 재작성
