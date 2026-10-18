> **English** · [한국어](ARCHITECTURE_KO.md)

# Harness Plugin Architecture & upstream Migration Guide

> This plugin is a fork that starts from [revfactory/harness](https://github.com/revfactory/harness) (Apache-2.0) and has been **restructured** to fit the in-house marketplace. upstream ships two skills (`harness` + `evolve`), but
> this fork splits the responsibilities into 4 skills + 4 commands (design / evolution / generation / validation, plus the lightweight loop).

## 1. Structure Overview

```
harness/
├── skills/
│   ├── team-harness/        # design: audit → domain analysis → execution mode + team pattern → agents/skills/orchestrator (meta-skill, v2)
│   ├── evolve/              # evolution: feedback → generalize → apply one change at a time → git-recorded delta
│   ├── flow-scaffolding/    # generation: component templates (used by create-flow)
│   └── flow-validation/     # validation: 10 rulesets (used by verify-flow)
├── commands/
│   ├── create-flow.md       # component generation entry point
│   ├── verify-flow.md       # component validation entry point
│   ├── loop-run.md          # lightweight generic loop start
│   └── loop-stop.md         # lightweight generic loop kill switch
├── hooks/                   # generic-loop-stop-hook.sh (engine=generic)
└── docs/
    └── ARCHITECTURE.md      # (this document)
```

**Design principle — single-responsibility separation:**
- **Design (team-harness)**: "who collaborates / how" — execution mode, pattern selection, agent separation criteria, model tiers, orchestrator design
- **Evolution (evolve)**: adjusts an existing harness from run feedback; structural redesign goes back to team-harness
- **Generation (create-flow + flow-scaffolding)**: scaffolds the decided design into actual files
- **Validation (verify-flow + flow-validation)**: mechanically validates the generated artifacts against rulesets

## 2. upstream ↔ fork Concept Mapping (upstream v2.1.0)

| upstream | fork counterpart |
|----------|-----------------|
| harness 0단계 state check (build / extend / operate) + v1 detection | team-harness Phase 0 Audit (+ 3-way Drift Detection) |
| 1단계 domain analysis | team-harness Phase 1 |
| 2단계 execution mode + team pattern + quality patterns | team-harness Execution Modes / 6 Patterns / verification·loop patterns, Phase 2 |
| 3단계 agent definitions (reuse check, model tiers, tools) | team-harness Phase 3 (reuse-first gate) → **generation delegated to create-flow** |
| 4단계 skill writing | team-harness Phase 4 |
| 5단계 integration (modes, data transfer, errors, scale, follow-ups) | team-harness Phase 5 |
| 5-4 CLAUDE.md trigger + change history table | team-harness Phase 6 — trigger only; **change history = git commit bodies** |
| 6단계 validation | team-harness Phase 7 → **verify-flow + flow-validation rulesets** |
| 7단계 operations / `harness:evolve` | team-harness Phase 7 operations / **evolve** skill |
| references (9) | same set; `team-patterns.md` replaces the old `agent-design-patterns.md`, plus the fork-only `loop-harness-guide.md` |

## 3. fork-specific Extensions (not in upstream)

- **Command separation**: independently invoke generation/validation via `/create-flow`·`/verify-flow`
- **flow-validation 10 rulesets**: agt/cmd/hk/loop/orc/qua/sec/skl/team/**xrf** (cross-reference) — mechanical checks, including v1-artifact detection and Workflow-script pitfalls
- **Verification·loop patterns**: Verification Gate / Guardrails on top of upstream's quality patterns, and the Loop Harness Design (4 elements) with a Stop-hook engine
- **Cross-harness orchestration**: collaboration call table, delegation boundaries, reuse-vs-clone rule for loop engines
- **Git as the change ledger**: evolve records every delta as one Conventional Commit with the why in the body, instead of a CLAUDE.md table
- **Production operation**: actually operating production harnesses such as `search`·`mvp`·`feature-loop` with this meta-skill

## 4. Cautions When Syncing with upstream

When tracking upstream, the principle is **selective concept porting, not version following**. Since the fork has structurally diverged:

1. Map upstream new features to the right place among the fork's responsibilities (design / evolution / generation / validation).
2. Do not port upstream's single-skill premises (step numbers, CLAUDE.md change-history table, `.claude/commands/` prohibition) as-is.
3. Merge 3-way: upstream previous sync point → fork → upstream new version, so fork-local additions survive.
4. After porting, record the source (upstream version + commit) and mapping in the commit body and update `NOTICE`.

Last sync: 2026-10-18 (upstream v2.1.0, commit 928de2c — v2 rebuild + evolve).
