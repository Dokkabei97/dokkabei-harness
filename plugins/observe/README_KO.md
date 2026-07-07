> [English](README.md) · **한국어**

# observe

> 하네스의 실사용을 훅으로 상관 로깅하고, 그 계측 결과를 개선 제안으로 되돌리는 관측·개선 플러그인.

## 개요

`observe`는 "어떤 프롬프트에서 어떤 스킬/에이전트를 **왜** 호출했고, 그 호출이 **완주**했는가"를 훅으로 상관 로깅해 하네스 자체의 건강을 진단한다. 6종의 훅이 세션 시작·프롬프트·스킬 호출·에이전트 호출·호출 결과·세션 종료를 각각 `.claude/skill-trace.jsonl`에 append하고, `session_id`·`prompt_id`·`tool_use_id`를 join 키로 삼아 프롬프트↔스킬↔에이전트↔결과↔세션 경계를 사후 결합한다. 축적된 트레이스는 `/observe-report`가 "결정론 집계(스크립트) → 해석(LLM) → 개선 제안서" 순으로 풀어내되, **파일은 일절 수정하지 않고 제안까지만** 산출한다.

observe의 존재 이유는 hermes agent와의 대비로 명확해진다. hermes agent가 사용자 행동에
기반해 스킬/하네스를 **자율적으로 생성하며** 발전해 나가는 생성형 진화라면, observe는 그 반대편에서
**이미 구축된 하네스**가 실사용에서 잘 호출되고 있는지를 계측하고, 그 계측 데이터를 근거로 하네스를
스스로 개선하는 **계측 기반 개선 루프**다. 새로운 자산을 만들어 늘리는 쪽이 아니라, 있는 자산이
설계 의도대로 발화·완주하는지 실측하고 description 튜닝·사장 자산 정리·계측 공백 보완으로
되먹임하는 쪽이 이 플러그인의 몫이다.

설계 의도는 명확한 경계에 있다. 이 플러그인은 **실사용 텔레메트리의 사후 진단** 전용이다. 비용/토큰/tool_decision 계측은 Claude Code 내장 OTel(`CLAUDE_CODE_ENABLE_TELEMETRY`)에 위임하고, description 발화율의 사전 벤치마크는 `skill-creator` eval 소관으로 넘긴다 — 서로 겹치지 않는 직교 보완재다. 또한 프롬프트 원문을 기록하는 특성상 `OBSERVE_TRACE=1` opt-in일 때만 동작하므로, `mvp`·`feature-loop` 같은 다른 루프형 플러그인에는 기본적으로 아무 영향을 주지 않는다.

Claude Code 네이티브 `/usage`는 최근 사용을 스킬·서브에이전트·MCP별로 분해한다 — observe는 그 지점에서 겹치되 더 깊이 간다: 각각이 *왜* 발화했는지, *완주*했는지, 놓친 발화, 사용 라이프사이클(stale/archive 후보), 교정 신호를 더하고, 트레이스를 지속 축적해 한 시점의 스냅샷이 아니라 세션을 넘어 복리로 쌓는다.

v1.3.0은 hermes-agent curator의 **결정론 절반만** 집계기에 이식했다: 사용 라이프사이클 후보(마지막 관측 사용 기준 stale ≥30일 / archive ≥90일, 임계 조정 가능, 테스트용 `--now` 주입)와 교정 후보 쌍(`followups` — 스킬/에이전트 호출 직후의 평문 프롬프트, 교정 여부 판정은 LLM 단계에서만). 상태 전이는 여전히 제안-온리다. 생성형 결합(스킬 자동 생성·수정)을 도입한다면 전제 조건도 hermes에서 온다: agent-created 자산의 별도 네임스페이스/마킹 격리, 삭제 금지(아카이브만), read-before-write — 셋이 갖춰지기 전까지 observe는 평가형에 머문다.

## 구성요소

### 커맨드

- `/observe-report` — skill-trace 텔레메트리 기반 하네스 건강 리포트. 결정론 집계(스킬/에이전트별 호출수·user/model 트리거 비율·완주율·소요시간, 미사용 자산, 미발화 후보 턴)를 실행한 뒤, 그 후보를 스킬 description과 대조해 "놓친 발화" vs "스킬 불필요"로 판정하고, description 튜닝안·사장 자산 후보·신규 스킬 후보·계측 개선 항목을 제안서로 산출한다. 옵션: `--raw`(집계 JSON만), `--window <days>`(최근 N일), `--focus skills|agents|prompts`, `--stale-days/--archive-days`(라이프사이클 임계), `--followups <n>`(교정 쌍 상한).

### 훅

모든 훅은 `OBSERVE_TRACE=1`일 때만 동작하며, stdout을 내지 않아(컨텍스트 오염 0) 항상 `exit 0`으로 종료한다 — 추적 실패가 스킬/에이전트 실행을 결코 막지 않는다.

