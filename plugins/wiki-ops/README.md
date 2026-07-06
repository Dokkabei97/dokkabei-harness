> **English** · [한국어](README_KO.md)

# wiki-ops

Knowledge-ops harness that **drives the [llm-wiki](https://github.com/Dokkabei97/llm-wiki) CLI as a tool** to
operate a cited, plain-text knowledge vault: gated feed → deterministic audit → curation loop → cited Q&A.

Core proposition: **the wiki's trust is produced by code, not by a model.** llmwiki ships three
LLM-0 deterministic lint gates (structure / citation integrity / frontmatter schema) — this plugin
does not invent its own gates; it assembles the tool's built-in gates into loop stop-conditions.
Completion is judged by exit codes, never by model self-assessment.

## Requirements

- `llmwiki` on PATH (`uv tool install`), or a local llm-wiki checkout pointed to by `LLMWIKI_REPO`
- A vault directory (any empty dir — `llmwiki init` scaffolds it) with git
- [Ollama](https://ollama.com) on loopback for real summaries/answers — **optional**: all three
  gate lints are LLM-0 and keep working when Ollama is down; `--provider fake` gives deterministic dry runs
- The `harness` plugin (dependency) — the curation loop reuses its generic Stop-hook loop engine

## Components

| Component | Kind | Purpose |
|-----------|------|---------|
| `wiki-ops-orchestrator` | skill | Gated state machine: Stage 0 intake → 1 feed → 2 audit → 3 curate loop → 4 ask |
| `/wiki-feed` | skill | Ingest files/dirs into the vault (sequential, per-file report) |
| `/wiki-audit` | skill | Run all lint gates + contradiction-ledger triage + curation-fraud check |
| `/wiki-curate` | skill | Fix lint findings until gates are green (delegates to `/loop-run`, engine=generic) |
| `/wiki-ask` | skill | Cited Q&A: query / `--persist` synthesis / research routing |
| `/wiki-status` | skill | Read-only one-screen vault status (never mutates state) |
| `wiki-curator` | agent | Maker — batch ingest, finding-resolution edits (has Edit) |
| `wiki-auditor` | agent | Checker — lint triage + fraud detection (no Edit by design) |
| `wiki-librarian` | agent | Q&A/synthesis routing, honest "no grounding" reporting |

## Quickstart

```
/wiki-feed ~/notes/*.md --vault ~/kb     # compile documents into the vault
/wiki-audit --vault ~/kb                 # deterministic health report + contradiction triage
/wiki-curate --vault ~/kb                # loop until structure/integrity/schema lints are green
/wiki-ask "When do tokens expire?"       # answer with verbatim-quote citations
```

## Loop safety

The curation loop runs on the harness generic engine: deterministic gate
(`lint && lint --integrity && lint --schema`), completion promise, max 12 iterations / 60 min /
no-progress detection, kill switch `/loop-stop`. Contradictions are **never auto-resolved** —
they always escalate to a human decision (★G1 user gate).

## Boundaries

- Developing the llm-wiki source code itself → `feature-loop` / stack plugins
- Company wiki documentation (Outline) → `workflow:document-latest`
- Web-based deep research reports → `deep-research` (vault-grounded research: `/wiki-ask --research`)
