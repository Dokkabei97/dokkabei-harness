> **English** · [한국어](ARCHITECTURE_KO.md)

# Harness Plugin Architecture & upstream Migration Guide

> This plugin is a fork that starts from [revfactory/harness](https://github.com/revfactory/harness) (Apache-2.0) and has been **restructured** to fit the in-house marketplace. upstream is a single `harness` skill (monolithic), but
> this fork splits the responsibilities into 3 skills + 2 commands.

## 1. Structure Overview

```
harness/
├── skills/
│   ├── team-harness/        # design: domain analysis → team architecture → orchestrator design (meta-skill)
│   ├── flow-scaffolding/    # generation: component templates (used by create-flow)
│   └── flow-validation/     # validation: 9 rulesets (used by verify-flow)
├── commands/
│   ├── create-flow.md       # component generation entry point
│   └── verify-flow.md       # component validation entry point
└── docs/
    └── ARCHITECTURE.md      # (this document)
```

**Design principle — single-responsibility separation:**
- **Design (team-harness)**: "who collaborates / how" — pattern selection, agent separation criteria, orchestrator design
- **Generation (create-flow + flow-scaffolding)**: scaffolds the decided design into actual files
- **Validation (verify-flow + flow-validation)**: mechanically validates the generated artifacts against rulesets

## 2. upstream ↔ fork Concept Mapping

| upstream (single harness skill) | fork counterpart |
|------------------------------|-----------|
| Phase 0 audit + Drift Detection | team-harness Phase 0 Audit |
| Phase 1 domain analysis | team-harness Phase 1 |
| Phase 2 team design (mode+pattern+4 axes) | team-harness Phase 2 |
| Phase 3·4 agent/skill generation | team-harness Phase 3 → **delegated to create-flow** |
| Phase 3-0/4-0 reuse review | team-harness Phase 3 "reuse-first gate" |
| Phase 5 integration·orchestration | team-harness Phase 4 registration |
| Phase 6 validation (6 stages) | team-harness Phase 5 → **verify-flow + flow-validation 9 rulesets** |
| Phase 7 evolution | team-harness Phase 6 Feedback Loop |
| 6 architecture patterns / 3 execution modes | preserved as-is + 4 additional validation·loop-reinforcing patterns |

## 3. fork-specific Extensions (not in upstream)

- **Command separation**: independently invoke generation/validation via `/create-flow`·`/verify-flow`
- **flow-validation 9 rulesets**: agt/cmd/hk/orc/qua/sec/skl/team/**xrf** (cross-reference) — more mechanical than upstream's "6-stage validation" description
- **Validation·loop-reinforcing patterns**: Adversarial Verify / Loop-until-dry / Verification Gate / Guardrails (reflecting 2026 trends)
- **Production operation**: actually operating production harnesses such as `search`·`legacy` with this meta-skill

## 4. Cautions When Syncing with upstream

When tracking upstream, the principle is **selective concept porting, not version following**. Since the fork has structurally diverged:

1. Map upstream new features to the right place among the fork's 3 responsibilities (design/generation/validation).
2. Do not port upstream's single-skill premises (Phase numbers, internal generation logic) as-is.
3. After porting, record the source (upstream version) and mapping in the CLAUDE.md `## Harness` change history.

Last sync: 2026-06-11 (based on upstream v1.2.1 + Unreleased, porting U1~U4).