- `SessionStart` → `trace-session.js` — 세션 시작(`source`, `plugin_root`=설치 루트 근거)을 `session_start` 레코드로 append. `plugin_root`는 리포트가 미사용 자산의 분모(인벤토리)를 트레이스와 **동일 설치본**에서 열거하기 위한 join 근거다.
- `UserPromptSubmit` → `trace-prompt.js` — 사용자 프롬프트 원문을 `prompt` 레코드로 append(`is_command` 근사 플래그 포함). 이후 스킬 호출과 `session_id`/`prompt_id`로 결합된다.
- `PreToolUse` (matcher `Skill`) → `trace-skill.js` — Skill 호출(skill·args)과 근거(`why`=현재 턴 preamble 추출)·`trigger`(user/model)·`turn_command`(커맨드 연쇄 provenance)·`tool_use_id`(결과 join 키)를 append. matcher는 tool 명 regex이며 표현식(`tool == …`)은 발화하지 않음을 실측 확인(2026-07).
- `PreToolUse` (matcher `Agent|Task`) → `trace-agent.js` — 서브에이전트 호출(`subagent_type`·description·prompt 앞 300자)과 근거(현재 턴 preamble)를 `agent` 레코드로 append. `Agent`는 v2.1.63에서 `Task`가 개명된 툴명이라 양쪽 matcher를 병기(레거시 호환).
- `PostToolUse` (matcher `Skill|Agent|Task`) → `trace-result.js` — 호출 완료를 `result` 레코드로 append. `tool_use_id`로 Pre 레코드와 join해 소요시간을, `response_bytes`로 산출물 유무를 프록시한다(본문은 용량·민감정보상 미기록). PostToolUse는 성공 호출에만 발화하므로 레코드 존재 자체가 완주 신호다.
- `SessionEnd` → `trace-session.js` — 세션 종료(`reason`)를 `session_end` 레코드로 append. 세션 경계·완주 여부('마지막 스킬'과 '로그 절단')를 구분하는 근거다.

### 집계 엔진

- `bin/observe-report.js` — 의존성 없는 결정론 집계기이자 `/observe-report`의 산출 엔진. tolerant reader로 트레이스를 읽어 호출·완주·미사용 자산·미발화 후보·세션 경계 요약을 JSON(`--json`) 또는 한국어 텍스트로 출력한다. LLM 판단(미발화 확정, description 진단)은 하지 않는 것이 이 파일의 계약이다. 인벤토리 분모는 `--plugins-dir` > 트레이스의 `session_start.plugin_root` > 파일 자신의 위치 역산 순으로 결정한다.

## 세팅

트레이스 수집은 opt-in이다 — `OBSERVE_TRACE=1`을 켜야 6종 훅이 동작한다. **전역**(모든 프로젝트)이냐 **프로젝트별**이냐에 따라 설정 파일이 다르며, 설정은 언제나 **다음에 새로 시작하는 세션부터** 적용된다(이미 열린 세션엔 소급 안 됨). 셸 프로필의 `export OBSERVE_TRACE=1`도 동작하지만, 아래 `settings.json` 방식이 세션 스코프가 명확해 권장된다.

### 1. 전역 — 모든 프로젝트에서 추적

`~/.claude/settings.json`의 `env` 블록에 넣는다. 이후 시작하는 모든 세션이 상속한다.

```json
{
  "env": {
    "OBSERVE_TRACE": "1"
  }
}
```

### 2. 프로젝트별 — 이 레포에서만

`<프로젝트>/.claude/settings.local.json`(개인용, `.gitignore`됨) 또는 `.claude/settings.json`(팀 공유, 커밋됨)의 `env`에 같은 키를 넣는다. **로컬이 전역을 이기므로**, 전역으로 켠 뒤 특정 민감 프로젝트만 끄려면 그 프로젝트에서 `"OBSERVE_TRACE": "0"`으로 오버라이드하면 된다.

### 3. 내장 OTel 스택과 함께 — 권장 (교차 검증)

observe는 "**왜**·완주"를, Claude Code 내장 OTel은 "비용·토큰·이벤트·**무엇이 언제**"를 담당하는 직교 보완재다. 둘을 같이 켜면 `session_id`·`prompt_id`가 동일 값이라 그대로 join되어 훅 발화 여부를 교차 검증할 수 있다(→ 이 레포 `infra/otel`에 로컬 수신 스택 `docker-compose`와 Grafana 대시보드 제공). 전역 `env`에 함께 설정:

```json
{
  "env": {
    "OBSERVE_TRACE": "1",
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317",
    "OTEL_LOG_TOOL_DETAILS": "1",
    "OTEL_LOG_USER_PROMPTS": "1"
  }
}
```

