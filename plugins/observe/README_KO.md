> [English](README.md) · **한국어**

# observe

> 하네스가 실제로 어떻게 쓰이는지(어떤 스킬·에이전트가 왜 발화했고 각 턴이 어떻게 끝났는지) 계측하고, 그 결과를 개선 제안으로 되돌린다. 제안만 하고 파일은 고치지 않는다.

## 개요

`observe` 는 레포마다 각 프롬프트가 어떤 스킬·에이전트를 호출했는지, 왜 호출했는지, 그 턴이 어떻게 끝났는지를 기록한다. 턴 결과는 `committed`·`cancelled`·`corrected`(교정 후보)·`failed`·`unknown` 가운데 하나다. 훅과 transcript 리더가 모든 기록을 `<repo>/.tracer/` 에 쓴다. `/observe-report` 는 결정론 집계를 돌리고 LLM 이 해석하게 한 뒤 제안을 만든다: 놓친 발화, description 튜닝 초안, 정체·사장 자산, 오케스트레이션 후보, 계측 공백. 파일은 일절 수정하지 않고 제안까지만 산출한다. 유일한 쓰기는 자기 저장소 `.tracer/recommendations.jsonl` 에 원문 없는 이벤트를 append 하는 것이다. 사용자가 제안마다 수락·거절·보류로 답하면 그 응답이 다음 리포트를 조정하는 피드백이 된다.

Nous Research 의 Hermes Agent 는 경험에서 스킬을 **생성**하며 자란다. observe 는 반대로 평가 우선 경로를 택한다. **이미 만든** 하네스가 설계대로 발화하는지, 그 턴이 성과로 이어지는지 확인하고 수정을 제안한다. Hermes curator 의 결정론 절반을 이식했다: 사용 라이프사이클(stale ≥30일, archive 후보 ≥90일)과 교정 신호.

Claude Code 의 `/usage` 는 스킬·서브에이전트·MCP 별 사용량을 한 시점에서 보여 준다. observe 는 여기에 각각이 발화한 이유, 그 턴이 끝난 방식, 놓친 발화, 교정 신호를 더하고, 트레이스를 남겨 세션을 넘어 결과가 쌓이게 한다.

프롬프트 원문이 로컬에 저장되므로 기록은 **opt-in**(`OBSERVE_TRACE=1`)이다. 설정하지 않으면 모든 훅이 즉시 끝난다.

## 구성요소

### 커맨드

| 커맨드 | 하는 일 |
|---|---|
| `/observe-report` | 하네스 건강 리포트: 집계 → 해석 → 제안 → 추천 ID 마다 사용자 응답 요청. 옵션: `--raw`(집계 JSON 만), `--window <days>`, `--focus skills\|agents\|prompts`, `--stale-days`/`--archive-days`, `--followups <n>`, `--all`(등록된 모든 레포 합산, 원문 제외), `--theta`/`--margin`/`--min-sample`/`--orch-min`(실험용, 기록 안 함), `--no-record`. |
| `/observe-git-hooks` | opt-in 커밋 경계 git 훅: `install [--no-pre-commit] [--trailer]`, `uninstall`, `status`, `print <hook>`. |

### Claude Code 훅 (`hooks/hooks.json`)

훅은 stdout 에 아무것도 내지 않고(컨텍스트 오염 0) 항상 `exit 0` 으로 끝나므로, 계측이 실패해도 작업을 막지 않는다. `OBSERVE_TRACE` 가 켜져 있지 않으면 아무것도 하지 않고, observe 가 자기 자식 프로세스에 거는 `OBSERVE_CHILD=1` 이면 즉시 돌아간다.

