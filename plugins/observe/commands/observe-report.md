---
name: observe-report
description: "계측 기반 하네스 건강 리포트 — .tracer 트레이스(Claude Code 훅, Codex·Antigravity 백필)를 결정론 집계(스킬·에이전트 호출, user/model trigger, 로드 수, 턴 결과 committed·cancelled·corrected 후보·failed, 미사용 자산, stale/archive 라이프사이클 후보, 미발화 후보 턴, 교정 후보 쌍, BM25 추천 missed·tune·orchestrate)한 뒤 해석해 description 튜닝 초안·폐기 후보·계측 개선 제안을 만들고, 추천 ID 마다 수락·거절·보류를 물어 명시 응답만 기록한다. 제안 전용 — 파일 수정 없음(유일한 예외: 자기 .tracer/recommendations.jsonl 에 원문 없는 추천 이벤트 append). Harness health report from observe telemetry: deterministic aggregation of real usage (skill/agent calls, user vs model triggers, load counts, per-turn outcomes committed/cancelled/correction-candidate/failed, unused and stale/archive assets, no-activation candidate turns, correction-candidate pairs, BM25 recommendations missed/tune/orchestrate), then interpretation into description-tuning drafts, deprecation candidates and measurement fixes; asks accept/reject/snooze per recommendation ID and records only explicit answers. Proposals only — never edits files (sole exception: appending no-raw recommendation events to its own .tracer/recommendations.jsonl). Use when: “하네스 리포트”, “스킬 사용 현황”, “안 쓰는 스킬 찾아줘”, “계측 결과 보여줘”, harness health report, skill usage stats, finding unused or missed skills, reviewing observe traces."
category: utility
complexity: intermediate
mcp-servers: []
personas: []
---

# /observe-report - 계측 기반 하네스 건강 리포트

## Triggers
- 하네스(스킬·커맨드·에이전트)가 실제로 잘 호출되고 잘 사용되는지 계측 결과로 점검하고 싶을 때
- "하네스 리포트", "스킬 사용 현황", "계측 결과 보여줘", "안 쓰는 스킬 찾아줘" 요청 시
- 스킬 description 튜닝·사장 자산 정리 등 하네스 개선 의사결정의 근거가 필요할 때
- OBSERVE_TRACE 수집을 켠 뒤 일정 기간이 지나 축적된 트레이스를 해석하고 싶을 때

## Usage
```
/observe-report [options]

Options:
  --raw               결정론 집계 JSON만 출력하고 해석(Phase 3~4)은 생략
  --window <days>     최근 N일 레코드만 집계 (기본 전체)
  --focus <area>      해석 초점: skills | agents | prompts (기본 전체)
  --stale-days <n>    라이프사이클 stale 임계 (집계기 전달, 기본 30 — 0이면 비활성)
  --archive-days <n>  라이프사이클 archive 후보 임계 (집계기 전달, 기본 90)
  --followups <n>     교정 후보 쌍 수집 상한 (집계기 전달, 기본 30 — 0이면 비활성)
  --all               전역 합산: ~/.tracer/index/repos.d/ 에 등록된 모든 레포 (집계기 전달, 원문 제외 —
                      candidates/followups·matches.turns 가 비므로 Phase 3 의 미발화·교정 판정은 생략)
  --theta <x> / --margin <x>   추천 엔진 missed 임계(BM25 top1 / top1-top2, 기본 10 / 3 — 수동 상수)
  --orch-min <n>      orchestrate n-gram 최소 근거 세션 수 (기본 3)
  --min-sample <n>    추천 최소 표본(사람 프롬프트 수, 기본 20 — 미만이면 추천 전부 reason sample 로 억제)
                      (임계를 기본값과 다르게 준 실행은 실험으로 보고 recommendations.jsonl 에 기록하지 않는다)
  --no-record         recommendations.jsonl 에 생성 이벤트를 쓰지 않음 (기본: .tracer 가 있는 레포 모드에서 기록 —
                      --window·--all·--trace·임계 오버라이드·--candidates 0(export 파이프) 실행도 기록하지 않음)
  --effect-days <n>   git 반영(Observe-Rec trailer) 추천의 전후 비교 창 (기본 30 — 기록 여부와 무관)

피드백 (Phase 6 에서 사용자 응답을 받은 뒤에만 실행 — 집계 없이 status 이벤트만 append):
  --accept <id>[,<id>…]   수락 (이후 그 추천은 다시 내지 않음)
  --reject <id>[,<id>…]   거절 (ID 기준 30일 쿨다운 — 그 안에서는 근거 세션 수가 거절 당시의 2배 이상일 때만 재노출)
  --snooze <id>[,<id>…]   보류 (--snooze-days <n> 일 뒤 다시 제안, 기본 7)
  (재노출 항목은 <id>@<evidence_n> — 쿨다운 안 근거 2배 재노출이면 응답 앞에 새 회차 created 를 쓴다)
```
θ(10)·margin(3)·만료(응답 없는 제안 30일)·precision 최소 분모(10)는 수동 상수다 — 자동 보정은 하지 않는다.

