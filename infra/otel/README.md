# 로컬 OTel 플랫폼 (grafana/otel-lgtm)

> Claude Code **내장 텔레메트리**(비용·토큰·이벤트)를 로컬에서 수신·시각화하는 올인원 스택.
> `observe` 플러그인의 직교 보완재이며, 로컬 전용이다.

## observe 플러그인과의 경계

이 스택은 observe 플러그인을 대체하지 않는다. 두 계측은 서로 다른 데이터를 본다.

| | observe 플러그인 | 이 스택 (내장 OTel) |
|---|---|---|
| 데이터 | 스킬/에이전트 호출의 **왜**(why·trigger·완주) | 비용·토큰·API 요청·훅 실행·이벤트 |
| 저장 | `.claude/skill-trace.jsonl` | Prometheus(메트릭) + Loki(이벤트 로그) |
| 활성화 | `OBSERVE_TRACE=1` | `CLAUDE_CODE_ENABLE_TELEMETRY=1` |
| 소비 | `/observe-report` | Grafana (http://localhost:3000) |

observe 훅이 실제로 발화하는지는 이 스택의 Loki에서 `hook_execution_start/complete`,
`plugin_loaded` 이벤트로 교차 검증할 수 있다 — observe 자체 로그(skill-trace.jsonl)와
내장 텔레메트리를 맞대보면 훅 미발화를 양쪽에서 잡아낸다.

## 왜 grafana/otel-lgtm인가

Claude Code 텔레메트리의 시그널 형태가 결정 근거다: **OTLP metrics + OTLP logs(이벤트)**가 주력이고
traces는 베타 부가 시그널. 따라서 메트릭 대시보딩(PromQL)과 로그 검색(LogQL) 둘 다 강한 백엔드가 필요하다.

- **SigNoz**: UI는 훌륭하나 5컨테이너 + ClickHouse + 4GB 최소 메모리 — 로컬 8GB VM에 과함
- **OpenObserve**: 가장 가볍지만(~512MB) 클라이언트에 http/json 프로토콜·Basic auth·delta temporality 설정 강제
- **Jaeger v2**: logs/metrics를 저장하지 못해 탈락
- **otel-desktop-viewer/otel-tui**: 뷰어일 뿐 히스토리·대시보드 없음
- **otel-lgtm**: 1컨테이너, 클라이언트 설정 최소(엔드포인트만), PromQL+LogQL, Grafana Labs가 로컬 개발용으로 공식 유지보수

## 구성

단일 컨테이너 안에 OTel Collector + Prometheus + Loki + Tempo + Pyroscope + Grafana가 돈다.

- **포트** (전부 `127.0.0.1` 바인딩 — Grafana가 기본 익명 Admin이라 LAN 노출 금지)
  - `3000` Grafana UI (로그인 불필요, 첫 화면 = Claude Code 대시보드)
  - `4317` OTLP gRPC ← Claude Code 기본 수신 지점
  - `4318` OTLP HTTP
- **영속성**: named volume `lgtm-data` → `/data` 하나로 5개 컴포넌트 데이터 전부 유지 (컨테이너 재생성 후 유지 실증됨)
- **자생성**: `restart: always` — 크래시·Docker 재시작·재부팅(OrbStack 로그인 시 자동 시작) 모두 복구
- **헬스체크**: 이미지 내장 (Grafana/Loki/Tempo/Prometheus/Collector 5종 ready 검사, 30s 간격)

### delta temporality 함정 (이 compose가 이미 해결함)

Claude Code 메트릭은 **delta temporality**로 송출되는데, Prometheus(v3.x) OTLP 수신기는
`--enable-feature=otlp-deltatocumulative` 없이는 delta를 **조용히 전량 드롭**한다.
증상: Loki에 로그는 쌓이는데 `claude_code_*` 메트릭만 없음. 컬렉터 카운터
(`otelcol_exporter_send_failed_metric_points_total`)로 확인 가능. 이 compose는
`PROMETHEUS_EXTRA_ARGS`로 플래그를 켜 두었다.

## 사용법

```bash
cd infra/otel
docker compose up -d      # 최초 기동 (healthy까지 ~35초)
open http://localhost:3000
```

Claude Code 쪽 연결은 이 레포의 `.claude/settings.local.json` env 블록에 이미 설정되어 있다
(다음 세션부터 적용). 다른 프로젝트나 셸 전역에서 쓰려면:

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_LOG_TOOL_DETAILS=1   # 서드파티 스킬 이름 마스킹 해제 (아래 참고)
export OTEL_LOG_USER_PROMPTS=1   # 프롬프트 원문 전송 (프롬프트↔스킬 상관 뷰용)
```

스택이 꺼져 있어도 Claude Code는 정상 동작한다(export 실패는 조용히 무시됨).

### 마스킹 게이트 (실측, 2026-07)

- `OTEL_LOG_TOOL_DETAILS` 미설정 시 마켓플레이스 플러그인 스킬은 `skill_name="custom_skill"`로
  **마스킹**되고 `plugin_name`/`marketplace_name`도 빠진다 — 하네스 계측이 목적이면 필수.
  설정 시 `skill_name="feature-loop:floop-status"`, `plugin_name="feature-loop"`,
  `marketplace_name="dokkabei-harness"`처럼 전체 귀속이 나온다 (번들 스킬은 게이트 없이도 실명).
- `OTEL_LOG_USER_PROMPTS` 미설정 시 `user_prompt` 이벤트의 `prompt`가 `<REDACTED>`
  (단, `command_name`·`prompt_length`는 항상 보임).

### 프라이버시 기본값

프롬프트 원문·응답·툴 입력은 기본 **미전송**(redacted). 위 두 게이트는 이 로컬 스택(루프백 전용)
한정으로 켠 opt-in이며, observe 플러그인이 `OBSERVE_TRACE=1`로 프롬프트를 로컬 기록하는 것과
같은 결정 층위다. 외부 수집기로 보낼 때는 다시 검토할 것.

## 수집 데이터 (실측 검증됨)

**Prometheus 메트릭** — OTLP→Prometheus 이름 변환 후 실제 이름:

| 문서상 이름 | Prometheus 실제 이름 | 주요 레이블 |
|---|---|---|
| `claude_code.cost.usage` | `claude_code_cost_usage_USD_total` | model, query_source, effort |
| `claude_code.token.usage` | `claude_code_token_usage_tokens_total` | type(input\|output\|cacheRead\|cacheCreation), model |
| `claude_code.session.count` | `claude_code_session_count_total` | — |
| `claude_code.active_time.total` | `claude_code_active_time_seconds_total` | type(user\|cli) |

(commit/PR/lines_of_code/edit_decision 계열은 해당 행위 발생 시 나타남)

**Loki 이벤트** — `{service_name="claude-code"}`, 스트림 레이블 `event_name`:
`user_prompt`, `assistant_response`, `api_request`, `api_error`, `tool_result`, `tool_decision`,
`skill_activated`, `plugin_loaded`, `hook_registered`, `hook_execution_start/complete`,
`mcp_server_connection`, `compaction` 등 24종.

**대시보드**: `grafana/claude-code-dashboard.json`이 프로비저닝되어 홈 화면에 뜬다.
수정하려면 JSON을 고치고 `docker compose restart` (프로비저닝 파일이라 UI 편집은 저장 안 됨 —
UI에서 "Save as"로 복제 후 편집).

- **요약 stat**: 비용/세션/토큰/활동시간 — 희소 카운터 staleness 때문에 단순 instant sum이 아니라
  `sum(last_over_time(...[$__range]))`을 쓴다 (세션 수가 "No data"로 비는 문제의 해법).
- **스킬/하네스 호출 누적**: `skill_activated` 이벤트 기반 — 스킬별·플러그인(하네스)별 bargauge,
  user-slash vs claude-proactive 트리거 파이, Agent/Task 호출 수. Loki 집계 패널은 instant가 아니라
  **range 쿼리 + lastNotNull** 감산이어야 시리즈 레이블이 산다 (instant는 "Value #A"로 뭉개짐).
- **프롬프트 ↔ 스킬 연쇄 타임라인**: `user_prompt`와 `skill_activated`를 시간순으로 섞어
  `[prompt_id 앞 8자]`로 결합 표시 — "어떤 프롬프트에서 어떤 스킬이 연달아 호출됐는지"를 그대로 읽는다.

### 상관 조회 레시피 (Grafana Explore → Loki)

`event_name`은 인덱스 레이블이 아니라 **구조화 메타데이터**다 — 셀렉터(`{event_name="..."}`)가 아닌
파이프라인 필터(`| event_name="..."`)로 걸러야 한다.

```logql
# 특정 프롬프트가 유발한 모든 이벤트 (타임라인 패널에서 prompt_id를 얻은 뒤)
{service_name="claude-code"} | prompt_id="7f66a472-65aa-4138-a943-45fef1ac2dde"

# 스킬 호출만, 이름/트리거/플러그인 포함
{service_name="claude-code"} | event_name="skill_activated"
  | line_format "{{.skill_name}} ({{.invocation_trigger}}) plugin={{.plugin_name}}"

# 세션 하나의 전체 흐름 재구성
{service_name="claude-code"} | session_id="<session_id>"

# 하네스별 호출 수 (지난 7일)
sum by (plugin_name) (count_over_time({service_name="claude-code"}
  | event_name="skill_activated" | plugin_name!="" [7d]))
```

observe 플러그인의 `.claude/skill-trace.jsonl`과는 `session_id`/`prompt_id`가 동일 값이므로
그대로 join된다 — observe가 "왜(why)·완주"를, 이 스택이 "무엇이·언제·얼마나"를 담당한다.

## 운영

```bash
docker compose ps                                  # 상태 (healthy 확인)
docker compose pull && docker compose up -d        # 이미지 업그레이드 (데이터 유지)
docker compose down                                # 중지 (데이터 유지)
docker compose down -v                             # 완전 리셋 (데이터 삭제)
```

- 재부팅 후 자동 기동은 OrbStack(또는 Docker Desktop)의 로그인 시 자동 시작 설정에 의존한다.
- 트레이스(베타)까지 보려면: env에 `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` + `OTEL_TRACES_EXPORTER=otlp` 추가 → Tempo에 적재.
- 이미지 버전 고정: `grafana/otel-lgtm:0.28.0` (2026-05). 주 단위 릴리스이므로 가끔 태그를 올려주면 된다.