| 이벤트 (matcher) | 스크립트 (`bin/hooks/adapters/claude/`) | 기록 |
|---|---|---|
| `SessionStart` | `trace-session.js` | `session_start`(source, 플러그인 설치 루트 — 미사용 자산 목록의 분모). 마감되지 않은 이전 세션도 따라잡는다. |
| `UserPromptSubmit` | `trace-prompt.js` | `prompt`(이벤트에는 메타만, 원문은 `raw/`) |
| `PreToolUse` (`Skill`) | `trace-skill.js` | `skill_use`: 이름, trigger(user/model), 턴 앞부분(`why`), `tool_use_id` |
| `PreToolUse` (`Agent\|Task`) | `trace-agent.js` | `subagent`: 유형, why, description·프롬프트 앞부분(`raw/`) |
| `PostToolUse` (`Skill\|Agent\|Task`) | `trace-result.js` | `tool_result`: `response_bytes`, 소요 시간. Skill 의 결과는 스킬 본문이 **로드**될 때 찍히므로, 리포트는 이를 완주가 아니라 `loaded` 라고 부른다. |
| `PostToolUse`/`PostToolUseFailure` (`*`, async) | `trace-tool.js` | `tool_call` 카운터. `OBSERVE_TRACE_SCOPE=tools` 일 때만 쓰고, 아니면 stdin 을 읽기 전에 끝난다. Codex 에서는 스킬·`spawn_agent` 감지도 맡는다(런타임 절 참고). 플러그인 훅은 env 로 조건부 등록할 수 없어서, 툴 호출마다 node 프로세스(약 20–30ms, async·비차단)가 여전히 뜬다. |
| `Stop` | `trace-stop.js` | **턴 다이제스트**(`turn_summary`), transcript 커서부터 증분으로 읽는다. 기록만 한다: 막지 않고, decision 이나 컨텍스트를 내지 않으며, `stop_hook_active` 면 즉시 끝난다. |
| `SessionEnd` | `trace-session.js` | `session_end` 를 남기고, detached worker 가 세션을 마감한다(마지막 턴 + `session_summary`). |

matcher 는 툴 이름 regex 만 쓴다(표현식 matcher 는 발화하지 않음, 2026-07 실측). 더 세밀한 필터는 스크립트 안에서 한다.

### CLI (`bin/`)

| CLI | 용도 |
|---|---|
| `observe-report.js` | `/observe-report` 의 결정론 집계기(`--json` 또는 한국어 텍스트). LLM 판정은 하지 않는다. 피드백 응답 기록도 맡는다(피드백 루프 참고). |
| `observe-backfill.js` | 작업 디렉터리가 이 레포인 지난 Claude Code·Codex·Antigravity 세션을 다이제스트로 만든다: `[--root] [--runtime claude\|codex\|antigravity\|all] [--claude-dir <dir>]… [--codex-dir <dir>]… [--antigravity-dir <dir>] [--dry-run] [--json]`. 여러 번 돌려도 결과가 같다. |
| `observe-migrate.js` | 1.x → 2.0 일회성 이전, `.claude/skill-trace.jsonl(.1)` 을 `.tracer/` 로 옮긴다: `[--root] [--dry-run]`. 구 파일은 지우지 않고 `*.migrated` 로 이름만 바꾼다. |
| `observe-git-hooks.js` | `/observe-git-hooks` 의 설치기. |
| `observe-export.js` | 집계 JSON(stdin)을 `wiki-ops:wiki-harness-feed` 용 위키 스냅샷(stdout)으로 바꾼다. 입력에 원문 필드가 하나라도 있으면 `exit 2` 로 거부한다(fail-closed). |

### 동작 방식

- **턴 다이제스트**(`adapters/claude/transcript.js`, `_lib/digest.js`). 턴은 `promptId` 로 나눈다. 각 `turn_summary` 에는 툴 흐름 `seq_compact`(예: `S1>B(other)2>B(git)2`), 개수, 실패·인터럽트·거부, 실행 종류, 편집 파일(레포 상대경로, ≤20), 스킬, 서브에이전트, 커밋·푸시, 토큰(message id 로 중복 제거), 모델, effort, 소요 시간이 담긴다. `outcome` 은 아래 우선순위로 고른다:
  1. `committed`: 턴에 커밋 SHA 가 있다.
  2. `cancelled`: `[Request interrupted by user…]` 마커가 있거나, 도구 거부 뒤 진행이 없다.
  3. `corrected`: 스킬·에이전트 턴 뒤에 평문 프롬프트가 온다. 후보일 뿐이고 판정은 LLM 단계가 한다.
  4. `failed`: 툴 결과의 절반 이상이 실패했다.
  5. `unknown`: 위 어디에도 해당하지 않는다.

  시스템 주입 턴(task notification, `!` bash 모드)은 `prompt_kind` 를 달고 outcome 집계에서 빠진다. 각 턴은 한 턴 늦게(다음 Stop·SessionEnd·따라잡기 때) 확정되고, 쓰기는 `(runtime, session, turn)` 기준 upsert-skip 이라 같은 턴을 두 번 쓰지 않는다.
