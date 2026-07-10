> **English** · [한국어](README_KO.md)

# scaleup

> The execution OS for a Series A–C scale-up — materializing OKR cadence, org scaling, board/investor reporting, and enterprise deal qualification as file contracts guarded by deterministic gates.

## Overview

`scaleup` runs the *execution* of a scaling company (not idea validation — that is `startup`). It structures the work along three pipelines — a quarterly OKR cycle, event-driven org/board work, and per-deal enterprise GTM — and materializes every deliverable as a file under `.planning/scaleup/`, following the design principle that state (cycle status, KRs, KPIs) is guaranteed by files rather than by session memory.

The core characteristic is **maker/checker separation + deterministic gates**. Makers draft (OKR trees, org plans, board decks, MEDDPICC scorecards); checkers — deliberately without the Edit tool — refute them and materialize a verdict.json; and a deterministic gate (`exit 0/1`) then re-checks the contract. "Whether it passes is decided by the harness, not the model." All outward deliverables (OKRs, board decks, deal commits) presume human approval.

Boundaries are explicit: financials/tax → `finance`, legal judgments (commercial law, SHA consent, M&A filing, whistleblower) → `legal`, JD/onboarding → `hr`, market research/unit economics/content → `startup`, and GRC / enterprise planning / M&A screening → `enterprise`.

## Components

### Commands (10)

- `/okr-plan` — Author the quarterly OKR tree (1–5 objectives, 1–4 KRs) with owner/baseline/target/due; drafted, then refuted by okr-checker, then human-approved.
- `/okr-checkin` — Weekly check-in: per-KR confidence, blockers, next-week commitments + a 5–15 metric scorecard.
- `/okr-score` — End-of-quarter scoring (0.0–1.0) + retro feeding the next `/okr-plan`.
- `/stage-check` — Blitzscaling 5-stage diagnosis + Korean headcount-threshold (10/30/50) flags; refuted by scale-checker.
- `/org-plan` — Forward-looking org chart + headcount plan aligned to the AOP budget (org-planner).
- `/board-deck` — Quarterly board deck (fixed sections) + standard KPI pack (board-reporter).
- `/investor-update` — Monthly Wins/Misses/Asks + cash/runway; doubles as the RCPS/SHA periodic-reporting document.
- `/deal-review` — Per-deal MEDDPICC scorecard; refuted by deal-qualifier.
- `/pipeline-audit` — CRM-export hygiene audit + forecast rollup (the showcase deterministic gate).
- `/scaleup-from-startup` — Bridge that carries `.planning/business/` outputs into the scaleup cycle.

### Agents (5)

- `org-planner` (maker) — forward-looking org chart + headcount plan, milestone linkage, AOP alignment.
- `board-reporter` (maker) — board deck, KPI pack, investor update to Sequoia/Sacks standards.
- `okr-checker` (checker, no Edit) — refutes KR-as-task-disguised-output; ADOPT/REWRITE/DROP.
- `deal-qualifier` (checker, no Edit) — refutes MEDDPICC 'verified' overclaims; COMMIT/DOWNGRADE/DISQUALIFY.
- `scale-checker` (checker, no Edit) — refutes premature stage transitions; ADVANCE/HOLD/NOT-YET.

### Skills (6)

- `scaleup-orchestrator` — master router for the three pipelines (+ `references/gate-policy.md`, the gate-criteria & schema source of truth).
- `operating-cadence` — OKR/EOS/4DX comparison, meeting rhythm, and the "skip a weekly session → collapse within 2 cycles" warning.
- `board-governance` — board-deck standard headings (canonical strings for gate-board-deck) + Korean governance turning points.
- `meddpicc-qualification` — the 8-element definitions and status spec (= gate-meddpicc contract).
- `revops-pipeline-schema` — sales stage/forecast_category enums (+ `references/pipeline-enums.json` the gate reads, and `references/hygiene-rules.md`).
- `korea-b2b-procurement` — CSAP/BMT/나라장터, negotiated-contract scoring (tech 90:price 10), the 85% cut.

### Gates (6, deterministic `exit 0/1`)

`gate-okr.sh` (`--scored`/`--require-verdict`) · `gate-cadence.sh` · `gate-headcount.sh` · `gate-board-deck.sh` · `gate-meddpicc.sh` (`--require-verdict`) · `gate-pipeline-hygiene.sh` (showcase). Regression tests: `tests/hooks/scaleup-gates.bats`.

## Deliverable Contract (`.planning/scaleup/`)

```
scaleup-master.json                 # cycle status
okr/okr-YYYYQn.json, okr/verdict.json
checkins/YYYY-Www.md, score/YYYYQn-retro.md
org/headcount.json, org/stage-verdict.json
board/YYYYQn-deck.md, board/kpi-pack.json, investor/YYYY-MM.md
gtm/deals/<id>/meddpicc.json + verdict.json
gtm/pipeline/YYYY-MM-DD-audit.json
```

Filenames use the quarter `YYYYQn` / week `YYYY-Www` / date `YYYY-MM-DD` conventions so gates can do date arithmetic from the filename alone.

## Usage Flow

- **New cycle**: `/scaleup-from-startup` (if `.planning/business/` exists) → `/okr-plan` → weekly `/okr-checkin` → `/okr-score`.
- **Org**: `/stage-check` → `/org-plan` (aligned to `enterprise/budget-*.json` when present).
- **Board/investors**: `/board-deck` each quarter, `/investor-update` monthly.
- **Enterprise GTM**: `/deal-review <deal-id>` per deal, `/pipeline-audit <export>` weekly.

## Delegation Boundaries

- **finance** — financial statements, tax, actuals/figure verification (board financials, headcount cost).
- **legal** — commercial law, SHA consent rights, M&A filing, whistleblower, personal-data judgments.
- **hr** — JD, onboarding, disciplinary clauses.
- **startup** — market research, unit economics, content/brand voice (read-only inheritance via the bridge).
- **enterprise** — GRC, enterprise annual planning, M&A screening (`budget-*.json` is enterprise-owned; scaleup only reads it when present).

## Notes

- No SaaS CRM/board-portal API integration — CSV/JSON export input only.
- Checkers hold no Edit tool by design, blocking the path of fixing a deliverable to make it pass; Write is limited to the verdict.json file.
