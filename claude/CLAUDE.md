Operating Principles (Andrej Karpathy)

1. Surface confusion before coding. If a request has multiple valid interpretations, ask. Don't run with the first assumption.
2. No unrequested abstractions. Touch only what the task requires. Three repeated lines beat a premature helper.
3. Convert tasks into verifiable success criteria before looping. Define "done" up front; then iterate until it's met.
4. Push back when wrong. Surface tradeoffs and inconsistencies instead of silently complying.

Workflow Orchestration (Boris Cherny)

1. Plan Mode Default

Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
If something goes sideways, STOP and re-plan immediately – don't keep pushing
Use plan mode for verification steps, not just building
Write detailed specs upfront to reduce ambiguity

2. Subagent Strategy

Use subagents liberally to keep main context window clean
Offload research, exploration, and parallel analysis to subagents
For complex problems, throw more compute at it via subagents
One task per subagent for focused execution

3. Self-Improvement Loop

After ANY correction from the user: update tasks/lessons.md with the pattern
Write rules for yourself that prevent the same mistake
Ruthlessly iterate on these lessons until mistake rate drops
Review lessons at session start for relevant project

4. Verification Before Done

Never mark a task complete without proving it works
Diff behavior between main and your changes when relevant
Ask yourself: "Would a staff engineer approve this?"
Run tests, check logs, demonstrate correctness

5. Demand Elegance (Balanced)

For non-trivial changes: pause and ask "is there a more elegant way?"
If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
Skip this for simple, obvious fixes – don't over-engineer
Challenge your own work before presenting it

6. Autonomous Bug Fixing

When given a bug report: just fix it. Don't ask for hand-holding
Point at logs, errors, failing tests – then resolve them
Zero context switching required from the user
Go fix failing CI tests without being told how

7. Task Management

Plan First: Write plan to tasks/todo.md with checkable items
Verify Plan: Check in before starting implementation
Track Progress: Mark items complete as you go
Explain Changes: High-level summary at each step
Document Results: Add review section to tasks/todo.md
Capture Lessons: Update tasks/lessons.md after corrections

8. Core Principles

Simplicity First: Make every change as simple as possible. Impact minimal code.
No Laziness: Find root causes. No temporary fixes. Senior developer standards.
Minimal Impact: Changes should only touch what's necessary. Avoid introducing bugs.

---

Installed Harnesses (dokkabei-harness marketplace)

This repository is the `dokkabei-harness` plugin marketplace. Plugins live under `plugins/<name>/`
and are registered in `.claude-plugin/marketplace.json`. Install with
`/plugin install <name>@dokkabei-harness`.

- Base & meta: base (guard hooks + LSP), harness (create-flow/verify-flow/team-harness, /loop-run), observe (skill-usage tracing)
- Dev workflow: analyze, test, workflow
- Loop engineering: mvp (greenfield), feature-loop (brownfield) — Stop-hook loop engines with gate state machines
- Backend: backend-shared + kotlin-spring / python-fastapi / go-mux / nextjs, search (Elasticsearch)
- Domain: legal, finance, hr, startup, etc
- Local observability: `infra/otel/` — grafana/otel-lgtm docker-compose receiving Claude Code
  built-in OTel (cost/tokens/events; Grafana at localhost:3000). Complements observe's
  `.claude/skill-trace.jsonl` (OBSERVE_TRACE=1); cross-check via shared session_id/prompt_id.

Conventions: component rules and validation live in `plugins/harness/skills/flow-validation/`;
scaffolding templates in `plugins/harness/skills/flow-scaffolding/`. Hook regression tests are
in `tests/hooks/*.bats`. Register new teams/orchestrators here per the Team Required Structure rule.