- **커밋 SHA**. 다이제스트는 `gitOperation.commit` → stdout 의 `[branch sha]` 줄 → 성공한 `git commit` 실행 구간의 `git log --all --reflog` 순으로 SHA 를 찾는다. `git-log`/`git-log-weak` 경로는 휴리스틱이고, 그렇다고 표시된다.
- **추천 엔진**(`bin/lib/match.js`, `recommend.js`). BM25 로 각 프롬프트를 스킬·커맨드 description 과 맞춘다. 한글은 문자 bigram, 영문은 단어 단위다. 따옴표 문구의 가중치가 가장 크고, 그다음 `triggers:`, "Use when", 산문 순이다. 엔진이 내는 유형은 세 가지다:
  - `missed`: 스킬을 쓰지 않고 확정된 턴인데 top1 ≥ θ(10)이고 margin ≥ 3 이거나, 골드 라벨이 있는 경우(다음 사람 턴이 그 슬래시 커맨드를 호출).
  - `tune`: description 에 없는 프롬프트 용어.
  - `orchestrate`: 3개 이상 세션에서 반복되는 연쇄나 툴 흐름.

  노이즈 제한: 사람 프롬프트 20개 미만이면 추천하지 않고, 근거는 세션당 1회만 세며, 원오프는 버리고, 유형당 최대 3개다. ID 는 `sha1(type|target)` 이고 `.tracer/recommendations.jsonl` 에 append 된다(append-only, 원문 없음).
- **피드백 루프**. `/observe-report` 는 마지막에 추천 ID 마다 응답을 묻고, 그 응답만 `observe-report.js --accept|--reject|--snooze <id>[,<id>…]`(`--snooze-days <n>`, 양의 정수)로 기록한다. 재노출 항목은 `<id>@<evidence_n>` 으로 넘겨, 기록하지 않은 실행에서 본 것이어도 응답이 늘 새 회차가 된다. 모르는 ID 나 서로 다른 응답이 섞이면 아무것도 쓰지 않고 exit 1 이다. 상태는 `proposed`·`accepted`·`rejected`(30일 쿨다운, 근거가 2배가 되면 일찍 재노출)·`snoozed`(기본 7일)·`expired`(30일 무응답, 기록하지 않고 계산으로 얻는 파생 상태) 가운데 하나다. 명시 응답만 기록한다. 리포트 머리에는 응답이 10건 이상일 때 유형별 `precision = 수락 / (수락 + 거절)` 을 보여 주고, 그보다 적으면 `표본 부족` 으로 표시한다. θ, margin, 만료 기간, 최소 분모는 수동 상수이고 자동 보정은 없다.
- **호환 reader**(`bin/lib/reader.js`). `.tracer/` v1 과 구 경로 `.claude/skill-trace.jsonl(.1)` v0 을 한 스트림으로 읽는다. 구 경로 폴백은 2.x 메이저 내내 유지한다.

## 세팅

설정은 **다음에 새로 시작하는 세션부터** 적용된다. 이미 열린 세션에는 반영되지 않는다.

### 1. Claude Code

전역(모든 프로젝트)은 `~/.claude/settings.json` 에 넣는다:

```json
{ "env": { "OBSERVE_TRACE": "1" } }
```

프로젝트별로는 같은 키를 `<project>/.claude/settings.local.json`(개인) 또는 `.claude/settings.json`(팀 공유)에 넣는다. 프로젝트 설정이 전역보다 우선하므로, 민감한 레포 하나만 끄려면 `"OBSERVE_TRACE": "0"` 을 쓴다. 셸에서 `export OBSERVE_TRACE=1` 을 해도 된다.