- `OTEL_LOG_TOOL_DETAILS`는 서드파티(마켓플레이스) 스킬 이름의 마스킹을 푼다 — 없으면 `skill_name`이 `custom_skill`로만 찍혀 하네스별 집계가 불가능하다(실측 2026-07).
- `OTEL_LOG_USER_PROMPTS`는 프롬프트 원문을 전송해 대시보드의 프롬프트↔스킬 상관 뷰를 채운다 — 없으면 `<REDACTED>`.
- 스택이 꺼져 있어도 세션은 정상 동작한다(OTLP export 실패는 조용히 무시). `CLAUDE_CODE_ENABLE_TELEMETRY`만으로는 observe 훅이 켜지지 않으니 `OBSERVE_TRACE`는 별도로 둔다 — 둘은 직교한다.

> ⚠️ **프라이버시**: `OBSERVE_TRACE`·`OTEL_LOG_USER_PROMPTS`는 프롬프트 **원문**을 기록한다. 전역으로 켜면 민감 프로젝트를 포함한 모든 프롬프트가 로컬(`.claude/skill-trace.jsonl` + 로컬 Loki)에 남는다 — 로컬 loopback이라 머신 밖 유출은 없지만, 원문 기록은 명시적 결정이다. 특정 프로젝트만 빼려면 그 프로젝트 `.claude/settings.local.json`의 `env`에서 `"0"`으로 끈다.

## 사용법

세팅을 마치면 평소처럼 세션을 진행하는 것만으로 6종 훅이 자동으로 `.claude/skill-trace.jsonl`에 레코드를 append한다(별도 호출 불필요). 일정 기간 트레이스가 쌓이면 리포트를 실행한다.

```
/observe-report                    # 집계 → 해석 → 개선 제안까지 전체 흐름
/observe-report --raw --window 14  # 최근 14일 결정론 집계 JSON만 (외부 도구 연계용)
/observe-report --focus skills     # 미발화 판정·user-only 스킬 진단 중심
```

트레이스가 비어 있으면(`OBSERVE_TRACE` 미설정) 리포트는 활성화 방법과 재수집 안내를 출력하고 종료한다. 표본이 작으면(세션 < 5) 해석에 "표본 부족 — 경향 참고용" 경고가 붙어 과잉 일반화를 방지한다. 제안서는 대상 파일 경로·현재 description·수정안·근거 턴 인용을 담되, **적용은 사용자 승인 후 별도 작업**이다.

## 의존성

- `requires`: `base` — 기반 플러그인 위에서 동작한다.
- 함께 쓰면 좋은 플러그인: `/observe-report`가 산출한 제안은 사장 자산은 `workflow:deprecation-guide`(폐기 절차)로, 신규 스킬/훅 후보는 `harness:create-flow`(스캐폴딩)로, description 수정안의 사전 발화율 검증은 `skill-creator` eval로 라우팅된다. 세션 일화 기반 교훈을 다루는 `workflow:retro`의 데이터 기반 보완재이기도 하다.

## 참고

- **opt-in 전제**: `OBSERVE_TRACE=1`일 때만 모든 훅이 동작한다. 이 커맨드/훅은 `OBSERVE_TRACE`를 자동 활성화하지 않는다 — 프롬프트 원문이 기록되는 결정은 사용자 몫이다.
- **프라이버시·저장**: 트레이스는 프로젝트 루트의 `.claude/skill-trace.jsonl`에 쌓이며, 최초 기록 시 `.gitignore`에 `.claude/skill-trace.jsonl*`을 idempotent하게 추가해 커밋을 막는다. 10MB 초과 시 `.1`로 1세대 로테이션한다. 호출 결과 본문은 용량·민감정보 우려로 기록하지 않고 `response_bytes`만 남긴다.
- **직교 경계**: 비용/토큰/tool_decision 계측은 내장 OTel(`CLAUDE_CODE_ENABLE_TELEMETRY`)에, 발화율 사전 벤치마크(트리거/비트리거 쿼리 eval)는 `skill-creator` eval에 위임한다 — 이 플러그인은 이를 재구현하지 않는다.
- **계측 경계 (실측 확인, 2026-07)**: 헤드리스(`claude -p "/커맨드"`) 실행의 user-slash 커맨드는 Skill 툴을 경유하지 않아 `skill` 레코드가 남지 않는다 — 이 경우 `prompt` 레코드의 `is_command` 플래그가 호출 근거다(인터랙티브 세션의 user-slash는 모델이 Skill 툴을 호출하므로 정상 추적). 내장 OTel의 `skill_activated` 이벤트(`invocation_trigger: user-slash|claude-proactive`)는 두 경로를 모두 잡으므로, 로컬 OTel 스택(`infra/otel`)과 `prompt_id`로 맞대면 훅 발화 여부를 교차 검증할 수 있다.
- **제안 전용**: `/observe-report`는 SKILL.md·커맨드·훅 등 어떤 파일도 수정하지 않는다. 훅 로직 버그도 직접 고치지 않고 플래그만 남긴다(무단 수정 금지 원칙).