## Behavioral Flow

전 과정은 "결정론 집계(스크립트) → 해석(LLM) → 제안(승인 전 제안서까지만)"의 경계를 지킨다.
비용/토큰 계측은 범위 밖(OTel 은 지원하지 않음), 발화율 사전 벤치마크는
skill-creator eval 소관 — 이 커맨드는 **실사용 텔레메트리의 사후 진단** 전용이다.

### Phase 1: 수집 상태 점검
1. **집계 실행**: `node ${CLAUDE_PLUGIN_ROOT}/bin/observe-report.js --json` (옵션 `--window` 전달).
   `${CLAUDE_PLUGIN_ROOT}` 미치환 환경이면 저장소의 `plugins/observe/bin/observe-report.js` 폴백
2. **가용성 판정**: `meta.trace_missing`이면 계측이 꺼진 상태 — OBSERVE_TRACE=1 활성화 방법
   (셸 프로필 또는 settings.json `env`)과 재수집 후 재실행 안내를 출력하고 **종료**.
   저장소는 레포 `.tracer/`(v1)이고 구 경로 `.claude/skill-trace.jsonl`(v0)도 함께 읽힌다 —
   `meta.schema.v0 > 0`이면 일회성 `node <observe>/bin/observe-migrate.js` 실행을 한 줄 안내(실행은 사용자 몫).
   Codex·Antigravity 도 쓰거나 훅을 켜기 전 Claude Code 기록이 있는 레포면 `node <observe>/bin/observe-backfill.js`(이 레포 세션만 다이제스트로 백필,
   다시 돌려도 중복 없음 — 턴 결과에 `runtime` 별로 섞여 들어간다)를 한 줄 안내(실행은 사용자 몫)
3. **분모 검증**: 기본 분모는 설치 목록(`meta.plugins_dir_source: "installed"` — `installed_plugins.json` 의
   플러그인당 installPath 하나, 캐시에 남은 archive·uninstall 고아 디렉터리 제외)이다. 출처가 `trace`/`self`
   (설치 목록 없음·깨짐 폴백)면 `meta.plugins_dir`이 마켓플레이스 루트인지 확인. 특정 플러그인 하나의 설치
   루트(예: `.../cache/<마켓>/observe/1.1.0`)로 잡혀 `inventory.plugins`가 1로 붕괴하면 커버리지
   분석이 "unused 없음"이라는 잘못된 안심을 준다(실측 2026-07) — 집계기가 버전 레이아웃을 상향
   인식하지만, 의심스러우면 `--plugins-dir <마켓 캐시 루트 또는 레포 plugins/>`로 명시 오버라이드
4. **표본 적정성**: 레코드 수·세션 수·기간을 보고하고, 표본이 작으면(세션 < 5) 이후 해석에
   "표본 부족 — 경향 참고용" 경고를 달아 과잉 일반화를 방지