| 변수 | 효과 |
|---|---|
| `OBSERVE_TRACE=1` | 기록을 켠다(`1`·`true`·`on`·`yes` 를 받는다). |
| `OBSERVE_TRACE_SCOPE=tools` | 툴별 `tool_call` 카운터도 쓴다. |
| `OBSERVE_LLM=1` | git post-commit worker 가 `commits/<sha>.md` 에 LLM 절을 붙이게 한다. |
| `OBSERVE_LLM_DAILY=<n>` | 그 LLM 호출의 일일 상한(기본 5). |
| `OBSERVE_CHILD=1` | observe 가 자기 자식 프로세스에 건다. 모든 훅이 즉시 끝난다. |

### 2. Codex (선택)

Codex 는 같은 `hooks/hooks.json`(Claude 형식 플러그인 훅)을 읽는다. 설정 순서:

1. Codex 에도 플러그인을 설치한다.
2. `/hooks` 에서 훅을 신뢰한다. 신뢰는 훅 해시에 묶이므로 업데이트할 때마다 다시 신뢰해야 한다.
3. 환경에 `OBSERVE_TRACE=1` 을 넣어 Codex 를 띄운다(예: `OBSERVE_TRACE=1 codex`).

Codex 는 `async` 훅을 동기로 돌린다. 그래서 훅을 신뢰하면 `OBSERVE_TRACE` 가 없어도 `*` PostToolUse 훅이 Codex 툴 호출마다 node 기동 1회(약 20–30ms)를 더한다. 이 비용을 없애려면 `/hooks` 에서 그 훅을 끄거나 신뢰를 해제한다.

### 3. Antigravity 와 지난 Claude Code·Codex 세션 (백필)

Antigravity 에는 훅이 없다. 그 transcript(`~/.gemini/antigravity-cli/brain/`), Codex rollout(`~/.codex/sessions`, `~/.codex/archived_sessions`), 훅을 켜기 전에 쌓인 이 레포의 Claude Code transcript(`~/.claude/projects/<인코딩된 레포 경로>/*.jsonl`)는 다음 명령이 읽는다:

```sh
node <observe>/bin/observe-backfill.js            # 이 레포 세션만, 여러 번 돌려도 안전
node <observe>/bin/observe-backfill.js --dry-run  # 개수만 센다
```

세션 기록 파일이 30분 넘게 유휴일 때만 그 세션을 마감한다. 진행 중인 세션은 마지막 사람 턴을 보류한다. Codex Desktop 이 외부 세션을 가져온 것(`external-import-turn-N` 턴, 또는 `<EXTERNAL SESSION IMPORTED>` 마커)은 같은 작업을 두 번 세지 않도록 건너뛰고 세션마다 stderr 한 줄로 알린다. `.jsonl.zst` rollout 은 `zstd` CLI 가 있어야 읽고, 없으면 건너뛰고 보고한다. `/observe-report` 전에 백필을 돌린다.

### 4. git 훅 (선택, 레포별)

```
/observe-git-hooks install             # post-commit + 비차단 pre-commit
/observe-git-hooks install --trailer   # Agent-Session trailer 도 추가 (기본 꺼짐)
/observe-git-hooks status | uninstall
```

- **post-commit** 은 HEAD 를 detached 분석기에 넘기고 바로 끝난다. 분석기는 `commit` 이벤트(`events/git-hook/<YYYY-MM>.jsonl`)를 append 하고 `.tracer/commits/<sha>.md` 를 쓴다: 제목, 변경 파일, 귀속된 세션·턴, 그 턴의 툴 흐름, 미처리 추천. 원문은 없다.
- **귀속 우선순위**:
  1. transcript SHA 일치.
  2. `Agent-Session` trailer.
  3. 훅 환경의 `CLAUDE_CODE_SESSION_ID`.
  4. 사람 커밋이면, 직전 2시간 안에 끝난 턴 가운데 편집 파일이 커밋과 가장 많이 겹치는 턴.
