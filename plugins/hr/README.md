> **English** · [한국어](README_KO.md)

# hr

> An HR harness that produces practical deliverables for recruiting (JD/interviews) and people-ops (onboarding/evaluation). A first-line practical tool that hands labor-law judgments off to `legal:labor-ip-counsel`.

## Overview

`hr` is a compact HR harness that structures and produces practical documents for recruiting and the post-hire experience (people-ops). It produces job-description (JD) drafts, competency-based interview kits, and onboarding 30-60-90 plans through two read-only advisory agents, three commands, and one shared guide skill. The goal is to turn the vague standard of "a good person" into verifiable competencies, "figuring things out on their own" into a measurable ramp-up, and "gut-feel evaluation" into an anchor-based rubric.

The core design principle is the **separation of practical work from legal judgment**. Labor-law issues such as hiring discrimination, dismissal, work rules, and annual leave/allowances are not conclusively judged by this harness; per the 'cross-domain-plugin risk escalation protocol' in the `hiring-guide` skill, they are forcibly cross-delegated to `legal:labor-ip-counsel`. In other words, hr is a first-line practical tool that designs the practical structure and hands legal-compliance judgment off to the legal harness.

Another principle is **no expansion before confirming real demand**. Orchestrators and hooks are not placed until real need is confirmed (compact edition). So the commands operate with a simple structure that delegates directly to their corresponding advisory agent.

## Components

### Commands

- `/jd-draft` — Structures a job-description (JD) draft into role, key responsibilities, and required/preferred qualifications, and heuristically inspects for discriminatory expressions regarding age, gender, appearance, origin, marital status, etc., applying neutral replacement wording. Use `--check-only` to inspect an existing JD only, and `--benchmark` to reflect market benchmarks.
- `/interview-kit` — Designs a competency model, behavioral (STAR) questions, and a 4-level anchor evaluation rubric, and generates an interview kit that includes a list of prohibited questions. It automatically inherits the `/jd-draft` deliverable and supports `--stages`, `--competencies`, and `--with-assignment`.
- `/onboarding-doc` — Writes a pre-hire (D-7)–through–first-week checklist and a 30-60-90 ramp-up plan, together with assigned owners, measurable completion criteria, and a manager check-in agenda. Supports `--format`, `--team`, and `--buddy`.

### Agents

- `recruiting-advisor` — Recruiting advisory agent (read-only). Advises on JD design, recruiting funnel composition, and competency-based interviews (questions/rubrics), and heuristically detects discriminatory expressions in postings. It does not make conclusive compliance judgments and recommends delegating to legal.
- `people-ops-advisor` — People-ops advisory agent (read-only). Advises on onboarding (30-60-90), evaluation rubrics/performance-review systems, and organizational documents (handbook/R&R/meeting bodies). It flags points of contact with statute such as work rules, dismissal, and annual leave/allowances, and recommends delegating to legal.

### Skill

- `hiring-guide` — The shared practical foundation of the harness. Provides a standard recruiting-funnel structure, a standard JD structure and a discriminatory-expression self-check table, competency-based interviews and a 4-level anchor rubric, and an onboarding 30-60-90 standard. The core is the **legal-judgment-needed trigger table** (hiring discrimination, dismissal, work rules, annual leave/allowances, employment contracts, employment type, harassment, organization-size boundary) and the **cross-domain risk escalation protocol**, which forces a `legal:labor-ip-counsel` call when a trigger is detected.

## Usage

- **Calling commands directly**: If the purpose is clear, use the relevant command right away. e.g. `/jd-draft 백엔드 개발자 (Kotlin/Spring, 검색 플랫폼팀)`, `/interview-kit --stages 3 --with-assignment 데이터 분석가`, `/onboarding-doc --team 검색플랫폼팀 --format full 데이터 엔지니어`.
- **Recruiting-pipeline linkage**: The deliverable that `/jd-draft` saves to `.planning/hr/jd/{직무명}.md` is automatically inherited by `/interview-kit`. It proceeds in the order JD writing → interview-kit design → onboarding document.
- **Automatic activation**: When recruiting/onboarding keywords such as `hiring, job description, interview kit, rubric, onboarding` are detected, the `hiring-guide` skill is triggered and applies the standard structure and escalation protocol.
- **When only advice is needed**: If you want only design direction without generating a document, the agent advises read-only. Saving deliverables is performed not by the agent but by the main session (`Write`) under `.planning/hr/`.
- **Handling legal triggers**: When wording such as probation termination, annual-leave grant, a conditional offer, or potentially discriminatory phrasing appears in a deliverable, mark `⚠ 법률 판단 필요` at that location and delegate to `legal:labor-ip-counsel` along with a summary of the facts. If legal is not installed, leave the item unresolved and guide the user to run the legal harness.

## Notes

- **Not a substitute for expert advice**: All deliverables are practical structural designs and do not replace advice from a labor attorney or lawyer. Legal issues are based on the first-line diagnosis of `legal:labor-ip-counsel`, and the final deliverable states that limitation explicitly.
- **No conclusive judgments**: The hr harness does not conclude the legality of hiring discrimination, dismissal, work rules, annual leave/allowances, or employment-contract clauses as "a violation / lawful." Such judgment is entirely the domain of `legal:labor-ip-counsel`; hr merely detects and flags signals and delegates.
- **legal-harness linkage recommended**: For tasks requiring labor-law judgment, it is advisable to install the `legal` plugin alongside. There is no separate mandatory plugin dependency, but if legal is absent when a trigger occurs, that item is left unresolved.
- **Beware the organization-size boundary**: The transition from under-5 employees to 5-or-more is a boundary where the applicable statutes change, so when designing onboarding/evaluation systems, confirm organization size first and treat the relevant items as legal triggers.
- **Discriminatory-expression inspection is heuristic**: Detection of discriminatory expressions in JDs and interview questions is a signal-based heuristic and not a conclusive determination of illegality. Hiring discrimination can be subject to sanctions under the Equal Employment Opportunity Act, the Age Discrimination Prohibition Act, the Hiring Procedures Act, and others, so conclusive judgment is delegated to legal.
- **Expansion policy**: Orchestrators, hooks, and deeper evaluation systems are not added before real demand is confirmed (`plugin.json` compact-edition principle).
