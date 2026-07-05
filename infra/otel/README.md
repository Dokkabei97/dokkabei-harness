> **English** · [한국어](README_KO.md)

# Local OTel Platform (grafana/otel-lgtm)

> An all-in-one stack that receives and visualizes Claude Code's **built-in telemetry** (cost, tokens, events) locally.
> It is an orthogonal complement to the `observe` plugin, and is local-only.

## Boundary with the observe plugin

This stack does not replace the observe plugin. The two instrumentations look at different data.

| | observe plugin | This stack (built-in OTel) |
|---|---|---|
| Data | The **why** of skill/agent calls (why, trigger, completion) | Cost, tokens, API requests, hook executions, events |
| Storage | `.claude/skill-trace.jsonl` | Prometheus (metrics) + Loki (event logs) |
| Activation | `OBSERVE_TRACE=1` | `CLAUDE_CODE_ENABLE_TELEMETRY=1` |
| Consumption | `/observe-report` | Grafana (http://localhost:3000) |

Whether the observe hooks actually activate can be cross-verified in this stack's Loki via the
`hook_execution_start/complete` and `plugin_loaded` events — cross-checking observe's own log (skill-trace.jsonl)
against the built-in telemetry catches missed hook activations on both sides.

## Why grafana/otel-lgtm

The signal shape of Claude Code telemetry is the deciding rationale: **OTLP metrics + OTLP logs (events)** are the mainstay,
while traces are a beta add-on signal. Therefore a backend strong in both metric dashboarding (PromQL) and log search (LogQL) is needed.

- **SigNoz**: excellent UI, but 5 containers + ClickHouse + 4GB minimum memory — overkill for a local 8GB VM
- **OpenObserve**: the lightest (~512MB) but forces http/json protocol, Basic auth, and delta temporality configuration on the client
- **Jaeger v2**: dropped because it cannot store logs/metrics
- **otel-desktop-viewer/otel-tui**: viewers only, no history or dashboards
- **otel-lgtm**: 1 container, minimal client configuration (endpoint only), PromQL+LogQL, officially maintained by Grafana Labs for local development

## Composition

Inside a single container, OTel Collector + Prometheus + Loki + Tempo + Pyroscope + Grafana run together.

- **Ports** (all bound to `127.0.0.1` — since Grafana defaults to anonymous Admin, LAN exposure is forbidden)
  - `3000` Grafana UI (no login required, first screen = Claude Code dashboard)
  - `4317` OTLP gRPC ← Claude Code's default receiving point
  - `4318` OTLP HTTP
- **Persistence**: a single named volume `lgtm-data` → `/data` retains all data of the 5 components (retention across container recreation is empirically verified)
- **Self-recovery**: `restart: always` — recovers from crashes, Docker restarts, and reboots (auto-starts on OrbStack login)
- **Health check**: built into the image (checks readiness of all 5 — Grafana/Loki/Tempo/Prometheus/Collector, at 30s intervals)

### The delta temporality pitfall (this compose already solves it)

Claude Code metrics are emitted with **delta temporality**, and the Prometheus (v3.x) OTLP receiver
**silently drops all** deltas without `--enable-feature=otlp-deltatocumulative`.
Symptom: logs accumulate in Loki but only the `claude_code_*` metrics are missing. It can be confirmed via the collector counter
(`otelcol_exporter_send_failed_metric_points_total`). This compose has the flag turned on via
`PROMETHEUS_EXTRA_ARGS`.

## Usage

```bash
cd infra/otel
docker compose up -d      # first startup (~35s until healthy)
open http://localhost:3000
```

The Claude Code side connection is already configured in this repo's `.claude/settings.local.json` env block
(applied from the next session onward). To use it in another project or shell-wide:

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_LOG_TOOL_DETAILS=1   # unmask third-party skill names (see below)
export OTEL_LOG_USER_PROMPTS=1   # send raw prompts (for the prompt↔skill correlation view)
```

Claude Code works normally even when the stack is down (export failures are silently ignored).

### Masking gates (measured, 2026-07)

- When `OTEL_LOG_TOOL_DETAILS` is unset, marketplace plugin skills are **masked** as `skill_name="custom_skill"`
  and `plugin_name`/`marketplace_name` are also dropped — essential if harness instrumentation is the goal.
  When set, full attribution appears, e.g. `skill_name="feature-loop:floop-status"`, `plugin_name="feature-loop"`,
  `marketplace_name="dokkabei-harness"` (bundled skills show their real names even without the gate).
- When `OTEL_LOG_USER_PROMPTS` is unset, the `prompt` of the `user_prompt` event is `<REDACTED>`
  (however, `command_name` and `prompt_length` are always visible).

### Privacy defaults

Raw prompts, responses, and tool inputs are by default **not sent** (redacted). The two gates above are opt-ins turned on only
for this local stack (loopback-only), the same decision layer as the observe plugin recording prompts locally with
`OBSERVE_TRACE=1`. Revisit them when sending to an external collector.

## Collected data (empirically verified)

**Prometheus metrics** — actual names after the OTLP→Prometheus name conversion:

| Documented name | Actual Prometheus name | Key labels |
|---|---|---|
| `claude_code.cost.usage` | `claude_code_cost_usage_USD_total` | model, query_source, effort |
| `claude_code.token.usage` | `claude_code_token_usage_tokens_total` | type(input\|output\|cacheRead\|cacheCreation), model |
| `claude_code.session.count` | `claude_code_session_count_total` | — |
| `claude_code.active_time.total` | `claude_code_active_time_seconds_total` | type(user\|cli) |

(the commit/PR/lines_of_code/edit_decision families appear when the corresponding action occurs)

**Loki events** — `{service_name="claude-code"}`, stream label `event_name`:
`user_prompt`, `assistant_response`, `api_request`, `api_error`, `tool_result`, `tool_decision`,
`skill_activated`, `plugin_loaded`, `hook_registered`, `hook_execution_start/complete`,
`mcp_server_connection`, `compaction`, and so on — 24 kinds.

**Dashboard (English / Korean variants)**: `grafana/dashboards/` holds two provisioned dashboards —
`claude-code-dashboard.en.json` (uid `claude-code-en`, English panel titles) and
`claude-code-dashboard.ko.json` (uid `claude-code-ko`, Korean panel titles). Both always appear under
Grafana's **Dashboards** list, so you can open whichever you prefer. The `localhost:3000` landing page
defaults to the English one; to make Korean the landing page, set the `GRAFANA_HOME_DASHBOARD` variable
(shell env or an `.env` file next to the compose file) and recreate:

```bash
# .env  (or: export GRAFANA_HOME_DASHBOARD=...)
GRAFANA_HOME_DASHBOARD=/otel-lgtm/dashboards/claude-code-dashboard.ko.json
```

Both variants are identical except for titles — same panels, queries, and layout. To modify them, edit the
JSON and `docker compose restart` (since they are provisioned files, UI edits are not saved — in the UI,
clone with "Save as" and then edit).

- **Summary stats**: cost/session/tokens/active time — because of sparse-counter staleness, they use
  `sum(last_over_time(...[$__range]))` rather than a plain instant sum (the fix for the problem where the session count shows "No data").
- **Skill/harness call totals**: based on `skill_activated` events — bargauge per skill and per plugin (harness),
  a user-slash vs claude-proactive trigger pie, Agent/Task call counts. Loki aggregation panels must be a
  **range query + lastNotNull** subtraction rather than instant for the series labels to survive (instant collapses them into "Value #A").
- **Prompt ↔ skill chain timeline**: mixes `user_prompt` and `skill_activated` in chronological order,
  jointly displayed by `[first 8 chars of prompt_id]` — reads directly "which prompt triggered which skills in succession."

### Correlation query recipes (Grafana Explore → Loki)

`event_name` is not an index label but **structured metadata** — filter it with a
pipeline filter (`| event_name="..."`) rather than a selector (`{event_name="..."}`).

```logql
# All events triggered by a specific prompt (after getting the prompt_id from the timeline panel)
{service_name="claude-code"} | prompt_id="7f66a472-65aa-4138-a943-45fef1ac2dde"

# Skill calls only, including name/trigger/plugin
{service_name="claude-code"} | event_name="skill_activated"
  | line_format "{{.skill_name}} ({{.invocation_trigger}}) plugin={{.plugin_name}}"

# Reconstruct the full flow of a single session
{service_name="claude-code"} | session_id="<session_id>"

# Call count per harness (last 7 days)
sum by (plugin_name) (count_over_time({service_name="claude-code"}
  | event_name="skill_activated" | plugin_name!="" [7d]))
```

Since `session_id`/`prompt_id` have the same values as the observe plugin's `.claude/skill-trace.jsonl`,
they join directly — observe handles the "why / completion" while this stack handles the "what / when / how much."

## Operations

```bash
docker compose ps                                  # status (check healthy)
docker compose pull && docker compose up -d        # image upgrade (data retained)
docker compose down                                # stop (data retained)
docker compose down -v                             # full reset (data deleted)
```

- Auto-startup after reboot depends on the login-time auto-start setting of OrbStack (or Docker Desktop).
- To also see traces (beta): add `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` + `OTEL_TRACES_EXPORTER=otlp` to the env → loaded into Tempo.
- Image version pinning: `grafana/otel-lgtm:0.28.0` (2026-05). Since releases are weekly, occasionally bump the tag.
