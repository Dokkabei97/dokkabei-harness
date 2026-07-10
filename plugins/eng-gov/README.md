> **English** · [한국어](README_KO.md)

# eng-gov

> A development-governance harness that materializes ADR, change evidence, threat model, and supply-chain controls as local `exit 0/1` gates — generating SOC2/ISMS-P audit evidence git-natively.

## Overview

`eng-gov` turns engineering governance into **deterministic local gates** instead of a heavyweight review board. Every control is a bash script with the `exit 0 = checked and passed` contract, so it plugs directly into the existing loop engines (mvp·feature-loop·generic) and into CI without a server. The design philosophy is inherited unchanged from the other harnesses: **single-pass command pipeline + maker/checker (checkers have no Edit) + deterministic gates + ".planning/ files guarantee state"**.

Its differentiator is the Korean audit-evidence angle: `/gov-audit` converts git-native evidence (change bundles, gate results) into a **Korean audit document** mapped to SOC2 CC8.1 · ISMS-P 2.9.1/2.8 controls, for ISMS-P and financial-sector reviews.

**Tool-absence policy — "skip at registration, fail-closed at runtime"**: a registered gate whose tool is missing fails closed (`exit 1` + install guidance), because a skip-green would be false audit evidence. The decision to *not* run a gate is made explicit at `/gov-init` time (`gates.json` `enabled:false` + `reason`). The only degraded exception is `gate-threat-model` (the deterministic half always judges; only threagile regeneration is skipped with a warning).

## Components

### Commands (8)

| Command | Role |
|---------|------|
| `/gov-init` | Detect stack·tools → scaffold `.planning/gov/` + `docs/decisions/` → register gates in `gates.json` (missing tools `enabled:false`) → trial run |
| `/gov-adr` | Write/supersede a MADR ADR + propose fitness-function conversions → adr-checker → gate-adr |
| `/gov-threat` | Analyze codebase → draft `threagile.yaml` → threagile (if present) → threat-model-checker → gate-threat-model |
| `/gov-slo` | SLO doc + error-budget policy + `thresholds.yaml` (separated) → trial-run gate-error-budget |
| `/gov-postmortem` | Blameless postmortem (timeline·5-why·owner/due actions) → postmortem-checker (no gate) |
| `/gov-change` | bash-precompute diff → change-risk-classifier → `evidence.json` → gate-change-evidence |
| `/gov-audit` | Run registered gates via run-registered.sh → append `audit-log.jsonl` → Korean audit doc |
| `/gov-dora` | DORA 4 Keys (DF/LT from git, CFR/MTTR from the postmortem ledger) — read-only |

### Agents (4, all opus)

- `change-risk-classifier` (**maker**) — grades a diff standard/normal/high and assembles `evidence.json`. PII/auth/payment/infra or 500+ lines forces high. Legal judgment delegated to legal.
- `adr-checker` (**checker, no Edit**) — falsifies ADR declaration vs code reality. Deterministic import checks belong to gate-fitness; boundary with analyze:arch-review. PASS/FIX/BLOCK.
- `threat-model-checker` (**checker, no Edit**) — falsifies STRIDE coverage gaps·missing assets·ungrounded accepted risks. PASS/FIX/BLOCK.
- `postmortem-checker` (**checker, no Edit**) — falsifies blame language·shallow root cause·ownerless actions. PASS/FIX/BLOCK.

> Checkers deliberately lack `Edit`. Their only `Write` target is their `verdict.json` (`.planning/gov/<area>/verdict.json`) — they never modify the artifact under review.

### Skills (3)

- `governance-templates` — the format single-source-of-truth. MADR·SLO·postmortem·change-policy templates + SOC2/ISMS-P control map (references/). Each template is aligned to its gate's contract.
- `fitness-function-guide` — stack tool selection (dependency-cruiser/import-linter/ArchUnit) + an ADR→enforceable-check conversion catalog.
- `supply-chain-guide` — gitleaks baseline operation·syft/grype·license denylist policy (references/license-denylist.json default).

### Gate scripts (not hook-registered — called via Bash by commands/loops)

`gate-adr` · `gate-fitness` · `gate-secrets` · `gate-supply-chain` · `gate-policy` · `gate-change-evidence` · `gate-threat-model` · `gate-error-budget` · `run-registered` (aggregator over `gates.json`). All take no arguments and honor `exit 0 = pass / 1 = fail` (`gate-error-budget` uses `2 = unmeasured`). External tools are overridable via `<TOOL>_BIN` env.

## Artifact contract (`.planning/gov/` + `docs/decisions/`)

```
docs/decisions/NNNN-<slug>.md          # ADR (industry-standard path)
.planning/gov/
├── gov-master.json                    # stack·init·adr_dir
├── gates.json                         # registered gates (plugin_root abs path + enabled/reason)
├── change/<sha>/evidence.json         # change evidence (gate-change-evidence)
├── threat/threagile.yaml, risks.json  # threat model
├── slo/thresholds.yaml, budget.json   # SLO thresholds (flat) + budget (observe/otel input)
├── postmortems/YYYY-MM-DD-<slug>.md    # blameless postmortems
├── <area>/verdict.json                # checker verdicts
└── audit-log.jsonl                    # append-only (no hand-editing — like HANDOFF auto-snapshot)
```

## Loop-engine linkage

1. **(a)** Every gate and `run-registered.sh` honors the no-argument `exit 0/1` contract → register any of them directly in a floop/mvp loop's `.planning/gate-cmd` (one line).
2. **(b)** `/loop-run "<goal>" --gate-cmd 'bash <plugin_root>/hooks/gates/run-registered.sh'` wires the generic loop straight to the whole registered set.
3. **(c)** `/gov-change`'s `evidence.json` (with `loop_artifacts` filled from `tasks.json`/`baseline.json`) connects "loop output = audit evidence."
4. **(d)** `gates.json`'s absolute `plugin_root` goes **stale when the plugin cache refreshes** → re-run `/gov-init` to re-register (the fix convention).

## Dependencies

- **requires**: none (no `hooks.json` — gates are invoked manually by commands/loops, so the common hook base is not required).
- **linkage**: `observe`·`infra/otel` (SLI input for `budget.json`), `mvp`·`feature-loop`·`harness:loop-run` (loop engines that can run the gates), `legal`/`finance`/`hr` (delegation boundaries for legal/financial/personnel judgment).

## Notes

- **A green gate means "checked and passed"** — never skip-green a missing tool for a registered gate. Make the skip explicit in `gates.json` (`enabled:false` + `reason`).
- **thresholds.yaml is flat** (`key: value`) so gates parse it with grep/sed — no yq dependency.
- **audit-log.jsonl / evidence bundles are evidence** — do not hand-edit or backfill; only `/gov-audit` and `/gov-change` write them.
- **No CI-server dependencies**: cosign/in-toto SLSA provenance is documentation-level only; SaaS GRC/scanner APIs are out (CSV/JSON export input only).
