---
name: policy-suite
description: |
  행동강령→정책→지침→절차 계층 + 내부신고 규정 스캐폴딩 + policy-index.json → grc-challenger 반증 → 게이트.
  Scaffolds the code-of-conduct → policy → standard → procedure hierarchy plus a whistleblowing policy and policy-index.json, runs grc-challenger for policy gaps, and enforces the gate. Use when: building or auditing the corporate policy suite.
category: governance
complexity: advanced
mcp-servers: []
personas: []
---

# /policy-suite - 정책 스위트 · 내부신고 규정

행동강령(code-of-conduct)을 정점으로 정책→지침→절차 계층과 내부신고(whistleblowing) 규정을 스캐폴딩하고,
`policy-index.json` 으로 목록을 관리한다. `grc-challenger`(checker)가 **정책 공백 관점**으로 반증하고,
`gate-policy-suite.sh` 가 필수 문서·frontmatter·review_date·index 정합을 검증한다. 기준은
`enterprise-orchestrator/references/gate-policy.md`, 근거는 ISO 37301·내부신고자 보호 원칙(`compliance-context`).

## Triggers
- "정책 체계", "행동강령", "내부신고 규정", "컴플라이언스 정책 스위트" 요청
- 인증·감사 대비 정책 문서 정합을 잡을 때

## Usage
```
/policy-suite [옵션]

Options:
  --list   현행 policies/ ↔ policy-index.json 정합만 점검
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/grc/policies/` 디렉토리 준비. 기존 정책이 있으면 읽어 계층에 편입.

### Phase 1: 스캐폴딩 (maker: 메인)
- 필수: `code-of-conduct.md`(행동강령), `whistleblowing-policy.md`(내부신고 규정).
- 각 정책 `.md` 는 frontmatter 에 `owner:`·`review_date:`(YYYY-MM-DD) 를 갖는다.
- 정책→지침→절차 하위 문서를 계층으로 배치하고 `policy-index.json`(`{policies:[basename…]}`)에 등록.

### Phase 2: grc-challenger 디스패치 (checker)
- 필수 정책의 **실질 공백**(형식만 존재, 신고 채널·보호조항 누락)을 반증한다.

### Phase 3: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-policy-suite.sh"`
- 필수 문서 존재·frontmatter owner/review_date·review_date 도과·index↔실파일 diff 를 검증.

## Boundaries

**Will:**
- 정책 계층·내부신고 규정 스캐폴딩, index 정합, 정책 공백 반증, 게이트 판정

**Will Not:**
- whistleblowing·data privacy 등 **법적 해석·적용 판단** → legal 위임
- 징계 조항·인사 규정 세부 → hr 위임
- 정책 본문 문구를 checker 가 수정 (grc-challenger Edit 미보유)