### Phase 2: 결정론 집계 보고
집계 JSON을 요약 표로 제시한다 (`--raw`면 여기서 JSON 출력 후 종료).
1. **호출 현황**: 스킬/커맨드/에이전트별 호출수·user/model 트리거 비율·로드 수(`loaded`)·평균 소요시간.
   `loaded` 는 PostToolUse result join 수다 — Skill result 는 본문 로드 시점에 찍히므로 **완주가 아니다**.
   `heuristic` 은 SKILL.md 읽기로 감지한 호출 수(Codex — Skill 툴·result 가 원천에 없다)다. 전부 heuristic 이면 로드는 `n/a` 로
   표시되며 "로드율 낮음"으로 해석하지 않는다. 백필 다이제스트(Codex·Antigravity)의 `turn_summary.skills` 는 미사용·라이프사이클
   판정의 사용 신호로만 들어가고 호출수에는 없다. heuristic 은 "열었다"를 "썼다"로 본다 — 레포 안 스킬 소스 읽기는 빼지만
   레포 밖에서 열어 보기만 한 스킬도 사용으로 잡힐 수 있으니, heuristic 만으로 미사용 후보에서 빠진 스킬은 단정하지 않는다
   작업 결과는 다음 항목의 턴 결과로만 말한다
2. **턴 결과**: `turns.outcomes`(Stop 다이제스트 — committed/cancelled/corrected/failed/unknown)와 항목별
   `skills[].outcome`·`agents[].outcome`(그 이름을 쓴 턴의 분포). 분모는 사람 턴뿐이다 — async 완료 알림·`!` 모드 같은
   시스템 주입 턴은 `turns.system` 으로만 센다. `corrected` 는 교정 **후보**(다음 사람 턴의 평문 프롬프트)이고
   `cancelled` 는 사용자 Esc 중단·(뒤에 진행이 없는) 도구 거부 마커다. `turns.count` 가 0 이면(다이제스트 없음 — 2.0 이전 기록뿐) 턴 결과 판정은 생략
3. **커버리지**: 인벤토리(트레이스와 동일 설치 루트에서 열거) 대비 미사용 스킬/커맨드/에이전트 수
4. **라이프사이클**: 사용된 자산의 stale(기본 ≥30일)·archive 후보(기본 ≥90일) — `inventory.lifecycle`.
   `meta.coverage.days`가 임계보다 짧으면 "관측 기간 부족 — 참고용"을 반드시 병기
5. **계측 품질**: parse_errors, trigger null 비율, why 커버리지, 인벤토리 밖 호출(unknown_called)
6. **추천 엔진 상태**: `recommendations.sample`(사람 프롬프트 < 20 이면 추천 없음 — "표본 부족"으로 보고),
   `matches.gold`(골드 라벨 N 과 top-3 비율 — `status` 가 `측정불가`(N<10)면 비율을 말하지 않는다),
   `recommendations.counts`·`suppressed`(cap·cooldown·accepted·applied·sample 사유별 억제 수)
7. **추천 precision**(보고 머리에 둔다): `recommendations.precision.<유형>` — `status` 가 `ok` 면 `precision`(= 수락/(수락+거절),
   명시 응답 + git 반영 기준 — `applied` 는 수락에 포함된 git 반영 회차 수)과 분모 `n` 을, `표본 부족`(n < 10)이면 값 없이
   "표본 부족(응답 n건)"만 쓴다. 값을 추정·보간하지 않는다
8. **반영된 추천**: `recommendations.applied` — 커밋 메시지 trailer `Observe-Rec: <id>`(HEAD 에서 닿는 커밋, git 이 원장)로 반영이
   확인된 추천. `items[]` 는 커밋 SHA·시각과 `effect`(마지막 반영 커밋 전/후 같은 길이 창의 호출 비율 = 호출 턴/(호출 턴+missed 근거 턴))를
   싣는다. `effect.status` 가 `ok` 면 전→후 비율과 `delta` 를, `표본 부족`(어느 쪽이든 매칭 턴 < `effect_min`)이면 숫자를 효과로
   해석하지 않는다(orchestrate 는 `측정 대상 아님`). `unknown` 은 기록·후보에 없는 ID(다른 레포·오타)다. `available:false`(git 없음)·
   `null`(`--all`·`--trace` — git 을 읽지 않음)이면 이 항목은 생략한다

