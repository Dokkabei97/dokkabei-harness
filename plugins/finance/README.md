> **English** · [한국어](README_KO.md)

# finance

> A harness that reviews already-incurred operational finance and tax in read-only mode to diagnose evidence gaps, anomaly signals, and Korean tax risks.

## Overview

`finance` is a read-only diagnostic tool that, targeting already-spent expenses and already-prepared financial materials, does not re-create the numbers but instead draws out anomaly signals, evidence gaps, and tax risks from those numbers. It covers three tracks: expense/documentation eligibility review, financial statement (income statement, balance sheet) and profit-and-loss first-pass interpretation, and Korean tax risk screening (VAT, withholding tax, corporate tax/comprehensive income tax). Use it when you want to understand the materials yourself before closing/filing, when you want to organize the issues in advance before sending them to a tax accountant, or when you have received a tax office notice and are at a loss for where to start.

The design revolves around two axes. One is the **disclaimer/escalation principle** — every deliverable is only a first-pass risk diagnosis and does not replace the advice of a tax accountant/CPA, and instead of definitive judgments ("no problem", "deductible as a loss") it describes only at the level of possibility/signal. It judges mandatory/advisory triggers along the three axes of tax audit likelihood × amount scale × filing deadline imminence, and on a mandatory trigger it forcibly places "⚠️ Must consult a tax accountant/CPA" at the very top of the report (transplanting the skeleton of the legal plugin's Escalation Policy). The other is the **no-hardcoding of tax rates/threshold amounts** — because Korean tax law is revised every year, whenever a tax rate/limit/deadline enters into a judgment it must confirm the current-year basis via WebSearch and cite the source and confirmation year alongside it, and on confirmation failure it leaves the figure blank and marks it "confirmation needed".

This plugin covers **only already-incurred operational finance and tax**. Forward-looking modeling such as unit economics for business planning, burn rate/runway, and funding strategy is out of scope and is handled by `startup:financial-modeler`.

## Components

### Commands

- `/expense-review` — Expense/spending documentation eligibility review. Detects qualified-evidence gaps, commingling of personal costs, and account classification anomalies in spending records, and proposes remediation directions. Supports `--target` (file path), `--period` (period), `--focus 증빙|분류|사적혼입` options. Delegates to `finance-analyst` and cross-checks tax-directly-related items with `tax-risk-advisor`.
- `/financial-review` — Financial statement/profit-and-loss first-pass interpretation. Analyzes trends, ratios, and anomalous items in the income statement/balance sheet and identifies cash flow warning signals. Supports `--target`, `--compare` (prior-period comparison), `--focus 손익|재무상태|현금흐름` options.
- `/tax-risk-scan` — Korean tax risk screening. Detects non-filing/under-filing/documentation-deficiency risks from the perspective of VAT, withholding tax, and corporate tax (comprehensive income tax) filing, and flags imminent deadlines. Supports `--scope vat|withholding|corporate|all`, `--entity 법인|개인-일반|개인-간이`, `--target`, `--deadline` options. Delegates to `tax-risk-advisor` and cross-checks documentation issues with `finance-analyst`.

### Agents

- `finance-analyst` — Operational finance analysis specialist. A read-only advisory agent that performs expense/spending documentation eligibility review, financial statement first-pass interpretation (trends, ratios, anomalous items), and detection of cost-structure and cash flow anomaly signals. Identifies only risk signals without definitive judgments.
- `tax-risk-advisor` — Korean tax risk screening specialist. Detects signals based on the penalty-tax risk axes (non-filing, under-filing, late payment, documentation deficiency, non-submission of payment statements) from the perspective of VAT, withholding tax, and corporate tax (comprehensive income tax). A read-only advisory agent that confirms specific tax rates/threshold amounts for the current year via WebSearch and cites the source alongside them.

### Skills

- `korean-tax-foundations` — Common foundations for the Korean tax harness. Provides the tax-item structure (VAT, withholding tax, corporate tax, comprehensive income tax, local tax), the filing-cycle axis, the penalty-tax risk axis, the qualified-evidence system, and the disclaimer principle. Does not carry specific tax rates/threshold amounts and enforces current-year confirmation via WebSearch.
- `finance-escalation-policy` — Escalation policy. Judges 8 mandatory/advisory triggers along the three axes of tax audit likelihood × amount scale × filing deadline imminence, and on a mandatory trigger enforces placement of an expert-consultation warning block at the very top of the report. When the judgment is ambiguous, applies a conservative-upgrade rule (cost of missing > cost of over-warning).

## Usage

Call the three commands directly. A command flows through 4 stages: material confirmation → agent dispatch → tax-linked cross-check → escalation judgment/reporting. The skills are loaded automatically in tax-judgment/expense-review contexts without a separate call, reinforcing the judgment foundation (common foundations) and the escalation rules.

```
# Check documentation eligibility for first-half expense records
/expense-review --target ./경비내역_2026상반기.csv --period 2026-1H

# Focused check on commingled personal costs for corporate-card weekend usage
/expense-review --focus 사적혼입 법인카드 주말 사용 건이 많은데 문제 없는지

# Financial statement interpretation vs. prior period
/financial-review --target ./재무제표_2025.csv --compare ./재무제표_2024.csv

# Comprehensive risk check before final VAT filing
/tax-risk-scan --entity 법인 --scope all 7월 부가세 확정신고 전 리스크 점검 --target ./거래내역

# Check after receiving a tax office request for explanation (advance identification of mandatory escalation)
/tax-risk-scan --entity 개인-일반 세무서에서 매출 과소신고 소명 요구를 받음 --deadline 2026-07-20
```

`/expense-review` and `/tax-risk-scan` cross-call the two agents depending on the nature of the discovered issues, and when results conflict they present the conservative option first. If a mandatory escalation trigger applies (contact from the taxation authority, involvement of tax-crime punishment, deadline within/past 7 days, high-value issues, appeal procedures), "⚠️ Must consult a tax accountant/CPA" and the reason are displayed at the very top of the final report.

## Notes

- **Every deliverable of this plugin is a first-pass risk diagnosis and does not replace the advice of a tax accountant/CPA.** Before actually executing filing, explanation, payment, appeal, etc., always consulting an expert is recommended.
- All agents are read-only — they do not prepare/modify financial statements, do journal entries/closing/filing preparation, or act as a proxy for Hometax procedures.
- Tax rates, limits, threshold amounts, and filing deadlines are not hardcoded. When they enter into a judgment, confirm the current-year basis via WebSearch (primary sources such as the National Tax Service nts.go.kr, the Korea Law Information Center law.go.kr, etc.) and cite the confirmation year alongside it, and on confirmation failure leave the figure blank and mark it "confirmation needed".
- It does not assist with tax avoidance/evasion schemes (concealment of omitted sales, fabricated expenses, false tax invoices, etc.).
- Confirming current-year tax rates/deadlines/threshold amounts via WebSearch presupposes an environment with web access.
- Financial modeling for business planning and funding strategy is out of scope — it pairs well with `startup:financial-modeler`.