- **pre-commit** 은 캐시에서 미처리 추천을 결정론 1줄로 stderr 에 낸다. LLM 을 쓰지 않고 커밋을 막지 않는다.
- **기존 훅**은 hooks 디렉터리 안의 `observe-orig/<hook>` 으로 옮긴다. 기존 훅이 먼저 돌고 그 종료코드가 그대로 반환된다. `uninstall` 은 바이트 그대로 되돌린다.
- `core.hooksPath`·husky·lefthook 이 있으면 아무것도 설치하지 않는다. 대신 `print <hook>` 출력을 그 도구의 훅에 넣는 방법을 안내한다.
- 측정 비용(임시 레포, 교대 40쌍): `git commit` 이 p95 기준 약 30ms 늘어난다.
- 터미널에서 하는 사람 커밋은 그 셸에도 `OBSERVE_TRACE=1` 이 있어야 기록된다. `settings.json` 의 `env` 는 Claude Code 안에만 적용되기 때문이다.
- 훅에는 플러그인의 절대경로가 박힌다. `/plugin update` 뒤에는 `status` 가 stale 로 보고하므로 `install` 을 다시 실행한다.

### 5. 1.x 에서 올리기

구 경로 `.claude/skill-trace.jsonl` 은 계속 v0 으로 읽히므로 이력을 잃지 않는다. `.tracer/` 로 옮기려면 `node <observe>/bin/observe-migrate.js` 를 한 번 실행한다.

## 사용법

평소대로 작업하면 기록이 `<repo>/.tracer/` 에 쌓인다. 트레이스가 어느 정도 쌓이면 다음을 실행한다:

```
/observe-report                    # 집계 → 해석 → 제안 → 사용자 응답
/observe-report --raw --window 14  # 최근 14일, 집계 JSON 만
/observe-report --focus skills     # 놓친 발화·사용자 전용 스킬 진단
/observe-report --all              # 등록된 모든 레포 (원문 없음, 턴별 판정 없음)
```

트레이스가 비어 있으면 리포트는 기록을 켜는 방법을 안내하고 끝난다. 세션이 5개 미만이면 해석에 표본 부족 경고가 붙는다. 제안마다 대상 파일, 현재 description, 수정 초안, 근거 턴이 나온다. 제안 적용은 사용자가 승인한 뒤의 별도 작업이다.

## `.tracer/` 레이아웃

```text
<repo>/.tracer/
├── .gitignore                         # "*" — 폴더 전체가 git status 에 안 나온다
├── VERSION                            # 스키마 버전 (1)
├── events/<runtime>/<YYYY-MM>/<session>.jsonl   # 정규 이벤트 — 원문 없음
├── events/git-hook/<YYYY-MM>.jsonl    # commit 이벤트 (git 훅)
├── raw/<YYYY-MM>/<session>.jsonl      # 프롬프트 원문·why·args (레드액션 후) — raw_ref/why_ref 로 참조
├── digests/<YYYY-MM>/<session>.jsonl  # turn_summary / session_summary — 원문 없음
├── cursors/<runtime>/<session>.json   # transcript 증분 오프셋
├── recommendations.jsonl              # 추천 created/status 이벤트 — append-only, 원문 없음
├── commits/<sha>.md                   # 커밋별 분석 (git 훅) — 원문 없음
└── index/                             # 파생물, 지워도 안전 (precommit.txt, llm-budget.json)

~/.tracer/index/repos.d/<sha1(root)>   # --all 용 레포 마커 (레포당 1개, 경로만)
```

`<runtime>` 은 `claude-code`·`codex`·`antigravity` 다. 레포 자체의 `.gitignore` 는 건드리지 않는다. 리포트와 migrate 는 cwd 에서 위로 올라가며 가장 가까운 `.tracer/` 를 찾으므로(git toplevel 에서 멈춤), 하위 디렉터리나 모노레포 패키지에서 실행해도 맞는 저장소를 찾는다.

## 런타임 지원 범위