### Phase 3: 해석 (LLM 판정)
집계가 제공한 후보를 판정한다 — 집계 스크립트는 후보 추출·랭킹까지, 판정은 여기서만.
**입력은 랭킹된 후보다**: `recommendations.items`(유형별 ≤3, 결정론 랭킹 — missed/tune/orchestrate, 같은 대상은
한 번만 — 대상이 missed 이기도 한 tune 은 그 missed 항목의 `tune` 하위 제안으로 붙는다)와
`matches.turns`(미발화 턴별 BM25 top-3·margin·gold). 인벤토리 전체를 훑어 새로 짝짓지 않는다 — 후보 밖
자산은 판정 대상이 아니다(BM25 는 후보 수집기라 정밀도가 낮을 수 있으므로 "기각"도 정상 결과다).
1. **미발화 판정**: `missed` 항목마다 근거 턴(`items[].evidence` 의 `session#turn` ref)을 대상 SKILL.md description 과 대조해
   "놓친 발화" vs "스킬 불필요(BM25 오매칭)"로 분류. ref 는 `<session>#<turn>`(turn 이 없으면 `<session>#<ts>`)이다.
   원문(`text`, 200자)은 `candidates[]` 에서 `` `${session_id}#${turn ?? ts}` `` 가 ref 와 같은 항목에 있고(`turn` = 프롬프트 ID),
   그 턴의 BM25 top-3 는 `matches.turns[]` 에서 `` `${session}#${turn ?? ts}` `` 가 같은 항목에 있다(`matches.turns` 에는
   원문이 없다 — 원문은 `candidates` 에서만). 노출 항목의 근거 턴은 `--candidates` 상한 밖이어도 두 목록에 보강된다 —
   orchestrate 경유 근거(`orchestrate` 항목, 그리고 `signal.chain` 이 있는 `missed` 항목에 합쳐진 세션 — 스킬 호출이 있던 턴)는
   미발화 턴이 아니라 보강 대상이 아니므로 ref 만 있고 원문 조회는 하지 않는다. `signal.chain` 이 있으면 `via` 값과 무관하게
   (bm25·gold 근거로 먼저 생긴 항목은 `via` 가 그대로다) 합쳐진 ref 가 섞여 있다 — `candidates` 에 없는 ref 는 원문 없는
   스킬 호출 턴 근거로 보고, 미발화 판정은 원문이 있는 ref 로만 한다.
   **`--all` 실행에는 원문이 없다** — `candidates`·`matches.turns` 가 비고 BM25 경유 missed·tune 은 나오지 않는다.
   남는 것은 연쇄 근거 항목뿐이다: `orchestrate` 항목과, 연쇄가 호스트 오케스트레이터로 라우팅된 `missed` 항목
   (`via: "orchestrate"` + `signal.chain`, ref 는 스킬 호출 턴). 이때는 미발화 판정을 생략하고 "원문 없는 실행 — 레포 모드에서 재실행"으로 적는다.
   (`--candidates 0` 도 두 목록을 비우므로 이 판정에는 쓰지 않는다 — export 파이프 전용.)
   놓친 발화는 어떤 스킬이 왜 매칭됐어야 하는지 근거 명시. `signal.gold > 0` 은 사용자가 바로 다음 턴에
   그 슬래시를 직접 입력한 근거라 가장 강하다. `skill_type` 이 orchestrator/guide 면 단발 프롬프트에서
   언어와 무관하게 잘 발화하지 않는 유형이므로 description 결함으로 단정하지 말고 "진입점(커맨드) 부재" 가설을 함께 적는다
   (`signal.chain` 은 그 오케스트레이터가 다루는 연쇄를 사용자가 수동으로 반복했다는 뜻 — `via: "orchestrate"` 는 그 연쇄만이 근거인 경우).
   `models`(근거 턴의 모델 분포 — 다이제스트가 있는 턴만 센다)가 하위 티어에 몰려 있으면 모델 티어 가설도 함께 적는다
