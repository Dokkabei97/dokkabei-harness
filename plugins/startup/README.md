> **English** · [한국어](README_KO.md)

# startup

> A harness that turns ideas into verifiable business hypotheses using Lean Startup methodology, dividing market, product, growth, and finance across specialized agents to generate deliverables.

## Overview

`startup` is a startup workbench that structures idea-stage businesses along a market research → product planning → growth marketing → financial modeling flow. It delegates each domain to a dedicated agent (maker), and all deliverables are materialized as files under `.planning/business/` — following the design principle that state such as tone, hypotheses, and metrics is guaranteed by files rather than by session memory.

The core characteristic is **maker/checker separation**. Business deliverables such as market research, lean canvas, unit economics, and growth plans almost always converge on "opportunity exists (GO)" because of the maker's confirmation bias. `assumption-killer` is a checker completely separated from the maker, deliberately without the Edit tool, serving as a counter-balance (kill-gate) that only looks for "reasons not to do this business."

The boundaries are also clear. Once the business hypothesis solidifies, `/mvp-from-startup` connects to the `mvp` harness (code stage); the advertising-regulation judgment for content is delegated to the `legal` plugin, and pitch deck pptx conversion to the official `pptx` skill. This plugin itself scopes to the authoring of business hypotheses, strategy, and deliverables.

## Components

### Commands

- `/lean-canvas` — Convert an idea into a structured business hypothesis via the lean canvas 9 blocks.
- `/market-research` — Generate a market research report including TAM/SAM/SOM estimation, competitor analysis, and customer segments.
- `/validate-idea` — Identify high-risk hypotheses based on Build-Measure-Learn and design experiments.
- `/unit-economics` — Calculate CAC, LTV, burn rate, and runway, and assess financial health.
- `/growth-plan` — Establish an AARRR-funnel-based channel strategy, experiment backlog, and 30/60/90-day execution plan.
- `/pitch-deck` — Design an investor-perspective storyline and the key message per slide (connects to the official pptx skill via `--export pptx`).
- `/content-draft` — Generate brand-voice-based blog/sns/pr/email content drafts. On first run, a 5-question interview materializes `brand-voice.md`, which all subsequent content then references.
- `/feedback-synthesis` — Structure secured interview notes, VoC, and review dumps into patterns, insights, and opportunity hypotheses. The 'story candidates' section is produced in a form the mvp harness reads (activates only when feedback files exist).
- `/kill-check` — Adversarially refute the load-bearing assumptions of business deliverables and issue a GO/PIVOT/KILL judgment.

### Agents

- `market-researcher` — TAM/SAM/SOM estimation, competitor analysis, customer segment/persona derivation, industry trend analysis (web-search based).
- `product-strategist` — Lean canvas authoring, MVP definition, formulating verifiable hypotheses, applying Build-Measure-Learn and Customer Development.
- `financial-modeler` — Unit economics, burn rate/runway, revenue model/revenue forecasting, funding strategy/valuation.
- `growth-marketer` — AARRR funnel design, Bullseye channel strategy, CAC/LTV optimization, content and SEO/ASO, growth experiment design (also handles content draft authoring).
- `assumption-killer` — A checker that skeptically refutes deliverables left by other agents. Identify load-bearing assumptions → adversarial attack ranked by vulnerability × impact → GO/PIVOT/KILL judgment. Not holding Edit fundamentally blocks the path of fixing a deliverable to make it pass.

### Skills

- `lean-startup-guide` — Build-Measure-Learn, the 4 stages of Customer Development, MVP type selection, pivot decision framework.
- `market-sizing-guide` — Top-Down/Bottom-Up/Value Theory market sizing methods and investor-perspective validation criteria.
- `unit-economics-guide` — CAC/LTV/Payback calculation methods, metrics per revenue model, burn rate/runway management and benchmarks.
- `growth-hacking-guide` — AARRR funnel, Bullseye channel strategy, ICE experiment prioritization, viral loops, North Star Metric.
- `pitch-deck-guide` — Sequoia/YC slide structure, emphasis points per round, storytelling, common mistakes and Q&A preparation.
- `content-guide` — Structure templates per blog/sns/pr/email type and the `brand-voice.md` schema and 5-question interview specification (per-type templates see `references/`).

## Usage

Invoke each command directly or trigger it with a natural-language request. Most deliverables are saved as files under `.planning/business/` and become the input for subsequent commands.

- **Initial hypothesis**: `/lean-canvas [idea]` → `/market-research [industry]` → design experiments with `/validate-idea`.
- **Finance/investment**: `/unit-economics --model saas` → `/pitch-deck --stage seed --export pptx`.
- **Growth**: After launch, establish channel/experiment/execution plans with `/growth-plan --stage post-pmf`.
- **Content**: `/content-draft --type blog [topic]` — a brand voice interview on first run, refresh with `--revoice`.
- **Customer feedback**: `/feedback-synthesis --source review ./reviews.csv` (feedback file required). Immediately refute derived hypotheses with `--kill-check`.
- **Decision gate**: Right before investment/kickoff, or before entering `/mvp-from-startup`, have load-bearing assumptions refuted with `/kill-check`.

## Dependencies

There are no hard dependencies. However, using it together with the following plugins/skills keeps the flow connected.

- `mvp` — Connect the business hypothesis to the code stage via `/mvp-from-startup`. The 'story candidates' of `/feedback-synthesis` are read by mvp's `product-strategist` as material for PRD authoring (Stage 1).
- `legal` — The judgment on display-advertising law and advertising-information regulation for content is delegated to `/compliance-check`.
- Official `pptx` skill (document-skills) — When `/pitch-deck --export pptx` runs, it converts the slide structure + speaker notes to pptx (when installed).

## Notes

- Agents collect real-time data via `WebSearch`/`WebFetch`. Numbers without evidence are marked as `[추정]`/`[근거 필요]` and not fabricated.
- `/content-draft` leaves guidance when it detects exaggerated-advertising or display-advertising-law risk expressions, but the regulatory-compliance judgment itself is the `legal` plugin's job.
- This plugin is a first-pass diagnostic tool for business, finance, and legal matters, and does not replace the advice of accountants, lawyers, or investment professionals.
