> **English** · [한국어](README_KO.md)

# legal

> A legal-team harness handling contract, corporate-investment, labor-IP, regulatory, and criminal-dispute risk under Korean law. A first-pass risk-diagnosis tool that does not replace attorney counsel.

## Overview

`legal` is a multi-agent legal harness that diagnoses legal matters under Korean law. Five specialist agents divide up contract review/drafting, corporate/investment legal work, labor/intellectual property, regulatory compliance, and criminal/dispute risk (defamation, insult, sex offenses, etc.), and the `legal-team-orchestrator` classifies the matter and attaches the appropriate specialist.

The team composition is an **Expert Pool + Fan-out/Fan-in** hybrid. For a single domain it dispatches one specialist; when two or more domains intersect, it deploys the relevant agents in parallel and then reports the cross-domain risk in an integrated fashion. All analysis takes the disclaimer, citation, and escalation principles of `korean-legal-foundations` as a shared foundation.

The core design intent is to respond to the **asymmetry of the cost of misjudgment**. When a matter trips a criminal signal, a sex-related issue, ongoing litigation, or a high-value/irreversible transaction, it forces a "must consult an attorney" notice at the very top of the output and advises against acting on the harness result alone. In other words, this tool is not advice that reaches a conclusion, but a first-pass screener that sorts out whether or not to go to a specialist and what to ask.

## Components

### Commands

- `/contract-review` — Reviews toxic clauses in contracts, NDAs, service agreements, investment agreements, etc., with per-clause risk grades and revised wording (redline), and identifies missing clauses.
- `/contract-redline` — Diff-aligns the counterparty's revision (counter draft) against the original clause by clause, and offers accept/revise/reject recommendations per change, three-version alternative wordings, and negotiation priorities.
- `/draft-legal-doc` — Drafts contracts, certified-mail (content-certified) letters, settlement agreements, notices, etc., in a Korean-law standard structure and presents options for key clauses. `--format docx` delegates to the official `docx` skill.
- `/compliance-check` — Checks compliance items under the Personal Information Protection Act, the Act on Consumer Protection in Electronic Commerce, and the Network Act, and presents violation risks and corrective actions.
- `/defamation-assess` — Analyzes the likelihood that the elements of defamation/insult are met and presents response options by victim/suspect perspective. Since it is a criminal matter, it strongly recommends retaining an attorney.
- `/legal-risk-scan` — A comprehensive scan that analyzes the matter, deploys the relevant specialist agents in parallel, and reports cross-domain risk in an integrated fashion.

### Agents

- `contract-counsel` — Contract-law specialist. Detects toxic clauses under the Civil Act and Commercial Act, reviews and drafts NDAs and service, mandate, investment, and license agreements, and produces per-clause risk grades and revised wording.
- `corporate-counsel` — Corporate/investment legal specialist. Under the Commercial Act and the Venture Business Act, analyzes company formation, shareholders' agreements (SHA), fundraising (term sheets, SAFE, convertible bonds), stock options, equity structure, and M&A fundamentals through the founder's-perspective lens of dilution and control risk.
- `labor-ip-counsel` — Labor/intellectual property specialist. Handles dismissal/wage/employment-rules risk under the Labor Standards Act, and protection strategies for trademarks, copyrights, patents, trade secrets, and employee inventions.
- `compliance-counsel` — Regulatory compliance specialist. Checks compliance with the Personal Information Protection Act, the Act on Consumer Protection in Electronic Commerce, the Network Act, the Location Information Act, and industry-specific licensing from a code/operations perspective, and quantifies sanction risk.
- `dispute-risk-counsel` — Criminal/dispute risk specialist. Under the Criminal Act, the Network Act, and the Act on the Punishment of Sexual Violence, evaluates the elements of defamation, insult, sex offenses, intimidation, and stalking, along with complaint/defense responses, and always recommends retaining an attorney as a priority.

### Skills

