---
name: wiki-audit
description: |
  llm-wiki vault 건강 감사 — wiki-auditor(checker)를 디스패치해 lint 3종(구조·무결성·스키마, LLM-0 결정론)을 실행하고 소견 triage + 모순 원장 요약 + 큐레이션 사기(claim 삭제·quote 변조) 적발 리포트를 생성한다. --semantic 옵션 시 LLM 교차 검증(Ollama 필요)까지. 모순 처리 방향은 항상 사용자 결정(★G1). Use when: "위키 감사해줘", "vault 상태 점검", "모순 확인", 큐레이션 루프 전후 검증 시.
  Audit an llm-wiki vault's health: dispatches the wiki-auditor checker to run the three LLM-0 lint gates, triage findings, summarize the contradiction ledger, and detect curation fraud. Use when: auditing vault health, checking contradictions, or verifying curation work.
---

# /wiki-audit — vault 감사

얇은 진입점이다 — 실행 로직은 `wiki-ops-orchestrator` Stage 2가 수행한다
(wiki-auditor 디스패치, Edit 미보유 checker).

## When to Apply

- feed 직후 또는 정기 vault 건강 점검이 필요할 때
- 큐레이션 루프 종료 후 게이트 그린이 조작이 아닌지 반증할 때
- 모순 원장(`wiki/_reports/contradictions.md`) 확인·triage가 필요할 때

## Usage

```
/wiki-audit [--vault <dir>] [--semantic]
```

| 인자 | 의미 |
|------|------|
| `--vault` | vault 경로 (생략 시 `$LLMWIKI_VAULT`) |
| `--semantic` | LLM 2nd pass 교차 검증 추가 — Ollama 필요, 게이트 아님 (감사 전용) |

## Flow

1. wiki-auditor 디스패치 (vault 절대경로 + LLMWIKI_BIN + 도구 계약 절대경로 3요소를 프롬프트에 명시)
2. `.planning/wiki-audit.md` 생성 — 게이트 결과 / triage / 원장 / 사기 검사
3. ★G1: 미해소 모순이 있으면 처리 방향을 사용자에게 질문 (자동 해소 절대 금지)

## Boundaries

Will: 결정론 감사 리포트, 모순 triage, 사기 반증
Will Not: 소견 해소 편집(→ `/wiki-curate`), 모순 자동 해소, semantic을 루프 게이트로 사용