2. **user-only 스킬 진단**: 호출 전부가 trigger=user인 스킬 — 모델이 자율 선택하지 못하는
   description 발견가능성 문제의 신호. why 코퍼스와 대조해 원인 가설 제시
3. **미사용 자산 분류**: 신생(추가된 지 얼마 안 됨 — git log 참조) / 중복(유사 스킬이 흡수) /
   사장(용도 소멸) 3분류. 분류 근거로 해당 SKILL.md description을 직접 읽어 인용
4. **오귀속·품질 이슈**: unknown_called, trigger null 급증, 로드 0 스킬(호출 후 result
   부재)·취소 비율이 높은 스킬(`outcome.cancelled`) 등 계측 자체의 개선점. 단 unknown_called는 **인벤토리 밖 호출**의 총칭이다 —
   번들 스킬(claude-in-chrome, update-config 등)·타 마켓플레이스 스킬이 정상적으로 여기 잡히므로,
   네임스페이스 드리프트·개명 흔적으로 판정하려면 이름이 인벤토리의 기존 자산과 유사한지 먼저 대조하라
5. **교정 신호 판정**: `followups`(스킬/에이전트 호출 직후의 평문 프롬프트 쌍)를 교정("그게
   아니라"·재작업 지시·불만·번복) vs 정상 후속 질문으로 분류. 교정으로 판정되면 그 자산은
   발화는 됐으나 **수행이 기대와 어긋난** 1급 개선 신호다 — description(발견가능성)이 아니라
   스킬 본문(절차·함정)의 결함 가능성을 우선 검토한다 (hermes-agent의 "frustration =
   first-class skill signal" 이식)

### Phase 4: 개선 제안 라우팅
판정 결과를 유형별 제안서로 산출한다 — **파일은 일절 수정하지 않는다** (retro (c)형 계약).

입력은 Phase 3 에서 판정한 `recommendations.items` 다 — 순서(랭킹)와 유형별 상한을 그대로 따르고, 각 제안에
추천 `id`(`sha1(type|target)`)와 `evidence_n`(근거 세션 수)을 붙인다(다음 단계 수락·거절 피드백의 키).
`status: resurfaced` 는 재노출임을 명시한다 — `resurfaced_from` 이 `rejected`·`snoozed` 면 근거가 2배 이상 늘었거나 쿨다운이
지난 것, `expired` 면 응답 없이 30일이 지난 제안을 다시 내는 것이다.

| 유형 | 신호 | 제안 형식 |
|------|------|----------|
| **(a) description 튜닝** | `missed` 항목과 그 `tune` 하위 제안(`item.tune`), `tune` 항목(`terms` 는 description 에 없는 프롬프트 용어 — Use when 추가안 재료, `reason: no_use_when` 은 Use when 절 부재. tune 근거는 프롬프트 텍스트 근거만이라 orchestrate 경유(`signal.chain`) 세션엔 붙지 않는다), user-only 스킬 | 대상 SKILL.md 경로 + 현재 description + 수정안 + 근거 턴 인용(`items[].evidence`). 적용 후 검증은 skill-creator eval 권고 |
| **(b) 사장 자산 정리** | 미사용 + 사장 분류, lifecycle stale/archive 후보 | `workflow:deprecation-guide` 절차로 넘길 후보 목록 + idle_days 근거 (전이 실행은 사용자 승인 후) |
| **(c) 하네스 구조** | `orchestrate` 항목(`chain:` 스킬 연쇄 / `flow:` 툴 흐름 n-gram 의 반복), 미발화가 스킬 부재 때문(기존 스킬로 커버 불가) | 신규 스킬/훅 후보 메모 — 스캐폴딩은 `harness:create-flow` 소관(`chain:` 연쇄를 맡을 오케스트레이터는 Phase 6 의 5번 라우팅), 여기서는 후보 식별까지 |
| **(d) 계측 개선** | trigger null·조인 실패·표본 편향 | observe 플러그인 자체 개선 항목 (훅 버그는 플래그만 — 무단 수정 금지 원칙) |

제안 공통 규율 (hermes-agent 학습 루프 이식 — .planning/hermes-research.md):
1. **read-before-write**: (a) description 수정안·(c) 스킬 후보 메모는 **대상 파일을 Read한 후에만**
   작성한다 — 트레이스 요약·인벤토리 id만 보고 초안을 쓰지 않는다
2. **update-over-create 4단 강등**: (c) 신규 스킬 후보는 ①기존 스킬 patch로 해소 가능한가 →
   ②기존 스킬 references/ 추가로 충분한가 → ③둘 다 불가한 class-level 공백인가를 순서대로
   기각한 뒤에만 제안한다. ④이름이 이번 관측 기간에만 유효하면(세션 아티팩트명) 후보 자체를 기각
3. **부정 주장 금지**: "X 스킬은 작동 안 함" 류 판정은 제안서에 쓰지 않는다 — 계측된 사실
   (로드 수·턴 결과 분포·조인 실패율)과 개선 가설만 기록한다 (부정 주장은 환경이 고쳐진 뒤에도 남는 부채)

### Phase 5: 보고
하네스 건강 요약(호출 집중도·커버리지·발화 정확도·계측 품질)과 제안 목록을 표로 제시하고,
제안 적용은 사용자 승인 후 별도 작업임을 명시한다. 표본이 부족했다면 재실행 주기를 함께
안내한다 — 통상 2주 뒤 `/observe-report --window 14`가 적절하며, 정기 실행은 전용 하네스를
만들지 말고 기존 `/loop`·`/schedule`을 재사용한다(하네스 신설은 반복이 입증된 뒤에).

### Phase 6: 피드백 수집 (추천 ID 별 응답)
보고 끝에서 `recommendations.items` 의 각 추천에 대해 사용자에게 응답을 받는다 — 상태 전이는 사용자의 명시 응답으로만 일어난다.
1. **대상**: 이번에 보여 준 항목의 `status` 로 고른다 — `proposed` 와 `resurfaced`(`resurfaced_from` 무관)는 `.tracer/recommendations.jsonl` 에
   created 가 이미 있으니 어떤 실행(`--window`·`--no-record`·임계 오버라이드 포함)이든 묻는다. `new` 는 이번 실행이 기록했을 때만 묻는다
   (`.tracer/` 가 있고 `--window`·`--all`·`--trace`·`--no-record`·임계 오버라이드·`--candidates 0` 이 아닌 실행 — 그러면 created 가 append 된다. `recommendations.record_error` 가 있으면 뺀다).
   거절·보류 뒤 재노출은 새 제안 회차다 — 기록하지 않은 실행에서 본 재노출은 응답 CLI 가 근거 수를 모르므로 3번에서 `<id>@<evidence_n>` 으로
   넘겨 집계기가 응답 앞에 새 회차 created 를 쓰게 한다(앞 회차의 응답을 덮지 않게).
   `recommendations.recorded` 는 이번에 새로 append 한 created **건수**일 뿐 대상 목록이 아니다 — 재실행에서 0 이어도 `proposed` 항목은 묻는다.
   `.tracer/` 가 없거나(`--all`·`--trace` 포함) 대상이 하나도 없으면(전부 기록 안 된 `new`) "응답을 남길 수 없는 실행"이라고
   한 줄 알리고 이 단계를 건너뛴다
2. **질문**: 추천마다 `id`·유형·대상·Phase 3 판정 한 줄을 보여 주고 수락 / 거절 / 보류 / 건너뛰기 중 하나를 묻는다
   (AskUserQuestion 이 있으면 그것으로, 없으면 번호 목록으로 한 번에). 판정이 "기각"이었던 항목도 그대로 묻는다 — 기각 판정은
   사용자 응답이 아니다. 응답을 대신 추정하거나 git diff 로 수락을 추론하지 않는다 — 반영 사실은 커밋의 `Observe-Rec: <id>` trailer 로만
   결정론으로 읽는다(그러면 `applied` 로 계산되어 다시 묻지 않는다. 옛 "암묵 수락" 백로그를 대체)
3. **기록**: 답한 것만 한 번에 `node ${CLAUDE_PLUGIN_ROOT}/bin/observe-report.js --accept <id,…> --reject <id,…> --snooze <id,…>`
   로 append 한다 — `status: resurfaced` 항목은 ID 를 `<id>@<evidence_n>`(보여 준 항목의 근거 수)으로 쓴다(건너뛰기는 아무것도 쓰지 않음 — 응답 없는 제안은 30일 뒤 만료로 계산된다). 모르는 ID·한 ID 에 서로 다른 응답이면
   집계기가 exit 1 로 아무것도 쓰지 않는다 — 출력 한 줄을 사용자에게 그대로 전한다
4. **확인**: 집계기가 출력한 `<id> → <상태>` 줄(거절·보류는 쿨다운 끝 날짜 포함)을 보여 준다. 상태·precision 은 다음
   리포트가 append-only 이벤트에서 다시 계산한다(파일을 고쳐 쓰지 않는다)
5. **다음 단계 라우팅**: 수락한 추천마다 넘길 곳과 브리프를 보여 주고 끝낸다 — 반영은 사용자가 그 스킬을 불러 별도 작업으로 한다
   (이 커맨드는 여전히 파일을 고치지 않는다). 넘길 곳이 세션의 스킬 목록에 없으면(`harness`·`workflow` 플러그인 미설치) 브리프만
   보여 주고 끝낸다 — observe 는 harness 에 의존하지 않는다

   | 수락 항목 | 다음 단계 |
   |----------|----------|
   | `missed`·`tune` (대상의 `tune` 하위 제안 포함) | `harness:evolve` — description 조정, 1변경 1커밋 |
   | `missed` 중 `signal.chain` 이 있는 항목(연쇄가 기존 호스트 오케스트레이터로 라우팅됨) | `harness:evolve` — 그 오케스트레이터 |
   | `orchestrate` `chain:` | 연쇄를 흡수할 기존 오케스트레이터가 있으면 `harness:evolve`, 새로 만들어야 하면 `harness:team-harness` (Phase 3 에서 판정) |
   | `orchestrate` `flow:` | `harness:create-flow` — 신규 스킬/훅 후보(Phase 4 (c)) |
   | `inventory.lifecycle` 의 `stale`·`archive_candidates` (추천 ID 가 없어 응답 없이 Phase 4 (b) 후보로 넘긴다) | `workflow:deprecation-guide` — `id`·`kind`·`last_used`·`idle_days` |

   브리프(추천 ID 가 있는 항목 — 원문 프롬프트는 싣지 않는다):
   ```
   추천: <id> · <type> · 근거 세션 <evidence_n>
   대상: <target> → <Phase 3 에서 Read 한 원본 파일 경로 — 플러그인 레포 소스. 설치 캐시 경로는 넘기지 않는다>
         (orchestrate 면 연쇄 원소와 흡수 후보 오케스트레이터)
   현재 description 요지: <Read 한 description 한두 줄>
   수정안 재료: <Phase 3 판정 한 줄> · terms <item.tune.terms 또는 tune 항목의 terms — 있을 때> · reason <no_use_when 이면 Use when 절 부재>
   근거 ref: <evidence 의 session#turn 최대 3개>
   반영 커밋: 본문 끝 trailer 에 Observe-Rec: <id> (여러 개면 한 줄에 하나) — 이 줄이 있어야 다음 리포트가 그 추천을
             applied 로 보고 전후 효과를 잰다(Phase 2 의 8번). trailer 는 이 레포의 HEAD 에서 닿는 커밋에서만 읽힌다
   ```

## Tool Coordination
- **Bash**: `node ${CLAUDE_PLUGIN_ROOT}/bin/observe-report.js --json [--window N]` — 결정론 집계,
  Phase 6 의 `--accept/--reject/--snooze <id>` — 사용자가 답한 응답 기록
- **Read**: 판정 대상 SKILL.md·커맨드 md의 frontmatter description — 미발화 judge·미사용 분류 근거
- **Glob**: 인벤토리 경로 확인 보조 (`plugins/*/skills/*/SKILL.md`)
- **Grep**: why 코퍼스에서 특정 스킬 언급 탐색 — user-only 원인 가설 보강

## Examples

### 기본 리포트
```
/observe-report
# 집계 → 해석 → 제안까지 전체 흐름. 트레이스 없으면 OBSERVE_TRACE 활성화 안내 후 종료
```

### 최근 2주만, 집계만
```
/observe-report --raw --window 14
# 최근 14일 결정론 집계 JSON만 출력 — 해석·제안 생략 (외부 도구 연계용)
```

### 스킬 발화 정확도에 집중
```
/observe-report --focus skills
# 미발화 판정과 user-only 스킬 진단 중심으로 해석 — 에이전트/프롬프트 절은 요약만
```

## Boundaries

**Will:**
- observe-report.js 결정론 집계를 실행하고 결과를 해석 가능한 표로 보고
- 미발화 후보를 스킬 description과 대조해 "놓친 발화" vs "스킬 불필요"로 판정
- description 튜닝 제안서·사장 자산 후보·신규 스킬 후보·계측 개선 항목을 산출
- 표본 부족·트레이스 부재를 명시하고 과잉 일반화를 방지
- 수락한 추천의 다음 단계(`harness:evolve`·`harness:team-harness`·`workflow:deprecation-guide`)와 `Observe-Rec` trailer 를 담은 브리프 제시

**Will Not:**
- SKILL.md·커맨드·훅 등 어떤 파일도 수정하지 않음 — 제안서 산출까지만 (적용은 사용자 승인 후 별도 작업).
  예외는 집계기가 observe 자기 저장소 `.tracer/recommendations.jsonl` 에 남기는 추천 생성 이벤트와, Phase 6 에서 사용자가
  명시로 답한 응답의 status 이벤트(둘 다 원문 없음, append-only)뿐
- 사용자 응답 없이 수락·거절·보류를 기록하지 않음 — 판정(Phase 3)이나 제안 적용 여부로 응답을 대신하지 않는다
- 비용/토큰/tool_decision 계측을 하지 않음 — 이 커맨드의 범위 밖
- 발화율 사전 벤치마크(트리거/비트리거 쿼리 eval)를 수행하지 않음 — skill-creator eval 소관
- OBSERVE_TRACE를 자동 활성화하지 않음 — 프롬프트 원문이 기록되는 opt-in은 사용자 결정
- 훅 로직 버그를 직접 수정하지 않음 — 플래그 후 별도 결정 (저장소 원칙)

## Related
- `observe` 훅 (`bin/hooks/adapters/claude/trace-{session,prompt,skill,agent,result,tool,stop}.js`) — 이 리포트의 데이터 생산자
- `harness:evolve` — 수락한 `missed`·`tune`·호스트 오케스트레이터 연쇄의 반영 소관(1변경 1커밋, `Observe-Rec` trailer)
- `harness:team-harness` — 새 오케스트레이터가 필요한 `orchestrate` 연쇄의 설계 소관
- `workflow:deprecation-guide` — (b) 사장 자산 후보의 폐기 절차 소관
- `harness:create-flow` — (c) 신규 스킬/훅 후보의 스캐폴딩 소관
- `workflow:retro` — 세션 일화 기반 교훈 라우팅 (본 커맨드의 데이터 기반 보완재)
- 공식 `skill-creator` eval — description 수정안의 사전 발화율 검증 경로 (외부: anthropic-agent-skills 마켓 소속, 이 마켓플레이스에 없음 — 미설치 시 이 검증 단계는 생략)
