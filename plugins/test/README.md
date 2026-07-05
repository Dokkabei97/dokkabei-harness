> **English** · [한국어](README_KO.md)

# test

> A test automation tool that bundles the TDD workflow and E2E testing (Playwright / Chrome) into a single plugin.

## Overview

`test` automates testing across the entire development cycle. It is built on two axes: a **TDD loop** (RED → GREEN → REFACTOR, 80%+ coverage) that forces you to write failing tests before writing code, and **E2E testing** that verifies completed user journeys. E2E splits into two paths depending on purpose. Playwright-based `/e2e` handles CI/CD regression, multi-browser, and headless automation, while Chrome Extension-based `/e2e-chrome` handles visual verification that needs an authenticated session or a quick, eyes-on local check.

It supports both TypeScript (Jest/Vitest/Playwright) and Kotlin (Kotest/MockK/Spring Boot Test) stacks. `/e2e` is designed to be reused as the **E2E acceptance gate (②ᴱ)** of the `mvp` plugin's Stage 4 loop, so the unit gate runs on every iteration while the slow E2E suite runs only once, just before completion.

## Components

### Commands

- `/tdd` — Enforces the TDD methodology. Proceeds in the order: scaffold interface → write failing test (RED) → minimal implementation (GREEN) → refactor (REFACTOR) → verify 80%+ coverage. It applies the `tdd-workflow` skill and provides both TypeScript and Kotlin examples.
- `/e2e` — Generates, maintains, and runs E2E tests with Playwright. Page Object Model-based test journey generation, multi-browser (Chromium/Firefox/WebKit) execution, screenshot/video/trace capture on failure, HTML/JUnit reports, flaky test detection and quarantine. The main session drives it directly via the `playwright` MCP server (when available) or the `npx playwright` CLI.
- `/e2e-chrome` — Controls a real browser via the Chrome Extension to visually verify natural-language scenarios. It decomposes natural language into test steps, checks per-step screenshots and console errors, and produces a checklist report containing failure causes and proposed fixes. Supports `--url` / `--gif` / `--viewport` options. Local-only, and it dispatches the `chrome-e2e-runner` agent.

### Agents

- `chrome-e2e-runner` — A visual E2E specialist agent that controls a real Chrome/Edge browser in `claude --chrome` mode. It leverages the browser's existing authenticated session to run natural-language journeys, verifies each step via DOM/console/screenshot, and produces a report that includes a session GIF and a severity-ranked issue table. (Tools: Read/Grep/Glob/Bash, model: opus)

### Skills

- `tdd-workflow` (`test:tdd-workflow`) — A skill that enforces test-first development when adding new features, fixing bugs, or refactoring. It covers the test pyramid (unit ~80% / integration ~15% / E2E ~5%), the Test Double preference hierarchy (Real > Fake > Stub > Mock), the DAMP > DRY principle for test code, and the Prove-It pattern of writing a bug reproduction test first. The `/tdd` command applies this skill.

## Usage

- **TDD**: `/tdd <description of the feature you want to implement>` — e.g. `/tdd I need a function to calculate market liquidity score`. The skill first defines the interface and generates a failing test, then drives just enough code to pass, the refactor, and the coverage report. For a bug fix, it starts by writing a reproduction test (RED).
- **Playwright E2E**: `/e2e <user journey to verify>` — e.g. `/e2e Test the market search and view flow`. It analyzes the scenario, generates test code, runs it across multiple browsers, and leaves failure artifacts. To wire it into the `mvp` loop, record the run command as a single line in `.planning/e2e-gate-cmd` (e.g. `npx playwright test`), and the Stop hook runs it automatically once all stories pass (if the file is absent, E2E is skipped, zero regression).
- **Chrome visual verification**: `/e2e-chrome <natural-language scenario>` — e.g. `/e2e-chrome --gif Fill out the signup form and confirm the redirect to the email verification page`. It requires `claude --chrome` mode; when inactive, it guides you to restart with `claude --chrome -c` while keeping the current session.

### Choosing `/e2e` vs `/e2e-chrome`

| Situation | Command |
|------|--------|
| CI/CD regression · multi-browser · headless | `/e2e` (Playwright) |
| Local visual check · authenticated session · external services (Google, etc.) | `/e2e-chrome` |
| Sharing results with the team as a GIF | `/e2e-chrome` |

## Dependencies

The plugin itself has no required dependencies. Good combinations to use together:

- `mvp` — Wires `/e2e` in as the E2E acceptance gate (②ᴱ) of the Stage 4 loop to verify the entire user journey just before completion.

## Notes

- **`/e2e-chrome` prerequisites**: `claude --chrome` mode, Claude in Chrome Extension v1.0.36+, Claude Code v2.0.73+, Chrome or Edge browser. It is a local-only path that does not work in CI/CD, and it does not generate Playwright code (that is the role of `/e2e`).
- **Caution for money-related flows**: E2E involving real funds must only be run on testnet/staging, and no automated tests are run against production. For financial tests, use the `test.skip(process.env.NODE_ENV === 'production')` guard and a small-amount test wallet.
- **Coverage baseline**: A minimum of 80% for all code, with 100% recommended for financial calculations, authentication, security, and core business logic.
- `chrome-e2e-runner` does not store or transmit user credentials and does not access browser data outside the active test tab.