| 런타임 | 방식 | 턴 키 | 스킬 감지 | 비고 |
|---|---|---|---|---|
| Claude Code | 훅 + transcript 다이제스트 | `promptId` | 명시(Skill 툴) | 전체 지원. |
| Codex | 같은 훅 + rollout 다이제스트(`adapters/codex/rollout.js`), 백필도 가능 | `turn_id` | 휴리스틱: 셸로 `…/skills/<name>/SKILL.md` 를 읽으면 `<plugin>:<skill>` 로 기록 | Skill·Agent 툴이 없어서 `trace-skill`/`trace-agent`/`trace-result` 는 발화하지 않는다. 툴 호출 없이 주입되는 `$skill` 언급은 보이지 않는다. 승인 거부는 모델링하지 않는다. 실 Codex 세션에서 훅을 돌려 보지는 않았다(0.164 바이너리의 훅 스키마로 대조). |
| Antigravity CLI | 백필만(`adapters/antigravity/transcript.js`) | `step:<USER_INPUT index>` | 휴리스틱(Codex 와 같음) | 원천에 토큰·모델·취소 마커가 없다. 레포 루트는 가장 많이 나온 `run_command` Cwd 다. |

휴리스틱 스킬 사용은 스킬을 열었다는 뜻이지 꼭 썼다는 뜻은 아니다. 세션 레포 안에서 스킬 자체 소스를 읽은 것(플러그인을 편집할 때처럼)은 세지 않는다.

## 프라이버시

- `OBSERVE_TRACE` 는 프롬프트 **원문**을 저장한다. 원문은 git 에서 무시되는 `<repo>/.tracer/raw/` 에만 있고, 쓰는 시점에 다음을 레드액션한다: AWS `AKIA…`, `ghp_…`/`github_pat_…`, `sk-…`, `xox[bp]-…`, JWT, PRIVATE KEY 블록, 이메일, IPv4, 홈 경로(→ `~`). 정규식 레드액션은 이름이나 사내 용어를 잡지 못한다. 그래서 원문을 따로 둔다. 자동 만료는 없으니, 지우려면 `raw/` 를 삭제한다.
- 이벤트·다이제스트·추천·커밋 `.md` 에는 이름, 개수, 상대경로, SHA, join 키만 있고 프롬프트·명령·출력 원문은 없다. 툴 결과 본문은 저장하지 않고 `response_bytes` 만 남긴다.
- 전역 층 `~/.tracer/` 에는 레포 경로 마커만 있다. 루트가 홈 디렉터리인 세션은 아예 기록하지 않는다.
- 업로드되는 것은 없다. 예외가 하나 있다: `OBSERVE_LLM=1` 이면 git worker 가 결정론 커밋 `.md`(원문 없음)를 `claude -p` 에 보낸다(도구 없음, 일일 상한). `observe-export.js` 는 원문이 실린 입력을 거부한다.
- OTel(Claude Code 내장 텔레메트리)은 지원하지 않는다: observe 는 OTel 을 읽지도 내보내지도 않는다.

## 의존성

- `requires`: 없음. observe 는 자체 완결형이고 `hook-stdin` 사본을 함께 담고 있다. Node 22 내장 모듈만 쓴다.
- 함께 쓰면 좋은 플러그인: `workflow:deprecation-guide`(사장 자산), `harness:create-flow`(새 스킬·훅 후보), `skill-creator` eval(description 초안을 채택하기 전 발화율 확인), `workflow:retro`(일화 기반 교훈, 상호 보완), `wiki-ops:wiki-harness-feed`(`observe-export.js` 를 거친 위키 스냅샷).

## 참고

- **범위 밖**: 비용 대시보드와 tool_decision 계측(다이제스트는 토큰 합계만 남긴다), description 발화율의 사전 벤치마크(`skill-creator` eval 을 쓴다).
- **헤드리스 슬래시 커맨드**(`claude -p "/command"`)는 Skill 툴을 거치지 않는다. 그래서 그 호출의 근거는 `prompt` 레코드의 `is_command` 플래그뿐이다.
- **제안 전용**: `/observe-report` 는 SKILL.md·커맨드·훅을 수정하지 않는다. 훅 버그도 직접 고치지 않는다. 쓰는 것은 자기 `.tracer/recommendations.jsonl` 에 하는 append 뿐이다: `created` 이벤트와 사용자 응답의 status 이벤트.
- **알려진 공백**: Codex 훅은 실 세션에서 검증하지 않았다. 서브에이전트 커밋은 `CLAUDE_CODE_SESSION_ID` 로만 귀속된다. post-commit 이 발화하지 않는 커밋(예: `git merge`)은 transcript 다이제스트로만 잡힌다. `corrected` 는 LLM 단계가 판정하기 전까지 후보다.