- `legal-team-orchestrator` — The legal-team orchestrator. Classifies the matter as Single/Multi/Full Scan, routes and parallel-dispatches agents, reports in an integrated fashion via cross-analysis and a prioritized action plan, and forces escalation.
- `korean-legal-foundations` — The harness's shared foundation. Provides the legal system and the hierarchy of sources of law (法源), rules for citing and verifying statutes, disclaimer principles and attorney-escalation criteria, and the principle of distinguishing fact from evaluation.
- `contract-law-guide` — Practical contract-law guide. Toxic-clause checklist, mandatory clauses by type, legal doctrine on penalties, damages, and the Act on the Regulation of Terms and Conditions, and redline-drafting patterns.
- `corporate-investment-guide` — Corporate/investment legal guide. Company formation, key SHA clauses, investment-agreement (RCPS, convertible-bond, SAFE-type) terms, stock-option structure, dilution/control analysis.
- `labor-ip-guide` — Practical labor/intellectual property guide. Dismissal/wage risk (Labor Standards Act), protection of trademarks, copyrights, patents, and trade secrets, attribution of employee inventions and works made for hire.
- `compliance-guide` — Regulatory compliance guide. Personal Information Protection Act (2023 amendment) lifecycle, obligations under the Act on Consumer Protection in Electronic Commerce, advertising regulation under the Network Act, industry-specific licensing.
- `dispute-criminal-risk-guide` — Criminal/dispute risk guide. Elements of defamation, insult, and cyber-defamation, overview of sex-related crimes, intimidation/stalking, evidence preservation, and victim/suspect response procedures.

## Usage

- **Direct command invocation**: When the purpose is clear, use the relevant command directly. E.g., `/contract-review --role 을 --type service 용역계약.pdf`, `/defamation-assess --role 피해자 --channel online 악성 댓글 상황`.
- **Redline round-trips**: With `/contract-redline 원안.md 상대방수정안.md --role 을 --round 2`, compare the counter draft against the original clause by clause. Handing over a single tracked-changes docx is enough.
- **Comprehensive scan (automatic orchestration)**: For requests like "Is there any legal problem?", "full risk check", "comprehensive legal review", or for matters entangling multiple legal domains, the `legal-team-orchestrator` is triggered to deploy the relevant agents in parallel and produce an integrated risk report. You can also start it directly with `/legal-risk-scan [상황] --scope all --target [경로]`.
- **Integrated reporting flow**: The orchestrator proceeds in the order matter classification (Single/Multi/Full) → routing → parallel dispatch → cross-analysis and prioritized action plan, and if the matter is an escalation target, it forces a "⚠️ Must consult an attorney" notice with the reason at the very top of the report.

## Dependencies

- There are no separate required plugin dependencies.
- `/draft-legal-doc --format docx` optionally uses the official `docx` skill (`document-skills`) and `python3`. If not installed, it automatically falls back (graceful degrade) to md output and prints a one-line installation guide: `/plugin marketplace add anthropics/skills` then `/plugin install document-skills@anthropic-agent-skills`.
- By domain boundary, financial/tax matters are handled separately by the `finance` plugin, which transplants the skeleton of `legal`'s Escalation Policy; and when an HR matter requires a labor-law determination, the `hr` plugin cross-delegates to `legal:labor-ip-counsel`.

## Notes

- **Not a replacement for expert counsel**: All outputs are a first-pass risk diagnosis and do not replace attorney counsel. In particular, for criminal signals (booking, investigation, summons, search and seizure, receipt of a complaint), sex-related matters, the merits of ongoing litigation, and irreversible/high-value transactions such as those with a transaction value of KRW 100 million or more, real estate, M&A, or joint-and-several guarantees, attorney review is mandatory before signing, remitting, making statements, or submitting.
- **Escalation thresholds are adjustable**: The amount cutoffs (KRW 100 million / 10 million) and the mandatory/recommended boundary are conservative defaults calibrated to an individual user, and can be adjusted to your own risk tolerance. If a trigger is ambiguous, apply it upward (conservatively).
- **Beware of hard-coded statutes**: Statutes and requirements may be amended, so verify the latest provisions when citing. Agents can verify grounds via `WebSearch`/`WebFetch`.
- **No definitive determinations**: The harness describes not "this is a violation" but "the likelihood the elements are met / the risk level," and does not assist in unlawful acts such as evidence destruction, false accusation, or law-evasion design.
