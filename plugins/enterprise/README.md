> **English** · [한국어](README_KO.md)

# enterprise

> A governance OS for mid-to-large enterprises that materializes GRC (risk, control, certification, compliance) and corporate planning (strategy cascade, annual plan, rolling forecast, M&A screening) as documented pipelines guarded by deterministic evidence gates.

## Overview

`enterprise` structures corporate governance into two file-contract pipelines — **GRC** and **corporate planning** — following the harness design principle that state is guaranteed by files under `.planning/grc/` and `.planning/enterprise/`, not by session memory. It deliberately excludes free-form virtual-executive meetings (a measured anti-pattern) and moves only through **maker draft → checker falsification → deterministic gate**.

The core characteristic is **maker/checker separation plus deterministic evidence gates**. Makers (`risk-assessor`, `strategy-analyst`, `fpna-planner`) draft deliverables; checkers (`grc-challenger`, `plan-challenger`), deliberately without the Edit tool, refute them and materialize a verdict to `verdict.json`; then a local bash gate (exit 0/1) recomputes the arithmetic and enum invariants. What determinism can catch (numbers, enums, sums, deadlines) the gate handles; the checker only judges the semantic remainder.

The boundaries are explicit. Legal judgment (corporate/company law, M&A and regulatory filings, whistleblowing, data privacy) is delegated to `legal`; financial-statement/tax/actuals verification to `finance`; JD/onboarding/discipline to `hr`; market research, unit economics, and unit-level finance to `startup`.

## Components

### Commands — GRC pipeline

- `/grc-intake` — Interview the company profile and declare which compliance frameworks/regulations apply (ISO 27001, SOC 2, GDPR, other), recorded in `grc-profile.json`.
- `/risk-register` — Declare risk appetite and build a COSO/ISO31000 5x5 register → grc-challenger → `gate-risk-register.sh --require-verdict`.
- `/control-matrix` — Map controls to risks (preventive/detective, three lines, evidence) with an ICFR (SOX-style) RCM skeleton → `gate-control-matrix.sh`.
- `/policy-suite` — Scaffold the code-of-conduct → policy → standard → procedure hierarchy plus a whistleblowing policy → `gate-policy-suite.sh`.
- `/cert-gap` — ISO/IEC 27001:2022 Annex A 93-control gap analysis with evidence paths and a SOC 2 crossmap → `gate-cert-readiness.sh`.
- `/comp-calendar` — Recurring compliance-duty calendar (annual filings, ISO surveillance audits, SOC 2 audit periods, training, access reviews) with deadline/D-14 gating → `gate-calendar.sh`.

### Commands — corporate planning pipeline

- `/strategy-cascade` — Playing to Win 5-choice one-pager + Three Horizons tags + 7S → plan-challenger (no gate).
- `/annual-plan` — Annual planning cycle → budget.json (CLAP, scenarios, dept sum = org total) → plan-challenger → `gate-budget.sh`.
- `/rolling-forecast` — Driver-based rolling forecast with variance/DERP commentary → `gate-variance.sh`.
- `/biz-screen` — M&A 5-category scorecard with stop rule and disqualifiers → plan-challenger → `gate-screen.sh --require-verdict`.
- `/enterprise-from-scaleup` — Bridge that carries `.planning/scaleup/` outputs into GRC/planning intake (falls back to a full interview).

### Agents

- `risk-assessor` (maker) — COSO/ISO31000 risk identification/assessment and control mapping.
- `strategy-analyst` (maker) — Playing to Win / 3H / 9-box / 7S cascade and M&A screening scorecards.
- `fpna-planner` (maker) — Enterprise-level annual plan, budget allocation, company P&L, and rolling forecast (unit-level finance is `startup:financial-modeler`).
- `grc-challenger` (checker, no Edit) — Refutes risk under-scoring, missing framework/regulation categories, owner reality, and policy gaps → `grc/verdict.json` (ACCEPT/REMEDIATE/ESCALATE).
- `plan-challenger` (checker, no Edit) — Refutes cascade logic gaps, hockey-stick budgets, sandbagging, and synergy substitution → `verdict.json` (APPROVE/REBASELINE/REJECT).

### Skills

- `enterprise-orchestrator` — Master routing the two pipelines; judgment criteria, schemas, and the decision table are canonical in `references/gate-policy.md`.
- `grc-frameworks` — COSO ERM, ISO 31000, IIA Three Lines (2020), and the 5x5 matrix (`references/risk-matrix.json` is the gate's source of truth).
- `compliance-context` — International framework selection (ISO 27001:2022 Annex A, SOC 2 TSC, GDPR pointers), ISO-vs-SOC 2 sequencing, and evidence discipline with `references/iso27001-annex-a.json`.
- `strategy-frameworks` — Playing to Win, 3H, 9-box, 7S, M&A 5 categories, and a merger-control (competition-authority filing) review reference.
- `fpna-planning` — Annual planning calendar, CLAP 5 elements (`references/clap-keys.json`), driver trees, and DERP (`references/derp-template.md`).

## Usage

Invoke each command directly or via natural language. Deliverables land under `.planning/grc/` and `.planning/enterprise/` and become inputs to later commands and gates.

- **GRC build**: `/grc-intake` → `/risk-register` → `/control-matrix` → `/policy-suite` → `/cert-gap` → `/comp-calendar`.
- **Planning cycle**: `/strategy-cascade` → `/annual-plan` → `/rolling-forecast`; screen deals with `/biz-screen`.
- **From scaleup**: `/enterprise-from-scaleup` to pre-fill intake from `.planning/scaleup/`.

Gates are plain local bash (`plugins/enterprise/hooks/gates/*.sh`), invoked by commands as `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-*.sh"`; regression tests live in `tests/hooks/enterprise-gates.bats`.

## Dependencies

No hard dependencies; the following keep the flow connected.

- `scaleup` — `/enterprise-from-scaleup` carries OKR/org/board outputs into governance intake.
- `legal` — Corporate/company law, M&A and regulatory filings, whistleblowing, and data-privacy judgments.
- `finance` — Financial-statement, tax, ICFR figures, and actuals verification.
- `startup` — Market research, unit economics, and unit-level financial modeling.

## Notes

- Enum/control data is single-sourced in skill `references/*.json` (ISO 27001 Annex A 93 controls, 5x5 matrix, CLAP keys); gates reference these files and never hardcode.
- The ISO 27001 Annex A control set carries a "needs update" stamp — reconfirm titles against the official standard before relying on them.
- This plugin is a first-pass governance tool and does not replace the advice of lawyers, accountants, or auditors. All external deliverables assume a human approval gate.
